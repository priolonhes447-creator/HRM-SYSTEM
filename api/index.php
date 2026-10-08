<?php
// ============================================================
// HRMS UNIFIED PHP REST API ROUTER & CONTROLLER
// ============================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/jwt.php';
require_once __DIR__ . '/ness.php';

$GLOBALS['hrms_request_started'] = microtime(true);
$GLOBALS['hrms_submission_stage'] = 'database_connect';
register_shutdown_function(static function (): void {
    if (!in_array($GLOBALS['route'] ?? ($_GET['route'] ?? ''), ['applicants', 'applicants/receipt'], true)) return;
    // No candidate details, credentials, or receipt secrets belong in logs.
    error_log('HRMS submission ' . json_encode([
        'stage' => $GLOBALS['hrms_submission_stage'] ?? 'unknown',
        'database_saved' => $GLOBALS['hrms_submission_saved'] ?? false,
        'duration_ms' => (int)((microtime(true) - $GLOBALS['hrms_request_started']) * 1000),
        'http_status' => http_response_code()
    ]));
});

try {
    $pdo = getDBConnection();
} catch (Throwable $e) {
    error_log('HRMS PostgreSQL connection failed: ' . $e->getMessage());
    respondError('PostgreSQL connection failed. No data was saved.', 503);
}
$requestMethod = $_SERVER['REQUEST_METHOD'];

// Extract path relative to api/ or route query parameter
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$uri = str_replace('\\', '/', $uri);

// Normalize route (strip base folder path if hosted under subfolder like /hr-folder/api/...)
$route = $_GET['route'] ?? '';
if (empty($route)) {
    if (preg_match('#/api/(.+)#i', $uri, $matches)) {
        $route = $matches[1];
    } else {
        $route = ltrim($uri, '/');
    }
}
$route = trim($route, '/');

// Decode JSON input body for POST/PUT requests
$input = json_decode(file_get_contents('php://input'), true) ?? $_POST;

if (
    $route === 'applicants' &&
    $requestMethod === 'POST' &&
    stripos($_SERVER['CONTENT_TYPE'] ?? '', 'multipart/form-data') === 0 &&
    (int)($_SERVER['CONTENT_LENGTH'] ?? 0) > 0 &&
    empty($_POST) &&
    empty($_FILES)
) {
    respondError('The application upload exceeds the server request-size limit. Reduce the total file size or contact HR.', 413);
}

function isRestrictedHrAccount(array $user): bool {
    return ($user['role'] ?? null) === 'hr'
        || strtolower(trim((string)($user['email'] ?? ''))) === 'phnhes@gmail.com';
}

function isHrDashboardUser(array $user): bool {
    return in_array($user['role'] ?? null, ['admin', 'hr'], true);
}

function hiddenUnhiredApplicantFilter(array $user): string {
    if (!isRestrictedHrAccount($user)) {
        return '';
    }
    return "
        AND NOT EXISTS (
            SELECT 1
            FROM employees hidden_employee
            WHERE hidden_employee.status = 'Unhired'
              AND (
                  (
                      NULLIF(BTRIM(COALESCE(a.email, '')), '') IS NOT NULL
                      AND LOWER(BTRIM(hidden_employee.email)) = LOWER(BTRIM(a.email))
                  )
                  OR LOWER(REGEXP_REPLACE(BTRIM(COALESCE(hidden_employee.name, '')), '[[:space:]]+', ' ', 'g'))
                     = LOWER(REGEXP_REPLACE(BTRIM(COALESCE(a.name, '')), '[[:space:]]+', ' ', 'g'))
              )
        )
    ";
}

function ensureContractSignedPhotoColumn(PDO $pdo): void {
    static $columnEnsured = false;
    if ($columnEnsured) {
        return;
    }
    $pdo->exec("ALTER TABLE employees ADD COLUMN IF NOT EXISTS contract_signed_photo_path VARCHAR(100) DEFAULT ''");
    $columnEnsured = true;
}

if ($route === 'health' && $requestMethod === 'GET') {
    respondJSON(['status' => 'ok', 'database' => 'postgresql']);
}

// Helper: Password verification & hashing using password_hash/bcrypt
function generateTemporaryPassword($length = 12) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
    $password = '';
    for ($i = 0; $i < $length; $i++) {
        $password .= $chars[random_int(0, strlen($chars) - 1)];
    }
    return $password;
}

function hashPassword($password) {
    return password_hash($password, PASSWORD_BCRYPT);
}
function verifyPassword($password, $hash) {
    if (substr($hash, 0, 4) === '$2a$' || substr($hash, 0, 4) === '$2y$' || substr($hash, 0, 4) === '$2b$') {
        return password_verify($password, $hash);
    }
    // Secure constant-time string comparison for any legacy unhashed credentials
    return hash_equals((string)$hash, (string)$password);
}

function genericPasswordResetMessage() {
    return 'If an account is associated with that email, a verification code has been sent.';
}

function findPasswordResetUser($pdo, $email) {
    $stmt = $pdo->prepare('SELECT id, email FROM users WHERE LOWER(email) = LOWER(?)');
    $stmt->execute([$email]);
    return $stmt->fetch();
}

