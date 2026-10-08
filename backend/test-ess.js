// Comprehensive test script for Employee Self-Service (ESS) functionality
const http = require('http');
const BASE = 'http://localhost:5000/api';
let passed = 0, failed = 0;

function req(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const r = http.request(BASE + path, { method, headers }, res => {
      let raw = '';
      res.on('data', c => raw += c);
      res.on('end', () => { 
        let p = null; 
        try { p = JSON.parse(raw); } catch (e) { p = raw; } 
        resolve({ status: res.statusCode, data: p }); 
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

function check(name, cond, extra) {
  if (cond) { passed++; console.log('  \u2705 ' + name); }
  else { failed++; console.log('  \u274c ' + name + ' ' + (extra ? JSON.stringify(extra) : '')); }
}

async function main() {
  console.log('=== STARTING ESS MODULE SUITE TESTS ===\n');

  // 1. Admin login
  console.log('=== STEP 1: ADMIN LOGIN ===');
  let res = await req('POST', '/auth/login', { email: 'admin@gmail.com', password: 'admin123' });
  check('Admin login', res.status === 200 && res.data.token, res);
  const adminToken = res.data.token;

  // 2. User (Employee) login
  console.log('\n=== STEP 2: EMPLOYEE USER LOGIN ===');
  res = await req('POST', '/auth/login', { email: 'user@gmail.com', password: 'user123' });
  check('Employee login', res.status === 200 && res.data.token, res);
  const userToken = res.data.token;

  // 3. ESS Profile View & Update
  console.log('\n=== STEP 3: ESS PROFILE VIEW & UPDATE ===');
  res = await req('GET', '/users/profile', null, userToken);
  check('Get profile details', res.status === 200 && res.data.email === 'user@gmail.com', res);

  res = await req('PUT', '/users/profile', {
    phone: '+1 555 987 6543',
    address: '456 ESS Innovation Ave, Tech District',
    emergency_contact: 'Jane Doe (Spouse) - 555-0199',
    bank_name: 'Metro National Bank',
    bank_account: '987654321012',
    tin: '333-444-555-000'
  }, userToken);
  check('Update profile details (bank, contact info, TIN)', res.status === 200 && res.data.user && res.data.user.bank_name === 'Metro National Bank', res);

  // 4. Leave Management
  console.log('\n=== STEP 4: LEAVE MANAGEMENT (BALANCES & FILING) ===');
  res = await req('GET', '/leave/balances', null, userToken);
  check('Get leave balances', res.status === 200 && res.data.vacation !== undefined, res);

  res = await req('POST', '/leave/request', {
    leave_type: 'Vacation',
    start_date: '2026-10-10',
    end_date: '2026-10-12',
    reason: 'Family vacation trip'
  }, userToken);
  check('File leave request', res.status === 201 && res.data.id, res);
  const leaveId = res.data.id;

  res = await req('GET', '/leave/my-requests', null, userToken);
  check('Get employee leave requests', res.status === 200 && Array.isArray(res.data) && res.data.length > 0, res);

  // Admin approves the leave
  res = await req('PUT', `/leave/${leaveId}/status`, { status: 'Approved' }, adminToken);
  check('Admin approve leave request', res.status === 200 && res.data.status === 'Approved', res);

  // 5. Attendance & Clocking
  console.log('\n=== STEP 5: ATTENDANCE CLOCK IN & OUT ===');
  res = await req('POST', '/attendance/clock-in', { notes: 'Working remotely today' }, userToken);
  const clockInOk = (res.status === 200 && res.data.clock_in) || (res.status === 400 && res.data.error.includes('Already clocked in'));
  check('Clock In employee (or already clocked in)', clockInOk, res);

  res = await req('POST', '/attendance/clock-out', { notes: 'End of shift' }, userToken);
  check('Clock Out employee', res.status === 200 && res.data.attendance, res);

  res = await req('GET', '/attendance/my-logs', null, userToken);
  check('Get attendance logs', res.status === 200 && Array.isArray(res.data) && res.data.length > 0, res);

  // 6. Payslips & Salary Details
  console.log('\n=== STEP 6: PAYSLIPS & SALARY ===');
  res = await req('GET', '/payslips/my-payslips', null, userToken);
  check('Get employee payslips', res.status === 200 && Array.isArray(res.data) && res.data.length > 0, res);

  // 7. Documents & COE Generation
  console.log('\n=== STEP 7: DOCUMENTS & CERTIFICATE OF EMPLOYMENT ===');
  res = await req('GET', '/documents/my-documents', null, userToken);
  check('Get employee documents list', res.status === 200 && Array.isArray(res.data), res);

  res = await req('POST', '/documents/request', { doc_type: 'Tax Certificate (Form 2316)', title: 'Tax Certificate', description: 'For Annual Tax Audit' }, userToken);
  check('Request custom document', res.status === 201 && res.data.id, res);

  res = await req('POST', '/documents/coe', { purpose: 'Bank Visa Application' }, userToken);
  check('Generate Certificate of Employment (COE)', res.status === 200 && res.data.certificateNo && res.data.employeeName, res);

  // 8. Benefits & Performance Reviews
  console.log('\n=== STEP 8: BENEFITS & PERFORMANCE ===');
  res = await req('GET', '/benefits/my-benefits', null, userToken);
  check('Get employee benefits details', res.status === 200 && res.data.healthInsurance !== undefined, res);

  res = await req('GET', '/performance/my-reviews', null, userToken);
  check('Get employee performance reviews', res.status === 200 && res.data.latestRating !== undefined, res);

  console.log(`\n====================================`);
  console.log(`ESS TEST SUITE RESULTS: ${passed} passed, ${failed} failed`);
  console.log(`====================================`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error('FATAL ERROR:', e); process.exit(1); });
