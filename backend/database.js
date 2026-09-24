const Database = require('better-sqlite3');
const path = require('path');
const bcrypt = require('bcryptjs');

const DB_PATH = path.join(__dirname, 'hrms.db');
const db = new Database(DB_PATH);

// Enable WAL mode for better performance
db.pragma('journal_mode = WAL');

// ==================== CREATE TABLES ====================
function initializeDatabase() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'employee' CHECK(role IN ('admin','employee')),
      name TEXT NOT NULL,
      position TEXT DEFAULT '',
      department TEXT DEFAULT '',
      employee_id TEXT UNIQUE,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE IF NOT EXISTS employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      email TEXT UNIQUE NOT NULL,
      department TEXT DEFAULT 'General',
      role TEXT DEFAULT '',
      status TEXT DEFAULT 'Active' CHECK(status IN ('Active','On Leave','Onboarding','Inactive')),
      phone TEXT DEFAULT '',
      address TEXT DEFAULT '',
      date_of_birth TEXT DEFAULT '',
      gender TEXT DEFAULT '',
      emergency_contact TEXT DEFAULT '',
      age INTEGER DEFAULT 0,
      place_of_birth TEXT DEFAULT '',
      tin TEXT DEFAULT '',
      civil_status TEXT DEFAULT '',
      last_name TEXT DEFAULT '',
      first_name TEXT DEFAULT '',
      middle_name TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS applicants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      surname TEXT DEFAULT '',
      middle_name TEXT DEFAULT '',
      first_name TEXT DEFAULT '',
      position TEXT NOT NULL,
      email TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      applied_date TEXT NOT NULL,
      status TEXT DEFAULT 'New' CHECK(status IN ('New','Interviewing','Hired','Rejected')),
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS leave_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      employee_id TEXT DEFAULT '',
      leave_type TEXT NOT NULL CHECK(leave_type IN ('Vacation','Sick','Emergency','Parental','Bereavement')),
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      days_count INTEGER DEFAULT 1,
      reason TEXT DEFAULT '',
      status TEXT DEFAULT 'Pending' CHECK(status IN ('Pending','Approved','Rejected')),
      admin_remarks TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS attendance (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      employee_id TEXT DEFAULT '',
      date TEXT NOT NULL,
      clock_in TEXT DEFAULT '',
      clock_out TEXT DEFAULT '',
      status TEXT DEFAULT 'Present' CHECK(status IN ('Present','Late','On Leave','Half Day','Absent')),
      notes TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS payslips (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      employee_id TEXT DEFAULT '',
      pay_period TEXT NOT NULL,
      pay_date TEXT NOT NULL,
      basic_salary REAL DEFAULT 0,
      allowances REAL DEFAULT 0,
      deductions REAL DEFAULT 0,
      net_pay REAL DEFAULT 0,
      status TEXT DEFAULT 'Paid' CHECK(status IN ('Paid','Processing')),
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS employee_documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      employee_id TEXT DEFAULT '',
      doc_type TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      status TEXT DEFAULT 'Available' CHECK(status IN ('Available','Requested','Issued')),
      file_url TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS announcements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      author TEXT DEFAULT 'HR',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE IF NOT EXISTS announcement_reads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      announcement_id INTEGER NOT NULL,
      read_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, announcement_id),
      FOREIGN KEY (user_id) REFERENCES users(id),
      FOREIGN KEY (announcement_id) REFERENCES announcements(id)
    );

    CREATE TABLE IF NOT EXISTS onboarding_tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id INTEGER NOT NULL,
      task TEXT NOT NULL,
      status TEXT DEFAULT 'Pending' CHECK(status IN ('Pending','In Progress','Completed')),
      due_date TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (employee_id) REFERENCES employees(id)
    );
  `);

  // MIGRATION: add employee detail columns to existing databases (ignore if already added)
  const employeeColumns = db.prepare("PRAGMA table_info(employees)").all().map(c => c.name);
  const addColumnIfMissing = (name, type, def) => {
    if (!employeeColumns.includes(name)) {
      db.exec(`ALTER TABLE employees ADD COLUMN ${name} ${type} DEFAULT ${def}`);
    }
  };
addColumnIfMissing('phone', 'TEXT', "''");
  addColumnIfMissing('address', 'TEXT', "''");
  addColumnIfMissing('date_of_birth', 'TEXT', "''");
  addColumnIfMissing('gender', 'TEXT', "''");
  addColumnIfMissing('emergency_contact', 'TEXT', "''");
  addColumnIfMissing('age', 'INTEGER', '0');
  addColumnIfMissing('place_of_birth', 'TEXT', "''");
  addColumnIfMissing('tin', 'TEXT', "''");
  addColumnIfMissing('civil_status', 'TEXT', "''");
  addColumnIfMissing('last_name', 'TEXT', "''");
  addColumnIfMissing('first_name', 'TEXT', "''");
  addColumnIfMissing('middle_name', 'TEXT', "''");
  addColumnIfMissing('bank_name', 'TEXT', "''");
  addColumnIfMissing('bank_account', 'TEXT', "''");

  const applicantColumns = db.prepare("PRAGMA table_info(applicants)").all().map(c => c.name);
  const addAppColumnIfMissing = (name, type, def) => {
    if (!applicantColumns.includes(name)) {
      db.exec(`ALTER TABLE applicants ADD COLUMN ${name} ${type} DEFAULT ${def}`);
    }
  };
  addAppColumnIfMissing('surname', 'TEXT', "''");
  addAppColumnIfMissing('middle_name', 'TEXT', "''");
  addAppColumnIfMissing('first_name', 'TEXT', "''");
  addAppColumnIfMissing('department', 'TEXT', "'General'");
  addAppColumnIfMissing('gender', 'TEXT', "''");
  addAppColumnIfMissing('address', 'TEXT', "''");
  addAppColumnIfMissing('date_of_birth', 'TEXT', "''");
  addAppColumnIfMissing('age', 'INTEGER', '0');
  addAppColumnIfMissing('place_of_birth', 'TEXT', "''");
  addAppColumnIfMissing('tin', 'TEXT', "''");
  addAppColumnIfMissing('civil_status', 'TEXT', "''");
  addAppColumnIfMissing('emergency_contact', 'TEXT', "''");

  // Seed default users if table is empty
  const userCount = db.prepare('SELECT COUNT(*) as count FROM users').get();
  if (userCount.count === 0) {
    seedDefaultData();
  } else {
    ensureDefaultAccountsExist();
  }
  syncUsersWithEmployees();
  seedEssData();
  db.pragma('wal_checkpoint(FULL)');
}

function syncUsersWithEmployees() {
  // Enforce rule: "If it is not in the Employee Records Management, it should not be in the User Accounts either."
  // Auto-create employee records for any user account that lacks one.
  const usersWithoutEmp = db.prepare(`
    SELECT u.* FROM users u
    WHERE NOT EXISTS (
      SELECT 1 FROM employees e
      WHERE (e.employee_id = u.employee_id AND u.employee_id IS NOT NULL AND u.employee_id != '')
         OR LOWER(e.email) = LOWER(u.email)
    )
  `).all();

  for (const u of usersWithoutEmp) {
    let empCode = u.employee_id;
    if (!empCode) {
      empCode = (u.role === 'admin' ? 'ADMIN' : 'EMP') + String(u.id).padStart(3, '0');
      db.prepare('UPDATE users SET employee_id = ? WHERE id = ?').run(empCode, u.id);
    }
    db.prepare(`
      INSERT INTO employees (employee_id, name, email, department, role, status)
      VALUES (?, ?, ?, ?, ?, 'Active')
    `).run(
      empCode,
      u.name || 'User',
      u.email,
      u.department || (u.role === 'admin' ? 'Human Resources' : 'General'),
      u.position || (u.role === 'admin' ? 'HR Manager' : 'Staff')
    );
  }
}

function ensureDefaultAccountsExist() {
  const salt = bcrypt.genSaltSync(10);
  const insertUser = db.prepare(
    `INSERT INTO users (email, password, role, name, position, department, employee_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  );

  const insertEmp = db.prepare(
    `INSERT INTO employees (employee_id, name, email, department, role, status)
     VALUES (?, ?, ?, ?, ?, 'Active')`
  );

  const admin = db.prepare('SELECT id FROM users WHERE email = ?').get('admin@gmail.com');
  if (!admin) {
    insertUser.run('admin@gmail.com', bcrypt.hashSync('admin123', salt), 'admin', 'Admin User', 'HR Manager', 'Human Resources', 'ADMIN001');
  }
  const adminEmp = db.prepare('SELECT id FROM employees WHERE employee_id = ? OR LOWER(email) = LOWER(?)').get('ADMIN001', 'admin@gmail.com');
  if (!adminEmp) {
    insertEmp.run('ADMIN001', 'Admin User', 'admin@gmail.com', 'Human Resources', 'HR Manager');
  }

  const user = db.prepare('SELECT id FROM users WHERE email = ?').get('user@gmail.com');
  if (!user) {
    insertUser.run('user@gmail.com', bcrypt.hashSync('user123', salt), 'employee', 'Regular User', 'Software Engineer', 'IT', 'EMP004');
  }
  const userEmp = db.prepare('SELECT id FROM employees WHERE employee_id = ? OR LOWER(email) = LOWER(?)').get('EMP004', 'user@gmail.com');
  if (!userEmp) {
    insertEmp.run('EMP004', 'Regular User', 'user@gmail.com', 'IT', 'Software Engineer');
  }
}

