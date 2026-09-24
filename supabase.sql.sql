-- ============================================================
-- HRMS SUPABASE POSTGRESQL SCHEMA & INITIAL DATA
-- Run this script in your Supabase SQL Editor
-- ============================================================

-- 1. DROP EXISTING TABLES (CAUTION: FOR RESETTING SCHEMA)
DROP TABLE IF EXISTS employee_documents CASCADE;
DROP TABLE IF EXISTS password_resets CASCADE;
DROP TABLE IF EXISTS payslips CASCADE;
DROP TABLE IF EXISTS attendance CASCADE;
DROP TABLE IF EXISTS leave_requests CASCADE;
DROP TABLE IF EXISTS announcement_reads CASCADE;
DROP TABLE IF EXISTS announcements CASCADE;
DROP TABLE IF EXISTS onboarding_tasks CASCADE;
DROP TABLE IF EXISTS applicants CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- 2. USERS TABLE (Portal Credentials)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'employee' CHECK (role IN ('admin', 'employee')),
    name VARCHAR(100) NOT NULL,
    position VARCHAR(100) DEFAULT '',
    department VARCHAR(100) DEFAULT '',
    employee_id VARCHAR(50) UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. EMPLOYEES TABLE (Core HR Records)
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    employee_id VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    department VARCHAR(100) DEFAULT 'General',
    role VARCHAR(100) DEFAULT '',
    status VARCHAR(20) DEFAULT 'Active' CHECK (status IN ('Active', 'On Leave', 'Onboarding', 'Inactive')),
    phone VARCHAR(50) DEFAULT '',
    address TEXT DEFAULT '',
    date_of_birth VARCHAR(20) DEFAULT '',
    gender VARCHAR(20) DEFAULT '',
    emergency_contact VARCHAR(50) DEFAULT '',
    age INT DEFAULT 0,
    place_of_birth VARCHAR(100) DEFAULT '',
    tin VARCHAR(50) DEFAULT '',
    civil_status VARCHAR(20) DEFAULT '',
    last_name VARCHAR(50) DEFAULT '',
    first_name VARCHAR(50) DEFAULT '',
    middle_name VARCHAR(50) DEFAULT '',
    bank_name VARCHAR(100) DEFAULT '',
    bank_account VARCHAR(100) DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. APPLICANTS TABLE (Recruitment Pipeline)
