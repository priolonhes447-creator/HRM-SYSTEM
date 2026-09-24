const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const {
  db,
  findUserByEmail,
  findUserById,
  getAllUsers,
  createUserAccount,
  updateUserProfile,
  changePassword,
  deleteUserAccount,
  getAllEmployees,
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
} = require('./database');

const app = express();
const PORT = process.env.PORT || 5000;
const JWT_SECRET = process.env.JWT_SECRET || 'hrms_pro_secret_key_2026';

// ==================== MIDDLEWARE ====================
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '..')));

// ==================== JWT AUTH MIDDLEWARE ====================
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({ error: 'Access denied. No token provided.' });
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(403).json({ error: 'Invalid or expired token.' });
  }
}

function requireRole(role) {
  return (req, res, next) => {
    if (req.user.role !== role) {
      return res.status(403).json({ error: `Access denied. ${role} role required.` });
    }
    next();
  };
}

// Public health check route
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', server: 'HRMS Pro API' });
});

// ==================== AUTH ROUTES ====================
app.post('/api/auth/login', (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required.' });
  }

  const user = findUserByEmail(email);
  if (!user) {
    return res.status(401).json({ error: 'Invalid email or password.' });
  }

  const validPassword = bcrypt.compareSync(password, user.password);
  if (!validPassword) {
    return res.status(401).json({ error: 'Invalid email or password.' });
  }

  const token = jwt.sign(
    {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
      position: user.position,
      department: user.department,
      employee_id: user.employee_id
    },
    JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '24h' }
  );

  res.json({
    token,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
      position: user.position,
      department: user.department,
      employee_id: user.employee_id
    }
  });
});

app.get('/api/auth/me', authenticateToken, (req, res) => {
  const user = findUserById(req.user.id);
  if (!user) {
    return res.status(404).json({ error: 'User not found.' });
  }
  res.json(user);
});

// Get detailed own profile
app.get('/api/users/profile', authenticateToken, (req, res) => {
  const fullProfile = getFullEmployeeForUser(req.user.id);
  if (!fullProfile) {
    return res.status(404).json({ error: 'User profile not found.' });
  }
  res.json(fullProfile);
});

// Update own profile (name, position, department, phone, address, emergency_contact, bank_name, bank_account, tin)
app.put('/api/users/profile', authenticateToken, (req, res) => {
  const { name, position, department, phone, address, emergency_contact, bank_name, bank_account, tin } = req.body;
  const updated = updateUserProfile(req.user.id, { name, position, department, phone, address, emergency_contact, bank_name, bank_account, tin });
  if (!updated) {
    return res.status(404).json({ error: 'User not found.' });
  }
  const fullUser = getFullEmployeeForUser(req.user.id);
  res.json({ message: 'Profile updated successfully.', user: fullUser });
});

// Change own password (any logged-in user)
app.put('/api/users/password', authenticateToken, (req, res) => {
  const { current_password, new_password } = req.body;

  if (!current_password || !new_password) {
    return res.status(400).json({ error: 'Current password and new password are required.' });
  }
  if (new_password.length < 6) {
    return res.status(400).json({ error: 'New password must be at least 6 characters.' });
  }

  const user = findUserById(req.user.id);
  if (!user) {
    return res.status(404).json({ error: 'User not found.' });
  }
  // load the hash (findUserById omits password)
  const userRow = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!bcrypt.compareSync(current_password, userRow.password)) {
    return res.status(401).json({ error: 'Current password is incorrect.' });
  }

  const changed = changePassword(req.user.id, new_password);
  if (!changed) {
    return res.status(404).json({ error: 'User not found.' });
  }
  res.json({ message: 'Password changed successfully.' });
});

// ==================== USER ACCOUNT ROUTES ====================
// Admin-only: list all user accounts (no passwords returned)
app.get('/api/users', authenticateToken, requireRole('admin'), (req, res) => {
  const users = getAllUsers();
  res.json(users);
});

