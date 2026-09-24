# HRMS - Human Resource Management System

HRMS is a vanilla HTML/CSS/JavaScript frontend with a PHP 8 and PostgreSQL API. The production runtime is the PHP API in `api/`. The Node.js/SQLite implementation under `backend/` is retained only for legacy local tests and is blocked from public web access.

## Requirements

- PHP 8.0-8.2
- PostgreSQL 14 or 15
- PHP extensions: PDO, `pdo_pgsql`, ctype, filter, hash, and OpenSSL
- Composer 2
- Apache or LiteSpeed with `.htaccess` support
- For container deployment: PHP built-in server using `router.php`
- HTTPS in production

## Local setup

1. Copy `.env.example` to `.env`.
2. Set the PostgreSQL credentials and generate a unique JWT secret:

   ```bash
   php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"
   ```

3. For a brand-new database, review and run `supabase.sql.sql`. This script resets the HRMS tables and loads demo data, so never run it over production data.
4. For an existing installation, run `database-migrations.sql` instead.
5. Install PHP dependencies:

   ```bash
   composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
   ```

6. Serve the project through Apache/LiteSpeed and open `index.html`.

## HostForge deployment

Use a HostForge Developer Hosting plan with PHP 8.2 and PostgreSQL enabled.

1. Create a PostgreSQL database and user in cPanel. Grant the user access to the database.
2. Deploy the Git repository into the domain's document root. Do not upload a local `.env`, database dump, or `hostforge.env` file.
3. SSH into the release directory and install dependencies:

   ```bash
   composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
   composer check-platform-reqs --no-dev
   ```

4. Create `.env` directly on HostForge from `.env.example`. At minimum configure:

   ```dotenv
   APP_ENV=production
   DB_HOST=127.0.0.1
   DB_PORT=5432
   DB_NAME=cpanel_database_name
   DB_USER=cpanel_database_user
   DB_PASS=replace_with_database_password
   DB_SSLMODE=prefer
   JWT_SECRET=replace_with_a_random_64_character_secret
   JWT_EXPIRES_IN=86400
   CORS_ALLOWED_ORIGIN=https://your-domain.example
   ```

5. Add SMTP settings if password recovery is enabled. Use a newly generated provider app password; never commit it.
6. Import the schema using cPanel/phpPgAdmin or `psql`. The included `supabase.sql.sql` is destructive and includes demo accounts, so it is suitable only for a new database.
7. Replace or remove the demo accounts immediately after the initial import.
8. Enable the HostForge SSL certificate and force HTTPS in cPanel.
9. Verify `https://your-domain.example/api/health`, then test login, application submission, password reset, and authenticated operations.

For HostForge's container deployment screen, use the repository root and this start command:

```bash
php -S 0.0.0.0:$PORT router.php
```

The router protects private files and forwards `/api/*` requests to the PHP controller because PHP's built-in server does not process `.htaccess` files.

The `.htaccess` file blocks access to environment files, SQL files, Composer metadata, the legacy backend, dependencies, logs, and repository metadata. Keep `AllowOverride` enabled so these protections and API rewrite rules take effect.

## Environment variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `APP_ENV` | Yes | Use `production` on HostForge. |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS` | Yes | PostgreSQL connection. |
| `DB_SSLMODE` | No | Defaults to `prefer`; use the value required by the database provider. |
| `JWT_SECRET` | Yes | Random secret of at least 32 characters. The API rejects missing or known default secrets. |
| `JWT_EXPIRES_IN` | No | Token lifetime in seconds; defaults to 86400. |
| `CORS_ALLOWED_ORIGIN` | No | Exact permitted cross-origin URL. Same-origin deployments may leave this blank. |
| `MAIL_*` | For password reset | SMTP host, port, username, password, encryption, and sender details. |

## Database changes

Database tables are never created during normal web requests. Apply schema changes explicitly before deploying code:

- New disposable installation: `supabase.sql.sql`
- Existing database: `database-migrations.sql`

Back up the production database before running any migration.

## Security notes

- Local `.env*` files are ignored except for `.env.example`.
- Never commit SMTP app passwords, database passwords, JWT secrets, SQL exports, or employee data.
- Production errors are logged server-side and return a generic response to clients.
- CORS is no longer open to every origin.
- Rotate any credential that has previously been stored in plaintext or shared.

## Repository layout

```text
api/                     Production PHP/PostgreSQL REST API
backend/                 Legacy Node.js/SQLite implementation and tests
index.html               Login and password recovery
dashboard.html           HR administrator portal
user-dashboard.html      Employee self-service portal
apply.html               Public application form
config.js                Browser API URL resolution
auth.js                  Browser authentication client
supabase.sql.sql          Destructive fresh-install schema with demo data
database-migrations.sql  Non-destructive migration for existing databases
.env.example             Production environment template
.htaccess                LiteSpeed/Apache protection and API routing
router.php               Container server protection and API routing
```
