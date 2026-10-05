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

const INACTIVITY_TIMEOUT_MS = 2 * 60 * 1000;
const SESSION_WARNING_MS = 60 * 1000;
const HR_DASHBOARD_URL = 'dashboard.html?v=hr-role-20261006';
let inactivityTimeoutId = null;
let inactivityWarningTimeoutId = null;
let inactivityListenersStarted = false;

function startInactivityTimeout() {
  if (inactivityListenersStarted) return;
  inactivityListenersStarted = true;

  const warningStyles = document.createElement('style');
  warningStyles.textContent = `
    #hrms-session-warning {
      position: fixed;
      z-index: 10000;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      display: flex;
      flex-direction: column;
      gap: 18px;
      width: min(480px, calc(100vw - 32px));
      padding: 24px;
      border: 1px solid #dbe4ec;
      border-top: 4px solid #d99a20;
      border-radius: 12px;
      background: #ffffff;
      box-shadow: 0 20px 60px rgba(15, 23, 42, 0.24);
      color: #1f2937;
      font: 15px/1.55 "DM Sans", Arial, sans-serif;
    }
    #hrms-session-warning[hidden] { display: none; }
    #hrms-session-warning h2 {
      margin: 0;
      color: #172b3a;
      font-size: 18px;
      font-weight: 700;
      line-height: 1.3;
    }
    #hrms-session-warning p {
      margin: 0;
      color: #465766;
    }
    @media (max-width: 480px) {
      #hrms-session-warning { padding: 20px; }
    }
  `;
  document.head.appendChild(warningStyles);

  const warning = document.createElement('aside');
  warning.id = 'hrms-session-warning';
  warning.setAttribute('role', 'alert');
  warning.setAttribute('aria-atomic', 'true');
  warning.hidden = true;

  const title = document.createElement('h2');
  title.textContent = 'Session Expiring.';

  const message = document.createElement('p');
  message.textContent = "Hello, I’m Ness, your AI Assistant. I’m reminding you that your session is about to expire. Please click or interact with the screen to keep your session active. Thank you.";
  warning.append(title, message);
  document.body.appendChild(warning);

  const resetInactivityTimeout = () => {
    window.clearTimeout(inactivityTimeoutId);
    window.clearTimeout(inactivityWarningTimeoutId);
    warning.hidden = true;
    inactivityWarningTimeoutId = window.setTimeout(() => {
      warning.hidden = false;
    }, INACTIVITY_TIMEOUT_MS - SESSION_WARNING_MS);
    inactivityTimeoutId = window.setTimeout(logout, INACTIVITY_TIMEOUT_MS);
  };

  ['mousemove', 'mousedown', 'keydown', 'touchstart', 'touchmove', 'pointerdown', 'pointermove', 'wheel', 'scroll', 'click', 'input', 'change', 'submit']
    .forEach(eventName => document.addEventListener(eventName, resetInactivityTimeout, { capture: true, passive: true }));

  resetInactivityTimeout();
}

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
  const loginUrl = window.getApiUrl('/auth/login');
  let res;
  try {
    res = await fetch(loginUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.trim(), password })
    });
  } catch (error) {
    throw new Error(`Unable to reach the HRMS API at ${loginUrl}. Start Apache, verify PostgreSQL is running, and open the app through Apache (not as a local file).`);
  }
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

  const hasRequiredRole = user.role === requiredRole
    || (requiredRole === 'admin' && user.role === 'hr');
  if (requiredRole && !hasRequiredRole) {
    if (user.role === 'admin' || user.role === 'hr') {
      window.location.replace(HR_DASHBOARD_URL);
    } else {
      window.location.href = 'user-dashboard.html';
    }
    return;
  }

  startInactivityTimeout();
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
