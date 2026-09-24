// Quick end-to-end API test for the HRMS backend
const http = require('http');

const BASE = 'http://localhost:5000/api';
let adminToken = null;
let employeeToken = null;
let passed = 0;
let failed = 0;

function req(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const url = BASE + path;
    const data = body ? JSON.stringify(body) : null;
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const r = http.request(url, { method, headers }, res => {
      let raw = '';
      res.on('data', c => raw += c);
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(raw); } catch (e) { parsed = raw; }
        resolve({ status: res.statusCode, data: parsed });
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

function check(name, cond, extra) {
  if (cond) {
    passed++;
    console.log(`  ✅ ${name}`);
  } else {
    failed++;
    console.log(`  ❌ ${name} ${extra ? JSON.stringify(extra) : ''}`);
  }
}

async function main() {
  // 1. Login admin
  console.log('\n=== ADMIN LOGIN ===');
  let res = await req('POST', '/auth/login', { email: 'admin@gmail.com', password: 'admin123' });
  check('admin login succeeds', res.status === 200 && res.data.token, res);
  adminToken = res.data.token;

  // 2. Login employee
  console.log('\n=== EMPLOYEE LOGIN ===');
  res = await req('POST', '/auth/login', { email: 'user@gmail.com', password: 'user123' });
  check('employee login succeeds', res.status === 200 && res.data.token, res);
  employeeToken = res.data.token;

  // 3. Invalid login
  console.log('\n=== INVALID LOGIN ===');
  res = await req('POST', '/auth/login', { email: 'admin@gmail.com', password: 'wrong' });
  check('invalid login rejected', res.status === 401, res);

  // 4. /auth/me
  console.log('\n=== AUTH ME ===');
  res = await req('GET', '/auth/me', null, adminToken);
  check('admin /auth/me works', res.status === 200 && res.data.email === 'admin@gmail.com', res);

  // 5. Dashboard stats
  console.log('\n=== DASHBOARD STATS ===');
  res = await req('GET', '/dashboard/stats', null, adminToken);
  check('dashboard stats works', res.status === 200 && typeof res.data.totalEmployees === 'number', res);

  // 6. Employees
  console.log('\n=== EMPLOYEES ===');
  res = await req('GET', '/employees', null, adminToken);
  check('list employees', res.status === 200 && Array.isArray(res.data), res);

  res = await req('POST', '/employees', { employee_id: 'TEST001', name: 'Test User', email: 'test@company.com', department: 'QA', role: 'Tester', status: 'Active' }, adminToken);
  check('add employee', res.status === 201, res);

  res = await req('GET', '/employees', null, adminToken);
  const testEmp = (res.data || []).find(e => e.email === 'test@company.com');
  check('added employee exists', !!testEmp, res);

  if (testEmp) {
    res = await req('PUT', `/employees/${testEmp.id}`, { role: 'Senior Tester' }, adminToken);
    check('update employee', res.status === 200 && res.data.employee.role === 'Senior Tester', res);

    res = await req('DELETE', `/employees/${testEmp.id}`, null, adminToken);
    check('delete employee', res.status === 200, res);
  }

  // 7. Applicants
  console.log('\n=== APPLICANTS ===');
  res = await req('GET', '/applicants', null, adminToken);
  check('list applicants', res.status === 200 && Array.isArray(res.data), res);

  res = await req('POST', '/applicants', { surname: 'Applicant', middle_name: 'Q', first_name: 'Test', position: 'Tester' }, adminToken);
  check('add applicant', res.status === 201, res);
  const testAppId = res.data.id;

  res = await req('POST', `/applicants/${testAppId}/hire`, null, adminToken);
  check('hire applicant', res.status === 200, res);

  res = await req('POST', '/applicants', { surname: 'Applicant', middle_name: 'X', first_name: 'Temp', position: 'Dev' }, adminToken);
  const tempAppId = res.data.id;
  res = await req('DELETE', `/applicants/${tempAppId}`, null, adminToken);
  check('delete applicant', res.status === 200, res);

  // 8. Announcements
  console.log('\n=== ANNOUNCEMENTS ===');
  res = await req('GET', '/announcements');
  check('public announcements', res.status === 200 && Array.isArray(res.data), res);

  res = await req('POST', '/announcements', { title: 'Test Announcement', content: 'Test content' }, adminToken);
  check('admin publish announcement', res.status === 201, res);
  const annId = res.data.id;

  res = await req('DELETE', `/announcements/${annId}`, null, adminToken);
  check('admin delete announcement', res.status === 200, res);

  // 9. Profile update
  console.log('\n=== PROFILE UPDATE ===');
  res = await req('PUT', '/users/profile', { name: 'Regular User', position: 'Senior Software Engineer', department: 'IT' }, employeeToken);
  check('update profile', res.status === 200 && res.data.user.position === 'Senior Software Engineer', res);

  // 10. Employee trying admin routes
  console.log('\n=== ROLE PROTECTION ===');
  res = await req('GET', '/employees', null, employeeToken);
  check('employee blocked from admin route', res.status === 403, res);

  console.log(`\n====================================`);
  console.log(`RESULTS: ${passed} passed, ${failed} failed`);
  console.log(`====================================`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('FATAL:', err.message);
  console.log('Is the backend running on port 5000? Start it with: cd backend && node server.js');
  process.exit(1);
});