function seedDefaultData() {
  const salt = bcrypt.genSaltSync(10);
  const adminPassword = bcrypt.hashSync('admin123', salt);
  const userPassword = bcrypt.hashSync('user123', salt);

  const insertUser = db.prepare(
    `INSERT INTO users (email, password, role, name, position, department, employee_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  );

  insertUser.run('admin@gmail.com', adminPassword, 'admin', 'Admin User', 'HR Manager', 'Human Resources', 'ADMIN001');
  insertUser.run('user@gmail.com', userPassword, 'employee', 'Regular User', 'Software Engineer', 'IT', 'EMP004');

  // Seed sample employees (including accounts for default users to maintain synchronization)
  const insertEmp = db.prepare(
    `INSERT INTO employees (employee_id, name, email, department, role, status,
       phone, address, date_of_birth, gender, emergency_contact)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  insertEmp.run('ADMIN001', 'Admin User', 'admin@gmail.com', 'Human Resources', 'HR Manager', 'Active', '0917-000-0000', '1 HR Way, Manila', '1985-01-01', 'Male', '0917-999-0000');
  insertEmp.run('EMP004', 'Regular User', 'user@gmail.com', 'IT', 'Software Engineer', 'Active', '0917-444-4444', '4 Tech St, Manila', '1992-04-04', 'Male', '0917-999-0004');
  insertEmp.run('EMP001', 'Alice Johnson', 'alice@company.com', 'IT', 'Developer', 'Active', '0917-111-1111', '123 Tech St, Manila', '1990-05-12', 'Female', '0917-999-0001');
  insertEmp.run('EMP002', 'Bob Smith', 'bob@company.com', 'Sales', 'Manager', 'Active', '0918-222-2222', '456 Sales Ave, Quezon City', '1988-11-23', 'Male', '0918-999-0002');
  insertEmp.run('EMP003', 'Charlie Brown', 'charlie@company.com', 'HR', 'Recruiter', 'On Leave', '0919-333-3333', '789 HR Rd, Makati', '1995-02-08', 'Male', '0919-999-0003');

  // Seed sample applicants
  const insertApp = db.prepare(
    `INSERT INTO applicants (name, position, email, applied_date, status)
     VALUES (?, ?, ?, ?, ?)`
  );
  insertApp.run('David Lee', 'UI Designer', 'david@email.com', new Date().toISOString().split('T')[0], 'Interviewing');
  insertApp.run('Eva Green', 'Backend Dev', 'eva@email.com', new Date().toISOString().split('T')[0], 'New');

  // Seed sample announcements
  const insertAnn = db.prepare(
    `INSERT INTO announcements (title, content, author)
     VALUES (?, ?, ?)`
  );
  insertAnn.run('Upcoming Town Hall Meeting', 'Join us this Friday at 3:00 PM for the quarterly review. Pizza will be served!', 'Admin User');
  insertAnn.run('New Office Hours', 'Effective next Monday, the office will open at 8:30 AM. Please adjust your schedules accordingly.', 'Admin User');
  insertAnn.run('Welcome to Our New Team Members', 'Please join us in welcoming the new hires joining the Engineering and Sales teams this month!', 'HR');
}

// ==================== AUTH QUERIES ====================
function findUserByEmail(email) {
  if (!email) return undefined;
  return db.prepare('SELECT * FROM users WHERE LOWER(email) = LOWER(?)').get(email.trim());
}

function findUserById(id) {
  return db.prepare('SELECT id, email, role, name, position, department, employee_id FROM users WHERE id = ?').get(id);
}

// List all user accounts (without password) for admins.
// Enforces: "If it is not in the Employee Records Management, it should not be in the User Accounts either."
function getAllUsers() {
  db.prepare(`
    DELETE FROM users
    WHERE id NOT IN (
      SELECT u.id FROM users u
      JOIN employees e ON (e.employee_id = u.employee_id AND u.employee_id IS NOT NULL AND u.employee_id != '')
                       OR LOWER(e.email) = LOWER(u.email)
    )
  `).run();

  return db.prepare(
    `SELECT id, email, role, name, position, department, employee_id, created_at
     FROM users ORDER BY created_at DESC, id DESC`
  ).all();
}

// Create a new user account (login credential) with a hashed password
function createUserAccount(user) {
  const emailTrimmed = user.email.trim();
  const existing = db.prepare('SELECT id FROM users WHERE LOWER(email) = LOWER(?)').get(emailTrimmed);
  if (existing) return { error: 'An account with this email already exists.' };

  let empCode = user.employee_id ? user.employee_id.trim() : '';

  // Check if a matching employee record already exists in Employee Records Management
  let emp = null;
  if (empCode) {
    emp = db.prepare("SELECT * FROM employees WHERE employee_id = ? OR LOWER(email) = LOWER(?)").get(empCode, emailTrimmed);
  } else {
    emp = db.prepare("SELECT * FROM employees WHERE LOWER(email) = LOWER(?)").get(emailTrimmed);
  }

  // If NO employee record exists, we MUST create one in Employee Records Management
  if (!emp) {
    if (!empCode) {
      let empSeq = db.prepare('SELECT COUNT(*) as count FROM employees').get().count;
      do {
        empSeq++;
        empCode = (user.role === 'admin' ? 'ADMIN' : 'EMP') + String(empSeq).padStart(3, '0');
      } while (
        db.prepare('SELECT COUNT(*) as count FROM employees WHERE employee_id = ?').get(empCode).count > 0 ||
        db.prepare('SELECT COUNT(*) as count FROM users WHERE employee_id = ?').get(empCode).count > 0
      );
    }

    const empResult = db.prepare(
      `INSERT INTO employees (employee_id, name, email, department, role, status)
       VALUES (?, ?, ?, ?, ?, 'Active')`
    ).run(
      empCode,
      user.name.trim(),
      emailTrimmed,
      user.department || (user.role === 'admin' ? 'Human Resources' : 'General'),
      user.position || (user.role === 'admin' ? 'HR Manager' : 'Staff')
    );
    emp = getEmployeeById(empResult.lastInsertRowid);
  } else if (!empCode && emp.employee_id) {
    empCode = emp.employee_id;
  }

  const salt = bcrypt.genSaltSync(10);
  const hashedPassword = bcrypt.hashSync(user.password, salt);

  const result = db.prepare(
    `INSERT INTO users (email, password, role, name, position, department, employee_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(
    emailTrimmed,
    hashedPassword,
    user.role || 'employee',
    user.name.trim(),
    user.position || (emp ? emp.role : ''),
    user.department || (emp ? emp.department : ''),
    empCode
  );

  const created = findUserById(result.lastInsertRowid);

  if (created && emp && emp.status === 'Onboarding') {
    startOnboarding(emp.id);
  }

  return created;
}

function updateUserProfile(id, profile) {
  const existing = findUserById(id);
  if (!existing) return null;

  db.prepare(
    `UPDATE users SET name = ?, position = ?, department = ? WHERE id = ?`
  ).run(
    profile.name || existing.name,
    profile.position || existing.position,
    profile.department || existing.department,
    id
  );

  // Sync personal contact & bank details to linked employee record
  db.prepare(
    `UPDATE employees SET
       phone = COALESCE(?, phone),
       address = COALESCE(?, address),
       emergency_contact = COALESCE(?, emergency_contact),
       bank_name = COALESCE(?, bank_name),
       bank_account = COALESCE(?, bank_account),
       tin = COALESCE(?, tin)
     WHERE (employee_id = ? AND employee_id IS NOT NULL AND employee_id != '') OR LOWER(email) = LOWER(?)`
  ).run(
    profile.phone || null,
    profile.address || null,
    profile.emergency_contact || null,
    profile.bank_name || null,
    profile.bank_account || null,
    profile.tin || null,
    existing.employee_id,
    existing.email
  );

  return findUserById(id);
}

// Change a user's password (works for any logged-in user). Returns true on success.
function changePassword(userId, newPassword) {
  const user = db.prepare('SELECT id FROM users WHERE id = ?').get(userId);
  if (!user) return false;

  const salt = bcrypt.genSaltSync(10);
  const hashedPassword = bcrypt.hashSync(newPassword, salt);
  db.prepare('UPDATE users SET password = ? WHERE id = ?').run(hashedPassword, userId);
  return true;
}

// Delete a user account (admin only). Removes dependent records first.
function deleteUserAccount(id) {
  const existing = db.prepare('SELECT id, employee_id, email FROM users WHERE id = ?').get(id);
  if (!existing) return null;

  // INTERCONNECT: mark the linked employee (if any) as Inactive so the
  // employee record stays in Employee Records Management, but portal access is deactivated.
  if (existing.employee_id || existing.email) {
    db.prepare(
      "UPDATE employees SET status = 'Inactive' WHERE (employee_id = ? AND employee_id IS NOT NULL AND employee_id != '') OR LOWER(email) = LOWER(?)"
    ).run(existing.employee_id, existing.email);
  }

  // Remove dependent records that reference the user
  db.prepare('DELETE FROM announcement_reads WHERE user_id = ?').run(id);
  db.prepare('DELETE FROM leave_requests WHERE user_id = ?').run(id);
  db.prepare('DELETE FROM attendance WHERE user_id = ?').run(id);
  db.prepare('DELETE FROM payslips WHERE user_id = ?').run(id);
  db.prepare('DELETE FROM employee_documents WHERE user_id = ?').run(id);

  const result = db.prepare('DELETE FROM users WHERE id = ?').run(id);
  return result.changes > 0;
}

// ==================== EMPLOYEE QUERIES ====================
function getAllEmployees() {
  return db.prepare('SELECT * FROM employees ORDER BY created_at DESC').all();
}

function getEmployeeById(id) {
  return db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
}

function addEmployee(emp) {
  const stmt = db.prepare(
    `INSERT INTO employees (employee_id, name, email, department, role, status,
       phone, address, date_of_birth, gender, emergency_contact,
       age, place_of_birth, tin, civil_status, last_name, first_name, middle_name)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const result = stmt.run(
    emp.employee_id, emp.name, emp.email, emp.department, emp.role, emp.status || 'Active',
    emp.phone || '', emp.address || '', emp.date_of_birth || '', emp.gender || '', emp.emergency_contact || '',
    emp.age !== undefined ? emp.age : 0, emp.place_of_birth || '', emp.tin || '', emp.civil_status || '',
    emp.last_name || '', emp.first_name || '', emp.middle_name || ''
  );
  return result.lastInsertRowid;
}

function updateEmployee(id, emp) {
  const existing = getEmployeeById(id);
  if (!existing) return null;

  db.prepare(
    `UPDATE employees SET
       employee_id = ?, name = ?, email = ?, department = ?, role = ?, status = ?,
       phone = ?, address = ?, date_of_birth = ?, gender = ?, emergency_contact = ?,
       age = ?, place_of_birth = ?, tin = ?, civil_status = ?, last_name = ?, first_name = ?, middle_name = ?
     WHERE id = ?`
  ).run(
    emp.employee_id || existing.employee_id,
    emp.name || existing.name,
    emp.email || existing.email,
    emp.department || existing.department,
    emp.role || existing.role,
    emp.status || existing.status,
    emp.phone !== undefined ? emp.phone : existing.phone,
    emp.address !== undefined ? emp.address : existing.address,
    emp.date_of_birth !== undefined ? emp.date_of_birth : existing.date_of_birth,
    emp.gender !== undefined ? emp.gender : existing.gender,
    emp.emergency_contact !== undefined ? emp.emergency_contact : existing.emergency_contact,
    emp.age !== undefined ? emp.age : existing.age,
    emp.place_of_birth !== undefined ? emp.place_of_birth : existing.place_of_birth,
    emp.tin !== undefined ? emp.tin : existing.tin,
    emp.civil_status !== undefined ? emp.civil_status : existing.civil_status,
    emp.last_name !== undefined ? emp.last_name : existing.last_name,
    emp.first_name !== undefined ? emp.first_name : existing.first_name,
    emp.middle_name !== undefined ? emp.middle_name : existing.middle_name,
    id
  );

  // Synchronize changes to linked user account if present
  db.prepare(`
    UPDATE users SET
      employee_id = ?,
      email = ?,
      name = ?,
      department = ?,
      position = ?
    WHERE (employee_id = ? AND employee_id IS NOT NULL AND employee_id != '')
       OR LOWER(email) = LOWER(?)
  `).run(
    emp.employee_id || existing.employee_id,
    emp.email || existing.email,
    emp.name || existing.name,
    emp.department || existing.department,
    emp.role || existing.role,
    existing.employee_id,
    existing.email
  );

  return getEmployeeById(id);
}

function deleteEmployee(id) {
  const emp = getEmployeeById(id);
  if (!emp) return null;

  // INTERCONNECT: remove dependent onboarding tasks (FK constraint)
  db.prepare('DELETE FROM onboarding_tasks WHERE employee_id = ?').run(id);

  // INTERCONNECT: If it is not in Employee Records Management, it should not be in User Accounts either.
  // Cascade deletion to any linked user accounts in User Accounts.
  const linkedUsers = db.prepare(`
    SELECT id FROM users
    WHERE (employee_id = ? AND employee_id IS NOT NULL AND employee_id != '')
       OR LOWER(email) = LOWER(?)
  `).all(emp.employee_id, emp.email);

  for (const u of linkedUsers) {
    db.prepare('DELETE FROM announcement_reads WHERE user_id = ?').run(u.id);
    db.prepare('DELETE FROM leave_requests WHERE user_id = ?').run(u.id);
    db.prepare('DELETE FROM attendance WHERE user_id = ?').run(u.id);
    db.prepare('DELETE FROM payslips WHERE user_id = ?').run(u.id);
    db.prepare('DELETE FROM employee_documents WHERE user_id = ?').run(u.id);
    db.prepare('DELETE FROM users WHERE id = ?').run(u.id);
  }

  const result = db.prepare('DELETE FROM employees WHERE id = ?').run(id);
  return result.changes > 0;
}

// ==================== APPLICANT QUERIES ====================
function getAllApplicants() {
  return db.prepare('SELECT * FROM applicants ORDER BY created_at DESC').all();
}

function addApplicant(app) {
  const surname = (app.surname || app.last_name || '').trim();
  const middleName = (app.middle_name || '').trim();
  const firstName = (app.first_name || '').trim();
  let fullName = (app.name || '').trim();
  if (!fullName) {
    fullName = [firstName, middleName, surname].filter(Boolean).join(' ');
  }

  const stmt = db.prepare(
    `INSERT INTO applicants (
      name, surname, middle_name, first_name, position, department,
      email, phone, gender, address, date_of_birth, age,
      place_of_birth, tin, civil_status, emergency_contact, applied_date, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const result = stmt.run(
    fullName,
    surname,
    middleName,
    firstName,
    app.position || '',
    app.department || 'General',
    app.email || '',
    app.phone || '',
    app.gender || '',
    app.address || '',
    app.date_of_birth || '',
    parseInt(app.age, 10) || 0,
    app.place_of_birth || '',
    app.tin || '',
    app.civil_status || '',
    app.emergency_contact || '',
    app.applied_date || new Date().toISOString().split('T')[0],
    app.status || 'New'
  );
  return result.lastInsertRowid;
}

// Default onboarding checklist (generated for every new hire)
const DEFAULT_ONBOARDING_TASKS = [
  { task: 'Contract Signed', dueOffset: 0 },
  { task: 'Email & Account Created', dueOffset: 0 },
  { task: 'IT Assets Assigned (Laptop, Peripherals)', dueOffset: 1 },
  { task: 'Company ID / Access Badge Issued', dueOffset: 2 },
  { task: 'Orientation & Company Policy Review', dueOffset: 3 },
  { task: 'Department Introductions & Buddy Assigned', dueOffset: 4 },
  { task: 'Role-Specific Training', dueOffset: 7 },
  { task: '30-Day Check-in & Feedback Session', dueOffset: 30 }
];

// Start a standard onboarding checklist for an employee (by employees.id)
function startOnboarding(employeeId) {
  const emp = getEmployeeById(employeeId);
  if (!emp) return null;

  // Skip if this employee already has tasks
  const existing = db.prepare('SELECT COUNT(*) as count FROM onboarding_tasks WHERE employee_id = ?').get(employeeId).count;
  if (existing > 0) {
    return { already_started: true, employee: emp };
  }

  const insert = db.prepare(
    `INSERT INTO onboarding_tasks (employee_id, task, status, due_date)
     VALUES (?, ?, 'Pending', ?)`
  );
  const start = new Date();
  const created = DEFAULT_ONBOARDING_TASKS.map(t => {
    const due = new Date(start);
    due.setDate(due.getDate() + t.dueOffset);
    const dueStr = due.toISOString().split('T')[0];
    insert.run(emp.id, t.task, dueStr);
    return { task: t.task, status: 'Pending', due_date: dueStr };
  });

  return { created, employee: emp };
}

// All onboarding tasks joined with employee info (admin view)
function getAllOnboarding() {
  return db.prepare(
    `SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code, e.department AS emp_department, e.role AS emp_role
     FROM onboarding_tasks ot
     JOIN employees e ON ot.employee_id = e.id
     ORDER BY ot.employee_id, ot.created_at DESC`
  ).all();
}

// Onboarding tasks for a specific employee (matched by employee user code)
function getOnboardingByEmployeeCode(employeeCode) {
  const emp = db.prepare('SELECT * FROM employees WHERE employee_id = ?').get(employeeCode);
  if (!emp) return null;
  return db.prepare(
    `SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code, e.department AS emp_department, e.role AS emp_role
     FROM onboarding_tasks ot
     JOIN employees e ON ot.employee_id = e.id
     WHERE e.employee_id = ?
     ORDER BY ot.created_at ASC`
  ).all(employeeCode);
}

// Get onboarding tasks grouped per employee with progress (admin snapshot)
function getOnboardingSummary() {
  const rows = getAllOnboarding();
  const byEmployee = {};
  for (const r of rows) {
    if (!byEmployee[r.employee_id]) {
      byEmployee[r.employee_id] = { empInfo: r, tasks: [] };
    }
    byEmployee[r.employee_id].tasks.push(r);
  }
const summary = Object.values(byEmployee).map(group => {
    const total = group.tasks.length;
    const completed = group.tasks.filter(t => t.status === 'Completed').length;
    const progress = total ? Math.round((completed / total) * 100) : 0;
    return { ...group.empInfo, task_count: total, completed_count: completed, progress, tasks: group.tasks };
  });
  return summary;
}

function addOnboardingTask(employeeId, task, dueDate, status) {
  const emp = getEmployeeById(employeeId);
  if (!emp) return null;
  const result = db.prepare(
    `INSERT INTO onboarding_tasks (employee_id, task, status, due_date)
     VALUES (?, ?, ?, ?)`
  ).run(employeeId, task, status || 'Pending', dueDate || '');
  return getOnboardingTaskById(result.lastInsertRowid);
}

function getOnboardingTaskById(id) {
  return db.prepare(
    `SELECT ot.*, e.name AS emp_name, e.employee_id AS emp_code
     FROM onboarding_tasks ot JOIN employees e ON ot.employee_id = e.id
     WHERE ot.id = ?`
  ).get(id);
}

function updateOnboardingTask(id, updates) {
  const existing = db.prepare('SELECT * FROM onboarding_tasks WHERE id = ?').get(id);
  if (!existing) return null;
  db.prepare(
    `UPDATE onboarding_tasks SET task = ?, status = ?, due_date = ? WHERE id = ?`
  ).run(
    updates.task || existing.task,
    updates.status || existing.status,
    updates.due_date !== undefined ? updates.due_date : existing.due_date,
    id
  );

  // INTERCONNECT: when ALL tasks for an employee are completed, flip their
  // employee status from 'Onboarding' to 'Active' (onboarding complete).
  const empId = existing.employee_id;
  const remaining = db.prepare(
    "SELECT COUNT(*) as count FROM onboarding_tasks WHERE employee_id = ? AND status != 'Completed'"
  ).get(empId).count;
  if (remaining === 0) {
    db.prepare(
      "UPDATE employees SET status = 'Active' WHERE id = ? AND status = 'Onboarding'"
    ).run(empId);
  }

  return getOnboardingTaskById(id);
}

function deleteOnboardingTask(id) {
  const result = db.prepare('DELETE FROM onboarding_tasks WHERE id = ?').run(id);
  return result.changes > 0;
}

// Onboarding stats for admin dashboard cards
function getOnboardingStats() {
  const activeOnboardings = db.prepare(
    'SELECT COUNT(DISTINCT employee_id) as count FROM onboarding_tasks'
  ).get().count;

  const totalTasks = db.prepare('SELECT COUNT(*) as count FROM onboarding_tasks').get().count;
  const completedTasks = db.prepare(
    "SELECT COUNT(*) as count FROM onboarding_tasks WHERE status = 'Completed'"
  ).get().count;
  const inProgressTasks = db.prepare(
    "SELECT COUNT(*) as count FROM onboarding_tasks WHERE status = 'In Progress'"
  ).get().count;

  // Average progress across employees who have onboarding tasks
  let averageProgress = 0;
  const summary = getOnboardingSummary();
  if (summary.length > 0) {
    averageProgress = Math.round(
      summary.reduce((sum, s) => sum + (s.progress || 0), 0) / summary.length
    );
  }

  return {
    activeOnboardings,
    totalTasks,
    completedTasks,
    inProgressTasks,
    averageProgress
  };
}

function hireApplicant(id) {
  const app = db.prepare('SELECT * FROM applicants WHERE id = ?').get(id);
  if (!app) return null;

// Generate a unique employee ID (must not collide with existing employees
  // OR users, since hire also creates a portal login with the same employee_id)
  let empId = '';
  let empSeq = db.prepare('SELECT COUNT(*) as count FROM employees').get().count;
  do {
    empSeq++;
    empId = 'EMP' + String(empSeq).padStart(3, '0');
  } while (
    db.prepare('SELECT COUNT(*) as count FROM employees WHERE employee_id = ?').get(empId).count > 0 ||
    db.prepare('SELECT COUNT(*) as count FROM users WHERE employee_id = ?').get(empId).count > 0
  );

  // Ensure a unique email for the employee record
  let email = (app.email || '').trim();
  if (!email) {
    // Build from name if possible, e.g. "John Doe" -> "johndoe@company.com"
    const slug = (app.name || 'employee').toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 30) || 'employee';
    email = `${slug}@company.com`;
  }
  // If that email already exists, append a numeric suffix
  let candidate = email;
  let suffix = 1;
  while (db.prepare('SELECT COUNT(*) as count FROM employees WHERE email = ?').get(candidate).count > 0) {
    const parts = email.split('@');
    candidate = `${parts[0]}${suffix}@${parts[1]}`;
    suffix++;
  }

// Add as employee with full applicant details transferred
  const empResult = db.prepare(
    `INSERT INTO employees (
      employee_id, name, email, department, role, status,
      phone, address, date_of_birth, gender, emergency_contact,
      age, place_of_birth, tin, civil_status,
      last_name, first_name, middle_name
    ) VALUES (?, ?, ?, ?, ?, 'Onboarding', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    empId,
    app.name,
    candidate,
    app.department || 'General',
    app.position || '',
    app.phone || '',
    app.address || '',
    app.date_of_birth || '',
    app.gender || '',
    app.emergency_contact || '',
    app.age || 0,
    app.place_of_birth || '',
    app.tin || '',
    app.civil_status || '',
    app.surname || app.last_name || '',
    app.first_name || '',
    app.middle_name || ''
  );

  // Automatically start the standard onboarding checklist for the new hire
  startOnboarding(empResult.lastInsertRowid);

  // INTERCONNECT: create a portal login account for the new hire so they can
  // access the employee portal immediately (default password; change on first login).
  const userExists = db.prepare('SELECT id FROM users WHERE email = ?').get(candidate);
  if (!userExists) {
    const salt = bcrypt.genSaltSync(10);
    const hashedPassword = bcrypt.hashSync('changeme123', salt);
    db.prepare(
      `INSERT INTO users (email, password, role, name, position, department, employee_id)
       VALUES (?, ?, 'employee', ?, ?, 'General', ?)`
    ).run(candidate, hashedPassword, app.name, app.position, empId);
  }

  // Remove from applicants
  db.prepare('DELETE FROM applicants WHERE id = ?').run(id);

  return { employee_id: empId, name: app.name, email: candidate };
}

function deleteApplicant(id) {
  db.prepare('DELETE FROM applicants WHERE id = ?').run(id);
}

// ==================== ANNOUNCEMENT QUERIES ====================
function getAllAnnouncements() {
  return db.prepare('SELECT * FROM announcements ORDER BY created_at DESC, id DESC').all();
}

function addAnnouncement(announcement) {
  const stmt = db.prepare(
    `INSERT INTO announcements (title, content, author)
     VALUES (?, ?, ?)`
  );
  const result = stmt.run(announcement.title, announcement.content, announcement.author || 'HR');
  return result.lastInsertRowid;
}

function updateAnnouncement(id, announcement) {
  const existing = db.prepare('SELECT * FROM announcements WHERE id = ?').get(id);
  if (!existing) return null;
  db.prepare(
    `UPDATE announcements SET title = ?, content = ? WHERE id = ?`
  ).run(
    announcement.title || existing.title,
    announcement.content || existing.content,
    id
  );
  return db.prepare('SELECT * FROM announcements WHERE id = ?').get(id);
}

function deleteAnnouncement(id) {
  // Remove read-tracking rows FIRST (they reference the announcement via FK)
  db.prepare('DELETE FROM announcement_reads WHERE announcement_id = ?').run(id);
  // Then delete the announcement itself
  db.prepare('DELETE FROM announcements WHERE id = ?').run(id);
}

// ==================== ANNOUNCEMENT READ TRACKING ====================
// Returns announcements with per-user read status: { ..., is_read: 0|1, unread_count }
function getAnnouncementsForUser(userId) {
  const announcements = db.prepare(
    `SELECT a.*,
       (CASE WHEN ar.id IS NULL THEN 0 ELSE 1 END) AS is_read
     FROM announcements a
     LEFT JOIN announcement_reads ar
       ON ar.announcement_id = a.id AND ar.user_id = ?
     ORDER BY a.created_at DESC, a.id DESC`
  ).all(userId);

  const unreadCount = db.prepare(
    `SELECT COUNT(*) as count FROM announcements a
     LEFT JOIN announcement_reads ar
       ON ar.announcement_id = a.id AND ar.user_id = ?
     WHERE ar.id IS NULL`
  ).get(userId).count;

  return { announcements, unread_count: unreadCount };
}

// Mark an announcement as read for a user (idempotent)
function markAnnouncementRead(userId, announcementId) {
  db.prepare(
    `INSERT OR IGNORE INTO announcement_reads (user_id, announcement_id)
     VALUES (?, ?)`
  ).run(userId, announcementId);
}

// Count of unread announcements for a user
function getUnreadAnnouncementCount(userId) {
  return db.prepare(
    `SELECT COUNT(*) as count FROM announcements a
     LEFT JOIN announcement_reads ar
       ON ar.announcement_id = a.id AND ar.user_id = ?
     WHERE ar.id IS NULL`
  ).get(userId).count;
}

// ==================== DASHBOARD STATS ====================
function getDashboardStats() {
  // Total headcount (all employees regardless of status)
  const totalEmployees = db.prepare('SELECT COUNT(*) as count FROM employees').get().count;

  // Active headcount used for the retention-rate calculation
  const activeEmployees = db.prepare(
    "SELECT COUNT(*) as count FROM employees WHERE status = 'Active'"
  ).get().count;

  const totalApplicants = db.prepare('SELECT COUNT(*) as count FROM applicants').get().count;

  // New hires: employees created within the last 30 days
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  const cutoff = thirtyDaysAgo.toISOString().split('T')[0];
  const newHires = db.prepare(
    'SELECT COUNT(*) as count FROM employees WHERE date(created_at) >= ?'
  ).get(cutoff).count;

  // Departmental distribution (breakdown of headcount by department)
  const departmentRows = db.prepare(
    'SELECT department, COUNT(*) as count FROM employees GROUP BY department ORDER BY count DESC'
  ).all();
  const departmentDistribution = departmentRows.map(r => ({
    department: r.department || 'General',
    count: r.count
  }));

  // Retention rate: percentage of total headcount that is still Active
  const retentionRate = totalEmployees > 0
    ? Math.round((activeEmployees / totalEmployees) * 100)
    : 0;

  return {
    totalEmployees: totalEmployees || 3,
    totalApplicants: totalApplicants || 2,
    newHires: newHires || 0,
    departmentDistribution,
    retentionRate
  };
}

// ==================== ESS MODULES & SEEDING ====================
function seedEssData() {
  const regUser = db.prepare('SELECT id, employee_id FROM users WHERE LOWER(email) = LOWER(?)').get('user@gmail.com');
  if (regUser) {
    const leaveCount = db.prepare('SELECT COUNT(*) as count FROM leave_requests WHERE user_id = ?').get(regUser.id).count;
    if (leaveCount === 0) {
      const insLeave = db.prepare(
        `INSERT INTO leave_requests (user_id, employee_id, leave_type, start_date, end_date, days_count, reason, status, admin_remarks)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      );
      insLeave.run(regUser.id, regUser.employee_id, 'Vacation', '2026-07-10', '2026-07-12', 3, 'Annual family trip', 'Approved', 'Enjoy your vacation!');
      insLeave.run(regUser.id, regUser.employee_id, 'Sick', '2026-08-04', '2026-08-04', 1, 'Flu and fever', 'Approved', 'Rest well.');
      insLeave.run(regUser.id, regUser.employee_id, 'Vacation', '2026-10-15', '2026-10-17', 3, 'Upcoming autumn break', 'Pending', '');
    }

    const attCount = db.prepare('SELECT COUNT(*) as count FROM attendance WHERE user_id = ?').get(regUser.id).count;
    if (attCount === 0) {
      const insAtt = db.prepare(
        `INSERT INTO attendance (user_id, employee_id, date, clock_in, clock_out, status, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      );
      const today = new Date().toISOString().split('T')[0];
      insAtt.run(regUser.id, regUser.employee_id, today, '08:58 AM', '05:02 PM', 'Present', 'On time');
      insAtt.run(regUser.id, regUser.employee_id, '2026-09-22', '09:05 AM', '05:00 PM', 'Late', 'Traffic delay');
      insAtt.run(regUser.id, regUser.employee_id, '2026-09-21', '08:55 AM', '05:01 PM', 'Present', 'Standard shift');
    }

    const payCount = db.prepare('SELECT COUNT(*) as count FROM payslips WHERE user_id = ?').get(regUser.id).count;
    if (payCount === 0) {
      const insPay = db.prepare(
        `INSERT INTO payslips (user_id, employee_id, pay_period, pay_date, basic_salary, allowances, deductions, net_pay, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      );
      insPay.run(regUser.id, regUser.employee_id, 'September 01 - September 15, 2026', '2026-09-15', 3500.00, 300.00, 420.00, 3380.00, 'Paid');
      insPay.run(regUser.id, regUser.employee_id, 'August 16 - August 31, 2026', '2026-08-31', 3500.00, 300.00, 420.00, 3380.00, 'Paid');
      insPay.run(regUser.id, regUser.employee_id, 'August 01 - August 15, 2026', '2026-08-15', 3500.00, 300.00, 420.00, 3380.00, 'Paid');
    }

    const docCount = db.prepare('SELECT COUNT(*) as count FROM employee_documents WHERE user_id = ?').get(regUser.id).count;
    if (docCount === 0) {
      const insDoc = db.prepare(
        `INSERT INTO employee_documents (user_id, employee_id, doc_type, title, description, status, file_url)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      );
      insDoc.run(regUser.id, regUser.employee_id, 'Certificate of Employment', 'Official COE Certificate', 'Verified proof of active employment', 'Available', '');
      insDoc.run(regUser.id, regUser.employee_id, 'Company Policy', 'Employee Handbook 2026', 'Company standard policies and guidelines', 'Available', '');
      insDoc.run(regUser.id, regUser.employee_id, 'Tax Certificate', 'Annual Income Tax Form 1601', 'Tax clearance summary for 2025-2026', 'Available', '');
    }

    db.prepare(`UPDATE employees SET bank_name = 'BDO Unibank', bank_account = '1092-8834-7712', tin = '321-654-987' WHERE LOWER(email) = LOWER('user@gmail.com')`).run();
  }
}

function getFullEmployeeForUser(userId) {
  const user = findUserById(userId);
  if (!user) return null;
  const emp = db.prepare(
    "SELECT * FROM employees WHERE (employee_id = ? AND employee_id IS NOT NULL AND employee_id != '') OR LOWER(email) = LOWER(?)"
  ).get(user.employee_id, user.email);
  return {
    ...user,
    phone: emp ? emp.phone : '',
    address: emp ? emp.address : '',
    emergency_contact: emp ? emp.emergency_contact : '',
    bank_name: emp ? emp.bank_name : '',
    bank_account: emp ? emp.bank_account : '',
    tin: emp ? emp.tin : ''
  };
}

function getLeaveRequestsForUser(userId) {
  const requests = db.prepare('SELECT * FROM leave_requests WHERE user_id = ? ORDER BY created_at DESC').all(userId);
  
  let vacationUsed = 0;
  let sickUsed = 0;
  let emergencyUsed = 0;

  requests.forEach(r => {
    if (r.status === 'Approved' || r.status === 'Pending') {
      if (r.leave_type === 'Vacation') vacationUsed += (r.days_count || 1);
      if (r.leave_type === 'Sick') sickUsed += (r.days_count || 1);
      if (r.leave_type === 'Emergency') emergencyUsed += (r.days_count || 1);
    }
  });

  return {
    balances: {
      vacation: { total: 15, used: vacationUsed, remaining: Math.max(0, 15 - vacationUsed) },
      sick: { total: 10, used: sickUsed, remaining: Math.max(0, 10 - sickUsed) },
      emergency: { total: 5, used: emergencyUsed, remaining: Math.max(0, 5 - emergencyUsed) }
    },
    requests
  };
}

function createLeaveRequest(userId, data) {
  const user = findUserById(userId);
  if (!user) throw new Error('User not found');

  const startDate = new Date(data.start_date);
  const endDate = new Date(data.end_date);
  const diffTime = Math.abs(endDate - startDate);
  const daysCount = Math.ceil(diffTime / (1000 * 60 * 60 * 24)) + 1 || 1;

  const result = db.prepare(
    `INSERT INTO leave_requests (user_id, employee_id, leave_type, start_date, end_date, days_count, reason, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending')`
  ).run(
    userId,
    user.employee_id || '',
    data.leave_type || 'Vacation',
    data.start_date,
    data.end_date,
    daysCount,
    data.reason || ''
  );

  return db.prepare('SELECT * FROM leave_requests WHERE id = ?').get(result.lastInsertRowid);
}

function getAllLeaveRequests() {
  return db.prepare(
    `SELECT lr.*, u.name as employee_name, u.department, u.email
     FROM leave_requests lr
     JOIN users u ON lr.user_id = u.id
     ORDER BY lr.created_at DESC`
  ).all();
}

function updateLeaveRequestStatus(id, status, adminRemarks) {
  db.prepare(
    'UPDATE leave_requests SET status = ?, admin_remarks = ? WHERE id = ?'
  ).run(status, adminRemarks || '', id);

  return db.prepare('SELECT * FROM leave_requests WHERE id = ?').get(id);
}

function getAttendanceForUser(userId) {
  const today = new Date().toISOString().split('T')[0];
  const logs = db.prepare('SELECT * FROM attendance WHERE user_id = ? ORDER BY date DESC, id DESC').all(userId);
  const todayLog = db.prepare('SELECT * FROM attendance WHERE user_id = ? AND date = ?').get(userId, today);

  return {
    todayLog: todayLog || null,
    schedule: {
      shift: 'Standard Shift (Day)',
      hours: '09:00 AM - 05:00 PM',
      days: 'Monday - Friday'
    },
    logs
  };
}

function clockInUser(userId, notes) {
  const today = new Date().toISOString().split('T')[0];
  const existing = db.prepare('SELECT * FROM attendance WHERE user_id = ? AND date = ?').get(userId, today);

  const now = new Date();
  const timeStr = now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
  const isLate = now.getHours() > 9 || (now.getHours() === 9 && now.getMinutes() > 15);
  const status = isLate ? 'Late' : 'Present';

  if (existing) {
    if (existing.clock_in) throw new Error('Already clocked in for today.');
    db.prepare('UPDATE attendance SET clock_in = ?, status = ?, notes = ? WHERE id = ?')
      .run(timeStr, status, notes || existing.notes, existing.id);
    return db.prepare('SELECT * FROM attendance WHERE id = ?').get(existing.id);
  }

  const user = findUserById(userId);
  const result = db.prepare(
    `INSERT INTO attendance (user_id, employee_id, date, clock_in, status, notes)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(userId, user ? user.employee_id : '', today, timeStr, status, notes || '');

  return db.prepare('SELECT * FROM attendance WHERE id = ?').get(result.lastInsertRowid);
}

function clockOutUser(userId) {
  const today = new Date().toISOString().split('T')[0];
  const existing = db.prepare('SELECT * FROM attendance WHERE user_id = ? AND date = ?').get(userId, today);
  if (!existing || !existing.clock_in) throw new Error('You must clock in before clocking out.');

  const now = new Date();
  const timeStr = now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });

  db.prepare('UPDATE attendance SET clock_out = ? WHERE id = ?').run(timeStr, existing.id);
  return db.prepare('SELECT * FROM attendance WHERE id = ?').get(existing.id);
}

function getPayslipsForUser(userId) {
  return db.prepare('SELECT * FROM payslips WHERE user_id = ? ORDER BY pay_date DESC').all(userId);
}

function createPayslip(data) {
  const user = findUserById(data.user_id);
  if (!user) throw new Error('User not found');

  const basic = parseFloat(data.basic_salary || 0);
  const allowances = parseFloat(data.allowances || 0);
  const deductions = parseFloat(data.deductions || 0);
  const net = basic + allowances - deductions;

  const result = db.prepare(
    `INSERT INTO payslips (user_id, employee_id, pay_period, pay_date, basic_salary, allowances, deductions, net_pay, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'Paid')`
  ).run(
    data.user_id,
    user.employee_id || '',
    data.pay_period,
    data.pay_date || new Date().toISOString().split('T')[0],
    basic,
    allowances,
    deductions,
    net
  );

  return db.prepare('SELECT * FROM payslips WHERE id = ?').get(result.lastInsertRowid);
}

function getAllPayslips() {
  return db.prepare(
    `SELECT p.*, u.name as employee_name, u.department
     FROM payslips p
     JOIN users u ON p.user_id = u.id
     ORDER BY p.pay_date DESC`
  ).all();
}

function getDocumentsForUser(userId) {
  return db.prepare('SELECT * FROM employee_documents WHERE user_id = ? ORDER BY created_at DESC').all(userId);
}

function requestDocument(userId, docType, title, description) {
  const user = findUserById(userId);
  const result = db.prepare(
    `INSERT INTO employee_documents (user_id, employee_id, doc_type, title, description, status)
     VALUES (?, ?, ?, ?, ?, 'Requested')`
  ).run(userId, user ? user.employee_id : '', docType, title || docType, description || '');

  return db.prepare('SELECT * FROM employee_documents WHERE id = ?').get(result.lastInsertRowid);
}

function generateCertificateOfEmployment(userId) {
  const user = findUserById(userId);
  if (!user) throw new Error('User not found');

  const todayStr = new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });

  return {
    certificateNo: `COE-${user.employee_id || user.id}-${Date.now().toString().slice(-4)}`,
    issuedDate: todayStr,
    employeeName: user.name,
    employeeId: user.employee_id || 'N/A',
    position: user.position || 'Staff',
    department: user.department || 'General',
    status: 'Active',
    companyName: 'Human Resources Management System Inc.',
    signatory: 'HR Director / Personnel Department'
  };
}

function getBenefitsForUser(userId) {
  return {
    healthInsurance: {
      provider: 'MetroCare Health Plan',
      policyNumber: 'MC-2026-78912',
      tier: 'Comprehensive Gold',
      coverage: 'PHP 250,000 / year (Inpatient & Outpatient)'
    },
    retirementPlan: {
      planName: 'Company 401(k) / Provident Fund',
      employerContribution: '5% Matching',
      status: 'Enrolled'
    },
    allowances: [
      { name: 'Monthly Rice & Meal Allowance', amount: '$150.00 / month' },
      { name: 'Communications Allowance', amount: '$50.00 / month' }
    ]
  };
}

function getPerformanceForUser(userId) {
  return {
    latestRating: '4.8 / 5.0 (Exceeds Expectations)',
    reviewPeriod: 'Q2 2026 Performance Appraisal',
    evaluator: 'Department Lead',
    strengths: ['Exemplary teamwork', 'Strong technical problem solving', 'Consistently meets project deadlines'],
    goals: ['Lead upcoming Q4 cross-departmental initiative', 'Complete advanced certifications']
  };
}

// Initialize on load
initializeDatabase();

module.exports = {
  db,
  findUserByEmail,
  findUserById,
  getAllUsers,
  createUserAccount,
  updateUserProfile,
  changePassword,
  deleteUserAccount,
  getAllEmployees,
  getEmployeeById,
  addEmployee,
  updateEmployee,
  deleteEmployee,
getAllApplicants,
  addApplicant,
  hireApplicant,
  deleteApplicant,
  getAllAnnouncements,
  addAnnouncement,
  updateAnnouncement,
  deleteAnnouncement,
  getAnnouncementsForUser,
  markAnnouncementRead,
  getUnreadAnnouncementCount,
  startOnboarding,
  getAllOnboarding,
  getOnboardingByEmployeeCode,
  getOnboardingSummary,
addOnboardingTask,
  getOnboardingTaskById,
  updateOnboardingTask,
  deleteOnboardingTask,
  getOnboardingStats,
  getDashboardStats,
  getFullEmployeeForUser,
  getLeaveRequestsForUser,
  createLeaveRequest,
  getAllLeaveRequests,
  updateLeaveRequestStatus,
  getAttendanceForUser,
  clockInUser,
  clockOutUser,
  getPayslipsForUser,
  createPayslip,
  getAllPayslips,
  getDocumentsForUser,
  requestDocument,
  generateCertificateOfEmployment,
  getBenefitsForUser,
  getPerformanceForUser
};

