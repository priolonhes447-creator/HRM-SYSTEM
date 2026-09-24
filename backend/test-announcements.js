// End-to-end test: Admin posts an announcement -> User receives it as an unread notification
// -> user marks it read -> badge clears.
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
  const uniqueTitle = `Company Announcement ${Date.now()}`;
  const content = 'This is an important company-wide update for all employees.';

  // 1. Admin logs in
  console.log('\n=== STEP 1: ADMIN LOGS IN ===');
  let res = await req('POST', '/auth/login', { email: 'admin@gmail.com', password: 'admin123' });
  check('admin login succeeds', res.status === 200 && res.data.token, res);
  const adminToken = res.data.token;

  // 2. User (employee) logs in
  console.log('\n=== STEP 2: USER LOGS IN ===');
  res = await req('POST', '/auth/login', { email: 'user@gmail.com', password: 'user123' });
  check('user login succeeds', res.status === 200 && res.data.token, res);
  const userToken = res.data.token;

  // 3. Get user's current unread count before posting
  console.log('\n=== STEP 3: BASELINE UNREAD COUNT ===');
  res = await req('GET', '/announcements/mine', null, userToken);
  check('GET /announcements/mine works', res.status === 200 && Array.isArray(res.data.announcements), res);
  const baselineUnread = res.data.unread_count;

  // 4. Admin posts an announcement
  console.log('\n=== STEP 4: ADMIN POSTS ANNOUNCEMENT ===');
  res = await req('POST', '/announcements', { title: uniqueTitle, content }, adminToken);
  check('announcement created', res.status === 201 && res.data.id, res);
  const annId = res.data.id;

  // 5. User fetches their announcements - should see the new one as unread
  console.log('\n=== STEP 5: USER SEES UNREAD ANNOUNCEMENT ===');
  res = await req('GET', '/announcements/mine', null, userToken);
  check('mine endpoint works', res.status === 200, res);
  const found = (res.data.announcements || []).find(a => a.id === annId);
  check('new announcement appears in user account', !!found, res.data.announcements);
  if (found) {
    check('announcement is unread (is_read=0)', found.is_read === 0, found);
    check('title matches', found.title === uniqueTitle, found);
    check('content matches', found.content === content, found);
  }
  check('unread count increased by 1', res.data.unread_count === baselineUnread + 1, { baselineUnread, unread: res.data.unread_count });

  // 6. User marks the announcement as read
  console.log('\n=== STEP 6: USER MARKS READ ===');
  res = await req('POST', `/announcements/${annId}/read`, null, userToken);
  check('mark read works', res.status === 200, res);
  check('unread count returns to baseline', res.data.unread_count === baselineUnread, res.data);

  // 7. Verify it's now read
  res = await req('GET', '/announcements/mine', null, userToken);
  const afterRead = (res.data.announcements || []).find(a => a.id === annId);
  check('announcement is now read (is_read=1)', afterRead && afterRead.is_read === 1, afterRead);

  // 8. Clean up - delete test announcement
  console.log('\n=== STEP 8: CLEANUP ===');
  res = await req('DELETE', `/announcements/${annId}`, null, adminToken);
  check('test announcement removed', res.status === 200, res);

  console.log(`\n====================================`);
  console.log(`RESULTS: ${passed} passed, ${failed} failed`);
  console.log(`====================================`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('FATAL:', err.message);
  process.exit(1);
});
