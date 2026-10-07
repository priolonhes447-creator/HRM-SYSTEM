<?php
// ============================================================
// HRMS PHP CONFIG & DATABASE CONNECTION (Supabase / PDO)
// ============================================================

// HTTP Security & CORS Response Headers
header("X-Content-Type-Options: nosniff");
header("X-Frame-Options: SAMEORIGIN");
header("Referrer-Policy: strict-origin-when-cross-origin");
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With");
header("Content-Type: application/json; charset=UTF-8");

// Load .env variables if file exists
function loadEnv($path) {
    if (!file_exists($path)) return;
    $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        list($name, $value) = explode('=', $line, 2);
        $name = trim($name);
        $value = trim($value);
        if (!array_key_exists($name, $_SERVER) && !array_key_exists($name, $_ENV)) {
            putenv(sprintf('%s=%s', $name, $value));
            $_ENV[$name] = $value;
            $_SERVER[$name] = $value;
        }
    }
}

loadEnv(__DIR__ . '/../.env');
loadEnv(__DIR__ . '/../backend/.env');

$allowedOrigin = trim(getenv('CORS_ALLOWED_ORIGIN') ?: '');
$requestOrigin = trim($_SERVER['HTTP_ORIGIN'] ?? '');
$localOrigins = ['http://localhost:5000', 'http://127.0.0.1:5000'];
if ($requestOrigin !== '' && $allowedOrigin !== '' && hash_equals($allowedOrigin, $requestOrigin)) {
    header('Access-Control-Allow-Origin: ' . $allowedOrigin);
    header('Vary: Origin');
} elseif ($requestOrigin !== '' && in_array($requestOrigin, $localOrigins, true)) {
    header('Access-Control-Allow-Origin: ' . $requestOrigin);
    header('Vary: Origin');
}

// Handle preflight after applying the same origin policy as API requests.
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$databaseUrl = getenv('DATABASE_URL') ?: '';
$databaseParts = $databaseUrl ? parse_url($databaseUrl) : false;
$databasePath = is_array($databaseParts) ? ltrim($databaseParts['path'] ?? '', '/') : '';

define('DB_HOST', getenv('DB_HOST') ?: getenv('PGHOST') ?: (is_array($databaseParts) ? ($databaseParts['host'] ?? '127.0.0.1') : '127.0.0.1'));
define('DB_PORT', getenv('DB_PORT') ?: getenv('PGPORT') ?: (is_array($databaseParts) ? ($databaseParts['port'] ?? '5432') : '5432'));
define('DB_NAME', getenv('DB_NAME') ?: getenv('DB_DATABASE') ?: getenv('PGDATABASE') ?: $databasePath ?: 'hrms_db');
define('DB_USER', getenv('DB_USER') ?: getenv('DB_USERNAME') ?: getenv('PGUSER') ?: (is_array($databaseParts) ? urldecode($databaseParts['user'] ?? 'postgres') : 'postgres'));
define('DB_PASS', getenv('DB_PASS') ?: getenv('DB_PASSWORD') ?: getenv('PGPASSWORD') ?: (is_array($databaseParts) ? urldecode($databaseParts['pass'] ?? '') : ''));
define('DB_SSLMODE', getenv('DB_SSLMODE') ?: 'prefer');
define('APP_ENV', getenv('APP_ENV') ?: 'production');
define('JWT_SECRET', getenv('JWT_SECRET') ?: '');
define('JWT_EXPIRES_IN', max(300, (int)(getenv('JWT_EXPIRES_IN') ?: 86400)));
define('MAIL_HOST', getenv('MAIL_HOST') ?: '');
define('MAIL_PORT', (int)(getenv('MAIL_PORT') ?: 587));
define('MAIL_USERNAME', getenv('MAIL_USERNAME') ?: '');
define('MAIL_PASSWORD', getenv('MAIL_PASSWORD') ?: '');
define('MAIL_ENCRYPTION', strtolower(getenv('MAIL_ENCRYPTION') ?: 'tls'));
define('MAIL_FROM_ADDRESS', getenv('MAIL_FROM_ADDRESS') ?: '');
define('MAIL_FROM_NAME', getenv('MAIL_FROM_NAME') ?: 'HRMS');

/**
 * Get the PostgreSQL connection used by every API request.
 * There is intentionally no local SQLite/MySQL fallback. A fallback would let
 * the API report successful writes to a different database than PostgreSQL.
 */
function getDBConnection() {
    static $pdo = null;
    if ($pdo !== null) return $pdo;

    $drivers = PDO::getAvailableDrivers();
    if (!in_array('pgsql', $drivers, true)) {
        throw new RuntimeException('PostgreSQL PDO driver is not installed on the server.');
    }

    $dsn = sprintf(
        'pgsql:host=%s;port=%s;dbname=%s;sslmode=%s;connect_timeout=5',
        DB_HOST,
        DB_PORT,
        DB_NAME,
        DB_SSLMODE
    );
    $pdo = new PDO($dsn, DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
    ]);
    return $pdo;
}

