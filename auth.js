// ================= HRMS AUTH & API CLIENT SYSTEM =================
// Dynamic API Base URL resolution for XAMPP (Apache PHP) or standalone server
// Dynamic API Base URL resolution for Node.js server, XAMPP (Apache PHP), or file://
var getApiBase = window.getApiBase || (() => {
  if (typeof window !== 'undefined' && window.HRMS_API_URL) {
    return window.HRMS_API_URL;
  }
  const origin = window.location ? window.location.origin : '';
  const pathname = window.location ? window.location.pathname : '';
  const protocol = window.location ? window.location.protocol : '';
  const hostname = window.location ? window.location.hostname : 'localhost';
  const port = window.location ? window.location.port : '';

  // 1. If running via file:// protocol
  if (protocol === 'file:') return 'http://localhost/hr-folder/api';

  if (port === '5000') return 'http://localhost/hr-folder/api';

  const dirPath = pathname.substring(0, pathname.lastIndexOf('/'));
  return `${origin}${dirPath}/api`;
});

var API_BASE = window.API_BASE || getApiBase();
window.API_BASE = API_BASE;

// Store token & session user in sessionStorage (memory per tab session, not persistent localStorage)
function storeToken(token) {
  sessionStorage.setItem('hrms_token', token);
}

function getToken() {
  return sessionStorage.getItem('hrms_token');
}

function clearAuth() {
  sessionStorage.removeItem('hrms_token');
  sessionStorage.removeItem('hrms_current_user');
  localStorage.removeItem('hrms_token');
  localStorage.removeItem('hrms_current_user');
}

// LOGIN via the configured PostgreSQL-backed API.
async function loginWithBackend(email, password) {
  const res = await fetch(window.getApiUrl('/auth/login'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.trim(), password })
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Unable to connect to the HRMS database server.');

  storeToken(data.token);
  sessionStorage.setItem('hrms_current_user', JSON.stringify(data.user));
  return data.user;
}

// CURRENT USER
function getCurrentUser() {
  try {
    const data = sessionStorage.getItem('hrms_current_user') || localStorage.getItem('hrms_current_user');
    if (localStorage.getItem('hrms_current_user')) {
      // Migrate legacy localStorage user to sessionStorage & clean up
      sessionStorage.setItem('hrms_current_user', localStorage.getItem('hrms_current_user'));
      localStorage.removeItem('hrms_current_user');
      localStorage.removeItem('hrms_token');
    }
    return data ? JSON.parse(data) : null;
  } catch (e) {
    clearAuth();
    return null;
  }
}

// PAGE PROTECTION
function protectPage(requiredRole) {
  const user = getCurrentUser();

  if (!user || !getToken()) {
    clearAuth();
    window.location.href = 'index.html';
    return;
  }

  if (requiredRole && user.role !== requiredRole) {
    if (user.role === 'admin') {
      window.location.href = 'dashboard.html';
    } else {
      window.location.href = 'user-dashboard.html';
    }
    return;
  }
}

// LOGOUT
function logout() {
  clearAuth();
  window.location.href = 'index.html';
}

// Auth header helper
function authHeaders(extra = {}) {
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${getToken()}`,
    ...extra
  };
}
