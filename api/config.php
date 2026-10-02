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

// Handle preflight OPTIONS requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

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
if ($allowedOrigin !== '' && $requestOrigin !== '' && hash_equals($allowedOrigin, $requestOrigin)) {
    header('Access-Control-Allow-Origin: ' . $allowedOrigin);
    header('Vary: Origin');
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
        'pgsql:host=%s;port=%s;dbname=%s;sslmode=%s',
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

// JSON Output Helper Functions
function respondJSON($data, $code = 200) {
    http_response_code($code);
    echo json_encode($data);
    exit();
}

function respondError($message, $code = 400) {
    respondJSON(["error" => $message], $code);
}
