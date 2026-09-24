<?php
// ============================================================
// HRMS UNIFIED PHP REST API ROUTER & CONTROLLER
// ============================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/jwt.php';

try {
    $pdo = getDBConnection();
} catch (Throwable $e) {
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
$input = json_decode(file_get_contents('php://input'), true) ?? [];

$pdo->exec(
    "CREATE TABLE IF NOT EXISTS password_resets (
        id BIGSERIAL PRIMARY KEY,
        user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        otp_hash VARCHAR(255) NOT NULL,
        reset_token_hash VARCHAR(255),
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        attempts INT NOT NULL DEFAULT 0,
        verified_at TIMESTAMP WITH TIME ZONE,
        used_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )"
);
$pdo->exec("CREATE INDEX IF NOT EXISTS password_resets_user_idx ON password_resets(user_id, created_at DESC)");

if ($route === 'health' && $requestMethod === 'GET') {
    respondJSON(['status' => 'ok', 'database' => 'postgresql']);
}

// Helper: Password verification & hashing using password_hash/bcrypt
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
    ['task' => 'Contract Signed', 'offset' => 0],
    ['task' => 'Email & Account Created', 'offset' => 0],
    ['task' => 'IT Assets Assigned (Laptop, Peripherals)', 'offset' => 1],
    ['task' => 'Company ID / Access Badge Issued', 'offset' => 2],
    ['task' => 'Orientation & Company Policy Review', 'offset' => 3],
    ['task' => 'Department Introductions & Buddy Assigned', 'offset' => 4],
    ['task' => 'Role-Specific Training', 'offset' => 7],
    ['task' => '30-Day Check-in & Feedback Session', 'offset' => 30]
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

// ============================================================
// ROUTE DISPATCHER
// ============================================================