CREATE TABLE applicants (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    surname VARCHAR(100) DEFAULT '',
    middle_name VARCHAR(100) DEFAULT '',
    first_name VARCHAR(100) DEFAULT '',
    position VARCHAR(100) NOT NULL,
    department VARCHAR(100) DEFAULT 'General',
    email VARCHAR(100) DEFAULT '',
    phone VARCHAR(50) DEFAULT '',
    gender VARCHAR(20) DEFAULT '',
    address TEXT DEFAULT '',
    date_of_birth VARCHAR(20) DEFAULT '',
    age INT DEFAULT 0,
    place_of_birth VARCHAR(100) DEFAULT '',
    tin VARCHAR(50) DEFAULT '',
    civil_status VARCHAR(20) DEFAULT '',
    emergency_contact VARCHAR(50) DEFAULT '',
    applied_date VARCHAR(20) NOT NULL,
    status VARCHAR(20) DEFAULT 'New' CHECK (status IN ('New', 'Interviewing', 'Hired', 'Rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. ANNOUNCEMENTS TABLE (Company Communication)
CREATE TABLE announcements (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    author VARCHAR(100) DEFAULT 'HR',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. ANNOUNCEMENT READS TABLE (Per-User Read Tracking)
CREATE TABLE announcement_reads (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    announcement_id INT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_announcement UNIQUE(user_id, announcement_id)
);

-- 7. ONBOARDING TASKS TABLE (New Hire Onboarding)
CREATE TABLE onboarding_tasks (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    task VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'Pending' CHECK (status IN ('Pending', 'In Progress', 'Completed')),
    due_date VARCHAR(20) DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 8. EMPLOYEE SELF-SERVICE TABLES
CREATE TABLE leave_requests (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    leave_type VARCHAR(20) NOT NULL,
    start_date VARCHAR(20) NOT NULL,
    end_date VARCHAR(20) NOT NULL,
    days_count INT DEFAULT 1,
    reason TEXT DEFAULT '',
    status VARCHAR(20) DEFAULT 'Pending',
    admin_remarks TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE attendance (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    date VARCHAR(20) NOT NULL,
    clock_in VARCHAR(30) DEFAULT '',
    clock_out VARCHAR(30) DEFAULT '',
    status VARCHAR(20) DEFAULT 'Present',
    notes TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE payslips (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    pay_period VARCHAR(100) NOT NULL,
    pay_date VARCHAR(20) NOT NULL,
    basic_salary NUMERIC(12,2) DEFAULT 0,
    allowances NUMERIC(12,2) DEFAULT 0,
    deductions NUMERIC(12,2) DEFAULT 0,
    net_pay NUMERIC(12,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'Paid',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE employee_documents (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(50) DEFAULT '',
    doc_type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT DEFAULT '',
    status VARCHAR(20) DEFAULT 'Available',
    file_url TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. PASSWORD RECOVERY OTP STATE
CREATE TABLE password_resets (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    otp_hash VARCHAR(255) NOT NULL,
    reset_token_hash VARCHAR(255),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    verified_at TIMESTAMP WITH TIME ZONE,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX password_resets_user_idx ON password_resets(user_id, created_at DESC);

-- ============================================================
-- SEED INITIAL DATA
-- Default Passwords:
-- admin@gmail.com -> admin123
-- user@gmail.com  -> user123
-- ============================================================

INSERT INTO users (email, password, role, name, position, department, employee_id) VALUES
('admin@gmail.com', '$2y$10$d5JeVuTsO17fS3.aEOwTsezZUeQwV75f2SVMmjrd.anooVk0Fxkoa', 'admin', 'Admin User', 'HR Manager', 'Human Resources', 'ADMIN001'),
('user@gmail.com', '$2y$10$lHPoq.T8KYiOtBP94M5To.YQo6XTMsIg4hCobWBED6sWY.ho0BdtC', 'employee', 'Regular User', 'Software Engineer', 'IT', 'EMP004');

INSERT INTO employees (employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact) VALUES
('EMP001', 'Alice Johnson', 'alice@company.com', 'IT', 'Developer', 'Active', '0917-111-1111', '123 Tech St, Manila', '1990-05-12', 'Female', '0917-999-0001'),
('EMP002', 'Bob Smith', 'bob@company.com', 'Sales', 'Manager', 'Active', '0918-222-2222', '456 Sales Ave, Quezon City', '1988-11-23', 'Male', '0918-999-0002'),
('EMP003', 'Charlie Brown', 'charlie@company.com', 'HR', 'Recruiter', 'On Leave', '0919-333-3333', '789 HR Rd, Makati', '1995-02-08', 'Male', '0919-999-0003'),
('EMP004', 'Regular User', 'user@gmail.com', 'IT', 'Software Engineer', 'Active', '0920-444-4444', '101 Dev Way, Taguig', '1992-07-15', 'Male', '0920-999-0004');

INSERT INTO applicants (name, surname, middle_name, first_name, position, email, phone, applied_date, status) VALUES
('David Lee', 'Lee', '', 'David', 'UI Designer', 'david@email.com', '0917-555-5555', CURRENT_DATE::text, 'Interviewing'),
('Eva Green', 'Green', '', 'Eva', 'Backend Dev', 'eva@email.com', '0918-666-6666', CURRENT_DATE::text, 'New');

INSERT INTO announcements (title, content, author) VALUES
('Upcoming Town Hall Meeting', 'Join us this Friday at 3:00 PM for the quarterly review. Refreshments will be served!', 'Admin User'),
('New Office Hours', 'Effective next Monday, the office will open at 8:30 AM. Please adjust your schedules accordingly.', 'Admin User'),
('Welcome to Our New Team Members', 'Please join us in welcoming the new hires joining the Engineering and Sales teams this month!', 'HR');

INSERT INTO onboarding_tasks (employee_id, task, status, due_date) VALUES
(4, 'Contract Signed', 'Completed', CURRENT_DATE::text),
(4, 'Email & Account Created', 'Completed', CURRENT_DATE::text),
(4, 'IT Assets Assigned (Laptop, Peripherals)', 'In Progress', CURRENT_DATE::text),
(4, 'Company ID / Access Badge Issued', 'Pending', CURRENT_DATE::text),
(4, 'Orientation & Company Policy Review', 'Pending', CURRENT_DATE::text),
(4, 'Department Introductions & Buddy Assigned', 'Pending', CURRENT_DATE::text),
(4, 'Role-Specific Training', 'Pending', CURRENT_DATE::text),
(4, '30-Day Check-in & Feedback Session', 'Pending', CURRENT_DATE::text);
