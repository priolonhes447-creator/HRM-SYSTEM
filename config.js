// ============================================================
// HRMS FRONTEND CONFIGURATION & API BASE RESOLUTION
// ============================================================
window.HRMS_API_URL = window.HRMS_API_URL || '';

window.getApiBase = function() {
    if (typeof window !== 'undefined' && window.HRMS_API_URL) {
        return window.HRMS_API_URL;
    }
    if (typeof window === 'undefined' || !window.location) {
        return 'http://localhost:5000/api';
    }
    const origin = window.location.origin || '';
    const pathname = window.location.pathname || '';
    const protocol = window.location.protocol || '';
    const hostname = window.location.hostname || 'localhost';
    const port = window.location.port || '';

    // 1. If running via file:// protocol
    if (protocol === 'file:') {
        return 'http://localhost/hr-folder/api';
    }

    if (port === '5000') {
        return 'http://localhost/hr-folder/api';
    }

    // Use the same Apache origin so requests reach the PostgreSQL PHP API.
    const dirPath = pathname.substring(0, pathname.lastIndexOf('/'));
    return `${origin}${dirPath}/api`;
};

var API_BASE = window.getApiBase();
window.API_BASE = API_BASE;
window.getApiUrl = function(route) {
    return `${window.API_BASE}/index.php?route=${encodeURIComponent(route.replace(/^\//, ''))}`;
};
