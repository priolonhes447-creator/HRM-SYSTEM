// End-to-end test for the Onboarding module:
// Admin starts a checklist -> 8 default tasks are generated ->
// employee sees their own checklist -> admin updates a task status ->
// admin adds a custom task -> cleanup.
const http = require('http');

const BASE = 'http://localhost:5000/api';
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
  const uniqueName = `Onboard Test ${Date.now()}`;
  const uniqueEmail = `onb${Date.now()}@test.com`;

  // 1. Admin logs in
  console.log('\n=== STEP 1: ADMIN LOGS IN ===');
  let res = await req('POST', '/auth/login', { email: 'admin@gmail.com', password: 'admin123' });
  check('admin login succeeds', res.status === 200 && res.data.token, res);
  const adminToken = res.data.token;

  // 2. Employee logs in
  console.log('\n=== STEP 2: USER (EMPLOYEE) LOGS IN ===');
  res = await req('POST', '/auth/login', { email: 'user@gmail.com', password: 'user123' });
  check('user login succeeds', res.status === 200 && res.data.token, res);
  const userToken = res.data.token;

  // 3. Admin adds a test employee
  console.log('\n=== STEP 3: ADMIN CREATES TEST EMPLOYEE ===');
  const empCode = 'TMP' + String(Date.now()).slice(-5);
  res = await req('POST', '/employees', {
    employee_id: empCode,
    name: uniqueName,
    email: uniqueEmail,
    department: 'QA',
    role: 'Tester',
    status: 'Onboarding'
  }, adminToken);
  check('test employee created', res.status === 201, res);
  const empId = res.data.id;

  // 4. Admin starts onboarding for that employee
  console.log('\n=== STEP 4: ADMIN STARTS ONBOARDING ===');
  const empEmployeeId = empCode;
  res = await req('POST', `/onboarding/employees/${empEmployeeId}/start`, null, adminToken);
  check('start onboarding returns 201', res.status === 201, res);
  check('generates 8 default tasks', res.data.created && res.data.created.length === 8, res.data);

  // 5. Admin sees the new employee in onboarding summary
  console.log('\n=== STEP 5: ADMIN VIEWS ONBOARDING SUMMARY ===');
  res = await req('GET', '/onboarding', null, adminToken);
  check('GET /onboarding returns admin scope', res.status === 200 && res.data.scope === 'admin', res.data);
  const group = (res.data.summary || []).find(g => g.emp_code === empCode);
  check('new hire appears in summary', !!group, res.data.summary);
  if (group) {
    check('task_count = 8', group.task_count === 8, group);
    check('progress starts at 0%', group.progress === 0, group);
  }
  check('stats include activeOnboardings', typeof res.data.stats.activeOnboardings === 'number', res.data.stats);

  // 6. Employee views their own checklist (empty by default for the seeded user)
  console.log('\n=== STEP 6: EMPLOYEE SELF-VIEW ===');
  res = await req('GET', '/onboarding', null, userToken);
  check('GET /onboarding returns employee scope', res.status === 200 && res.data.scope === 'employee', res.data);
  check('employee checklist is an array', Array.isArray(res.data.checklist), res.data);

  // 7. Admin updates a task status to Completed
  console.log('\n=== STEP 7: ADMIN UPDATES TASK STATUS ===');
  res = await req('GET', '/onboarding', null, adminToken);
  const grp = (res.data.summary || []).find(g => g.emp_code === empCode);
  check('found group with tasks', grp && grp.tasks && grp.tasks.length > 0, grp);
  const firstTaskId = grp.tasks[0].id;
  res = await req('PUT', `/onboarding/${firstTaskId}`, { status: 'Completed' }, adminToken);
  check('status update returns 200', res.status === 200, res);
  check('task now Completed', res.data.task && res.data.task.status === 'Completed', res.data.task);

  // 8. Admin adds a custom task
  console.log('\n=== STEP 8: ADMIN ADDS CUSTOM TASK ===');
  res = await req('POST', '/onboarding', {
    employee_id: empId,
    task: 'Custom Background Check',
    due_date: new Date().toISOString().split('T')[0],
    status: 'In Progress'
  }, adminToken);
  check('custom task added', res.status === 201 && res.data.task, res.data);

  // 9. Verify summary reflects progress after completed task + custom task
  console.log('\n=== STEP 9: VERIFY PROGRESS RECOMPUTED ===');
  res = await req('GET', '/onboarding', null, adminToken);
  const grp2 = (res.data.summary || []).find(g => g.emp_code === empCode);
  check('task_count now 9 (8 + custom)', grp2 && grp2.task_count === 9, grp2);
  check('completed_count = 1', grp2 && grp2.completed_count === 1, grp2);

  // 10. Cleanup: delete the test employee
  console.log('\n=== STEP 10: CLEANUP ===');
  // Delete onboarding tasks first via API, then the employee.
  const grp3res = await req('GET', '/onboarding', null, adminToken);
  const grp3 = (grp3res.data.summary || []).find(g => g.emp_code === empCode);
  if (grp3 && grp3.tasks) {
    for (const t of grp3.tasks) {
      await req('DELETE', `/onboarding/${t.id}`, null, adminToken);
    }
  }
  res = await req('DELETE', `/employees/${empId}`, null, adminToken);
  check('test employee removed', res.status === 200, res);

  console.log(`\n====================================`);
  console.log(`RESULTS: ${passed} passed, ${failed} failed`);
  console.log(`====================================`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('FATAL:', err.message);
  process.exit(1);
});

