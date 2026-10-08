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
4. For an existing installation, run `database-migrations.sql` instead. It consolidates existing applicant records with matching email addresses or matching full name and phone number, preserves linked interviews and missing profile details (including applicant identification numbers and document uploads), adds employee profile fields for hired applicants, backfills available applicant documents, enforces uniqueness for future submissions, and updates interview status values.
   The migration also allows the Admin Employee Directory to categorize records as **Complete** or **Unhired**, stores employee comments used by the Unhired module, and adds certificate-receipt tracking for the Employee module.
   The Admin Employee Directory also shows a separate **Complete Onboarding** status when an employee has at least one required onboarding task and all required tasks are completed; this does not change the employee's operational status.
   It also prevents duplicate full names across employee and applicant records (case-insensitive and whitespace-normalized), while allowing the corresponding employee record for a hired applicant with the same email. Resolve any other existing duplicate names before applying the migration.
   The migration supports a distinct `hr` user role and converts `phnhes@gmail.com` from Admin to HR. After applying it, that account must sign out and back in to receive an HR-role session. HR accounts remain excluded from Unhired employee records across employee, onboarding, account, document, and dashboard API views.
   The dashboard includes Ness, a system-workflow help assistant for HR and Admin. It uses curated, server-side answers about this application only, returns an explicit outside-scope response for other questions, and does not query or send employee/applicant records to an AI provider.
   For an existing installation that only needs this name-protection rule, back up the database and run `repair-duplicate-person-names.sql`. The repair does not remove or merge existing records.
   If only the employee status constraint needs repair, back up the database and run `repair-employee-status.sql` against the same database used by the API. This focused repair preserves employee rows and reports the active database and resulting constraint.
   New onboarding checklists set due dates from the checklist start date: Contract Signed in 5 days, Health Card Picture in 20 days, Orientation & Company Policy Review and Role-Specific Training in 10 days, and Complete Required Initial Training in 15 days.
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

5. Add SMTP settings for password recovery, Admin/HR login verification, and interview notifications. Use a newly generated provider app password; never commit it.
6. Import the schema using cPanel/phpPgAdmin or `psql`. The included `supabase.sql.sql` is destructive and includes demo accounts, so it is suitable only for a new database.
7. Replace or remove the demo accounts immediately after the initial import.
8. Enable the HostForge SSL certificate and force HTTPS in cPanel.
9. Verify `https://your-domain.example/api/health`, then test login, application submission, password reset, and authenticated operations.

The public application form accepts up to seven files, each no larger than 5 MB. Configure the HostForge PHP limits to allow the full multipart request (`upload_max_filesize` at least `5M`, `post_max_size` at least `40M`, and `max_file_uploads` at least `7`). Otherwise PHP may discard the submitted form before the API can validate it.

The reverse proxy must also accept the complete upload. On 2026-10-08, the deployed `corehr.tour-sphere.com` portal returned a non-JSON **413 Request Entity Too Large** page from nginx/1.27.5 for a deliberately incomplete 5 MB upload, while its database health and private receipt queries returned HTTP 200. The incomplete upload cannot pass candidate validation or insert a record. This confirms a deployment upload-size mismatch independent of the database migration. The previous frontend treated the HTML 413 as an uncertain submission; the updated form recognizes HTTP 413 before parsing its body and displays the upload-limit cause immediately.

The HostForge operator must configure the actual proxy serving this application, including any outer proxy, with sufficient request capacity. For Nginx, set the following directive in the applicable `http`, `server`, or `location` block, validate the configuration, and reload Nginx:

```nginx
client_max_body_size 40m;
```

Reference: https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size. Adding PHP settings or `.htaccess` rules cannot change an upstream Nginx request limit. A repository push does not configure HostForge's managed proxy; use its available upload-limit control or ask HostForge support to apply this setting for `corehr.tour-sphere.com`. Also verify the PHP multipart limits above in the deployed runtime. For a PHP built-in server, pass upload settings at process startup (it does not apply Apache `.htaccess` settings):

```bash
php -d upload_max_filesize=5M -d post_max_size=40M -d max_file_uploads=7 -S 0.0.0.0:$PORT router.php
```