function ensureLoginVerificationsTable(PDO $pdo): void {
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS login_verifications (
            id BIGSERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            challenge_hash CHAR(64) NOT NULL UNIQUE,
            otp_hash VARCHAR(255) NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            expires_at TIMESTAMPTZ NOT NULL,
            used_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ");
    $pdo->exec('CREATE INDEX IF NOT EXISTS login_verifications_user_created_idx ON login_verifications (user_id, created_at DESC)');
}

function buildAuthenticatedUserPayload(array $user): array {
    return [
        'id' => (int)$user['id'],
        'email' => $user['email'],
        'role' => $user['role'],
        'name' => $user['name'],
        'position' => $user['position'] ?? '',
        'department' => $user['department'] ?? '',
        'employee_id' => $user['employee_id'] ?? ''
    ];
}

function issueAuthenticatedSession(array $user): array {
    $payload = buildAuthenticatedUserPayload($user);
    return [
        'token' => PHPJWT::encode($payload, getJwtSecret(), JWT_EXPIRES_IN),
        'user' => $payload
    ];
}

function requiresLoginEmailVerification(array $user): bool {
    return in_array(strtolower((string)($user['role'] ?? '')), ['admin', 'hr'], true)
        || strtolower(trim((string)($user['email'] ?? ''))) === 'phnhes@gmail.com';
}

function calculateApplicantAgeYears(?string $dateOfBirth): ?int {
    if ($dateOfBirth === null || trim((string)$dateOfBirth) === '') {
        return null;
    }

    $dob = DateTimeImmutable::createFromFormat('!Y-m-d', trim((string)$dateOfBirth));
    $errors = DateTimeImmutable::getLastErrors();
    if ($dob === false || ($errors && ($errors['warning_count'] > 0 || $errors['error_count'] > 0))) {
        return null;
    }

    $today = new DateTimeImmutable('today');
    $age = (int)$today->format('Y') - (int)$dob->format('Y');
    if ($today->format('md') < $dob->format('md')) {
        $age--;
    }

    return $age >= 0 ? $age : null;
}

function validatePositionAgeRequirement(string $position, ?string $dateOfBirth): ?string {
    $position = trim($position);
    if ($position === '') {
        return null;
    }

    $minimumAgeByPosition = [
        'Staff' => 20,
        'Cashier' => 20,
        'Team Leader' => 20,
        'Driver' => 25,
    ];

    if (!isset($minimumAgeByPosition[$position])) {
        return null;
    }

    $age = calculateApplicantAgeYears($dateOfBirth);
    if ($age === null) {
        return "Applicants for {$position} must provide a valid date of birth.";
    }

    $minimumAge = $minimumAgeByPosition[$position];
    if ($age < $minimumAge) {
        return "Applicants for {$position} must be at least {$minimumAge} years old.";
    }

    return null;
}

function issuePasswordReset($pdo, $email, $enforceCooldown = false) {
    $user = findPasswordResetUser($pdo, $email);
    if (!$user) {
        return ['status' => 202, 'message' => genericPasswordResetMessage()];
    }

    $latestStmt = $pdo->prepare('SELECT created_at FROM password_resets WHERE user_id = ? ORDER BY created_at DESC LIMIT 1');
    $latestStmt->execute([$user['id']]);
    $latest = $latestStmt->fetch();
    if ($enforceCooldown && $latest && strtotime($latest['created_at']) > time() - 60) {
        return ['status' => 429, 'error' => 'Please wait before requesting another code.'];
    }

    $otp = (string)random_int(100000, 999999);
    $otpHash = password_hash($otp, PASSWORD_DEFAULT);
    $pdo->beginTransaction();
    try {
        $pdo->prepare('DELETE FROM password_resets WHERE user_id = ?')->execute([$user['id']]);
        $insert = $pdo->prepare(
            "INSERT INTO password_resets (user_id, otp_hash, expires_at)
             VALUES (?, ?, CURRENT_TIMESTAMP + INTERVAL '5 minutes') RETURNING id"
        );
        $insert->execute([$user['id'], $otpHash]);
        $resetId = $insert->fetchColumn();
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }

    try {
        require_once __DIR__ . '/mailer.php';
        sendPasswordResetEmail($user['email'], $otp);
    } catch (Throwable $e) {
        $pdo->prepare('DELETE FROM password_resets WHERE id = ?')->execute([$resetId]);
        throw new RuntimeException('Unable to send the verification email. Check the server SMTP configuration.');
    }

    return ['status' => 202, 'message' => genericPasswordResetMessage()];
}

// Default Onboarding Checklist definition
$DEFAULT_ONBOARDING_TASKS = [
    ['task' => 'Contract Signed', 'offset' => 5],
    ['task' => 'Health Card Picture', 'offset' => 20],
    ['task' => 'Orientation & Company Policy Review', 'offset' => 10],
    ['task' => 'Role-Specific Training', 'offset' => 10],
    ['task' => 'Complete Required Initial Training', 'offset' => 15]
];

// Helper: Start onboarding for an employee
function startOnboardingChecklist($pdo, $employeeDbId, $DEFAULT_ONBOARDING_TASKS) {
    // Check if tasks already exist for employee
    $stmt = $pdo->prepare("SELECT COUNT(*) as cnt FROM onboarding_tasks WHERE employee_id = ?");
    $stmt->execute([$employeeDbId]);
    if ($stmt->fetch()['cnt'] > 0) {
        return ['already_started' => true];
    }

    $insert = $pdo->prepare("INSERT INTO onboarding_tasks (employee_id, task, status, due_date) VALUES (?, ?, 'Pending', ?)");
    $created = [];
    $today = new DateTime();
    foreach ($DEFAULT_ONBOARDING_TASKS as $t) {
        $due = clone $today;
        $due->modify("+{$t['offset']} days");
        $dueStr = $due->format('Y-m-d');
        $insert->execute([$employeeDbId, $t['task'], $dueStr]);
        $created[] = ['task' => $t['task'], 'status' => 'Pending', 'due_date' => $dueStr];
    }
    return ['created' => $created];
}

function generateUniqueEmployeeCode(PDO $pdo): string {
    if (!$pdo->inTransaction()) {
        throw new LogicException('Employee IDs can only be allocated inside a transaction.');
    }

    $pdo->query("SELECT pg_advisory_xact_lock(hashtext('hrms_employee_id_generation'))");
    $nextNumber = (int)$pdo->query("
        SELECT COALESCE(MAX(employee_number), 0) + 1
        FROM (
            SELECT CAST(SUBSTRING(employee_id FROM 4) AS INTEGER) AS employee_number
            FROM employees
            WHERE employee_id ~ '^EMP[0-9]+$'
            UNION ALL
            SELECT CAST(SUBSTRING(employee_id FROM 4) AS INTEGER) AS employee_number
            FROM users
            WHERE employee_id ~ '^EMP[0-9]+$'
        ) AS existing_employee_codes
    ")->fetchColumn();

    $codeCheck = $pdo->prepare("
        SELECT 1 FROM employees WHERE employee_id = ?
        UNION ALL
        SELECT 1 FROM users WHERE employee_id = ?
        LIMIT 1
    ");
    do {
        $employeeCode = 'EMP' . str_pad((string)$nextNumber++, 3, '0', STR_PAD_LEFT);
        $codeCheck->execute([$employeeCode, $employeeCode]);
    } while ($codeCheck->fetchColumn());

    return $employeeCode;
}

function normalizeEmployeeDepartment($department): string {
    $department = trim((string)($department ?? ''));
    return $department === '' || strcasecmp($department, 'General') === 0
        ? 'HR'
        : $department;
}

function isDuplicateApplicantSubmission(PDO $pdo, string $email, string $name, string $phone): bool {
    $stmt = $pdo->prepare("
        SELECT 1
        FROM applicants
        WHERE LOWER(BTRIM(COALESCE(email, ''))) = LOWER(BTRIM(?))
          AND LOWER(REGEXP_REPLACE(BTRIM(COALESCE(name, '')), '[[:space:]]+', ' ', 'g'))
              = LOWER(REGEXP_REPLACE(BTRIM(?), '[[:space:]]+', ' ', 'g'))
          AND REGEXP_REPLACE(COALESCE(phone, ''), '\\D', '', 'g') = ?
        LIMIT 1
    ");
    $stmt->execute([$email, $name, $phone]);
    return (bool)$stmt->fetchColumn();
}

// ============================================================
// ROUTE DISPATCHER
// ============================================================

try {
    if ($route === 'applicants/receipt' && $requestMethod === 'POST') {
        $pdo->exec("SET lock_timeout = '3s'");
        $pdo->exec("SET statement_timeout = '10s'");
        $key = trim((string)($input['submission_key'] ?? ''));
        if (!preg_match('/^[a-f0-9]{64}$/D', $key)) respondError('Invalid application receipt.', 400);
        header('Cache-Control: no-store');
        $stmt = $pdo->prepare('SELECT 1 FROM applicants WHERE submission_key = ?');
        $stmt->execute([$key]);
        respondJSON(['received' => (bool)$stmt->fetchColumn()]);
    }
    // --------------------------------------------------------
    // 1. AUTH ROUTES
    // --------------------------------------------------------
    if ($route === 'auth/login' && $requestMethod === 'POST') {
        $email = trim($input['email'] ?? '');
        $password = trim($input['password'] ?? '');

        if (!$email || !$password) {
            respondError("Email and password are required.", 400);
        }

        $stmt = $pdo->prepare("SELECT * FROM users WHERE LOWER(email) = LOWER(?)");
        $stmt->execute([$email]);
        $user = $stmt->fetch();

        if (!$user || !verifyPassword($password, $user['password'])) {
            respondError("Invalid email or password.", 401);
        }
        // Auto-upgrade legacy password hashes to bcrypt upon login
        if (substr($user['password'], 0, 4) !== '$2a$' && substr($user['password'], 0, 4) !== '$2y$' && substr($user['password'], 0, 4) !== '$2b$') {
            $upgradedHash = hashPassword($password);
            $pdo->prepare("UPDATE users SET password = ? WHERE id = ?")->execute([$upgradedHash, $user['id']]);
        }

        if (requiresLoginEmailVerification($user)) {
            ensureLoginVerificationsTable($pdo);
            $recentChallenge = $pdo->prepare("
                SELECT created_at FROM login_verifications
                WHERE user_id = ? AND used_at IS NULL
                ORDER BY created_at DESC LIMIT 1
            ");
            $recentChallenge->execute([(int)$user['id']]);
            $latestChallenge = $recentChallenge->fetchColumn();
            if ($latestChallenge && strtotime($latestChallenge) > time() - 60) {
                respondError('A verification code was recently sent. Please wait before trying again or use Resend Code.', 429);
            }

            $otp = (string)random_int(100000, 999999);
            $challengeId = bin2hex(random_bytes(32));
            $challengeHash = hash('sha256', $challengeId);
            $pdo->beginTransaction();
            try {
                $pdo->prepare('UPDATE login_verifications SET used_at = CURRENT_TIMESTAMP WHERE user_id = ? AND used_at IS NULL')
                    ->execute([(int)$user['id']]);
                $insert = $pdo->prepare("
                    INSERT INTO login_verifications (user_id, challenge_hash, otp_hash, expires_at)
                    VALUES (?, ?, ?, CURRENT_TIMESTAMP + INTERVAL '5 minutes')
                ");
                $insert->execute([(int)$user['id'], $challengeHash, password_hash($otp, PASSWORD_DEFAULT)]);
                $pdo->commit();
            } catch (Throwable $error) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                throw $error;
            }

            try {
                require_once __DIR__ . '/mailer.php';
                sendAdminLoginVerificationEmail($user['email'], $otp);
            } catch (Throwable $error) {
                error_log('HRMS login verification email failed: ' . $error->getMessage());
                $pdo->prepare('UPDATE login_verifications SET used_at = CURRENT_TIMESTAMP WHERE challenge_hash = ?')
                    ->execute([$challengeHash]);
                respondError('Unable to send the login verification email. Please try again later.', 503);
            }

            respondJSON([
                'requires_otp' => true,
                'challenge_id' => $challengeId,
                'email' => $user['email']
            ]);
        }

        $session = issueAuthenticatedSession($user);

        $GLOBALS['hrms_activity_user'] = $session['user'];
        respondJSON($session);
    }

    if ($route === 'auth/resend-login-otp' && $requestMethod === 'POST') {
        $challengeId = trim((string)($input['challenge_id'] ?? ''));
        if (!preg_match('/^[a-f0-9]{64}$/', $challengeId)) {
            respondError('Login verification session is invalid. Please sign in again.', 400);
        }
        ensureLoginVerificationsTable($pdo);
        $challengeHash = hash('sha256', $challengeId);
        $stmt = $pdo->prepare("
            SELECT lv.id, lv.user_id, lv.created_at, u.email, u.role
            FROM login_verifications lv
            JOIN users u ON u.id = lv.user_id
            WHERE lv.challenge_hash = ? AND lv.used_at IS NULL
            ORDER BY lv.created_at DESC LIMIT 1
        ");
        $stmt->execute([$challengeHash]);
        $verification = $stmt->fetch();
        if (!$verification || !requiresLoginEmailVerification($verification)) {
            respondError('Login verification session is invalid. Please sign in again.', 401);
        }
        if (strtotime($verification['created_at']) > time() - 60) {
            respondError('Please wait before requesting another verification code.', 429);
        }

        $otp = (string)random_int(100000, 999999);
        $update = $pdo->prepare("
            UPDATE login_verifications
            SET otp_hash = ?, attempts = 0, expires_at = CURRENT_TIMESTAMP + INTERVAL '5 minutes',
                created_at = CURRENT_TIMESTAMP
            WHERE id = ? AND used_at IS NULL
        ");
        $update->execute([password_hash($otp, PASSWORD_DEFAULT), (int)$verification['id']]);
        if ($update->rowCount() !== 1) respondError('Login verification session is no longer valid.', 409);
        try {
            require_once __DIR__ . '/mailer.php';
            sendAdminLoginVerificationEmail($verification['email'], $otp);
        } catch (Throwable $error) {
            error_log('HRMS login verification resend failed: ' . $error->getMessage());
            $pdo->prepare('UPDATE login_verifications SET used_at = CURRENT_TIMESTAMP WHERE id = ?')
                ->execute([(int)$verification['id']]);
            respondError('Unable to send the login verification email. Please sign in again later.', 503);
        }
        respondJSON(['message' => 'A new verification code has been sent.']);
    }

    if ($route === 'auth/verify-login-otp' && $requestMethod === 'POST') {
        $challengeId = trim((string)($input['challenge_id'] ?? ''));
        $otp = trim((string)($input['otp'] ?? ''));
        if (!preg_match('/^[a-f0-9]{64}$/', $challengeId) || !preg_match('/^\d{6}$/', $otp)) {
            respondError('Invalid verification code.', 400);
        }
        ensureLoginVerificationsTable($pdo);
        $challengeHash = hash('sha256', $challengeId);
        $pdo->beginTransaction();
        try {
            $stmt = $pdo->prepare("
                SELECT lv.*, u.email, u.role, u.name, u.position, u.department, u.employee_id
                FROM login_verifications lv
                JOIN users u ON u.id = lv.user_id
                WHERE lv.challenge_hash = ? AND lv.used_at IS NULL
                FOR UPDATE OF lv
            ");
            $stmt->execute([$challengeHash]);
            $verification = $stmt->fetch();
            if (!$verification || !requiresLoginEmailVerification($verification)) {
                $pdo->rollBack();
                respondError('Login verification session is invalid. Please sign in again.', 401);
            }
            if (strtotime($verification['expires_at']) <= time()) {
                $pdo->prepare('UPDATE login_verifications SET used_at = CURRENT_TIMESTAMP WHERE id = ?')
                    ->execute([(int)$verification['id']]);
                $pdo->commit();
                respondError('Verification code has expired. Sign in again to request a new code.', 410);
            }
            if ((int)$verification['attempts'] >= 5) {
                $pdo->prepare('UPDATE login_verifications SET used_at = CURRENT_TIMESTAMP WHERE id = ?')
                    ->execute([(int)$verification['id']]);
                $pdo->commit();
                respondError('Too many invalid attempts. Sign in again to request a new code.', 429);
            }
            if (!password_verify($otp, $verification['otp_hash'])) {
                $pdo->prepare('UPDATE login_verifications SET attempts = attempts + 1 WHERE id = ?')
                    ->execute([(int)$verification['id']]);
                $pdo->commit();
                respondError('Invalid verification code.', 400);
            }
            $pdo->prepare('UPDATE login_verifications SET used_at = CURRENT_TIMESTAMP WHERE id = ?')
                ->execute([(int)$verification['id']]);
            $pdo->commit();
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $error;
        }

        $session = issueAuthenticatedSession($verification);
        $GLOBALS['hrms_activity_user'] = $session['user'];
        respondJSON($session);
    }

    if ($route === 'auth/forgot-password' && $requestMethod === 'POST') {
        $email = trim(strtolower($input['email'] ?? ''));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            respondJSON(['message' => genericPasswordResetMessage()], 202);
        }

        try {
            $result = issuePasswordReset($pdo, $email);
            respondJSON(['message' => $result['message'] ?? $result['error']], $result['status']);
        } catch (Throwable $e) {
            respondError('Unable to send the verification email. Please try again later.', 503);
        }
    }

    if ($route === 'auth/resend-otp' && $requestMethod === 'POST') {
        $email = trim(strtolower($input['email'] ?? ''));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            respondJSON(['message' => genericPasswordResetMessage()], 202);
        }

        try {
            $result = issuePasswordReset($pdo, $email, true);
            if (isset($result['error'])) respondError($result['error'], $result['status']);
            respondJSON(['message' => $result['message']], $result['status']);
        } catch (Throwable $e) {
            respondError('Unable to send the verification email. Please try again later.', 503);
        }
    }

    if ($route === 'auth/verify-otp' && $requestMethod === 'POST') {
        $email = trim(strtolower($input['email'] ?? ''));
        $otp = trim((string)($input['otp'] ?? ''));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || !preg_match('/^\d{6}$/', $otp)) {
            respondError('Invalid verification code.', 400);
        }

        $stmt = $pdo->prepare(
            "SELECT pr.* FROM password_resets pr
             JOIN users u ON u.id = pr.user_id
             WHERE LOWER(u.email) = LOWER(?) AND pr.used_at IS NULL
             ORDER BY pr.created_at DESC LIMIT 1"
        );
        $stmt->execute([$email]);
        $reset = $stmt->fetch();
        if (!$reset || strtotime($reset['expires_at']) <= time()) {
            respondError('Verification code has expired. Request a new code.', 410);
        }
        if ((int)$reset['attempts'] >= 5) {
            respondError('Too many invalid attempts. Request a new code.', 429);
        }

        if (!password_verify($otp, $reset['otp_hash'])) {
            $pdo->prepare('UPDATE password_resets SET attempts = attempts + 1 WHERE id = ?')->execute([$reset['id']]);
            respondError('Invalid verification code.', 400);
        }

        $resetToken = bin2hex(random_bytes(32));
        $tokenHash = hash('sha256', $resetToken);
        $update = $pdo->prepare(
            'UPDATE password_resets SET verified_at = CURRENT_TIMESTAMP, reset_token_hash = ? WHERE id = ? AND used_at IS NULL'
        );
        $update->execute([$tokenHash, $reset['id']]);
        if ($update->rowCount() !== 1) respondError('Verification session is no longer valid.', 409);
        respondJSON(['reset_token' => $resetToken]);
    }

    if ($route === 'auth/reset-password' && $requestMethod === 'POST') {
        $resetToken = trim((string)($input['reset_token'] ?? ''));
        $newPassword = (string)($input['new_password'] ?? '');
        $confirmPassword = (string)($input['confirm_password'] ?? '');

        if (!preg_match('/^[a-f0-9]{64}$/', $resetToken)) respondError('Invalid or expired reset session.', 401);
        if (strlen($newPassword) < 6) respondError('Password must be at least 6 characters.', 400);
        if ($newPassword !== $confirmPassword) respondError('Passwords do not match.', 400);

        $tokenHash = hash('sha256', $resetToken);
        $stmt = $pdo->prepare(
            "SELECT pr.id, pr.user_id FROM password_resets pr
             WHERE pr.reset_token_hash = ? AND pr.verified_at IS NOT NULL
               AND pr.used_at IS NULL AND pr.expires_at > CURRENT_TIMESTAMP"
        );
        $stmt->execute([$tokenHash]);
        $reset = $stmt->fetch();
        if (!$reset) respondError('Invalid or expired reset session.', 401);

        $pdo->beginTransaction();
        try {
            $passwordHash = password_hash($newPassword, PASSWORD_DEFAULT);
            $passwordUpdate = $pdo->prepare('UPDATE users SET password = ? WHERE id = ?');
            $passwordUpdate->execute([$passwordHash, $reset['user_id']]);
            if ($passwordUpdate->rowCount() !== 1) throw new RuntimeException('User password was not updated.');

            $usedUpdate = $pdo->prepare('UPDATE password_resets SET used_at = CURRENT_TIMESTAMP WHERE id = ? AND used_at IS NULL');
            $usedUpdate->execute([$reset['id']]);
            if ($usedUpdate->rowCount() !== 1) throw new RuntimeException('Reset session was not invalidated.');
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            respondError('Password reset failed. No password was changed.', 500);
        }

        respondJSON(['message' => 'Password reset successfully.']);
    }

    if ($route === 'auth/me' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $stmt = $pdo->prepare("SELECT id, email, role, name, position, department, employee_id FROM users WHERE id = ?");
        $stmt->execute([$authUser['id']]);
        $user = $stmt->fetch();
        if (!$user) respondError("User not found.", 404);
        respondJSON($user);
    }

    // --------------------------------------------------------
    // AI ASSISTANT ROUTE
    // --------------------------------------------------------
    if ($route === 'ai/chat' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $message = trim((string)($input['message'] ?? ''));
        if (!$message) respondError("Message is required.", 400);
        $messageLength = preg_match_all('/./us', $message);
        if ($messageLength === false) respondError('Message must be valid UTF-8.', 400);
        if ($messageLength > 2000) respondError('Message must be 2,000 characters or fewer.', 400);
        respondJSON([
            'reply' => getNessReply($message),
            'source' => 'ness-system-guide',
            'userRole' => $authUser['role']
        ]);
    }


    // --------------------------------------------------------
    // 2. USER PROFILE & PASSWORD ROUTES
    // --------------------------------------------------------
    if ($route === 'users/profile' && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        $name = trim($input['name'] ?? '');
        $position = trim($input['position'] ?? '');
        $department = trim($input['department'] ?? '');

        if (!$name) respondError("Name is required.", 400);

        $stmt = $pdo->prepare("UPDATE users SET name = ?, position = ?, department = ? WHERE id = ?");
        $stmt->execute([$name, $position, $department, $authUser['id']]);

        $stmt = $pdo->prepare("SELECT id, email, role, name, position, department, employee_id FROM users WHERE id = ?");
        $stmt->execute([$authUser['id']]);
        $updated = $stmt->fetch();

        respondJSON(['message' => 'Profile updated successfully.', 'user' => $updated]);
    }

    if ($route === 'users/password' && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        $currentPw = $input['current_password'] ?? '';
        $newPw = $input['new_password'] ?? '';

        if (!$currentPw || !$newPw) respondError("Current password and new password are required.", 400);
        if (strlen($newPw) < 6) respondError("New password must be at least 6 characters.", 400);

        $stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
        $stmt->execute([$authUser['id']]);
        $user = $stmt->fetch();

        if (!$user || !verifyPassword($currentPw, $user['password'])) {
            respondError("Current password is incorrect.", 401);
        }

        $newHash = hashPassword($newPw);
        $stmt = $pdo->prepare("UPDATE users SET password = ? WHERE id = ?");
        $stmt->execute([$newHash, $authUser['id']]);

        respondJSON(['message' => 'Password changed successfully.']);
    }

    // --------------------------------------------------------
    // 3. USER MANAGEMENT (Admin Only)
    // --------------------------------------------------------
    if ($route === 'users' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireExactRole($authUser, 'admin');

        // Enforce rule: purge orphan user accounts that are not in Employee Records Management
        $pdo->exec("DELETE FROM users WHERE id NOT IN (
            SELECT u.id FROM users u
            JOIN employees e ON (e.employee_id = u.employee_id AND u.employee_id IS NOT NULL AND u.employee_id != '')
                             OR LOWER(e.email) = LOWER(u.email)
        )");

        $sql = "
            SELECT u.id, u.email, u.role, u.name, u.position, u.department, u.employee_id, u.created_at
            FROM users u
        ";
        if (isRestrictedHrAccount($authUser)) {
            $sql .= "
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM employees e
                    WHERE e.status = 'Unhired'
                      AND (
                          (e.employee_id = u.employee_id AND NULLIF(u.employee_id, '') IS NOT NULL)
                          OR LOWER(e.email) = LOWER(u.email)
                      )
                )
            ";
        }
        $stmt = $pdo->query($sql . ' ORDER BY u.id DESC');
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'users' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireExactRole($authUser, 'admin');

        $email = trim(strtolower($input['email'] ?? ''));
        $password = $input['password'] ?? '';
        $name = trim($input['name'] ?? '');
        $role = $input['role'] ?? 'employee';
        $position = trim($input['position'] ?? '');
        $department = trim($input['department'] ?? '');
        $empId = trim($input['employee_id'] ?? '');

        if (!$email || !$password || !$name) respondError("email, password, and name are required.", 400);
        if (!in_array($role, ['admin', 'hr', 'employee'], true)) respondError('Invalid user role.', 400);
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) respondError("A valid email address is required.", 400);
        if (strlen($password) < 6) respondError("Password must be at least 6 characters.", 400);
        if ($role === 'employee') {
            $department = normalizeEmployeeDepartment($department);
        }

        // Check if existing user email
        $stmt = $pdo->prepare("SELECT id FROM users WHERE LOWER(email) = ?");
        $stmt->execute([$email]);
        if ($stmt->fetch()) respondError("An account with this email already exists.", 409);

        // Check if employee record exists; auto-create one if missing so every user has an employee record
        $stmt = $pdo->prepare("SELECT * FROM employees WHERE (employee_id = ? AND employee_id != '') OR LOWER(email) = ?");
        $stmt->execute([$empId, $email]);
        $emp = $stmt->fetch();

        if (!$emp) {
            if (!$empId) {
                $stmtCount = $pdo->query("SELECT COUNT(*) as cnt FROM employees");
                $empSeq = $stmtCount->fetch()['cnt'] + 1;
                $rolePrefix = $role === 'admin' ? 'ADMIN' : ($role === 'hr' ? 'HR' : 'EMP');
                $empId = $rolePrefix . str_pad($empSeq, 3, '0', STR_PAD_LEFT);
            }
            $isHrRole = in_array($role, ['admin', 'hr'], true);
            $stmtIns = $pdo->prepare("INSERT INTO employees (employee_id, name, email, department, role, status) VALUES (?, ?, ?, ?, ?, 'Active')");
            $stmtIns->execute([$empId, $name, $email, $department ?: ($isHrRole ? 'Human Resources' : 'HR'), $position ?: ($isHrRole ? 'HR Manager' : 'Staff')]);
            $empDbId = $pdo->lastInsertId();
        } else {
            if (!$empId && !empty($emp['employee_id'])) {
                $empId = $emp['employee_id'];
            }
            $empDbId = $emp['id'];
        }

        $hashed = hashPassword($password);
        $stmt = $pdo->prepare("INSERT INTO users (email, password, role, name, position, department, employee_id) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$email, $hashed, $role, $name, $position, $department, $empId]);
        $newId = $pdo->lastInsertId();

        if ($emp && $emp['status'] === 'Onboarding') {
            startOnboardingChecklist($pdo, $empDbId, $DEFAULT_ONBOARDING_TASKS);
        }

        $stmt = $pdo->prepare("SELECT id, email, role, name, position, department, employee_id, created_at FROM users WHERE id = ?");
        $stmt->execute([$newId]);
        respondJSON(['message' => 'User account created successfully.', 'user' => $stmt->fetch()], 201);
    }

    if (preg_match('#^users/(\d+)$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireExactRole($authUser, 'admin');
        $id = (int)$matches[1];
        $email = trim(strtolower($input['email'] ?? ''));
        $name = trim($input['name'] ?? '');
        $role = $input['role'] ?? 'employee';
        $position = trim($input['position'] ?? '');
        $department = trim($input['department'] ?? '');
        $password = (string)($input['password'] ?? '');

        if (!$name || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            respondError('Name and a valid email address are required.', 400);
        }
        if (!in_array($role, ['admin', 'hr', 'employee'], true)) respondError('Invalid user role.', 400);
        if ($role === 'employee') {
            $department = normalizeEmployeeDepartment($department);
        }
        if ($password !== '' && strlen($password) < 6) respondError('Password must be at least 6 characters.', 400);

        $existing = $pdo->prepare('SELECT * FROM users WHERE id = ?');
        $existing->execute([$id]);
        $user = $existing->fetch();
        if (!$user) respondError('User account not found.', 404);

        $duplicate = $pdo->prepare('SELECT id FROM users WHERE LOWER(email) = LOWER(?) AND id <> ?');
        $duplicate->execute([$email, $id]);
        if ($duplicate->fetch()) respondError('An account with this email already exists.', 409);

        $pdo->beginTransaction();
        try {
            $sql = 'UPDATE users SET email = ?, name = ?, role = ?, position = ?, department = ?';
            $params = [$email, $name, $role, $position, $department];
            if ($password !== '') {
                $sql .= ', password = ?';
                $params[] = password_hash($password, PASSWORD_DEFAULT);
            }
            $sql .= ' WHERE id = ?';
            $params[] = $id;
            $update = $pdo->prepare($sql);
            $update->execute($params);
            if ($update->rowCount() !== 1) throw new RuntimeException('User account was not updated.');

            $linkedEmployee = $pdo->prepare(
                "UPDATE employees SET email = ?, name = ?, role = ?, department = ?
                 WHERE (employee_id = ? AND employee_id IS NOT NULL AND employee_id != '')
                    OR LOWER(email) = LOWER(?)"
            );
            $linkedEmployee->execute([$email, $name, $position, $department, $user['employee_id'], $user['email']]);
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            respondError('User account update failed. No changes were saved.', 500);
        }

        $updated = $pdo->prepare('SELECT id, email, role, name, position, department, employee_id, created_at FROM users WHERE id = ?');
        $updated->execute([$id]);
        respondJSON(['message' => 'User account updated successfully.', 'user' => $updated->fetch()]);
    }

    if (preg_match('#^users/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireExactRole($authUser, 'admin');
        $id = (int)$matches[1];

        if ($authUser['id'] === $id) respondError("You cannot delete your own account.", 400);

        // Deactivate linked employee if exists
        $stmt = $pdo->prepare("SELECT employee_id, email FROM users WHERE id = ?");
        $stmt->execute([$id]);
        $user = $stmt->fetch();
        if ($user) {
            $pdo->prepare("UPDATE employees SET status = 'Inactive' WHERE (employee_id = ? AND employee_id != '') OR LOWER(email) = LOWER(?)")->execute([$user['employee_id'], $user['email']]);
        }

        $pdo->prepare("DELETE FROM announcement_reads WHERE user_id = ?")->execute([$id]);
        $stmt = $pdo->prepare("DELETE FROM users WHERE id = ?");
        $stmt->execute([$id]);
        if ($stmt->rowCount() !== 1) respondError("User account not found.", 404);

        respondJSON(['message' => 'User account deleted successfully.']);
    }

    // --------------------------------------------------------
    // 4. EMPLOYEE ROUTES (Admin Only)
    // --------------------------------------------------------
    if ($route === 'employees' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        ensureContractSignedPhotoColumn($pdo);

        $sql = "
            SELECT e.*,
                   CASE WHEN (
                       EXISTS (
                           SELECT 1
                           FROM onboarding_tasks ot
                           WHERE ot.employee_id = e.id
                             AND ot.task NOT IN (
                                 'Email & Account Created',
                                 'IT Assets Assigned (Laptop, Peripherals)',
                                 'Company ID / Access Badge Issued',
                                 'Department Introductions & Buddy Assigned'
                             )
                       )
                       AND NOT EXISTS (
                           SELECT 1
                           FROM onboarding_tasks ot
                           WHERE ot.employee_id = e.id
                             AND ot.task NOT IN (
                                 'Email & Account Created',
                                 'IT Assets Assigned (Laptop, Peripherals)',
                                 'Company ID / Access Badge Issued',
                                 'Department Introductions & Buddy Assigned'
                             )
                             AND ot.status IS DISTINCT FROM 'Completed'
                       )
                   ) THEN 1 ELSE 0 END AS onboarding_completed
            FROM employees e
        ";
        if (isRestrictedHrAccount($authUser)) {
            $sql .= " WHERE COALESCE(e.status, '') <> 'Unhired'";
        }
        $stmt = $pdo->query($sql . ' ORDER BY e.id DESC');
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'employees' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $empId = trim($input['employee_id'] ?? '');
        $name = trim($input['name'] ?? '');
        $email = trim($input['email'] ?? '');
        if (!$empId || !$name || !$email) respondError("employee_id, name, and email are required.", 400);

        $stmt = $pdo->prepare("INSERT INTO employees (employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([
            $empId, $name, $email,
            normalizeEmployeeDepartment($input['department'] ?? ''),
            $input['role'] ?? '',
            $input['status'] ?? 'Active',
            $input['phone'] ?? '',
            $input['address'] ?? '',
            $input['date_of_birth'] ?? '',
            $input['gender'] ?? '',
            $input['emergency_contact'] ?? '',
            (int)($input['age'] ?? 0),
            $input['place_of_birth'] ?? '',
            $input['tin'] ?? '',
            $input['civil_status'] ?? '',
            $input['last_name'] ?? '',
            $input['first_name'] ?? '',
            $input['middle_name'] ?? ''
        ]);

        respondJSON(['id' => (int)$pdo->lastInsertId(), 'message' => 'Employee added successfully.'], 201);
    }

    if (preg_match('#^employees/(\d+)$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];
        if (isRestrictedHrAccount($authUser)) {
            $employeeCheck = $pdo->prepare("SELECT 1 FROM employees WHERE id = ? AND status = 'Unhired'");
            $employeeCheck->execute([$id]);
            if ($employeeCheck->fetchColumn()) respondError('Employee not found.', 404);
        }

        $stmt = $pdo->prepare("UPDATE employees SET employee_id=?, name=?, email=?, department=?, role=?, status=?, phone=?, address=?, date_of_birth=?, gender=?, emergency_contact=?, age=?, place_of_birth=?, tin=?, civil_status=?, last_name=?, first_name=?, middle_name=? WHERE id=?");
        $stmt->execute([
            $input['employee_id'] ?? '',
            $input['name'] ?? '',
            $input['email'] ?? '',
            normalizeEmployeeDepartment($input['department'] ?? ''),
            $input['role'] ?? '',
            $input['status'] ?? 'Active',
            $input['phone'] ?? '',
            $input['address'] ?? '',
            $input['date_of_birth'] ?? '',
            $input['gender'] ?? '',
            $input['emergency_contact'] ?? '',
            (int)($input['age'] ?? 0),
            $input['place_of_birth'] ?? '',
            $input['tin'] ?? '',
            $input['civil_status'] ?? '',
            $input['last_name'] ?? '',
            $input['first_name'] ?? '',
            $input['middle_name'] ?? '',
            $id
        ]);
        if ($stmt->rowCount() !== 1) respondError("Employee not found or was not updated.", 404);

        $stmt = $pdo->prepare("SELECT * FROM employees WHERE id = ?");
        $stmt->execute([$id]);
        respondJSON(['message' => 'Employee updated successfully.', 'employee' => $stmt->fetch()]);
    }

    if (preg_match('#^employees/(\d+)/status$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        if (isRestrictedHrAccount($authUser)) {
            respondError('Access denied. This action is only available to the Admin account.', 403);
        }
        $status = trim((string)($input['status'] ?? ''));
        if (!in_array($status, ['Complete', 'Unhired'], true)) {
            respondError('Employee status must be Complete or Unhired.', 400);
        }
        $comment = trim((string)($input['comment'] ?? ''));
        if ($status === 'Unhired' && $comment === '') respondError('A comment is required to move an employee to Unhired.', 400);
        if (strlen($comment) > 2000) respondError('The comment must be 2,000 characters or fewer.', 400);

        if ($status === 'Unhired') {
            $stmt = $pdo->prepare("
                UPDATE employees
                SET status = ?, comments = ?
                WHERE id = ?
                RETURNING id, status, comments
            ");
            $stmt->execute([$status, $comment, (int)$matches[1]]);
        } else {
            $stmt = $pdo->prepare("
                UPDATE employees
                SET status = ?
                WHERE id = ?
                RETURNING id, status
            ");
            $stmt->execute([$status, (int)$matches[1]]);
        }
        $employee = $stmt->fetch();
        if (!$employee) respondError('Employee not found.', 404);
        respondJSON(['message' => 'Employee status updated successfully.', 'employee' => $employee]);
    }

    if (preg_match('#^employees/(\d+)/certificate-received$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        if (isRestrictedHrAccount($authUser)) {
            respondError('Access denied. Certificate management is only available to the Admin account.', 403);
        }
        if (($input['received'] ?? null) !== true) {
            respondError('received must be true.', 400);
        }

        $stmt = $pdo->prepare('UPDATE employees SET certificate_received_at = CURRENT_TIMESTAMP WHERE id = ? RETURNING id, certificate_received_at');
        $stmt->execute([(int)$matches[1]]);
        $employee = $stmt->fetch();
        if (!$employee) respondError('Employee not found.', 404);
        respondJSON(['message' => 'Certificate receipt recorded.', 'employee' => $employee]);
    }

    if (preg_match('#^employees/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $sql = "SELECT employee_id, email, status FROM employees WHERE id = ?";
        if (isRestrictedHrAccount($authUser)) {
            $sql .= " AND COALESCE(status, '') <> 'Unhired'";
        }
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$id]);
        $emp = $stmt->fetch();

        if ($emp) {
            $pdo->prepare("DELETE FROM onboarding_tasks WHERE employee_id = ?")->execute([$id]);
            $stmtUser = $pdo->prepare("SELECT id FROM users WHERE (employee_id = ? AND employee_id != '') OR LOWER(email) = LOWER(?)");
            $stmtUser->execute([$emp['employee_id'], $emp['email']]);
            foreach ($stmtUser->fetchAll() as $user) {
                $pdo->prepare("DELETE FROM announcement_reads WHERE user_id = ?")->execute([$user['id']]);
                $pdo->prepare("DELETE FROM users WHERE id = ?")->execute([$user['id']]);
            }
            $stmtDelete = $pdo->prepare("DELETE FROM employees WHERE id = ?");
            $stmtDelete->execute([$id]);
            if ($stmtDelete->rowCount() !== 1) respondError("Employee was not deleted.", 500);
        } else {
            respondError("Employee not found.", 404);
        }
        respondJSON(['message' => 'Employee deleted successfully.']);
    }

    // --------------------------------------------------------
    // 5. APPLICANT ROUTES (Admin Only)
    // --------------------------------------------------------
    if ($route === 'applicants' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $stmt = $pdo->query("SELECT a.* FROM applicants a WHERE TRUE" . hiddenUnhiredApplicantFilter($authUser) . " ORDER BY a.id DESC");
        respondJSON($stmt->fetchAll());
    }

    if (preg_match('#^applicants/(\d+)$#', $route, $matches) && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $stmt = $pdo->prepare('SELECT a.* FROM applicants a WHERE a.id = ?' . hiddenUnhiredApplicantFilter($authUser));
        $stmt->execute([(int)$matches[1]]);
        $applicant = $stmt->fetch();
        if (!$applicant) respondError('Applicant not found.', 404);
        respondJSON($applicant);
    }

    if (preg_match('#^applicants/(\d+)/(id-photo|2x2-photo|resume|sss-photo|pag-ibig-photo|nbi-photo|health-card-photo|psa-photo)$#', $route, $matches) && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $documentColumns = [
            'id-photo' => 'id_photo_path',
            '2x2-photo' => 'id_picture_path',
            'resume' => 'resume_path',
            'sss-photo' => 'sss_photo_path',
            'pag-ibig-photo' => 'pag_ibig_photo_path',
            'nbi-photo' => 'nbi_photo_path',
            'health-card-photo' => 'health_card_photo_path',
            'psa-photo' => 'psa_photo_path'
        ];
        $documentColumn = $documentColumns[$matches[2]];
        $stmt = $pdo->prepare("SELECT a.{$documentColumn} FROM applicants a WHERE a.id = ?" . hiddenUnhiredApplicantFilter($authUser));
        $stmt->execute([(int)$matches[1]]);
        $documentName = $stmt->fetchColumn();
        if (!$documentName) respondError('Applicant document not found.', 404);

        $documentPath = __DIR__ . '/applicant-id-photos/' . basename($documentName);
        if (!is_file($documentPath)) respondError('Applicant document not found.', 404);
        $mimeType = (new finfo(FILEINFO_MIME_TYPE))->file($documentPath);
        $extensions = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
        if ($matches[2] === 'resume') {
            $extensions['application/pdf'] = 'pdf';
        }
        if (!isset($extensions[$mimeType])) respondError('Applicant document type is not supported.', 415);

        header_remove('Content-Type');
        header('Content-Type: ' . $mimeType);
        header('Content-Disposition: inline; filename="applicant-' . $matches[2] . '-' . (int)$matches[1] . '.' . $extensions[$mimeType] . '"');
        header('Cache-Control: private, no-store');
        header('X-Content-Type-Options: nosniff');
        readfile($documentPath);
        exit;
    }

    if (preg_match('#^employees/(\d+)/(id-photo|2x2-photo|resume|sss-photo|pag-ibig-photo|nbi-photo|health-card-photo|psa-photo|contract-signed-photo)$#', $route, $matches) && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        ensureContractSignedPhotoColumn($pdo);

        $documentColumns = [
            'id-photo' => 'id_photo_path',
            '2x2-photo' => 'id_picture_path',
            'resume' => 'resume_path',
            'sss-photo' => 'sss_photo_path',
            'pag-ibig-photo' => 'pag_ibig_photo_path',
            'nbi-photo' => 'nbi_photo_path',
            'health-card-photo' => 'health_card_photo_path',
            'psa-photo' => 'psa_photo_path',
            'contract-signed-photo' => 'contract_signed_photo_path'
        ];
        $documentColumn = $documentColumns[$matches[2]];
        $sql = "SELECT {$documentColumn} FROM employees WHERE id = ?";
        if (isRestrictedHrAccount($authUser)) {
            $sql .= " AND COALESCE(status, '') <> 'Unhired'";
        }
        $stmt = $pdo->prepare($sql);
        $stmt->execute([(int)$matches[1]]);
        $documentName = $stmt->fetchColumn();
        if (!$documentName) respondError('Employee document not found.', 404);

        $documentPath = __DIR__ . '/applicant-id-photos/' . basename($documentName);
        if (!is_file($documentPath)) respondError('Employee document not found.', 404);
        $mimeType = (new finfo(FILEINFO_MIME_TYPE))->file($documentPath);
        $extensions = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
        if ($matches[2] === 'resume') {
            $extensions['application/pdf'] = 'pdf';
        }
        if (!isset($extensions[$mimeType])) respondError('Employee document type is not supported.', 415);

        header_remove('Content-Type');
        header('Content-Type: ' . $mimeType);
        header('Content-Disposition: inline; filename="employee-' . $matches[2] . '-' . (int)$matches[1] . '.' . $extensions[$mimeType] . '"');
        header('Cache-Control: private, no-store');
        header('X-Content-Type-Options: nosniff');
        readfile($documentPath);
        exit;
    }

    if (preg_match('#^applicants/(\d+)/decision$#', $route, $matches) && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $applicantCheck = $pdo->prepare('SELECT a.id FROM applicants a WHERE a.id = ?' . hiddenUnhiredApplicantFilter($authUser));
        $applicantCheck->execute([(int)$matches[1]]);
        if (!$applicantCheck->fetchColumn()) respondError('Applicant not found.', 404);

        $decision = trim((string)($input['decision'] ?? ''));
        $comments = trim((string)($input['comments'] ?? ''));

        if (!in_array($decision, ['Interviewing', 'Rejected'], true)) respondError('Invalid applicant decision.', 400);
        if ($decision === 'Rejected' && $comments === '') respondError('A reason for disqualification is required.', 400);
        if ($decision === 'Interviewing') {
            $statusStmt = $pdo->prepare('SELECT a.status FROM applicants a WHERE a.id = ?' . hiddenUnhiredApplicantFilter($authUser));
            $statusStmt->execute([(int)$matches[1]]);
            $currentStatus = $statusStmt->fetchColumn();
            if ($currentStatus === false) respondError('Applicant not found.', 404);
            if ($currentStatus === 'Rejected') respondError('Applicants marked as not qualified cannot be moved to interviews.', 409);
        }

        $storedComments = $decision === 'Rejected' ? $comments : '';
        $pdo->exec("ALTER TABLE applicants ADD COLUMN IF NOT EXISTS comments TEXT DEFAULT ''");
        $stmt = $pdo->prepare('UPDATE applicants SET status = ?, comments = ? WHERE id = ?');
        $stmt->execute([$decision, $storedComments, (int)$matches[1]]);
        if ($stmt->rowCount() !== 1) respondError('Applicant not found or decision was not saved.', 404);
        respondJSON(['message' => 'Applicant decision saved.', 'status' => $decision, 'comments' => $storedComments]);
    }

    if ($route === 'applicants' && $requestMethod === 'POST') {
        $GLOBALS['hrms_submission_stage'] = 'validation_and_duplicate_check';
        // Bound database work independently of the browser upload deadline.
        $pdo->exec("SET lock_timeout = '3s'");
        $pdo->exec("SET statement_timeout = '10s'");
        $submissionKey = trim((string)($input['submission_key'] ?? ''));
        if ($submissionKey !== '' && !preg_match('/^[a-f0-9]{64}$/D', $submissionKey)) {
            respondError('Invalid application receipt. Reload the form and try again.', 400);
        }
        if ($submissionKey !== '') {
            $receipt = $pdo->prepare('SELECT id FROM applicants WHERE submission_key = ?');
            $receipt->execute([$submissionKey]);
            if ($receipt->fetchColumn()) {
                respondJSON(['message' => 'Your application has already been received.', 'already_submitted' => true]);
            }
        }
        $surname = trim($input['surname'] ?? '');
        $middleName = trim($input['middle_name'] ?? '');
        $firstName = trim($input['first_name'] ?? '');
        $name = trim($input['name'] ?? '');
        if (!$name) {
            $name = trim(implode(' ', array_filter([$firstName, $middleName, $surname])));
        }
        $position = trim($input['position'] ?? '');
        if (!$name && (!$surname || !$firstName)) respondError("Surname and first name are required.", 400);

        $uploadedFiles = [
            'id_photo' => $_FILES['id_photo'] ?? null,
            'id_picture' => $_FILES['id_picture'] ?? null,
            'resume' => $_FILES['resume'] ?? null,
            'sss_picture' => $_FILES['sss_picture'] ?? null,
            'pag_ibig_picture' => $_FILES['pag_ibig_picture'] ?? null,
            'nbi_picture' => $_FILES['nbi_picture'] ?? null,
            'psa_picture' => $_FILES['psa_picture'] ?? null
        ];
        foreach ($uploadedFiles as $field => $uploadedFile) {
            if ($uploadedFile && $uploadedFile['error'] === UPLOAD_ERR_NO_FILE) {
                $uploadedFiles[$field] = null;
            }
        }

        $isAdminManualEntry = count(array_filter($uploadedFiles)) === 0;
        if ($isAdminManualEntry) {
            $authUser = requireAuth();
            requireRole($authUser, 'admin');
        } else {
            $requiredFields = [
                'first_name' => $firstName,
                'surname' => $surname,
                'email' => trim((string)($input['email'] ?? '')),
                'phone' => trim((string)($input['phone'] ?? '')),
                'position' => $position,
                'date_of_birth' => trim((string)($input['date_of_birth'] ?? ''))
            ];
            foreach ($requiredFields as $field => $value) {
                if ($value === '') {
                    respondError('Complete all required information before submitting your application.', 400);
                }
            }
            if (!filter_var($requiredFields['email'], FILTER_VALIDATE_EMAIL)) {
                respondError('Enter a valid email address before submitting your application.', 400);
            }
            if (!preg_match('/^\d{1,11}$/', preg_replace('/\D/', '', $requiredFields['phone']))) {
                respondError('Enter a valid phone number with no more than 11 digits.', 400);
            }
            if (!in_array($position, ['Driver', 'Staff', 'Cashier', 'Team Leader'], true)) {
                respondError('Select a valid position before submitting your application.', 400);
            }
            foreach (array_keys($uploadedFiles) as $requiredDocument) {
                if (!$uploadedFiles[$requiredDocument]) {
                    respondError('Upload all required documents: ID Photo, 2x2 Picture, PDF resume, SSS, Pag-IBIG, NBI, and PSA pictures before submitting your application.', 400);
                }
            }
        }

        $ageRequirementError = validatePositionAgeRequirement($position, (string)($input['date_of_birth'] ?? ''));
        if ($ageRequirementError !== null) {
            respondError($ageRequirementError, 400);
        }

        if (!$uploadedFiles['resume'] && !$isAdminManualEntry) {
            respondError('A resume in PDF format is required.', 400);
        }

        foreach (['sss_number', 'pag_ibig_number', 'nbi_number'] as $numberField) {
            if (strlen(trim((string)($input[$numberField] ?? ''))) > 50) {
                respondError('Identification numbers must not exceed 50 characters.', 400);
            }
        }

        $email = trim((string)($input['email'] ?? ''));
        $phone = trim((string)($input['phone'] ?? ''));
        $normalizedPhone = preg_replace('/\D/', '', $phone);
        $emergencyContactPhone = trim((string)($input['emergency_contact_phone'] ?? ''));
        $normalizedEmergencyContactPhone = preg_replace('/\D/', '', $emergencyContactPhone);
        if (strlen($normalizedPhone) > 11 || strlen($normalizedEmergencyContactPhone) > 11) {
            respondError('Applicant phone numbers must not exceed 11 digits.', 400);
        }
        if ($email !== '') {
            if (isDuplicateApplicantSubmission($pdo, $email, $name, $normalizedPhone)) {
                respondJSON(['message' => 'Your application has already been received.', 'already_submitted' => true]);
            }

            $emailStmt = $pdo->prepare("
                SELECT email
                FROM (
                    SELECT email FROM applicants
                    UNION ALL
                    SELECT email FROM employees
                    UNION ALL
                    SELECT email FROM users
                ) AS existing_emails
                WHERE LOWER(BTRIM(COALESCE(email, ''))) = LOWER(BTRIM(?))
                LIMIT 1
            ");
            $emailStmt->execute([$email]);
            if ($emailStmt->fetch()) {
                respondError('This email is already in use. Please use a different email address.', 409);
            }
        }
        $duplicateStmt = $pdo->prepare("
            SELECT 1 FROM applicants
            WHERE LOWER(REGEXP_REPLACE(BTRIM(COALESCE(name, '')), '[[:space:]]+', ' ', 'g'))
                = LOWER(REGEXP_REPLACE(BTRIM(?), '[[:space:]]+', ' ', 'g'))
            UNION ALL
            SELECT 1 FROM employees
            WHERE LOWER(REGEXP_REPLACE(BTRIM(COALESCE(name, '')), '[[:space:]]+', ' ', 'g'))
                = LOWER(REGEXP_REPLACE(BTRIM(?), '[[:space:]]+', ' ', 'g'))
            LIMIT 1
        ");
        $duplicateStmt->execute([$name, $name]);
        if ($duplicateStmt->fetch()) {
            respondError('A person with this full name already exists in Employee or Applicant records.', 409);
        }

        $extensions = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
        $photoExtensions = [];
        $resumeExtension = null;
        if (($uploadedFiles['id_photo'] && !$uploadedFiles['id_picture']) || (!$uploadedFiles['id_photo'] && $uploadedFiles['id_picture'])) {
            respondError('Upload both the identification document and 2x2 picture.', 400);
        }
        foreach ($uploadedFiles as $field => $uploadedFile) {
            if (!$uploadedFile) {
                continue;
            }
            if ($uploadedFile['error'] !== UPLOAD_ERR_OK || $uploadedFile['size'] > 5 * 1024 * 1024) {
                respondError($field === 'resume'
                    ? 'The resume must be a valid PDF no larger than 5 MB.'
                    : 'Each applicant image must be valid and no larger than 5 MB.', 400);
            }
            $mimeType = (new finfo(FILEINFO_MIME_TYPE))->file($uploadedFile['tmp_name']);
            if ($field === 'resume') {
                $resumeFile = fopen($uploadedFile['tmp_name'], 'rb');
                $resumeHeader = $resumeFile ? fread($resumeFile, 1024) : false;
                if ($resumeFile) fclose($resumeFile);
                if ($mimeType !== 'application/pdf' || $resumeHeader === false || strpos($resumeHeader, '%PDF-') === false) {
                    respondError('The resume must be a valid PDF file.', 415);
                }
                $resumeExtension = 'pdf';
                continue;
            }
            if (!isset($extensions[$mimeType])) respondError('Applicant images must be JPG, PNG, or WebP files.', 415);
            $photoExtensions[$field] = $extensions[$mimeType];
        }

        $appliedDate = $input['applied_date'] ?? date('Y-m-d');
        $GLOBALS['hrms_submission_stage'] = 'save_uploads';
        $photoDirectory = __DIR__ . '/applicant-id-photos';
        $savedPhotos = [];
        if ($photoExtensions || $resumeExtension !== null) {
            if (!is_dir($photoDirectory) && !mkdir($photoDirectory, 0700, true) && !is_dir($photoDirectory)) {
                respondError('Unable to save applicant images.', 500);
            }
            $filesToSave = $photoExtensions;
            $filesToSave['resume'] = $resumeExtension;
            foreach ($filesToSave as $field => $extension) {
                $filename = bin2hex(random_bytes(16)) . '.' . $extension;
                if (!move_uploaded_file($uploadedFiles[$field]['tmp_name'], $photoDirectory . '/' . $filename)) {
                    foreach ($savedPhotos as $savedPhoto) @unlink($photoDirectory . '/' . $savedPhoto);
                    respondError('Unable to save applicant images.', 500);
                }
                chmod($photoDirectory . '/' . $filename, 0600);
                $savedPhotos[$field] = $filename;
            }
        }

        try {
            $GLOBALS['hrms_submission_stage'] = 'insert_applicant';
            $stmt = $pdo->prepare("INSERT INTO applicants (name, surname, middle_name, first_name, position, department, email, phone, gender, address, date_of_birth, age, place_of_birth, tin, sss_number, pag_ibig_number, nbi_number, civil_status, emergency_contact, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path, sss_photo_path, pag_ibig_photo_path, nbi_photo_path, health_card_photo_path, psa_photo_path, applied_date, submission_key, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'New') RETURNING id");
            $stmt->execute([
                $name, $surname, $middleName, $firstName, $position,
                $input['department'] ?? 'General', $input['email'] ?? '', $normalizedPhone,
                $input['gender'] ?? '', $input['address'] ?? '', $input['date_of_birth'] ?? '',
                (int)($input['age'] ?? 0), $input['place_of_birth'] ?? '', $input['tin'] ?? '',
                trim((string)($input['sss_number'] ?? '')), trim((string)($input['pag_ibig_number'] ?? '')),
                trim((string)($input['nbi_number'] ?? '')),
                $input['civil_status'] ?? '', $input['emergency_contact'] ?? '',
                $input['emergency_contact_name'] ?? '', $normalizedEmergencyContactPhone,
                $savedPhotos['id_photo'] ?? null, $savedPhotos['id_picture'] ?? null, $savedPhotos['resume'] ?? null,
                $savedPhotos['sss_picture'] ?? null, $savedPhotos['pag_ibig_picture'] ?? null,
                $savedPhotos['nbi_picture'] ?? null, null,
                $savedPhotos['psa_picture'] ?? null,
                $appliedDate, $submissionKey !== '' ? $submissionKey : null
            ]);
            $applicantId = (int)$stmt->fetchColumn();
        } catch (Throwable $error) {
            foreach ($savedPhotos as $savedPhoto) @unlink($photoDirectory . '/' . $savedPhoto);
            if ($error instanceof PDOException && $error->getCode() === '23505') {
                if ($submissionKey !== '') {
                    $receipt->execute([$submissionKey]);
                    if ($receipt->fetchColumn()) {
                        respondJSON(['message' => 'Your application has already been received.', 'already_submitted' => true]);
                    }
                }
                if (isDuplicateApplicantSubmission($pdo, $email, $name, $normalizedPhone)) {
                    respondJSON(['message' => 'Your application has already been received.', 'already_submitted' => true]);
                }
                if (strpos((string)($error->errorInfo[2] ?? ''), 'applicants_email_unique_idx') !== false) {
                    respondError('This email is already in use. Please use a different email address.', 409);
                }
                if (strpos((string)($error->errorInfo[2] ?? ''), 'DUPLICATE_PERSON_NAME') !== false) {
                    respondError('A person with this full name already exists in Employee or Applicant records.', 409);
                }
                respondError('An applicant with the same email address or full name and phone number already exists.', 409);
            }
            throw $error;
        }

        $GLOBALS['hrms_submission_stage'] = 'saved';
        respondJSON(['id' => $applicantId, 'message' => 'Applicant added successfully.'], 201);
    }

    if (preg_match('#^applicants/(\d+)/hire$#', $route, $matches) && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $stmt = $pdo->prepare("SELECT a.* FROM applicants a WHERE a.id = ?" . hiddenUnhiredApplicantFilter($authUser));
        $stmt->execute([$id]);
        $app = $stmt->fetch();
        if (!$app) respondError("Applicant not found.", 404);
        if ($app['status'] === 'Rejected') respondError('Applicants marked as not qualified cannot be hired.', 409);

        $email = trim($app['email'] ?? '');
        if (!$email) {
            $slug = strtolower(preg_replace('/[^a-z0-9]+/', '', $app['name']));
            $email = ($slug ?: 'employee') . '@company.com';
        }

        $pdo->beginTransaction();
        try {
            $empCode = generateUniqueEmployeeCode($pdo);
            $applicantUpdate = $pdo->prepare("UPDATE applicants SET status = 'Hired', email = ? WHERE id = ?");
            $applicantUpdate->execute([$email, $id]);

            $stmtIns = $pdo->prepare("INSERT INTO employees (employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name, sss_number, pag_ibig_number, nbi_number, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path, sss_photo_path, pag_ibig_photo_path, nbi_photo_path, health_card_photo_path, psa_photo_path, applied_date) VALUES (?, ?, ?, ?, ?, 'Onboarding', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
            $stmtIns->execute([
                $empCode, $app['name'], $email,
                normalizeEmployeeDepartment($app['department'] ?? ''),
                $app['position'] ?? '',
                $app['phone'] ?? '',
                $app['address'] ?? '',
                $app['date_of_birth'] ?? '',
                $app['gender'] ?? '',
                $app['emergency_contact'] ?? '',
                (int)($app['age'] ?? 0),
                $app['place_of_birth'] ?? '',
                $app['tin'] ?? '',
                $app['civil_status'] ?? '',
                $app['surname'] ?? $app['last_name'] ?? '',
                $app['first_name'] ?? '',
                $app['middle_name'] ?? '',
                $app['sss_number'] ?? '', $app['pag_ibig_number'] ?? '', $app['nbi_number'] ?? '',
                $app['emergency_contact_name'] ?? '', $app['emergency_contact_phone'] ?? '',
                $app['id_photo_path'] ?? '', $app['id_picture_path'] ?? '', $app['resume_path'] ?? '',
                $app['sss_photo_path'] ?? '', $app['pag_ibig_photo_path'] ?? '', $app['nbi_photo_path'] ?? '',
                $app['health_card_photo_path'] ?? '', $app['psa_photo_path'] ?? '', $app['applied_date'] ?? ''
            ]);
            $empDbId = $pdo->lastInsertId();

            startOnboardingChecklist($pdo, $empDbId, $DEFAULT_ONBOARDING_TASKS);

            $stmtUser = $pdo->prepare("SELECT id FROM users WHERE email = ?");
            $stmtUser->execute([$email]);
            if (!$stmtUser->fetch()) {
                $temporaryPassword = generateTemporaryPassword();
                $defaultHash = hashPassword($temporaryPassword);
                $stmtAcc = $pdo->prepare("INSERT INTO users (email, password, role, name, position, department, employee_id) VALUES (?, ?, 'employee', ?, ?, ?, ?)");
                $stmtAcc->execute([$email, $defaultHash, $app['name'], $app['position'], normalizeEmployeeDepartment($app['department'] ?? ''), $empCode]);
            }

            $pdo->prepare("DELETE FROM applicants WHERE id = ?")->execute([$id]);
            $pdo->commit();
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $error;
        }

        respondJSON([
            'message' => "{$app['name']} hired successfully. Employee record, onboarding checklist, and portal login created.",
            'employee_id' => $empCode,
            'email' => $email,
            'temporary_password' => $temporaryPassword ?? null
        ]);
    }

    if (preg_match('#^applicants/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $deleteSql = "DELETE FROM applicants AS a WHERE a.id = ?" . hiddenUnhiredApplicantFilter($authUser);
        $deleteStmt = $pdo->prepare($deleteSql);
        $deleteStmt->execute([$id]);
        if ($deleteStmt->rowCount() !== 1) respondError('Applicant not found.', 404);
        respondJSON(['message' => 'Applicant deleted.']);
    }

    // --------------------------------------------------------
    // 6. INTERVIEW ROUTES (Admin Only)
    // --------------------------------------------------------
    if ($route === 'interviews' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $stmt = $pdo->query("SELECT i.*, a.name AS applicant_name, a.position AS applicant_position
            FROM interviews i JOIN applicants a ON a.id = i.applicant_id
            WHERE a.status NOT IN ('Rejected', 'Hired')
            " . hiddenUnhiredApplicantFilter($authUser) . "
            ORDER BY i.scheduled_at DESC, i.id DESC");
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'interviews' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $applicantId = (int)($input['applicant_id'] ?? 0);
        $scheduledInput = trim($input['scheduled_at'] ?? '');
        $interviewer = trim($input['interviewer'] ?? '');
        $scheduledAt = DateTime::createFromFormat('Y-m-d\\TH:i', $scheduledInput);
        $dateErrors = DateTime::getLastErrors();
        if (!$applicantId || !$scheduledAt || !$interviewer || ($dateErrors && ($dateErrors['warning_count'] || $dateErrors['error_count']))) {
            respondError('Candidate, valid interview date and time, and interviewer are required.', 400);
        }

        $stmtApplicant = $pdo->prepare("SELECT a.id, a.name, a.position, a.email FROM applicants a WHERE a.id = ? AND a.status <> 'Rejected'" . hiddenUnhiredApplicantFilter($authUser));
        $stmtApplicant->execute([$applicantId]);
        $applicant = $stmtApplicant->fetch();
        if (!$applicant) respondError('Applicant not found or is marked as not qualified.', 404);
        $applicantEmail = trim((string)($applicant['email'] ?? ''));
        if (!filter_var($applicantEmail, FILTER_VALIDATE_EMAIL)) {
            respondError('The applicant does not have a valid email address on their application. Update the application email before scheduling.', 400);
        }

        $location = trim($input['location'] ?? '');
        $notes = trim($input['notes'] ?? '');
        $scheduledAtValue = $scheduledAt->format('Y-m-d H:i:s');
        $pdo->beginTransaction();
        try {
            $stmt = $pdo->prepare("INSERT INTO interviews (applicant_id, scheduled_at, interviewer, location, notes)
                VALUES (?, ?, ?, ?, ?) RETURNING id");
            $stmt->execute([$applicantId, $scheduledAtValue, $interviewer, $location, $notes]);
            $interviewId = (int)$stmt->fetchColumn();

            require_once __DIR__ . '/mailer.php';
            sendInterviewScheduledEmail($applicantEmail, [
                'applicant_name' => $applicant['name'],
                'position' => $applicant['position'] ?? '',
                'interview_date' => $scheduledAt->format('l, F j, Y'),
                'interview_time' => $scheduledAt->format('g:i A'),
                'interviewer' => $interviewer,
                'location' => $location,
                'notes' => $notes
            ]);
            $pdo->commit();
        } catch (Throwable $mailError) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            error_log('Interview scheduling or email delivery failed: ' . $mailError->getMessage());
            respondError('The interview could not be scheduled because its notification email was not sent. Check the mail settings and try again.', 503);
        }

        respondJSON([
            'id' => $interviewId,
            'email_sent' => true,
            'message' => 'Interview scheduled and all details emailed to the applicant.'
        ], 201);
    }

    if (preg_match('#^interviews/(\\d+)$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $status = trim($input['status'] ?? '');
        $allowedStatuses = ['Completed', 'Did Not Pass the Interview', 'No Show'];
        if (!in_array($status, $allowedStatuses, true)) respondError('Invalid interview status.', 400);
        $pdo->beginTransaction();
        try {
            $interviewStmt = $pdo->prepare("
                SELECT i.applicant_id, a.*
                FROM interviews i
                JOIN applicants a ON a.id = i.applicant_id
                WHERE i.id = ?
                " . hiddenUnhiredApplicantFilter($authUser) . "
                FOR UPDATE OF i, a
            ");
            $interviewStmt->execute([(int)$matches[1]]);
            $applicant = $interviewStmt->fetch();
            if (!$applicant) {
                $pdo->rollBack();
                respondError('Interview not found.', 404);
            }

            if ($status === 'Completed' && $applicant['status'] === 'Rejected') {
                $pdo->rollBack();
                respondError('Applicants marked as not qualified cannot be moved to onboarding.', 409);
            }

            $stmt = $pdo->prepare('UPDATE interviews SET status = ? WHERE id = ?');
            $stmt->execute([$status, (int)$matches[1]]);

            $onboardingResult = null;
            if ($status === 'Completed' && $applicant['status'] !== 'Hired') {
                $email = trim((string)($applicant['email'] ?? ''));
                if ($email === '') {
                    $slug = strtolower(preg_replace('/[^a-z0-9]+/', '', $applicant['name']));
                    $baseEmail = ($slug ?: 'employee') . '@company.com';
                    $email = $baseEmail;
                    $suffix = 1;
                    while (true) {
                        $emailCheck = $pdo->prepare('SELECT 1 FROM employees WHERE LOWER(email) = LOWER(?) UNION ALL SELECT 1 FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1');
                        $emailCheck->execute([$email, $email]);
                        if (!$emailCheck->fetch()) break;
                        $email = $suffix++ . '.' . $baseEmail;
                    }
                }

                $markHired = $pdo->prepare("UPDATE applicants SET status = 'Hired', email = ? WHERE id = ?");
                $markHired->execute([$email, (int)$applicant['applicant_id']]);

                $employeeStmt = $pdo->prepare('SELECT id, employee_id FROM employees WHERE LOWER(email) = LOWER(?) LIMIT 1 FOR UPDATE');
                $employeeStmt->execute([$email]);
                $employee = $employeeStmt->fetch();

                if (!$employee) {
                    $employeeCode = generateUniqueEmployeeCode($pdo);

                    $employeeInsert = $pdo->prepare("INSERT INTO employees (employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name, sss_number, pag_ibig_number, nbi_number, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path, sss_photo_path, pag_ibig_photo_path, nbi_photo_path, health_card_photo_path, psa_photo_path, applied_date)
                        VALUES (?, ?, ?, ?, ?, 'Onboarding', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id");
                    $employeeInsert->execute([
                        $employeeCode, $applicant['name'], $email,
                        normalizeEmployeeDepartment($applicant['department'] ?? ''),
                        $applicant['position'] ?? '',
                        $applicant['phone'] ?? '',
                        $applicant['address'] ?? '',
                        $applicant['date_of_birth'] ?? '',
                        $applicant['gender'] ?? '',
                        $applicant['emergency_contact'] ?? '',
                        (int)($applicant['age'] ?? 0),
                        $applicant['place_of_birth'] ?? '',
                        $applicant['tin'] ?? '',
                        $applicant['civil_status'] ?? '',
                        $applicant['surname'] ?? '',
                        $applicant['first_name'] ?? '',
                        $applicant['middle_name'] ?? '',
                        $applicant['sss_number'] ?? '', $applicant['pag_ibig_number'] ?? '', $applicant['nbi_number'] ?? '',
                        $applicant['emergency_contact_name'] ?? '', $applicant['emergency_contact_phone'] ?? '',
                        $applicant['id_photo_path'] ?? '', $applicant['id_picture_path'] ?? '', $applicant['resume_path'] ?? '',
                        $applicant['sss_photo_path'] ?? '', $applicant['pag_ibig_photo_path'] ?? '', $applicant['nbi_photo_path'] ?? '',
                        $applicant['health_card_photo_path'] ?? '', $applicant['psa_photo_path'] ?? '', $applicant['applied_date'] ?? ''
                    ]);
                    $employee = ['id' => $employeeInsert->fetchColumn(), 'employee_id' => $employeeCode];
                } else {
                    $employeeUpdate = $pdo->prepare("
                        UPDATE employees SET
                            status = 'Onboarding',
                            name = COALESCE(NULLIF(?, ''), name),
                            department = COALESCE(NULLIF(?, ''), department),
                            role = COALESCE(NULLIF(?, ''), role),
                            phone = COALESCE(NULLIF(?, ''), phone),
                            address = COALESCE(NULLIF(?, ''), address),
                            date_of_birth = COALESCE(NULLIF(?, ''), date_of_birth),
                            gender = COALESCE(NULLIF(?, ''), gender),
                            emergency_contact = COALESCE(NULLIF(?, ''), emergency_contact),
                            age = CASE WHEN ? > 0 THEN ? ELSE age END,
                            place_of_birth = COALESCE(NULLIF(?, ''), place_of_birth),
                            tin = COALESCE(NULLIF(?, ''), tin),
                            civil_status = COALESCE(NULLIF(?, ''), civil_status),
                            last_name = COALESCE(NULLIF(?, ''), last_name),
                            first_name = COALESCE(NULLIF(?, ''), first_name),
                            middle_name = COALESCE(NULLIF(?, ''), middle_name),
                            sss_number = COALESCE(NULLIF(?, ''), sss_number),
                            pag_ibig_number = COALESCE(NULLIF(?, ''), pag_ibig_number),
                            nbi_number = COALESCE(NULLIF(?, ''), nbi_number),
                            emergency_contact_name = COALESCE(NULLIF(?, ''), emergency_contact_name),
                            emergency_contact_phone = COALESCE(NULLIF(?, ''), emergency_contact_phone),
                            id_photo_path = COALESCE(NULLIF(?, ''), id_photo_path),
                            id_picture_path = COALESCE(NULLIF(?, ''), id_picture_path),
                            resume_path = COALESCE(NULLIF(?, ''), resume_path),
                            sss_photo_path = COALESCE(NULLIF(?, ''), sss_photo_path),
                            pag_ibig_photo_path = COALESCE(NULLIF(?, ''), pag_ibig_photo_path),
                            nbi_photo_path = COALESCE(NULLIF(?, ''), nbi_photo_path),
                            health_card_photo_path = COALESCE(NULLIF(?, ''), health_card_photo_path),
                            psa_photo_path = COALESCE(NULLIF(?, ''), psa_photo_path),
                            applied_date = COALESCE(NULLIF(?, ''), applied_date)
                        WHERE id = ?
                    ");
                    $employeeUpdate->execute([
                        $applicant['name'] ?? '', $applicant['department'] ?? '', $applicant['position'] ?? '',
                        $applicant['phone'] ?? '', $applicant['address'] ?? '', $applicant['date_of_birth'] ?? '',
                        $applicant['gender'] ?? '', $applicant['emergency_contact'] ?? '',
                        (int)($applicant['age'] ?? 0), (int)($applicant['age'] ?? 0),
                        $applicant['place_of_birth'] ?? '', $applicant['tin'] ?? '', $applicant['civil_status'] ?? '',
                        $applicant['surname'] ?? '', $applicant['first_name'] ?? '', $applicant['middle_name'] ?? '',
                        $applicant['sss_number'] ?? '', $applicant['pag_ibig_number'] ?? '', $applicant['nbi_number'] ?? '',
                        $applicant['emergency_contact_name'] ?? '', $applicant['emergency_contact_phone'] ?? '',
                        $applicant['id_photo_path'] ?? '', $applicant['id_picture_path'] ?? '', $applicant['resume_path'] ?? '',
                        $applicant['sss_photo_path'] ?? '', $applicant['pag_ibig_photo_path'] ?? '', $applicant['nbi_photo_path'] ?? '',
                        $applicant['health_card_photo_path'] ?? '', $applicant['psa_photo_path'] ?? '', $applicant['applied_date'] ?? '',
                        $employee['id']
                    ]);
                }

                startOnboardingChecklist($pdo, $employee['id'], $DEFAULT_ONBOARDING_TASKS);

                $userStmt = $pdo->prepare('SELECT id FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1');
                $userStmt->execute([$email]);
                if (!$userStmt->fetch()) {
                    $temporaryPassword = generateTemporaryPassword();
                    $userInsert = $pdo->prepare("INSERT INTO users (email, password, role, name, position, department, employee_id)
                        VALUES (?, ?, 'employee', ?, ?, ?, ?)");
                    $userInsert->execute([
                        $email,
                        hashPassword($temporaryPassword),
                        $applicant['name'],
                        $applicant['position'] ?? '',
                        normalizeEmployeeDepartment($applicant['department'] ?? ''),
                        $employee['employee_id']
                    ]);
                }

                $onboardingResult = [
                    'employee_id' => $employee['employee_id'],
                    'email' => $email,
                    'temporary_password' => $temporaryPassword ?? null
                ];
            }

            $pdo->commit();
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $error;
        }

        respondJSON([
            'message' => $onboardingResult
                ? 'Interview completed. Applicant moved to onboarding.'
                : 'Interview status updated.',
            'onboarding' => $onboardingResult
        ]);
    }

    // --------------------------------------------------------
    // 7. ANNOUNCEMENT ROUTES
    // --------------------------------------------------------
    if ($route === 'announcements/mine' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $userId = $authUser['id'];

        $stmt = $pdo->prepare("
            SELECT a.*, (CASE WHEN ar.id IS NULL THEN 0 ELSE 1 END) AS is_read
            FROM announcements a
            LEFT JOIN announcement_reads ar ON ar.announcement_id = a.id AND ar.user_id = ?
            ORDER BY a.id DESC
        ");
        $stmt->execute([$userId]);
        $announcements = $stmt->fetchAll();

        $stmtUnread = $pdo->prepare("
            SELECT COUNT(*) as count FROM announcements a
            LEFT JOIN announcement_reads ar ON ar.announcement_id = a.id AND ar.user_id = ?
            WHERE ar.id IS NULL
        ");
        $stmtUnread->execute([$userId]);
        $unreadCount = (int)$stmtUnread->fetch()['count'];

        respondJSON(['announcements' => $announcements, 'unread_count' => $unreadCount]);
    }

    if (preg_match('#^announcements/(\d+)/read$#', $route, $matches) && $requestMethod === 'POST') {
        $authUser = requireAuth();
        $userId = $authUser['id'];
        $annId = (int)$matches[1];

        // Insert ignore
        $stmt = $pdo->prepare("SELECT id FROM announcement_reads WHERE user_id = ? AND announcement_id = ?");
        $stmt->execute([$userId, $annId]);
        if (!$stmt->fetch()) {
            $pdo->prepare("INSERT INTO announcement_reads (user_id, announcement_id) VALUES (?, ?)")->execute([$userId, $annId]);
        }

        $stmtUnread = $pdo->prepare("
            SELECT COUNT(*) as count FROM announcements a
            LEFT JOIN announcement_reads ar ON ar.announcement_id = a.id AND ar.user_id = ?
            WHERE ar.id IS NULL
        ");
        $stmtUnread->execute([$userId]);
        respondJSON(['message' => 'Announcement marked as read.', 'unread_count' => (int)$stmtUnread->fetch()['count']]);
    }

    if ($route === 'announcements' && $requestMethod === 'GET') {
        $stmt = $pdo->query("SELECT * FROM announcements ORDER BY id DESC");
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'announcements' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $title = trim($input['title'] ?? '');
        $content = trim($input['content'] ?? '');
        if (!$title || !$content) respondError("title and content are required.", 400);

        $stmt = $pdo->prepare("INSERT INTO announcements (title, content, author) VALUES (?, ?, ?)");
        $stmt->execute([$title, $content, $authUser['name'] ?? 'HR']);

        respondJSON(['id' => (int)$pdo->lastInsertId(), 'message' => 'Announcement published.'], 201);
    }

    if (preg_match('#^announcements/(\d+)$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $title = trim($input['title'] ?? '');
        $content = trim($input['content'] ?? '');
        if (!$title || !$content) respondError("title and content are required.", 400);

        $stmt = $pdo->prepare("UPDATE announcements SET title = ?, content = ? WHERE id = ?");
        $stmt->execute([$title, $content, $id]);
        if ($stmt->rowCount() !== 1) respondError("Announcement not found or was not updated.", 404);

        $stmt = $pdo->prepare("SELECT * FROM announcements WHERE id = ?");
        $stmt->execute([$id]);
        respondJSON(['message' => 'Announcement updated successfully.', 'announcement' => $stmt->fetch()]);
    }

    if (preg_match('#^announcements/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $pdo->prepare("DELETE FROM announcement_reads WHERE announcement_id = ?")->execute([$id]);
        $stmt = $pdo->prepare("DELETE FROM announcements WHERE id = ?");
        $stmt->execute([$id]);
        if ($stmt->rowCount() !== 1) respondError("Announcement not found.", 404);
        respondJSON(['message' => 'Announcement deleted.']);
    }

    // --------------------------------------------------------
    // 7. ONBOARDING ROUTES
    // --------------------------------------------------------
    if ($route === 'onboarding' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        ensureContractSignedPhotoColumn($pdo);

        if (isHrDashboardUser($authUser)) {
            $visibleEmployeeFilter = isRestrictedHrAccount($authUser) ? " AND COALESCE(e.status, '') <> 'Unhired'" : '';
            $pdo->exec("
                INSERT INTO onboarding_tasks (employee_id, task, status, due_date)
                SELECT e.id, 'Health Card Picture', 'Pending', CURRENT_DATE
                FROM employees e
                WHERE e.status = 'Onboarding'
                  AND EXISTS (
                      SELECT 1 FROM onboarding_tasks existing_task
                      WHERE existing_task.employee_id = e.id
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM onboarding_tasks health_card_task
                      WHERE health_card_task.employee_id = e.id
                        AND LOWER(BTRIM(health_card_task.task)) = LOWER('Health Card Picture')
                  )
                  " . ($visibleEmployeeFilter !== '' ? "AND COALESCE(e.status, '') <> 'Unhired'" : '') . "
            ");
            $pdo->exec("
                UPDATE onboarding_tasks AS ot
                SET status = 'Completed'
                FROM employees AS e
                WHERE ot.employee_id = e.id
                  AND LOWER(ot.task) = LOWER('Contract Signed')
                  AND ot.status <> 'Completed'
                  AND NULLIF(e.contract_signed_photo_path, '') IS NOT NULL
                  " . ($visibleEmployeeFilter !== '' ? "AND COALESCE(e.status, '') <> 'Unhired'" : '') . "
            ");
            $pdo->exec("
                UPDATE onboarding_tasks AS ot
                SET status = 'Completed'
                FROM employees AS e
                WHERE ot.employee_id = e.id
                  AND LOWER(BTRIM(ot.task)) = LOWER('Health Card Picture')
                  AND ot.status <> 'Completed'
                  AND NULLIF(e.health_card_photo_path, '') IS NOT NULL
                  " . ($visibleEmployeeFilter !== '' ? "AND COALESCE(e.status, '') <> 'Unhired'" : '') . "
            ");
            $stmt = $pdo->query("
                SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code, e.department AS emp_department, e.role AS emp_role,
                       e.contract_signed_photo_path, e.health_card_photo_path
                FROM onboarding_tasks ot
                JOIN employees e ON ot.employee_id = e.id
                WHERE ot.task NOT IN (
                    'Email & Account Created',
                    'IT Assets Assigned (Laptop, Peripherals)',
                    'Company ID / Access Badge Issued',
                    'Department Introductions & Buddy Assigned'
                )
                {$visibleEmployeeFilter}
                ORDER BY ot.employee_id, ot.id ASC
            ");
            $rows = $stmt->fetchAll();

            $byEmployee = [];
            foreach ($rows as $r) {
                $empId = $r['employee_id'];
                if (!isset($byEmployee[$empId])) {
                    $byEmployee[$empId] = ['empInfo' => $r, 'tasks' => []];
                }
                $byEmployee[$empId]['tasks'][] = $r;
            }

            $summary = [];
            foreach ($byEmployee as $grp) {
                $total = count($grp['tasks']);
                $completed = count(array_filter($grp['tasks'], fn($t) => $t['status'] === 'Completed'));
                $progress = $total ? (int)round(($completed / $total) * 100) : 0;
                $summary[] = array_merge($grp['empInfo'], [
                    'task_count' => $total,
                    'completed_count' => $completed,
                    'progress' => $progress,
                    'tasks' => $grp['tasks']
                ]);
            }

            $activeCnt = count($summary);
            $totalTasks = count($rows);
            $avgProgress = $activeCnt ? (int)round(array_sum(array_column($summary, 'progress')) / $activeCnt) : 0;

            respondJSON([
                'scope' => 'admin',
                'summary' => $summary,
                'stats' => [
                    'activeOnboardings' => $activeCnt,
                    'totalTasks' => $totalTasks,
                    'averageProgress' => $avgProgress
                ]
            ]);
        } else {
            // Employee View
            $code = $authUser['employee_id'] ?? '';
            if ($code) {
                $stmtEmp = $pdo->prepare("SELECT * FROM employees WHERE employee_id = ?");
                $stmtEmp->execute([$code]);
                $empRow = $stmtEmp->fetch();

                if (!$empRow && !empty($authUser['email'])) {
                    $stmtEmail = $pdo->prepare("SELECT * FROM employees WHERE email = ?");
                    $stmtEmail->execute([$authUser['email']]);
                    $empRow = $stmtEmail->fetch();
                }

                if (!$empRow) {
                    $stmtIns = $pdo->prepare("INSERT INTO employees (employee_id, name, email, department, role, status) VALUES (?, ?, ?, ?, ?, 'Onboarding')");
                    $stmtIns->execute([$code, $authUser['name'] ?? 'Employee', $authUser['email'] ?? '', normalizeEmployeeDepartment($authUser['department'] ?? ''), $authUser['position'] ?? '']);
                    $empDbId = $pdo->lastInsertId();
                    startOnboardingChecklist($pdo, $empDbId, $DEFAULT_ONBOARDING_TASKS);
                } else {
                    startOnboardingChecklist($pdo, $empRow['id'], $DEFAULT_ONBOARDING_TASKS);
                }

                $stmtTasks = $pdo->prepare("
                    SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code
                    FROM onboarding_tasks ot
                    JOIN employees e ON ot.employee_id = e.id
                    WHERE e.employee_id = ?
                    ORDER BY ot.id ASC
                ");
                $stmtTasks->execute([$code]);
                $tasks = $stmtTasks->fetchAll();

                $total = count($tasks);
                $completed = count(array_filter($tasks, fn($t) => $t['status'] === 'Completed'));
                $progress = $total ? (int)round(($completed / $total) * 100) : 0;

                respondJSON([
                    'scope' => 'employee',
                    'checklist' => $tasks,
                    'total' => $total,
                    'completed' => $completed,
                    'progress' => $progress
                ]);
            } else {
                respondJSON(['scope' => 'employee', 'checklist' => [], 'total' => 0, 'completed' => 0, 'progress' => 0]);
            }
        }
    }

    if (preg_match('#^onboarding/employees/([^/]+)/start$#', $route, $matches) && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $code = $matches[1];

        $employeeSql = "SELECT * FROM employees WHERE employee_id = ?";
        if (isRestrictedHrAccount($authUser)) {
            $employeeSql .= " AND COALESCE(status, '') <> 'Unhired'";
        }
        $stmt = $pdo->prepare($employeeSql);
        $stmt->execute([$code]);
        $emp = $stmt->fetch();
        if (!$emp) respondError("Employee not found.", 404);

        $res = startOnboardingChecklist($pdo, $emp['id'], $DEFAULT_ONBOARDING_TASKS);
        if (isset($res['already_started'])) {
            respondJSON(['message' => 'Onboarding checklist already started for this employee.', 'already_started' => true]);
        }
        respondJSON(['message' => 'Onboarding checklist started.', 'created' => $res['created'], 'employee' => $emp], 201);
    }

    if ($route === 'onboarding' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $empDbId = (int)($input['employee_id'] ?? 0);
        $task = trim($input['task'] ?? '');
        if (!$empDbId || !$task) respondError("employee_id and task are required.", 400);

        if (isRestrictedHrAccount($authUser)) {
            $employeeCheck = $pdo->prepare("SELECT 1 FROM employees WHERE id = ? AND status = 'Unhired'");
            $employeeCheck->execute([$empDbId]);
            if ($employeeCheck->fetchColumn()) respondError('Employee not found.', 404);
        }

        $stmt = $pdo->prepare("INSERT INTO onboarding_tasks (employee_id, task, status, due_date) VALUES (?, ?, ?, ?)");
        $stmt->execute([$empDbId, $task, $input['status'] ?? 'Pending', $input['due_date'] ?? '']);
        $taskId = $pdo->lastInsertId();

        $stmtTask = $pdo->prepare("SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code FROM onboarding_tasks ot JOIN employees e ON ot.employee_id = e.id WHERE ot.id = ?");
        $stmtTask->execute([$taskId]);

        respondJSON(['message' => 'Onboarding task added.', 'task' => $stmtTask->fetch()], 201);
    }

    if (preg_match('#^onboarding/(\d+)/contract-signed-photo$#', $route, $matches) && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        ensureContractSignedPhotoColumn($pdo);
        $taskId = (int)$matches[1];

        $taskSql = "
            SELECT ot.id AS task_id, ot.employee_id, e.status AS employee_status, e.contract_signed_photo_path
            FROM onboarding_tasks ot
            JOIN employees e ON e.id = ot.employee_id
            WHERE ot.id = ?
              AND LOWER(BTRIM(ot.task)) = LOWER('Contract Signed')
        ";
        if (isRestrictedHrAccount($authUser)) {
            $taskSql .= " AND COALESCE(e.status, '') <> 'Unhired'";
        }
        $taskStmt = $pdo->prepare($taskSql);
        $taskStmt->execute([$taskId]);
        $taskRow = $taskStmt->fetch();
        if (!$taskRow) respondError('Contract Signed onboarding task not found.', 404);

        if (empty($_FILES['file']) || !isset($_FILES['file']['tmp_name']) || $_FILES['file']['tmp_name'] === '') {
            respondError('A signed contract picture file is required.', 400);
        }
        $uploadedFile = $_FILES['file'];
        if ($uploadedFile['error'] !== UPLOAD_ERR_OK) {
            respondError('The signed contract picture could not be processed. Please try another file.', 400);
        }
        if ($uploadedFile['size'] > 5 * 1024 * 1024) {
            respondError('The signed contract picture must be 5 MB or smaller.', 400);
        }

        $mimeType = (new finfo(FILEINFO_MIME_TYPE))->file($uploadedFile['tmp_name']);
        $allowedTypes = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
        if (!isset($allowedTypes[$mimeType]) || !getimagesize($uploadedFile['tmp_name'])) {
            respondError('Only valid JPG, PNG, and WebP signed contract pictures are accepted.', 415);
        }

        $photoDirectory = __DIR__ . '/applicant-id-photos';
        if (!is_dir($photoDirectory) && !mkdir($photoDirectory, 0700, true) && !is_dir($photoDirectory)) {
            respondError('Unable to save the signed contract picture.', 500);
        }

        $employeeId = (int)$taskRow['employee_id'];
        $filename = 'employee-' . $employeeId . '-contract-' . bin2hex(random_bytes(12)) . '.' . $allowedTypes[$mimeType];
        $targetPath = $photoDirectory . '/' . $filename;
        if (!move_uploaded_file($uploadedFile['tmp_name'], $targetPath)) {
            respondError('Unable to save the signed contract picture.', 500);
        }
        chmod($targetPath, 0600);

        try {
            $pdo->beginTransaction();
            $updateEmployee = $pdo->prepare('UPDATE employees SET contract_signed_photo_path = ? WHERE id = ?');
            $updateEmployee->execute([$filename, $employeeId]);
            if ($updateEmployee->rowCount() !== 1) {
                throw new RuntimeException('Employee signed contract picture was not updated.');
            }

            $pdo->prepare("UPDATE onboarding_tasks SET status = 'Completed' WHERE id = ?")->execute([$taskId]);
            $remainingTasks = $pdo->prepare("SELECT COUNT(*) FROM onboarding_tasks WHERE employee_id = ? AND status <> 'Completed'");
            $remainingTasks->execute([$employeeId]);
            if ((int)$remainingTasks->fetchColumn() === 0) {
                $pdo->prepare("UPDATE employees SET status = 'Active' WHERE id = ? AND status = 'Onboarding'")->execute([$employeeId]);
            }
            $pdo->commit();
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            @unlink($targetPath);
            throw $error;
        }

        if (!empty($taskRow['contract_signed_photo_path'])) {
            $existingPath = $photoDirectory . '/' . basename($taskRow['contract_signed_photo_path']);
            $existingReference = $pdo->prepare('SELECT 1 FROM employees WHERE contract_signed_photo_path = ? LIMIT 1');
            $existingReference->execute([$taskRow['contract_signed_photo_path']]);
            if (!$existingReference->fetchColumn() && is_file($existingPath)) {
                @unlink($existingPath);
            }
        }

        respondJSON([
            'message' => 'Signed contract picture uploaded and saved to the employee profile.',
            'photo_path' => $filename,
            'employee_id' => $employeeId,
            'task_id' => $taskId
        ]);
    }

    if (preg_match('#^onboarding/(\d+)/health-card-photo$#', $route, $matches) && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $taskId = (int)$matches[1];

        $taskSql = "
            SELECT ot.id AS task_id, ot.employee_id, e.status AS employee_status, e.health_card_photo_path
            FROM onboarding_tasks ot
            JOIN employees e ON e.id = ot.employee_id
            WHERE ot.id = ?
              AND LOWER(BTRIM(ot.task)) = LOWER('Health Card Picture')
        ";
        if (isRestrictedHrAccount($authUser)) {
            $taskSql .= " AND COALESCE(e.status, '') <> 'Unhired'";
        }
        $taskStmt = $pdo->prepare($taskSql);
        $taskStmt->execute([$taskId]);
        $taskRow = $taskStmt->fetch();
        if (!$taskRow) respondError('Health Card Picture onboarding task not found.', 404);

        if (empty($_FILES['file']) || !isset($_FILES['file']['tmp_name']) || $_FILES['file']['tmp_name'] === '') {
            respondError('A health card picture file is required.', 400);
        }
        $uploadedFile = $_FILES['file'];
        if ($uploadedFile['error'] !== UPLOAD_ERR_OK) {
            respondError('The health card picture could not be processed. Please try another file.', 400);
        }
        if ($uploadedFile['size'] > 5 * 1024 * 1024) {
            respondError('The health card picture must be 5 MB or smaller.', 400);
        }

        $mimeType = (new finfo(FILEINFO_MIME_TYPE))->file($uploadedFile['tmp_name']);
        $allowedTypes = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
        if (!isset($allowedTypes[$mimeType]) || !getimagesize($uploadedFile['tmp_name'])) {
            respondError('Only valid JPG, PNG, and WebP health card pictures are accepted.', 415);
        }

        $photoDirectory = __DIR__ . '/applicant-id-photos';
        if (!is_dir($photoDirectory) && !mkdir($photoDirectory, 0700, true) && !is_dir($photoDirectory)) {
            respondError('Unable to save the health card picture.', 500);
        }

        $employeeId = (int)$taskRow['employee_id'];
        $filename = 'employee-' . $employeeId . '-health-card-' . bin2hex(random_bytes(12)) . '.' . $allowedTypes[$mimeType];
        $targetPath = $photoDirectory . '/' . $filename;
        if (!move_uploaded_file($uploadedFile['tmp_name'], $targetPath)) {
            respondError('Unable to save the health card picture.', 500);
        }
        chmod($targetPath, 0600);

        try {
            $pdo->beginTransaction();
            $updateEmployee = $pdo->prepare('UPDATE employees SET health_card_photo_path = ? WHERE id = ?');
            $updateEmployee->execute([$filename, $employeeId]);
            if ($updateEmployee->rowCount() !== 1) {
                throw new RuntimeException('Employee health card picture was not updated.');
            }

            $pdo->prepare("UPDATE onboarding_tasks SET status = 'Completed' WHERE id = ?")->execute([$taskId]);
            $remainingTasks = $pdo->prepare("SELECT COUNT(*) FROM onboarding_tasks WHERE employee_id = ? AND status <> 'Completed'");
            $remainingTasks->execute([$employeeId]);
            if ((int)$remainingTasks->fetchColumn() === 0) {
                $pdo->prepare("UPDATE employees SET status = 'Active' WHERE id = ? AND status = 'Onboarding'")->execute([$employeeId]);
            }
            $pdo->commit();
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            @unlink($targetPath);
            throw $error;
        }

        if (!empty($taskRow['health_card_photo_path'])) {
            $existingPath = $photoDirectory . '/' . basename($taskRow['health_card_photo_path']);
            $existingReference = $pdo->prepare("
                SELECT 1 FROM applicants WHERE health_card_photo_path = ?
                UNION ALL
                SELECT 1 FROM employees WHERE health_card_photo_path = ?
                LIMIT 1
            ");
            $existingReference->execute([$taskRow['health_card_photo_path'], $taskRow['health_card_photo_path']]);
            if (!$existingReference->fetchColumn() && is_file($existingPath)) {
                @unlink($existingPath);
            }
        }

        respondJSON([
            'message' => 'Health card picture uploaded and saved to the employee profile.',
            'photo_path' => $filename,
            'employee_id' => $employeeId,
            'task_id' => $taskId
        ]);
    }

    if (preg_match('#^onboarding/(\d+)$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $taskSql = "
            SELECT ot.*, e.status AS employee_status
            FROM onboarding_tasks ot
            JOIN employees e ON e.id = ot.employee_id
            WHERE ot.id = ?
        ";
        if (isRestrictedHrAccount($authUser)) {
            $taskSql .= " AND COALESCE(e.status, '') <> 'Unhired'";
        }
        $stmtCur = $pdo->prepare($taskSql);
        $stmtCur->execute([$id]);
        $taskRow = $stmtCur->fetch();
        if (!$taskRow) respondError("Onboarding task not found.", 404);

        $task = $input['task'] ?? $taskRow['task'];
        $status = $input['status'] ?? $taskRow['status'];
        $dueDate = $input['due_date'] ?? $taskRow['due_date'];

        $stmt = $pdo->prepare("UPDATE onboarding_tasks SET task = ?, status = ?, due_date = ? WHERE id = ?");
        $stmt->execute([$task, $status, $dueDate, $id]);

        // Interconnect: flip status to Active if all tasks completed
        $empId = $taskRow['employee_id'];
        $stmtRem = $pdo->prepare("SELECT COUNT(*) as cnt FROM onboarding_tasks WHERE employee_id = ? AND status != 'Completed'");
        $stmtRem->execute([$empId]);
        if ($stmtRem->fetch()['cnt'] == 0) {
            $pdo->prepare("UPDATE employees SET status = 'Active' WHERE id = ? AND status = 'Onboarding'")->execute([$empId]);
        }

        $stmtTask = $pdo->prepare("SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code FROM onboarding_tasks ot JOIN employees e ON ot.employee_id = e.id WHERE ot.id = ?" . (isRestrictedHrAccount($authUser) ? " AND COALESCE(e.status, '') <> 'Unhired'" : ''));
        $stmtTask->execute([$id]);
        respondJSON(['message' => 'Onboarding task updated.', 'task' => $stmtTask->fetch()]);
    }

    if (preg_match('#^onboarding/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        if (isRestrictedHrAccount($authUser)) {
            $taskCheck = $pdo->prepare("SELECT 1 FROM onboarding_tasks ot JOIN employees e ON e.id = ot.employee_id WHERE ot.id = ? AND e.status = 'Unhired'");
            $taskCheck->execute([$id]);
            if ($taskCheck->fetchColumn()) respondError('Onboarding task not found.', 404);
        }
        $pdo->prepare("DELETE FROM onboarding_tasks WHERE id = ?")->execute([$id]);
        respondJSON(['message' => 'Onboarding task deleted.']);
    }

    // --------------------------------------------------------
    // 8. DASHBOARD STATS ROUTE
    // --------------------------------------------------------
    if ($route === 'dashboard/stats' && $requestMethod === 'GET') {
        $authUser = requireAuth();

        $visibleEmployeeFilter = isRestrictedHrAccount($authUser) ? " AND COALESCE(status, '') <> 'Unhired'" : '';
        $visibleAliasedEmployeeFilter = isRestrictedHrAccount($authUser) ? " AND COALESCE(e.status, '') <> 'Unhired'" : '';
        $totalEmp = (int)$pdo->query("SELECT COUNT(*) as cnt FROM employees WHERE TRUE{$visibleEmployeeFilter}")->fetch()['cnt'];
        $employeeDirectoryCount = (int)$pdo->query("
            SELECT COUNT(*) as cnt
            FROM employees
            WHERE COALESCE(role, '') <> 'admin'
              AND COALESCE(email, '') <> 'phnhes@gmail.com'
              AND COALESCE(employee_id, '') NOT IN ('ADMIN001', 'ADMIN002')
              {$visibleEmployeeFilter}
        ")->fetch()['cnt'];
        $totalApps = (int)$pdo->query("
            SELECT COUNT(*) as cnt
            FROM applicants a
            WHERE a.status NOT IN ('Rejected', 'Hired', 'Interviewing')
              " . hiddenUnhiredApplicantFilter($authUser)
        )->fetch()['cnt'];

        $thirtyDaysAgo = date('Y-m-d', strtotime('-30 days'));
        $stmtNewHires = $pdo->prepare("SELECT COUNT(*) as cnt FROM employees WHERE date(created_at) >= ?{$visibleEmployeeFilter}");
        $stmtNewHires->execute([$thirtyDaysAgo]);
        $newHires = (int)$stmtNewHires->fetch()['cnt'];

        $stmtEmployeePositions = $pdo->query("
            SELECT CASE LOWER(TRIM(role))
                       WHEN 'driver' THEN 'Driver'
                       WHEN 'staff' THEN 'Staff'
                       WHEN 'cashier' THEN 'Cashier'
                       WHEN 'team leader' THEN 'Team Leader'
                       ELSE TRIM(role)
                   END AS position,
                   COUNT(*) AS count
            FROM employees
            WHERE COALESCE(role, '') <> 'admin'
              AND COALESCE(email, '') <> 'phnhes@gmail.com'
              AND COALESCE(employee_id, '') NOT IN ('ADMIN001', 'ADMIN002')
              AND NULLIF(TRIM(role), '') IS NOT NULL
              {$visibleEmployeeFilter}
            GROUP BY CASE LOWER(TRIM(role))
                         WHEN 'driver' THEN 'Driver'
                         WHEN 'staff' THEN 'Staff'
                         WHEN 'cashier' THEN 'Cashier'
                         WHEN 'team leader' THEN 'Team Leader'
                         ELSE TRIM(role)
                     END
            ORDER BY count DESC, position ASC
        ");
        $employeePositions = $stmtEmployeePositions->fetchAll();
        $completedOnboardings = (int)$pdo->query("
            SELECT COUNT(*) AS cnt
            FROM (
                SELECT e.id
                FROM employees e
                JOIN onboarding_tasks ot ON ot.employee_id = e.id
                WHERE ot.task NOT IN (
                    'Email & Account Created',
                    'IT Assets Assigned (Laptop, Peripherals)',
                    'Company ID / Access Badge Issued',
                    'Department Introductions & Buddy Assigned'
                )
                {$visibleAliasedEmployeeFilter}
                GROUP BY e.id
                HAVING COUNT(*) FILTER (WHERE ot.status = 'Completed') = COUNT(*)
            ) completed
        ")->fetch()['cnt'];
        respondJSON([
            'totalEmployees' => $totalEmp,
            'employeeDirectoryCount' => $employeeDirectoryCount,
            'totalApplicants' => $totalApps,
            'newHires' => $newHires,
            'employeePositionDistribution' => array_map(fn($position) => ['position' => $position['position'], 'count' => (int)$position['count']], $employeePositions),
            'completedOnboardings' => $completedOnboardings
        ]);
    }

    if ($route === 'activities/recent' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $stmt = $pdo->query("
            SELECT id, actor_name, actor_role, activity, created_at
            FROM system_activities
            ORDER BY created_at DESC, id DESC
            LIMIT 30
        ");
        respondJSON($stmt->fetchAll());
    }

    // --------------------------------------------------------
    // 9. ESS MODULE ROUTES
    // --------------------------------------------------------
    if ($route === 'users/profile' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $stmt = $pdo->prepare("SELECT u.id, u.email, u.role, u.name, u.position, u.department, u.employee_id, e.phone, e.address, e.emergency_contact, e.bank_name, e.bank_account, e.tin FROM users u LEFT JOIN employees e ON (e.employee_id = u.employee_id OR LOWER(e.email) = LOWER(u.email)) WHERE u.id = ?");
        $stmt->execute([$authUser['id']]);
        respondJSON($stmt->fetch() ?: $authUser);
    }

    if ($route === 'leave/mine' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $stmt = $pdo->prepare("SELECT * FROM leave_requests WHERE user_id = ? ORDER BY created_at DESC");
        $stmt->execute([$authUser['id']]);
        $requests = $stmt->fetchAll();

        $vacationUsed = 0; $sickUsed = 0; $emergencyUsed = 0;
        foreach ($requests as $r) {
            if ($r['status'] === 'Approved' || $r['status'] === 'Pending') {
                if ($r['leave_type'] === 'Vacation') $vacationUsed += (int)($r['days_count'] ?: 1);
                if ($r['leave_type'] === 'Sick') $sickUsed += (int)($r['days_count'] ?: 1);
                if ($r['leave_type'] === 'Emergency') $emergencyUsed += (int)($r['days_count'] ?: 1);
            }
        }
        respondJSON([
            'balances' => [
                'vacation' => ['total' => 15, 'used' => $vacationUsed, 'remaining' => max(0, 15 - $vacationUsed)],
                'sick' => ['total' => 10, 'used' => $sickUsed, 'remaining' => max(0, 10 - $sickUsed)],
                'emergency' => ['total' => 5, 'used' => $emergencyUsed, 'remaining' => max(0, 5 - $emergencyUsed)]
            ],
            'requests' => $requests
        ]);
    }

    if ($route === 'leave/request' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        $leaveType = $input['leave_type'] ?? 'Vacation';
        $startDate = $input['start_date'] ?? '';
        $endDate = $input['end_date'] ?? '';
        $reason = $input['reason'] ?? '';

        if (!$startDate || !$endDate) respondError("start_date and end_date are required.", 400);

        $days = (int)round((strtotime($endDate) - strtotime($startDate)) / (60 * 60 * 24)) + 1;
        if ($days < 1) $days = 1;

        $stmt = $pdo->prepare("INSERT INTO leave_requests (user_id, employee_id, leave_type, start_date, end_date, days_count, reason, status) VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending')");
        $stmt->execute([$authUser['id'], $authUser['employee_id'] ?? '', $leaveType, $startDate, $endDate, $days, $reason]);

        $reqId = $pdo->lastInsertId();
        $stmtFetch = $pdo->prepare("SELECT * FROM leave_requests WHERE id = ?");
        $stmtFetch->execute([$reqId]);
        respondJSON(['message' => 'Leave request submitted successfully.', 'leave' => $stmtFetch->fetch()], 201);
    }

    if ($route === 'leave/all' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $hiddenEmployeeUserFilter = isRestrictedHrAccount($authUser) ? "
            AND NOT EXISTS (
                SELECT 1
                FROM employees hidden_employee
                WHERE hidden_employee.status = 'Unhired'
                  AND (
                      (NULLIF(u.employee_id, '') IS NOT NULL AND hidden_employee.employee_id = u.employee_id)
                      OR LOWER(hidden_employee.email) = LOWER(u.email)
                  )
            )
        " : '';
        $stmt = $pdo->query("SELECT lr.*, u.name as employee_name, u.department, u.email FROM leave_requests lr JOIN users u ON lr.user_id = u.id WHERE TRUE {$hiddenEmployeeUserFilter} ORDER BY lr.created_at DESC");
        respondJSON($stmt->fetchAll());
    }

    if (preg_match('#^leave/(\d+)/status$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];
        $status = $input['status'] ?? 'Pending';
        $remarks = $input['admin_remarks'] ?? '';

        $stmt = $pdo->prepare("UPDATE leave_requests SET status = ?, admin_remarks = ? WHERE id = ?");
        $stmt->execute([$status, $remarks, $id]);
        $stmtFetch = $pdo->prepare("SELECT * FROM leave_requests WHERE id = ?");
        $stmtFetch->execute([$id]);
        respondJSON(['message' => "Leave request {$status} successfully.", 'leave' => $stmtFetch->fetch()]);
    }

    if ($route === 'attendance/mine' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $today = date('Y-m-d');
        $stmtLogs = $pdo->prepare("SELECT * FROM attendance WHERE user_id = ? ORDER BY date DESC, id DESC");
        $stmtLogs->execute([$authUser['id']]);
        $logs = $stmtLogs->fetchAll();

        $stmtToday = $pdo->prepare("SELECT * FROM attendance WHERE user_id = ? AND date = ?");
        $stmtToday->execute([$authUser['id'], $today]);
        $todayLog = $stmtToday->fetch();

        respondJSON([
            'todayLog' => $todayLog ?: null,
            'schedule' => [
                'shift' => 'Standard Shift (Day)',
                'hours' => '09:00 AM - 05:00 PM',
                'days' => 'Monday - Friday'
            ],
            'logs' => $logs
        ]);
    }

    if ($route === 'attendance/clock-in' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        $today = date('Y-m-d');
        $stmtCur = $pdo->prepare("SELECT * FROM attendance WHERE user_id = ? AND date = ?");
        $stmtCur->execute([$authUser['id'], $today]);
        $cur = $stmtCur->fetch();
        if ($cur && !empty($cur['clock_in'])) respondError("Already clocked in for today.", 400);

        $timeStr = date('h:i A');
        $status = (date('H') > 9 || (date('H') == 9 && date('i') > 15)) ? 'Late' : 'Present';
        $notes = $input['notes'] ?? '';

        if ($cur) {
            $pdo->prepare("UPDATE attendance SET clock_in = ?, status = ?, notes = ? WHERE id = ?")->execute([$timeStr, $status, $notes ?: $cur['notes'], $cur['id']]);
            $resId = $cur['id'];
        } else {
            $stmt = $pdo->prepare("INSERT INTO attendance (user_id, employee_id, date, clock_in, status, notes) VALUES (?, ?, ?, ?, ?, ?)");
            $stmt->execute([$authUser['id'], $authUser['employee_id'] ?? '', $today, $timeStr, $status, $notes]);
            $resId = $pdo->lastInsertId();
        }
        $stmtFetch = $pdo->prepare("SELECT * FROM attendance WHERE id = ?");
        $stmtFetch->execute([$resId]);
        respondJSON(['message' => 'Clocked in successfully.', 'attendance' => $stmtFetch->fetch()]);
    }

    if ($route === 'attendance/clock-out' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        $today = date('Y-m-d');
        $stmtCur = $pdo->prepare("SELECT * FROM attendance WHERE user_id = ? AND date = ?");
        $stmtCur->execute([$authUser['id'], $today]);
        $cur = $stmtCur->fetch();
        if (!$cur || empty($cur['clock_in'])) respondError("You must clock in before clocking out.", 400);

        $timeStr = date('h:i A');
        $pdo->prepare("UPDATE attendance SET clock_out = ? WHERE id = ?")->execute([$timeStr, $cur['id']]);
        $stmtFetch = $pdo->prepare("SELECT * FROM attendance WHERE id = ?");
        $stmtFetch->execute([$cur['id']]);
        respondJSON(['message' => 'Clocked out successfully.', 'attendance' => $stmtFetch->fetch()]);
    }

    if ($route === 'payslips/mine' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $stmt = $pdo->prepare("SELECT * FROM payslips WHERE user_id = ? ORDER BY pay_date DESC");
        $stmt->execute([$authUser['id']]);
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'documents/mine' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $stmt = $pdo->prepare("SELECT * FROM employee_documents WHERE user_id = ? ORDER BY created_at DESC");
        $stmt->execute([$authUser['id']]);
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'documents/coe' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        $department = trim((string)($authUser['department'] ?? ''));
        if ($department === '' || strcasecmp($department, 'General') === 0) {
            $department = 'HR';
        }
        respondJSON([
            'certificateNo' => "COE-{$authUser['employee_id']}-" . substr(time(), -4),
            'issuedDate' => date('F d, Y'),
            'employeeName' => $authUser['name'],
            'employeeId' => $authUser['employee_id'] ?: 'N/A',
            'position' => $authUser['position'] ?: 'Staff',
            'department' => $department,
            'status' => 'Active',
            'companyName' => '2GO Travel',
            'signatory' => 'HR Director / Personnel Department'
        ]);
    }

    if ($route === 'benefits/mine' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        respondJSON([
            'healthInsurance' => [
                'provider' => 'MetroCare Health Plan',
                'policyNumber' => 'MC-2026-78912',
                'tier' => 'Comprehensive Gold',
                'coverage' => 'PHP 250,000 / year (Inpatient & Outpatient)'
            ],
            'retirementPlan' => [
                'planName' => 'Company 401(k) / Provident Fund',
                'employerContribution' => '5% Matching',
                'status' => 'Enrolled'
            ],
            'allowances' => [
                ['name' => 'Monthly Rice & Meal Allowance', 'amount' => '$150.00 / month'],
                ['name' => 'Communications Allowance', 'amount' => '$50.00 / month']
            ]
        ]);
    }

    if ($route === 'performance/mine' && $requestMethod === 'GET') {
        $authUser = requireAuth();
        respondJSON([
            'latestRating' => '4.8 / 5.0 (Exceeds Expectations)',
            'reviewPeriod' => 'Q2 2026 Performance Appraisal',
            'evaluator' => 'Department Lead',
            'strengths' => ['Exemplary teamwork', 'Strong technical problem solving', 'Consistently meets project deadlines'],
            'goals' => ['Lead upcoming Q4 cross-departmental initiative', 'Complete advanced certifications']
        ]);
    }

    // Fallback if route not matched
    respondError("API Endpoint not found: [{$requestMethod}] /{$route}", 404);

} catch (Throwable $e) {
    error_log('HRMS API error: ' . $e->getMessage());
    if ($e instanceof PDOException && in_array($e->getCode(), ['55P03', '57014'], true)
        && in_array($route, ['applicants', 'applicants/receipt'], true)) {
        respondError('The recruitment database is busy. Please retry shortly using this same form.', 503);
    }
    if ($e instanceof PDOException && $e->getCode() === '42703') {
        respondError('The database schema is out of date. Contact HR to apply the required database migration.', 503);
    }
    if ($e instanceof PDOException && $e->getCode() === '42P01') {
        respondError('Recent activities are not set up in this database. Back up the database, run the latest database-migrations.sql, then try again.', 503);
    }
    if ($e instanceof PDOException && $e->getCode() === '23505'
        && strpos((string)($e->errorInfo[2] ?? ''), 'DUPLICATE_PERSON_NAME') !== false) {
        respondError('A person with this full name already exists in Employee or Applicant records.', 409);
    }
    if ($e instanceof PDOException && $e->getCode() === '23514' && preg_match('#^employees/\d+/status$#', $route) === 1) {
        $databaseMessage = (string)($e->errorInfo[2] ?? $e->getMessage());
        if (preg_match('/violates check constraint "([^"]+)"/i', $databaseMessage, $constraintMatch) === 1
            && $constraintMatch[1] === 'employees_status_check') {
            respondError('The employee status configuration is out of date. Back up the database, run repair-employee-status.sql against the same database used by the API, then try again. No data was saved.', 503);
        }
    }
    $message = APP_ENV === 'development'
        ? 'Internal Server Error: ' . $e->getMessage()
        : 'Internal Server Error.';
    respondError($message, 500);
}