try {
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

        $payload = [
            'id' => (int)$user['id'],
            'email' => $user['email'],
            'role' => $user['role'],
            'name' => $user['name'],
            'position' => $user['position'] ?? '',
            'department' => $user['department'] ?? '',
            'employee_id' => $user['employee_id'] ?? ''
        ];

        $token = PHPJWT::encode($payload, JWT_SECRET);

        respondJSON([
            'token' => $token,
            'user' => $payload
        ]);
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
        $message = trim($input['message'] ?? '');
        if (!$message) respondError("Message is required.", 400);

        // Fetch DB facts
        $empCount = (int)$pdo->query("SELECT COUNT(*) FROM employees")->fetchColumn();
        $appCount = (int)$pdo->query("SELECT COUNT(*) FROM applicants")->fetchColumn();
        $deptStmt = $pdo->query("SELECT department, COUNT(*) as cnt FROM employees GROUP BY department");
        $depts = [];
        while ($r = $deptStmt->fetch()) {
            $depts[$r['department'] ?? 'General'] = (int)$r['cnt'];
        }

        $msgLower = strtolower($message);
        $reply = "";

        if (strpos($msgLower, 'department') !== false || strpos($msgLower, 'dept') !== false) {
            $deptLines = [];
            foreach ($depts as $d => $c) {
                $deptLines[] = "- **$d**: $c employee(s)";
            }
            $reply = "### 📊 Department Roster Summary\n\n" . (empty($deptLines) ? "No departments yet." : implode("\n", $deptLines)) . "\n\n**Total Employees:** $empCount";
        } elseif (strpos($msgLower, 'employee') !== false || strpos($msgLower, 'staff') !== false) {
            $empStmt = $pdo->query("SELECT name, department, role, status FROM employees LIMIT 10");
            $empList = [];
            while ($e = $empStmt->fetch()) {
                $empList[] = "- **{$e['name']}** ({$e['department']}) — *{$e['role']}* [{$e['status']}]";
            }
            $reply = "### 👥 Employee Roster Overview\nTotal registered employees: **$empCount**\n\n" . implode("\n", $empList);
        } elseif (strpos($msgLower, 'applicant') !== false || strpos($msgLower, 'hiring') !== false) {
            $reply = "### 💼 Applicant & Hiring Pipeline\nTotal Applicants: **$appCount**\n\nCheck the **Applicants** tab to manage candidate statuses.";
        } elseif (strpos($msgLower, 'draft') !== false || strpos($msgLower, 'announcement') !== false) {
            $reply = "### 📢 Drafted Announcement\n\n**Title:** Important Company Update\n\n**Content:**\nDear Team,\n\nPlease be informed of upcoming company updates. Reach out to HR if you have any questions.\n\n*Best regards,*\n*HR Management Team*";
        } else {
            $reply = "### 🤖 Aura HR Assistant\nHello {$authUser['name']}! I am your HR AI Assistant.\n\n**Quick Stats:**\n- Total Employees: **$empCount**\n- Total Applicants: **$appCount**\n\nHow can I assist you with HR operations today?";
        }

        respondJSON([
            'reply' => $reply,
            'source' => 'php-hr-ai',
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
        requireRole($authUser, 'admin');

        // Enforce rule: purge orphan user accounts that are not in Employee Records Management
        $pdo->exec("DELETE FROM users WHERE id NOT IN (
            SELECT u.id FROM users u
            JOIN employees e ON (e.employee_id = u.employee_id AND u.employee_id IS NOT NULL AND u.employee_id != '')
                             OR LOWER(e.email) = LOWER(u.email)
        )");

        $stmt = $pdo->query("SELECT id, email, role, name, position, department, employee_id, created_at FROM users ORDER BY id DESC");
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'users' && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');

        $email = trim(strtolower($input['email'] ?? ''));
        $password = $input['password'] ?? '';
        $name = trim($input['name'] ?? '');
        $role = $input['role'] ?? 'employee';
        $position = trim($input['position'] ?? '');
        $department = trim($input['department'] ?? '');
        $empId = trim($input['employee_id'] ?? '');

        if (!$email || !$password || !$name) respondError("email, password, and name are required.", 400);
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) respondError("A valid email address is required.", 400);
        if (strlen($password) < 6) respondError("Password must be at least 6 characters.", 400);

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
                $empId = ($role === 'admin' ? 'ADMIN' : 'EMP') . str_pad($empSeq, 3, '0', STR_PAD_LEFT);
            }
            $stmtIns = $pdo->prepare("INSERT INTO employees (employee_id, name, email, department, role, status) VALUES (?, ?, ?, ?, ?, 'Active')");
            $stmtIns->execute([$empId, $name, $email, $department ?: ($role === 'admin' ? 'Human Resources' : 'General'), $position ?: ($role === 'admin' ? 'HR Manager' : 'Staff')]);
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
        requireRole($authUser, 'admin');
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
        if (!in_array($role, ['admin', 'employee'], true)) respondError('Invalid user role.', 400);
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
        requireRole($authUser, 'admin');
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

        $stmt = $pdo->query("SELECT * FROM employees ORDER BY id DESC");
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
            $input['department'] ?? 'General',
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

        $stmt = $pdo->prepare("UPDATE employees SET employee_id=?, name=?, email=?, department=?, role=?, status=?, phone=?, address=?, date_of_birth=?, gender=?, emergency_contact=?, age=?, place_of_birth=?, tin=?, civil_status=?, last_name=?, first_name=?, middle_name=? WHERE id=?");
        $stmt->execute([
            $input['employee_id'] ?? '',
            $input['name'] ?? '',
            $input['email'] ?? '',
            $input['department'] ?? 'General',
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

    if (preg_match('#^employees/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $stmt = $pdo->prepare("SELECT employee_id, email FROM employees WHERE id = ?");
        $stmt->execute([$id]);
        $emp = $stmt->fetch();

        if ($emp) {
            $pdo->prepare("DELETE FROM onboarding_tasks WHERE employee_id = ?")->execute([$id]);
            $stmtUser = $pdo->prepare("SELECT id FROM users WHERE (employee_id = ? AND employee_id != '') OR LOWER(email) = LOWER(?)");
            $stmtUser->execute([$emp['employee_id'], $emp['email']]);
            $users = $stmtUser->fetchAll();
            foreach ($users as $u) {
                $pdo->prepare("DELETE FROM announcement_reads WHERE user_id = ?")->execute([$u['id']]);
                $pdo->prepare("DELETE FROM users WHERE id = ?")->execute([$u['id']]);
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

        $stmt = $pdo->query("SELECT * FROM applicants ORDER BY id DESC");
        respondJSON($stmt->fetchAll());
    }

    if ($route === 'applicants' && $requestMethod === 'POST') {
        $surname = trim($input['surname'] ?? '');
        $middleName = trim($input['middle_name'] ?? '');
        $firstName = trim($input['first_name'] ?? '');
        $name = trim($input['name'] ?? '');
        if (!$name) {
            $name = trim(implode(' ', array_filter([$firstName, $middleName, $surname])));
        }
        $position = trim($input['position'] ?? '');
        if ((!$name && (!$surname || !$firstName)) || !$position) respondError("Surname, first name, and position are required.", 400);

        $appliedDate = $input['applied_date'] ?? date('Y-m-d');
        $stmt = $pdo->prepare("INSERT INTO applicants (name, surname, middle_name, first_name, position, department, email, phone, gender, address, date_of_birth, age, place_of_birth, tin, civil_status, emergency_contact, applied_date, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([
            $name, $surname, $middleName, $firstName, $position,
            $input['department'] ?? 'General',
            $input['email'] ?? '', $input['phone'] ?? '',
            $input['gender'] ?? '', $input['address'] ?? '',
            $input['date_of_birth'] ?? '', (int)($input['age'] ?? 0),
            $input['place_of_birth'] ?? '', $input['tin'] ?? '',
            $input['civil_status'] ?? '', $input['emergency_contact'] ?? '',
            $appliedDate, $input['status'] ?? 'New'
        ]);

        respondJSON(['id' => (int)$pdo->lastInsertId(), 'message' => 'Applicant added successfully.'], 201);
    }

    if (preg_match('#^applicants/(\d+)/hire$#', $route, $matches) && $requestMethod === 'POST') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $stmt = $pdo->prepare("SELECT * FROM applicants WHERE id = ?");
        $stmt->execute([$id]);
        $app = $stmt->fetch();
        if (!$app) respondError("Applicant not found.", 404);

        // Generate unique EMP code
        $stmtCnt = $pdo->query("SELECT COUNT(*) as cnt FROM employees");
        $cnt = $stmtCnt->fetch()['cnt'] + 1;
        $empCode = 'EMP' . str_pad($cnt, 3, '0', STR_PAD_LEFT);

        $email = trim($app['email'] ?? '');
        if (!$email) {
            $slug = strtolower(preg_replace('/[^a-z0-9]+/', '', $app['name']));
            $email = ($slug ?: 'employee') . '@company.com';
        }

        // Insert employee with full details transferred
        $stmtIns = $pdo->prepare("INSERT INTO employees (employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name) VALUES (?, ?, ?, ?, ?, 'Onboarding', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmtIns->execute([
            $empCode, $app['name'], $email,
            $app['department'] ?? 'General',
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
            $app['middle_name'] ?? ''
        ]);
        $empDbId = $pdo->lastInsertId();

        // Start onboarding
        startOnboardingChecklist($pdo, $empDbId, $DEFAULT_ONBOARDING_TASKS);

        // Create portal login
        $stmtUser = $pdo->prepare("SELECT id FROM users WHERE email = ?");
        $stmtUser->execute([$email]);
        if (!$stmtUser->fetch()) {
            $defaultHash = hashPassword('changeme123');
            $stmtAcc = $pdo->prepare("INSERT INTO users (email, password, role, name, position, department, employee_id) VALUES (?, ?, 'employee', ?, ?, 'General', ?)");
            $stmtAcc->execute([$email, $defaultHash, $app['name'], $app['position'], $empCode]);
        }

        // Remove from applicants
        $pdo->prepare("DELETE FROM applicants WHERE id = ?")->execute([$id]);

        respondJSON([
            'message' => "{$app['name']} hired successfully. Employee record, onboarding checklist, and portal login created.",
            'employee_id' => $empCode,
            'email' => $email,
            'default_password' => 'changeme123'
        ]);
    }

    if (preg_match('#^applicants/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $pdo->prepare("DELETE FROM applicants WHERE id = ?")->execute([$id]);
        respondJSON(['message' => 'Applicant deleted.']);
    }

    // --------------------------------------------------------
    // 6. ANNOUNCEMENT ROUTES
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

        if ($authUser['role'] === 'admin') {
            $stmt = $pdo->query("
                SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code, e.department AS emp_department, e.role AS emp_role
                FROM onboarding_tasks ot
                JOIN employees e ON ot.employee_id = e.id
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
            $completedTasks = count(array_filter($rows, fn($t) => $t['status'] === 'Completed'));
            $avgProgress = $activeCnt ? (int)round(array_sum(array_column($summary, 'progress')) / $activeCnt) : 0;

            respondJSON([
                'scope' => 'admin',
                'summary' => $summary,
                'stats' => [
                    'activeOnboardings' => $activeCnt,
                    'totalTasks' => $totalTasks,
                    'completedTasks' => $completedTasks,
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
                    $stmtIns->execute([$code, $authUser['name'] ?? 'Employee', $authUser['email'] ?? '', $authUser['department'] ?? 'General', $authUser['position'] ?? '']);
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

        $stmt = $pdo->prepare("SELECT * FROM employees WHERE employee_id = ?");
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

        $stmt = $pdo->prepare("INSERT INTO onboarding_tasks (employee_id, task, status, due_date) VALUES (?, ?, ?, ?)");
        $stmt->execute([$empDbId, $task, $input['status'] ?? 'Pending', $input['due_date'] ?? '']);
        $taskId = $pdo->lastInsertId();

        $stmtTask = $pdo->prepare("SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code FROM onboarding_tasks ot JOIN employees e ON ot.employee_id = e.id WHERE ot.id = ?");
        $stmtTask->execute([$taskId]);

        respondJSON(['message' => 'Onboarding task added.', 'task' => $stmtTask->fetch()], 201);
    }

    if (preg_match('#^onboarding/(\d+)$#', $route, $matches) && $requestMethod === 'PUT') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $stmtCur = $pdo->prepare("SELECT * FROM onboarding_tasks WHERE id = ?");
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

        $stmtTask = $pdo->prepare("SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code FROM onboarding_tasks ot JOIN employees e ON ot.employee_id = e.id WHERE ot.id = ?");
        $stmtTask->execute([$id]);
        respondJSON(['message' => 'Onboarding task updated.', 'task' => $stmtTask->fetch()]);
    }

    if (preg_match('#^onboarding/(\d+)$#', $route, $matches) && $requestMethod === 'DELETE') {
        $authUser = requireAuth();
        requireRole($authUser, 'admin');
        $id = (int)$matches[1];

        $pdo->prepare("DELETE FROM onboarding_tasks WHERE id = ?")->execute([$id]);
        respondJSON(['message' => 'Onboarding task deleted.']);
    }

    // --------------------------------------------------------
    // 8. DASHBOARD STATS ROUTE
    // --------------------------------------------------------
    if ($route === 'dashboard/stats' && $requestMethod === 'GET') {
        $authUser = requireAuth();

        $totalEmp = (int)$pdo->query("SELECT COUNT(*) as cnt FROM employees")->fetch()['cnt'];
        $activeEmp = (int)$pdo->query("SELECT COUNT(*) as cnt FROM employees WHERE status = 'Active'")->fetch()['cnt'];
        $totalApps = (int)$pdo->query("SELECT COUNT(*) as cnt FROM applicants")->fetch()['cnt'];

        $thirtyDaysAgo = date('Y-m-d', strtotime('-30 days'));
        $stmtNewHires = $pdo->prepare("SELECT COUNT(*) as cnt FROM employees WHERE date(created_at) >= ?");
        $stmtNewHires->execute([$thirtyDaysAgo]);
        $newHires = (int)$stmtNewHires->fetch()['cnt'];

        $stmtDept = $pdo->query("SELECT department, COUNT(*) as count FROM employees GROUP BY department ORDER BY count DESC");
        $depts = $stmtDept->fetchAll();

        $retentionRate = $totalEmp > 0 ? (int)round(($activeEmp / $totalEmp) * 100) : 0;

        respondJSON([
            'totalEmployees' => $totalEmp,
            'totalApplicants' => $totalApps,
            'newHires' => $newHires,
            'departmentDistribution' => array_map(fn($d) => ['department' => $d['department'] ?: 'General', 'count' => (int)$d['count']], $depts),
            'retentionRate' => $retentionRate
        ]);
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
        $stmt = $pdo->query("SELECT lr.*, u.name as employee_name, u.department, u.email FROM leave_requests lr JOIN users u ON lr.user_id = u.id ORDER BY lr.created_at DESC");
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
        respondJSON([
            'certificateNo' => "COE-{$authUser['employee_id']}-" . substr(time(), -4),
            'issuedDate' => date('F d, Y'),
            'employeeName' => $authUser['name'],
            'employeeId' => $authUser['employee_id'] ?: 'N/A',
            'position' => $authUser['position'] ?: 'Staff',
            'department' => $authUser['department'] ?: 'General',
            'status' => 'Active',
            'companyName' => 'Human Resources Management System Inc.',
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

} catch (Exception $e) {
    respondError("Internal Server Error: " . $e->getMessage(), 500);
}