After changing the hosting settings, repeat an invalid 5 MB multipart upload with required fields omitted. It should reach the application's JSON HTTP 400 validator instead of Nginx HTTP 413, without creating a candidate. Then verify a valid candidate submission and its receipt. A tiny invalid upload took approximately 11 seconds in the same investigation; worker queuing or intermittent database/network delays still require server logs if they continue after the upload limit is fixed. These public probes do not determine whether a particular earlier candidate submission was saved.

### Application submission repair

Before deploying the updated `api/index.php`, `api/config.php`, and `apply.html`, back up the production database and run `repair-application-submission.sql` against the database configured for that PHP deployment. This focused migration preserves candidate rows and uploads, adds private submission receipts and lookup indexes, and replaces the shared person-name lock with a lock for each normalized name. It also installs any missing person-name triggers. Do not import a database dump over production to apply this repair. If the migration reports a lock timeout, it rolls back; apply it during a quiet period and verify successful completion before updating the PHP files.

The form retains its 90-second upload/request deadline. PostgreSQL submission queries have a 10-second statement limit and a 3-second lock limit. Optional activity recording has a 2-second limit and runs after the success response is released. Receipts use 32 random bytes; the public receipt endpoint returns only whether that receipt was saved, without exposing candidate information. Uncertain requests retain their receipt for a safe manual retry; a lost response triggers a receipt lookup instead of automatically sending the files again. For pre-repair submissions without a receipt, HR must inspect the existing applicant record to determine whether it was saved.

The supplied database dump contains a global advisory lock in `enforce_unique_person_name`, so a long-running employee/applicant transaction can hold up every application. This is a reproducible local defect, but it is not proof of the particular production timeout. To determine the deployed cause, correlate the HostForge access log, PHP error log, and PostgreSQL activity at the time of a slow submission. Updated PHP logs emit `HRMS submission` records with the last stage, server processing duration, HTTP status, and `database_saved` flag, without candidate details or receipt secrets. PHP processing duration begins after the web server has received/parses the multipart upload; use access-log duration to identify time spent uploading, waiting for a PHP worker, or proxy buffering. An unresponsive single-worker container can also queue submissions behind SMTP requests from other users, even though applications themselves do not send email.

During an incident, run the following read-only query as the database operator. It reports blocking sessions without printing SQL text or candidate details:

```sql
SELECT pid, state, wait_event_type, wait_event,
       clock_timestamp() - query_start AS elapsed,
       pg_blocking_pids(pid) AS blockers
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid();
```

Confirm the deployed PHP runtime has `pdo_pgsql` and `fileinfo`, correct database connectivity/SSL settings, writable persistent `api/applicant-id-photos` storage, and sufficient multipart limits. Test the actual public application URL and inspect the browser request URL to confirm it reaches this PHP deployment. A success from `/api/health` proves a database connection only; it does not verify INSERT permissions, triggers, uploads, or worker capacity. Do not terminate blocking production sessions before understanding their transactions.

Regression checks: `node backend/test-submission-frontend.js` tests lost-response reconciliation, stable retry receipts, new-form receipts, validation errors, and the double-click guard. `python backend/test-submission.py` creates and removes a temporary PostgreSQL database and PHP server using synthetic candidate data only. It requires PostgreSQL binaries (`HRMS_TEST_PG_BIN` may override their location), PHP, and free local ports 55439/55440. It tests real multipart uploads, receipt lookup/retry, concurrent inserts, unrelated-name locks, bounded lock failure and upload cleanup, and success delivery before blocked activity logging.

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
| `MAIL_*` | For email notifications | SMTP host, port, username, password, encryption, and sender details. Required for password reset, Admin/HR login verification, and interview scheduling emails. |

## Database changes

Database tables are never created during normal web requests. Apply schema changes explicitly before deploying code:

- New disposable installation: `supabase.sql.sql`
- Existing database: `database-migrations.sql`

Back up the production database before running any migration.

If updating an interview to **Did Not Pass the Interview** fails, run `repair-interview-status.sql` against the same database used by the API. This repair expands the interview status column to 50 characters and includes every supported interview status while preserving existing interviews.

To change existing employee and employee-account departments from **General** to **HR**, run `repair-general-employee-departments.sql` against the same database used by the API.

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
