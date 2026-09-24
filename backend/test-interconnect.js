// Tests the module interconnections:
// 1) Hire applicant -> employee + onboarding checklist + user account created
// 2) New hire can log in with default password
// 3) Complete all onboarding tasks -> employee status becomes Active
// 4) Delete user account -> linked employee marked Inactive
// 5) Delete employee -> cascades onboarding tasks + user account (no orphans)
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
      res.on('end', () => { let p = null; try { p = JSON.parse(raw); } catch (e) { p = raw; } resolve({ status: res.statusCode, data: p }); });
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
  const unique = Date.now();
  const name = 'Interconnect Test ' + unique;
  const email = 'interconnect' + unique + '@test.com';

  // Admin login
  let res = await req('POST', '/auth/login', { email: 'admin@gmail.com', password: 'admin123' });
  check('admin login', res.status === 200 && res.data.token, res);
  const adminToken = res.data.token;

  // 1. Add an applicant
  console.log('\n=== STEP 1: ADD APPLICANT ===');
  res = await req('POST', '/applicants', { surname: 'Tester', middle_name: 'Q', first_name: name, position: 'QA Analyst', email }, adminToken);
  check('applicant added', res.status === 201 && res.data.id, res);
  const applicantId = res.data.id;

  // 2. Hire the applicant
  console.log('\n=== STEP 2: HIRE APPLICANT (creates employee + onboarding + login) ===');
  res = await req('POST', `/applicants/${applicantId}/hire`, null, adminToken);
  check('hire succeeds', res.status === 200 && res.data.employee_id, res);
  check('hire returns portal credentials', res.data.email && res.data.default_password === 'changeme123', res.data);
  const empCode = res.data.employee_id;
  const empEmail = res.data.email;

  // 3. Verify employee created with Onboarding status
  console.log('\n=== STEP 3: EMPLOYEE + ONBOARDING + USER CREATED ===');
  res = await req('GET', '/employees', null, adminToken);
  const emp = (res.data || []).find(e => e.employee_id === empCode);
  check('employee created', !!emp, res.data);
  if (emp) check('employee status is Onboarding', emp.status === 'Onboarding', emp);

  res = await req('GET', '/onboarding', null, adminToken);
  const ob = (res.data.summary || []).find(s => s.emp_code === empCode);
  check('onboarding checklist started', !!ob && ob.task_count === 8, ob);
  if (ob) check('onboarding has 8 tasks', ob.task_count === 8, ob);

  res = await req('GET', '/users', null, adminToken);
  const user = (res.data || []).find(u => u.email === empEmail);
  check('user account auto-created', !!user, res.data);
  if (user) check('user linked to employee code', user.employee_id === empCode, user);

  // 4. New hire can log in with default password
  console.log('\n=== STEP 4: NEW HIRE LOGIN ===');
  res = await req('POST', '/auth/login', { email: empEmail, password: 'changeme123' });
  check('new hire login with default password', res.status === 200 && res.data.token, res);
  const empToken = res.data.token;

  // 5. Employee sees their own onboarding checklist
  console.log('\n=== STEP 5: EMPLOYEE SELF-VIEW ONBOARDING ===');
  res = await req('GET', '/onboarding', null, empToken);
  check('employee sees own checklist', res.data.scope === 'employee' && res.data.total === 8, res.data);

  // 6. Complete all onboarding tasks -> employee becomes Active
  console.log('\n=== STEP 6: COMPLETE ALL TASKS -> ACTIVE ===');
  const taskIds = (ob.tasks || []).map(t => t.id);
  for (const tid of taskIds) {
    res = await req('PUT', `/onboarding/${tid}`, { status: 'Completed' }, adminToken);
  }
  res = await req('GET', '/employees', null, adminToken);
  const empAfter = (res.data || []).find(e => e.employee_id === empCode);
  check('employee status flipped to Active', empAfter && empAfter.status === 'Active', empAfter);

  // 7. Delete user account -> employee marked Inactive
  console.log('\n=== STEP 7: DELETE USER -> EMPLOYEE INACTIVE ===');
  res = await req('GET', '/users', null, adminToken);
  const user2 = (res.data || []).find(u => u.employee_id === empCode);
  check('user account found for delete', !!user2, user);
  res = await req('DELETE', `/users/${user2.id}`, null, adminToken);
  check('user account deleted', res.status === 200, res.data);
  res = await req('GET', '/employees', null, adminToken);
  const empInactive = (res.data || []).find(e => e.employee_id === empCode);
  check('employee marked Inactive', empInactive && empInactive.status === 'Inactive', empInactive);

  // 8. Delete employee -> cascades onboarding + user (no orphan)
  console.log('\n=== STEP 8: DELETE EMPLOYEE -> CASCADE ===');
  res = await req('DELETE', `/employees/${empInactive.id}`, null, adminToken);
  check('employee deleted', res.status === 200, res.data);
  res = await req('GET', '/users', null, adminToken);
  const orphanUser = (res.data || []).find(u => u.employee_id === empCode);
  check('no orphan user account remains', !orphanUser, orphanUser);
  res = await req('GET', '/onboarding', null, adminToken);
  const orphanOnb = (res.data.summary || []).find(s => s.emp_code === empCode);
  check('no orphan onboarding tasks remain', !orphanOnb, orphanOnb);

  console.log(`\n====================================`);
  console.log(`RESULTS: ${passed} passed, ${failed} failed`);
  console.log(`====================================`);
  process.exit(failed > 0 ? 1 : 0);
}
main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
