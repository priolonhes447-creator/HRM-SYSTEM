<?php

declare(strict_types=1);

// Router for container platforms that use PHP's built-in web server.
// Apache/LiteSpeed deployments continue to use .htaccess instead.
$requestPath = rawurldecode(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/');
$requestPath = '/' . ltrim(str_replace('\\', '/', $requestPath), '/');

// Never expose configuration, source metadata, dependencies, or local tooling.
$blockedDirectory = preg_match('#^/(?:backend|vendor|\.git|\.vscode)(?:/|$)#i', $requestPath);
$blockedFile = preg_match(
    '#(?:^|/)(?:\.[^/]+|[^/]+\.(?:env|sql|db|log|md|lock|phar|toml|vbs)|package\.json|composer\.json)$#i',
    $requestPath
);

if ($blockedDirectory || $blockedFile) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=UTF-8');
    echo 'Not Found';
    exit;
}

// Send all API paths through the PHP API controller without relying on rewrites.
if ($requestPath === '/api' || str_starts_with($requestPath, '/api/')) {
    $_GET['route'] = trim(substr($requestPath, 4), '/');
    require __DIR__ . '/api/index.php';
    exit;
}

$publicFile = __DIR__ . $requestPath;
if ($requestPath !== '/' && is_file($publicFile)) {
    return false;
}

if ($requestPath === '/' || $requestPath === '/index.html') {
    return false;
}

http_response_code(404);
header('Content-Type: text/plain; charset=UTF-8');
echo 'Not Found';
