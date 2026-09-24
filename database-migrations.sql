-- HRMS non-destructive PostgreSQL migration for existing installations.
-- Run this against the target database before deploying the PHP API.

ALTER TABLE applicants ADD COLUMN IF NOT EXISTS department VARCHAR(100) DEFAULT 'General';
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS gender VARCHAR(20) DEFAULT '';
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS address TEXT DEFAULT '';
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS date_of_birth VARCHAR(20) DEFAULT '';
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS age INT DEFAULT 0;
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS place_of_birth VARCHAR(100) DEFAULT '';
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS tin VARCHAR(50) DEFAULT '';
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS civil_status VARCHAR(20) DEFAULT '';
ALTER TABLE applicants ADD COLUMN IF NOT EXISTS emergency_contact VARCHAR(50) DEFAULT '';

ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_name VARCHAR(50) DEFAULT '';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS first_name VARCHAR(50) DEFAULT '';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS middle_name VARCHAR(50) DEFAULT '';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_name VARCHAR(100) DEFAULT '';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_account VARCHAR(100) DEFAULT '';

CREATE TABLE IF NOT EXISTS leave_requests (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    leave_type VARCHAR(20) NOT NULL,
    start_date VARCHAR(20) NOT NULL,
    end_date VARCHAR(20) NOT NULL,
    days_count INT DEFAULT 1,
    reason TEXT DEFAULT '',
    status VARCHAR(20) DEFAULT 'Pending',
    admin_remarks TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS attendance (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    date VARCHAR(20) NOT NULL,
    clock_in VARCHAR(30) DEFAULT '',
    clock_out VARCHAR(30) DEFAULT '',
    status VARCHAR(20) DEFAULT 'Present',
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS payslips (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    pay_period VARCHAR(100) NOT NULL,
    pay_date VARCHAR(20) NOT NULL,
    basic_salary NUMERIC(12,2) DEFAULT 0,
    allowances NUMERIC(12,2) DEFAULT 0,
    deductions NUMERIC(12,2) DEFAULT 0,
    net_pay NUMERIC(12,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'Paid',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS employee_documents (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    doc_type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT DEFAULT '',
    status VARCHAR(20) DEFAULT 'Available',
    file_url TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS password_resets (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    otp_hash VARCHAR(255) NOT NULL,
    reset_token_hash VARCHAR(255),
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    verified_at TIMESTAMPTZ,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS password_resets_user_idx
    ON password_resets(user_id, created_at DESC);
