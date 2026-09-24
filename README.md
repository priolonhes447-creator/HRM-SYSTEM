# HRMS - Human Resource Management System

A production-ready, full-featured Human Resource Management System featuring a modern **Vanilla CSS/JS** frontend, **PHP (PostgreSQL)** REST API, **JWT Authentication**, interactive **AI Assistant**, and automated test suites.


## 🏗️ Technical Architecture & Stack



## 🚀 Quick Setup & Deployment Guide

1. Create the PostgreSQL database and run [`supabase.sql.sql`](supabase.sql.sql) for a new installation. For an existing database, run [`database-migrations.sql`](database-migrations.sql) instead.
2. Copy [.env.example](.env.example) to the server-side `.env` file and set `DB_*`, `JWT_SECRET`, and SMTP values.
3. From the project root, install PHP dependencies:
   ```bash
   composer install --no-dev --optimize-autoloader
   ```
4. Upload the project to the PHP document root, including `vendor/`, or run Composer on the host.
5. Ensure PHP has `pdo_pgsql`, `openssl`, and `zip` enabled, then start Apache.
6. Open `http://localhost/hr-folder/index.html` locally or the Hostforge domain after deployment.


## 🔑 Demo Credentials

| Role | Email | Password | Access Portal |
| :--- | :--- | :--- | :--- |
| **Admin** | `admin@gmail.com` | `admin123` | [dashboard.html](dashboard.html) (HR Command Center) |
| **Employee** | `user@gmail.com` | `user123` | [user-dashboard.html](user-dashboard.html) (Employee Portal) |

## Password Recovery Email Setup

Password recovery uses PHPMailer and Gmail SMTP. From the project root, install dependencies with `composer install`. Copy the SMTP variables from `.env.example` into the server-side `.env` file, then set `MAIL_USERNAME` and `MAIL_FROM_ADDRESS` to the system sender Gmail address and `MAIL_PASSWORD` to a Google App Password. Never place this password in frontend files.

The API creates the `password_resets` PostgreSQL table automatically if it is missing; the full definition is also included in `supabase.sql.sql`.


## 🧪 Automated Testing

Run the automated test suite verifying all 71 endpoint, authentication, announcement, onboarding, and pipeline tests:

```bash
cd backend
npm test
```


## 🛠️ Publishing to GitHub

```bash
# 1. Initialize repository
git init

# 2. Stage files (ignoring runtime databases & logs)
git add .

# 3. Create initial commit
git commit -m "feat: Production publication release of HRMS System"

# 4. Push to remote repository
git remote add origin https://github.com/YOUR_USERNAME/hr-folder.git
git branch -M main
git push -u origin main
```


## 📁 Repository Structure

```
hr-folder/
├── api/                    # PHP REST API (Config, Router, JWT)
├── backend/                # Node.js Express REST API & SQLite DB
│   ├── ai.js               # AI Assistant handler
│   ├── database.js         # SQLite database operations & schema
│   ├── server.js           # Express API server entry point
│   ├── test-api.js         # Core API test suite
│   ├── test-announcements.js # Announcements test suite
│   ├── test-interconnect.js  # Interconnectivity test suite
│   └── test-onboarding.js  # Onboarding workflow test suite
├── .env.example            # Environment template for PHP/Supabase
├── .gitignore              # Git ignore rules for node_modules, logs & databases
├── .htaccess               # Apache URL rewrite rules for XAMPP
├── logo.png                # HRMS application logo asset
├── index.html              # Login & Authentication Page
├── dashboard.html          # HR Manager Command Center
├── user-dashboard.html     # Employee Self-Service Portal
├── config.js               # Frontend API URL configuration
├── auth.js                 # JS authentication & fetch API client
├── ai-assistant.js         # Dynamic AI assistant UI client
├── ai-assistant.css        # AI assistant styles
├── netlify.toml            # Netlify deployment configuration
├── _redirects              # Netlify SPA routing rules
└── supabase_schema.sql     # Supabase PostgreSQL DDL & seed script
```