// Admin-only: create a new user account (login credentials)
app.post('/api/users', authenticateToken, requireRole('admin'), (req, res) => {
  const { email, password, role, name, position, department, employee_id } = req.body;

  if (!email || !password || !name) {
    return res.status(400).json({ error: 'email, password, and name are required.' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters.' });
  }
  if (role && !['admin', 'employee'].includes(role)) {
    return res.status(400).json({ error: 'role must be either "admin" or "employee".' });
  }

  const newUser = createUserAccount({
    email: email.trim().toLowerCase(),
    password,
    role: role || 'employee',
    name: name.trim(),
    position,
    department,
    employee_id
  });

  if (newUser.error) {
    return res.status(409).json({ error: newUser.error });
  }

  res.status(201).json({ message: 'User account created successfully.', user: newUser });
});

// Admin-only: delete a user account
app.delete('/api/users/:id', authenticateToken, requireRole('admin'), (req, res) => {
  const id = parseInt(req.params.id);

  // Prevent deleting your own account
  if (req.user.id === id) {
    return res.status(400).json({ error: 'You cannot delete your own account.' });
  }

  const deleted = deleteUserAccount(id);
  if (!deleted) {
    return res.status(404).json({ error: 'User account not found.' });
  }
  res.json({ message: 'User account deleted successfully.' });
});

// ==================== EMPLOYEE ROUTES ====================
app.get('/api/employees', authenticateToken, requireRole('admin'), (req, res) => {
  const employees = getAllEmployees();
  res.json(employees);
});

app.post('/api/employees', authenticateToken, requireRole('admin'), (req, res) => {
  const { employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name } = req.body;
  if (!employee_id || !name || !email) {
    return res.status(400).json({ error: 'employee_id, name, and email are required.' });
  }
  const id = addEmployee({ employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name });
  res.status(201).json({ id, message: 'Employee added successfully.' });
});

app.put('/api/employees/:id', authenticateToken, requireRole('admin'), (req, res) => {
  const { employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name } = req.body;
  const updated = updateEmployee(parseInt(req.params.id), {
    employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name
  });
  if (!updated) {
    return res.status(404).json({ error: 'Employee not found.' });
  }
  res.json({ message: 'Employee updated successfully.', employee: updated });
});

app.delete('/api/employees/:id', authenticateToken, requireRole('admin'), (req, res) => {
  const deleted = deleteEmployee(parseInt(req.params.id));
  if (!deleted) {
    return res.status(404).json({ error: 'Employee not found.' });
  }
  res.json({ message: 'Employee deleted successfully.' });
});

// ==================== APPLICANT ROUTES ====================
app.get('/api/applicants', authenticateToken, requireRole('admin'), (req, res) => {
  const applicants = getAllApplicants();
  res.json(applicants);
});

app.post('/api/applicants', (req, res) => {
  const { surname, middle_name, first_name, name, position, applied_date } = req.body;
  const fullName = (name || [first_name, middle_name, surname].filter(Boolean).join(' ')).trim();

  if ((!fullName && (!surname || !first_name)) || !position) {
    return res.status(400).json({ error: 'Surname, first name, and position are required.' });
  }
  const date = applied_date || new Date().toISOString().split('T')[0];
  const id = addApplicant({ ...req.body, name: fullName, applied_date: date, status: 'New' });
  res.status(201).json({ id, message: 'Your application has been submitted successfully! Our recruitment team will review your details.' });
});

app.post('/api/applicants/:id/hire', authenticateToken, requireRole('admin'), (req, res) => {
  const result = hireApplicant(parseInt(req.params.id));
  if (!result) {
    return res.status(404).json({ error: 'Applicant not found.' });
  }
  res.json({
    message: `${result.name} hired successfully. Employee record, onboarding checklist, and portal login created.`,
    employee_id: result.employee_id,
    email: result.email,
    default_password: 'changeme123'
  });
});

app.delete('/api/applicants/:id', authenticateToken, requireRole('admin'), (req, res) => {
  deleteApplicant(parseInt(req.params.id));
  res.json({ message: 'Applicant deleted.' });
});

// ==================== ANNOUNCEMENT ROUTES ====================
// Authenticated read endpoint: returns per-user read status + unread count.
app.get('/api/announcements/mine', authenticateToken, (req, res) => {
  const { announcements, unread_count } = getAnnouncementsForUser(req.user.id);
  res.json({ announcements, unread_count });
});

// Mark an announcement as read for the logged-in user
app.post('/api/announcements/:id/read', authenticateToken, (req, res) => {
  markAnnouncementRead(req.user.id, parseInt(req.params.id));
  const unread_count = getUnreadAnnouncementCount(req.user.id);
  res.json({ message: 'Announcement marked as read.', unread_count });
});

// Public read endpoint so employees can view announcements (falls back to plain list)
app.get('/api/announcements', (req, res) => {
  const announcements = getAllAnnouncements();
  res.json(announcements);
});

// Admin-only create
app.post('/api/announcements', authenticateToken, requireRole('admin'), (req, res) => {
  const { title, content } = req.body;
  if (!title || !content) {
    return res.status(400).json({ error: 'title and content are required.' });
  }
  const id = addAnnouncement({
    title,
    content,
    author: req.user.name || 'HR'
  });
  res.status(201).json({ id, message: 'Announcement published.' });
});

// Admin-only update
app.put('/api/announcements/:id', authenticateToken, requireRole('admin'), (req, res) => {
  const { title, content } = req.body;
  if (!title || !content) {
    return res.status(400).json({ error: 'title and content are required.' });
  }
  const updated = updateAnnouncement(parseInt(req.params.id), { title, content });
  if (!updated) {
    return res.status(404).json({ error: 'Announcement not found.' });
  }
  res.json({ message: 'Announcement updated successfully.', announcement: updated });
});

// Admin-only delete
app.delete('/api/announcements/:id', authenticateToken, requireRole('admin'), (req, res) => {
  deleteAnnouncement(parseInt(req.params.id));
  res.json({ message: 'Announcement deleted.' });
});

// ==================== ONBOARDING ROUTES ====================
// Role-aware: admin sees full summary + stats; employee sees only their own checklist
app.get('/api/onboarding', authenticateToken, (req, res) => {
  if (req.user.role === 'admin') {
    const summary = getOnboardingSummary();
    const stats = getOnboardingStats();
    return res.json({ scope: 'admin', summary, stats });
  }

  // Employee: look up their checklist by their employee_id code
  const code = req.user.employee_id;
  if (!code) {
    return res.json({ scope: 'employee', checklist: [], total: 0, completed: 0, progress: 0 });
  }

  // Auto-provision: ensure an employee record + the default onboarding checklist
  // exist for this user, so their "My Onboarding" section is always populated
  // (fixes existing accounts that never got a checklist).
  let empRow = db.prepare('SELECT * FROM employees WHERE employee_id = ?').get(code);
  if (!empRow && req.user.email) {
    empRow = db.prepare('SELECT * FROM employees WHERE email = ?').get(req.user.email);
  }
  if (!empRow) {
    const empRes = db.prepare(
      `INSERT INTO employees (employee_id, name, email, department, role, status)
       VALUES (?, ?, ?, ?, ?, 'Onboarding')`
    ).run(
      code,
      req.user.name || 'Employee',
      req.user.email || '',
      req.user.department || 'General',
      req.user.position || ''
    );
    empRow = db.prepare('SELECT * FROM employees WHERE id = ?').get(empRes.lastInsertRowid);
  } else if (empRow.employee_id !== code) {
    db.prepare('UPDATE employees SET employee_id = ? WHERE id = ?').run(code, empRow.id);
    empRow = db.prepare('SELECT * FROM employees WHERE id = ?').get(empRow.id);
  }
  if (empRow) {
    startOnboarding(empRow.id); // idempotent: skips if already started
  }

  const tasks = getOnboardingByEmployeeCode(code);
  if (!tasks) {
    return res.json({ scope: 'employee', checklist: [], total: 0, completed: 0, progress: 0 });
  }
  const total = tasks.length;
  const completed = tasks.filter(t => t.status === 'Completed').length;
  const progress = total ? Math.round((completed / total) * 100) : 0;
  res.json({ scope: 'employee', checklist: tasks, total, completed, progress });
});

// Admin-only: onboarding stats
app.get('/api/onboarding/stats', authenticateToken, requireRole('admin'), (req, res) => {
  const stats = getOnboardingStats();
  res.json(stats);
});

// Admin-only: start the standard 8-task checklist for an employee (by employee code)
app.post('/api/onboarding/employees/:employee_id/start', authenticateToken, requireRole('admin'), (req, res) => {
  const employeeRow = db.prepare('SELECT * FROM employees WHERE employee_id = ?').get(req.params.employee_id);
  if (!employeeRow) {
    return res.status(404).json({ error: 'Employee not found.' });
  }
  const result = startOnboarding(employeeRow.id);
  if (result && result.already_started) {
    return res.json({ message: 'Onboarding checklist already started for this employee.', already_started: true });
  }
  res.status(201).json({ message: 'Onboarding checklist started.', created: result.created, employee: result.employee });
});

// Admin-only: add a custom task to an employee's checklist
app.post('/api/onboarding', authenticateToken, requireRole('admin'), (req, res) => {
  const { employee_id, task, due_date, status } = req.body;
  if (!employee_id || !task) {
    return res.status(400).json({ error: 'employee_id and task are required.' });
  }
  const taskRecord = addOnboardingTask(parseInt(employee_id), task, due_date, status);
  if (!taskRecord) {
    return res.status(404).json({ error: 'Employee not found.' });
  }
  res.status(201).json({ message: 'Onboarding task added.', task: taskRecord });
});

// Admin-only: update a task (edit task text / status / due date)
app.put('/api/onboarding/:id', authenticateToken, requireRole('admin'), (req, res) => {
  const { task, status, due_date } = req.body;
  if (status && !['Pending', 'In Progress', 'Completed'].includes(status)) {
    return res.status(400).json({ error: 'status must be Pending, In Progress, or Completed.' });
  }
  const updated = updateOnboardingTask(parseInt(req.params.id), { task, status, due_date });
  if (!updated) {
    return res.status(404).json({ error: 'Onboarding task not found.' });
  }
  res.json({ message: 'Onboarding task updated.', task: updated });
});

// Admin-only: delete a task
app.delete('/api/onboarding/:id', authenticateToken, requireRole('admin'), (req, res) => {
  const deleted = deleteOnboardingTask(parseInt(req.params.id));
  if (!deleted) {
    return res.status(404).json({ error: 'Onboarding task not found.' });
  }
  res.json({ message: 'Onboarding task deleted.' });
});

// ==================== DASHBOARD STATS ====================
app.get('/api/dashboard/stats', authenticateToken, (req, res) => {
  const stats = getDashboardStats();
  res.json(stats);
});

// ==================== AI ASSISTANT ROUTE ====================
const { processAIChat } = require('./ai');

app.post('/api/ai/chat', authenticateToken, async (req, res) => {
  try {
    const { message, history } = req.body;
    if (!message) {
      return res.status(400).json({ error: 'Message field is required.' });
    }

    const result = await processAIChat({
      message,
      history: history || [],
      user: req.user
    });

    res.json(result);
  } catch (err) {
    console.error('Error in /api/ai/chat endpoint:', err);
    res.status(500).json({ error: err.message || 'Internal AI service error.' });
  }
});

// ==================== ESS MODULE ROUTES ====================

// Leave Management Routes
app.get('/api/leave/mine', authenticateToken, (req, res) => {
  const data = getLeaveRequestsForUser(req.user.id);
  res.json(data);
});

app.get('/api/leave/balances', authenticateToken, (req, res) => {
  const data = getLeaveRequestsForUser(req.user.id);
  res.json(data.balances);
});

app.get('/api/leave/my-requests', authenticateToken, (req, res) => {
  const data = getLeaveRequestsForUser(req.user.id);
  res.json(data.requests);
});

app.post('/api/leave/request', authenticateToken, (req, res) => {
  try {
    const { leave_type, start_date, end_date, reason } = req.body;
    if (!start_date || !end_date) {
      return res.status(400).json({ error: 'start_date and end_date are required.' });
    }
    const leave = createLeaveRequest(req.user.id, { leave_type, start_date, end_date, reason });
    res.status(201).json({ message: 'Leave request submitted successfully.', leave, id: leave.id });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

app.get('/api/leave/all', authenticateToken, requireRole('admin'), (req, res) => {
  const leaves = getAllLeaveRequests();
  res.json(leaves);
});

app.put('/api/leave/:id/status', authenticateToken, requireRole('admin'), (req, res) => {
  const id = parseInt(req.params.id);
  const { status, admin_remarks } = req.body;
  if (!status || !['Approved', 'Rejected', 'Pending'].includes(status)) {
    return res.status(400).json({ error: 'Valid status is required (Approved, Rejected, Pending).' });
  }
  const updated = updateLeaveRequestStatus(id, status, admin_remarks);
  res.json({ message: `Leave request ${status.toLowerCase()} successfully.`, leave: updated, status: updated.status });
});

// Attendance Routes
app.get('/api/attendance/mine', authenticateToken, (req, res) => {
  const data = getAttendanceForUser(req.user.id);
  res.json(data);
});

app.get('/api/attendance/my-logs', authenticateToken, (req, res) => {
  const data = getAttendanceForUser(req.user.id);
  res.json(data.logs || []);
});

app.post('/api/attendance/clock-in', authenticateToken, (req, res) => {
  try {
    const { notes } = req.body;
    const log = clockInUser(req.user.id, notes);
    res.json({ message: 'Clocked in successfully.', attendance: log, clock_in: log.clock_in });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

app.post('/api/attendance/clock-out', authenticateToken, (req, res) => {
  try {
    const log = clockOutUser(req.user.id);
    res.json({ message: 'Clocked out successfully.', attendance: log, clock_out: log.clock_out });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// Payslips Routes
app.get('/api/payslips/mine', authenticateToken, (req, res) => {
  const payslips = getPayslipsForUser(req.user.id);
  res.json(payslips);
});

app.get('/api/payslips/my-payslips', authenticateToken, (req, res) => {
  const payslips = getPayslipsForUser(req.user.id);
  res.json(payslips);
});

app.get('/api/payslips/all', authenticateToken, requireRole('admin'), (req, res) => {
  const payslips = getAllPayslips();
  res.json(payslips);
});

app.post('/api/payslips', authenticateToken, requireRole('admin'), (req, res) => {
  try {
    const payslip = createPayslip(req.body);
    res.status(201).json({ message: 'Payslip created successfully.', payslip });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// Employee Documents & Certificate Routes
app.get('/api/documents/mine', authenticateToken, (req, res) => {
  const docs = getDocumentsForUser(req.user.id);
  res.json(docs);
});

app.get('/api/documents/my-documents', authenticateToken, (req, res) => {
  const docs = getDocumentsForUser(req.user.id);
  res.json(docs);
});

app.post('/api/documents/request', authenticateToken, (req, res) => {
  const { doc_type, title, description } = req.body;
  if (!doc_type) {
    return res.status(400).json({ error: 'doc_type is required.' });
  }
  const doc = requestDocument(req.user.id, doc_type, title, description);
  res.status(201).json({ message: 'Document requested successfully.', document: doc, id: doc.id });
});

const handleCOE = (req, res) => {
  try {
    const coe = generateCertificateOfEmployment(req.user.id);
    res.json(coe);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

app.get('/api/documents/coe', authenticateToken, handleCOE);
app.post('/api/documents/coe', authenticateToken, handleCOE);

// Benefits & Performance Overview Routes
app.get('/api/benefits/mine', authenticateToken, (req, res) => {
  const benefits = getBenefitsForUser(req.user.id);
  res.json(benefits);
});

app.get('/api/benefits/my-benefits', authenticateToken, (req, res) => {
  const benefits = getBenefitsForUser(req.user.id);
  res.json(benefits);
});

app.get('/api/performance/mine', authenticateToken, (req, res) => {
  const performance = getPerformanceForUser(req.user.id);
  res.json(performance);
});

app.get('/api/performance/my-reviews', authenticateToken, (req, res) => {
  const performance = getPerformanceForUser(req.user.id);
  res.json(performance);
});

// ==================== START SERVER ====================
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () => {
  console.log(`HRMS API Server running on http://${HOST}:${PORT}`);
  console.log(`Endpoints:`);
  console.log(`  POST   /api/auth/login`);
  console.log(`  GET    /api/auth/me`);
  console.log(`  POST   /api/ai/chat`);
  console.log(`  GET    /api/users`);
  console.log(`  POST   /api/users`);
  console.log(`  GET    /api/dashboard/stats`);
  console.log(`  GET    /api/employees`);
  console.log(`  POST   /api/employees`);
  console.log(`  GET    /api/applicants`);
  console.log(`  POST   /api/applicants`);
  console.log(`  POST   /api/applicants/:id/hire`);
  console.log(`  DELETE /api/applicants/:id`);
  console.log(`  GET    /api/announcements`);
  console.log(`  GET    /api/announcements/mine`);
  console.log(`  POST   /api/announcements`);
  console.log(`  POST   /api/announcements/:id/read`);
  console.log(`  DELETE /api/announcements/:id`);
  console.log(`  GET    /api/onboarding`);
  console.log(`  GET    /api/onboarding/stats`);
  console.log(`  POST   /api/onboarding/employees/:employee_id/start`);
  console.log(`  POST   /api/onboarding`);
  console.log(`  PUT    /api/onboarding/:id`);
  console.log(`  DELETE /api/onboarding/:id`);
});