function getJwtSecret() {
    if (strlen(JWT_SECRET) < 32 || JWT_SECRET === 'hrms_php_supabase_secret_key_2026') {
        throw new RuntimeException('JWT_SECRET is missing or insecure. Configure a random secret of at least 32 characters.');
    }
    return JWT_SECRET;
}

function describeSystemActivity(string $route, string $method): string {
    $route = trim($route, '/');
    $method = strtoupper($method);

    if (($route === 'auth/login' || $route === 'auth/verify-login-otp') && $method === 'POST') return 'logged in';
    if ($route === 'users/profile' && $method === 'PUT') return 'updated their account profile';
    if ($route === 'users/password' && $method === 'PUT') return 'changed their password';
    if ($route === 'users' && $method === 'POST') return 'created a user account';
    if (preg_match('#^users/\d+$#', $route)) return $method === 'DELETE' ? 'deleted a user account' : 'updated a user account';
    if ($route === 'employees' && $method === 'POST') return 'added an employee record';
    if ($route === 'employees' && $method === 'GET') return '';
    if (preg_match('#^employees/\d+/2x2-photo$#', $route)) return 'uploaded a Contract Signed picture';
    if (preg_match('#^employees/\d+/status$#', $route)) return 'updated an employee category';
    if (preg_match('#^employees/\d+$#', $route)) return $method === 'DELETE' ? 'deleted an employee record' : 'updated an employee record';
    if ($route === 'applicants' && $method === 'POST') return 'submitted an application';
    if (preg_match('#^applicants/\d+/decision$#', $route)) return 'updated an applicant decision';
    if (preg_match('#^applicants/\d+/hire$#', $route)) return 'hired an applicant';
    if (preg_match('#^applicants/\d+$#', $route) && $method === 'DELETE') return 'deleted an applicant record';
    if ($route === 'interviews' && $method === 'POST') return 'scheduled an interview';
    if (preg_match('#^interviews/\d+$#', $route)) return 'updated an interview';
    if (preg_match('#^announcements/\d+/read$#', $route)) return 'read an announcement';
    if ($route === 'announcements' && $method === 'POST') return 'published an announcement';
    if (preg_match('#^announcements/\d+$#', $route)) return $method === 'DELETE' ? 'deleted an announcement' : 'updated an announcement';
    if (preg_match('#^onboarding/employees/[^/]+/start$#', $route)) return 'started an employee onboarding checklist';
    if ($route === 'onboarding' && $method === 'POST') return 'added an onboarding task';
    if (preg_match('#^onboarding/\d+$#', $route)) return $method === 'DELETE' ? 'deleted an onboarding task' : 'updated an onboarding task';
    if ($route === 'leave/request') return 'submitted a leave request';
    if (preg_match('#^leave/\d+/status$#', $route)) return 'updated a leave request';
    if ($route === 'attendance/clock-in') return 'clocked in';
    if ($route === 'attendance/clock-out') return 'clocked out';
    if ($route === 'auth/reset-password') return 'reset their password';

    return '';
}

function recordSystemActivity($data, int $code): void {
    global $pdo;
    $route = $GLOBALS['route'] ?? '';
    $method = strtoupper($GLOBALS['requestMethod'] ?? ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
    if ($code < 200 || $code >= 300 || !in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'], true)) return;
    if ($route === 'auth/login' && !empty($data['requires_otp'])) return;
    if ($route === 'applicants' && !empty($data['already_submitted'])) return;
    if ($route === 'ai/chat' || strpos($route, 'auth/forgot-password') === 0 || strpos($route, 'auth/resend-otp') === 0 || strpos($route, 'auth/verify-otp') === 0) return;

    $activity = describeSystemActivity($route, $method);
    if ($activity === '') return;

    $user = $GLOBALS['hrms_activity_user'] ?? [];
    if (!$user && is_array($data) && isset($data['user']) && is_array($data['user'])) {
        $user = $data['user'];
    }
    $actorName = trim((string)($user['name'] ?? ''));
    if ($actorName === '') {
        $actorName = $route === 'applicants' ? 'Applicant' : 'Admin';
    }
    $actorId = isset($user['id']) ? (int)$user['id'] : null;
    $actorRole = (string)($user['role'] ?? ($route === 'applicants' ? 'applicant' : ''));

    try {
        $pdo->exec("SET lock_timeout = '2s'");
        $stmt = $pdo->prepare(
            'INSERT INTO system_activities (actor_id, actor_name, actor_role, activity) VALUES (?, ?, ?, ?)'
        );
        $stmt->execute([$actorId, $actorName, $actorRole, $activity]);
    } catch (Throwable $error) {
        error_log('HRMS activity recording failed for ' . $method . ' /' . $route . ': ' . $error->getMessage());
    }
}

// JSON Output Helper Functions
function respondJSON($data, $code = 200) {
    $json = json_encode($data, JSON_THROW_ON_ERROR);
    http_response_code($code);

    if (function_exists('fastcgi_finish_request')) {
        echo $json;
        fastcgi_finish_request();
        recordSystemActivity($data, (int)$code);
    } else {
        recordSystemActivity($data, (int)$code);
        echo $json;
    }

    exit();
}

function respondError($message, $code = 400) {
    respondJSON(["error" => $message], $code);
}
