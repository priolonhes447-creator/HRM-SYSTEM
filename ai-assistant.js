// ============================================================
// NHES HR AI ASSISTANT FRONTEND CONTROLLER
// ============================================================

(function () {
  'use strict';

  // Global state
  let isDrawerOpen = false;
  let chatHistory = []; // Stores past messages for conversation memory
  let isRequestPending = false;

  // Resolve API Endpoint
  function getAIChatEndpoint() {
    if (typeof API_BASE !== 'undefined') {
      return typeof window.getApiUrl === 'function'
        ? window.getApiUrl('/ai/chat')
        : `${API_BASE}/index.php?route=ai/chat`;
    }
    const origin = window.location.origin;
    if (window.location.protocol === 'file:') return 'http://localhost/hr-folder/api/ai/chat';
    return `${origin}/api/ai/chat`;
  }

  // Get Auth user from auth.js or localStorage
  function getAuthUser() {
    if (typeof getCurrentUser === 'function') {
      const u = getCurrentUser();
      if (u) return u;
    }
    try {
      const cached = localStorage.getItem('hrms_current_user');
      return cached ? JSON.parse(cached) : null;
    } catch (e) {
      return null;
    }
  }

  // Escape HTML helper
  function escapeHTML(str) {
    if (!str) return '';
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // Markdown Formatter helper for AI responses
  function renderMarkdown(text) {
    if (!text) return '';

    let html = escapeHTML(text);

    // Headers
    html = html.replace(/^### (.*$)/gim, '<h3>$1</h3>');
    html = html.replace(/^## (.*$)/gim, '<h2>$1</h2>');
    html = html.replace(/^# (.*$)/gim, '<h1>$1</h1>');

    // Bold & Italics
    html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*(.*?)\*/g, '<em>$1</em>');

    // Code
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

    // Bullet Lists
    html = html.replace(/^\s*-\s+(.*$)/gim, '<li>$1</li>');
    html = html.replace(/(<li>.*<\/li>)/g, '<ul>$1</ul>');
    // Fix consecutive <ul>
    html = html.replace(/<\/ul>\s*<ul>/g, '');

    // Line breaks
    html = html.replace(/\n\n/g, '</p><p>');
    html = html.replace(/\n/g, '<br>');

    return `<p>${html}</p>`;
  }

  // Inject Widget DOM Elements into document
  function injectWidgetDOM() {
    if (document.getElementById('ai-assistant-fab')) return;

    const user = getAuthUser();
    const isAdmin = user && user.role === 'admin';

    // 1. FAB Button
    const fab = document.createElement('button');
    fab.id = 'ai-assistant-fab';
    fab.setAttribute('title', 'Open Nhes HR AI Assistant');
    fab.innerHTML = `
      <i class="fa-solid fa-sparkles"></i>
      <span class="fab-badge"></span>
    `;
    document.body.appendChild(fab);

    // 2. Drawer Container
    const drawer = document.createElement('div');
    drawer.id = 'ai-assistant-drawer';
    drawer.innerHTML = `
      <div class="ai-drawer-header">
        <div class="ai-drawer-branding">
          <div class="ai-avatar-icon">
            <i class="fa-solid fa-robot"></i>
          </div>
          <div class="ai-drawer-title-group">
            <h4>Nhes HR AI <span style="font-size:10px; background:linear-gradient(135deg, #2F80ED, #7B61FF); padding:2px 6px; border-radius:10px;">PRO</span></h4>
            <div class="ai-status-tag">
              <span class="ai-status-dot"></span> Powered by Gemini 2.5
            </div>
          </div>
        </div>
        <div class="ai-drawer-actions">
          <button class="ai-btn-icon" id="ai-clear-btn" title="Clear Chat History"><i class="fa-solid fa-trash-can"></i></button>
          <button class="ai-btn-icon" id="ai-close-btn" title="Close Assistant"><i class="fa-solid fa-xmark"></i></button>
        </div>
      </div>

      <div class="ai-chat-body" id="ai-chat-body">
        <!-- Messages rendered dynamically -->
      </div>

      <div class="ai-chips-wrapper" id="ai-chips-wrapper">
        <!-- Dynamic Chip Pills -->
      </div>

      <div class="ai-drawer-footer">
        <form class="ai-input-form" id="ai-input-form">
          <input type="text" class="ai-input-field" id="ai-input-field" placeholder="Ask Aura about employees, policies, drafts..." autocomplete="off" />
          <button type="submit" class="ai-send-btn" id="ai-send-btn" title="Send Message">
            <i class="fa-solid fa-paper-plane"></i>
          </button>
        </form>
      </div>
    `;
    document.body.appendChild(drawer);

    // Event Listeners
    fab.addEventListener('click', toggleDrawer);
    document.getElementById('ai-close-btn').addEventListener('click', toggleDrawer);
    document.getElementById('ai-clear-btn').addEventListener('click', clearChat);
    document.getElementById('ai-input-form').addEventListener('submit', handleFormSubmit);

    // Render Initial Welcome Message & Chips
    renderChips();
    renderWelcomeMessage();
  }

  // Toggle Drawer Open/Close
  function toggleDrawer() {
    const drawer = document.getElementById('ai-assistant-drawer');
    const fab = document.getElementById('ai-assistant-fab');

    isDrawerOpen = !isDrawerOpen;
    if (isDrawerOpen) {
      drawer.classList.add('open');
      fab.innerHTML = `<i class="fa-solid fa-xmark"></i>`;
      document.getElementById('ai-input-field').focus();
    } else {
      drawer.classList.remove('open');
      fab.innerHTML = `<i class="fa-solid fa-sparkles"></i><span class="fab-badge"></span>`;
    }
  }

  // Open Drawer explicitly from external triggers (e.g. sidebar link)
  window.openAIAssistant = function(promptText) {
    if (!isDrawerOpen) toggleDrawer();
    if (promptText) {
      document.getElementById('ai-input-field').value = promptText;
      sendUserMessage(promptText);
    }
  };

  // Render Role-specific Chip Pills
  function renderChips() {
    const user = getAuthUser();
    const isAdmin = user && user.role === 'admin';
    const wrapper = document.getElementById('ai-chips-wrapper');
    if (!wrapper) return;

    const chips = isAdmin
      ? [
          { label: '📊 Dept Summary', prompt: 'Show count by department' },
          { label: '📢 Draft Announcement', prompt: 'Draft an announcement about company holiday' },
          { label: '🚀 Pending Onboarding', prompt: 'List all pending onboarding tasks' },
          { label: '👥 Employee Roster', prompt: 'List all active employees' },
          { label: '💼 Applicant Pipeline', prompt: 'Show job applicant pipeline summary' }
        ]
      : [
          { label: '📅 Leave Policies', prompt: 'What is our company leave policy?' },
          { label: '⏰ Working Hours', prompt: 'What are the standard working hours and schedule?' },
          { label: '💳 Payroll Dates', prompt: 'When are the payroll payout dates?' },
          { label: '📢 Latest News', prompt: 'What are the recent company announcements?' }
        ];

    wrapper.innerHTML = chips
      .map(
        c => `<button class="ai-chip" data-prompt="${escapeHTML(c.prompt)}">${escapeHTML(c.label)}</button>`
      )
      .join('');

    wrapper.querySelectorAll('.ai-chip').forEach(btn => {
      btn.addEventListener('click', () => {
        const prompt = btn.getAttribute('data-prompt');
        if (prompt) sendUserMessage(prompt);
      });
    });
  }

  // Render Welcome Message
  function renderWelcomeMessage() {
    const user = getAuthUser();
    const userName = user ? user.name : 'there';
    const roleText = user && user.role === 'admin' ? 'HR Manager' : 'Team Member';

    const welcomeHTML = `
      <div class="ai-msg assistant">
        <div class="ai-msg-bubble">
          <p>Hello <strong>${escapeHTML(userName)}</strong>! 👋 I am <strong>Aura</strong>, your HR AI Assistant.</p>
          <p>How can I assist you with HR operations, database stats, or company policies today?</p>
        </div>
        <div class="ai-msg-meta">
          <span class="ai-source-badge">✨ Gemini AI</span> • Ready
        </div>
      </div>
    `;

    document.getElementById('ai-chat-body').innerHTML = welcomeHTML;
  }

  // Clear Chat History
  function clearChat() {
    chatHistory = [];
    renderWelcomeMessage();
  }

  // Form Submit Handler
  function handleFormSubmit(e) {
    e.preventDefault();
    const input = document.getElementById('ai-input-field');
    const msg = input.value.trim();
    if (!msg || isRequestPending) return;

    input.value = '';
    sendUserMessage(msg);
  }

  // Send User Message to Backend API
  async function sendUserMessage(text) {
    if (isRequestPending) return;

    const chatBody = document.getElementById('ai-chat-body');

    // 1. Append User Bubble
    const userMsgHTML = `
      <div class="ai-msg user">
        <div class="ai-msg-bubble">
          ${escapeHTML(text)}
        </div>
        <div class="ai-msg-meta">
          Just now
        </div>
      </div>
    `;
    chatBody.insertAdjacentHTML('beforeend', userMsgHTML);

    // 2. Append Typing Indicator
    const typingId = 'typing-' + Date.now();
    const typingHTML = `
      <div class="ai-msg assistant" id="${typingId}">
        <div class="ai-msg-bubble">
          <div class="ai-typing-indicator">
            <span></span><span></span><span></span>
          </div>
        </div>
      </div>
    `;
    chatBody.insertAdjacentHTML('beforeend', typingHTML);
    chatBody.scrollTop = chatBody.scrollHeight;

    // Set Loading State
    isRequestPending = true;
    const sendBtn = document.getElementById('ai-send-btn');
    if (sendBtn) sendBtn.disabled = true;

    // Track history
    chatHistory.push({ sender: 'user', text: text });

    try {
      const token = typeof getToken === 'function' ? getToken() : localStorage.getItem('hrms_token');
      const response = await fetch(getAIChatEndpoint(), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          message: text,
          history: chatHistory.slice(-6) // Send last 6 turns for context
        })
      });

      const data = await response.json();

      // Remove Typing Indicator
      const typingElem = document.getElementById(typingId);
      if (typingElem) typingElem.remove();

      if (!response.ok) {
        throw new Error(data.error || 'Failed to get AI response');
      }

      const replyText = data.reply || 'No response generated.';
      const sourceTag = data.source === 'gemini-2.5-flash' ? '✨ Gemini 2.5' : '🤖 HR Engine';

      chatHistory.push({ sender: 'assistant', text: replyText });

      // Check if reply contains announcement draft for HR
      const isDraftAnnouncement = replyText.toLowerCase().includes('drafted announcement') || replyText.toLowerCase().includes('apply to announcement');

      const formattedBody = renderMarkdown(replyText);

      // Construct AI Bubble HTML
      let aiBubbleHTML = `
        <div class="ai-msg assistant">
          <div class="ai-msg-bubble">
            ${formattedBody}
            ${
              isDraftAnnouncement
                ? `<div class="ai-action-btn-row">
                     <button class="ai-action-btn" onclick="window.applyAIDraftToAnnouncement()"><i class="fa-solid fa-bullhorn"></i> Apply to Announcement</button>
                   </div>`
                : ''
            }
          </div>
          <div class="ai-msg-meta">
            <span class="ai-source-badge">${sourceTag}</span> • Just now
          </div>
        </div>
      `;

      chatBody.insertAdjacentHTML('beforeend', aiBubbleHTML);
    } catch (err) {
      console.error('AI Chat Error:', err);
      // Remove Typing Indicator
      const typingElem = document.getElementById(typingId);
      if (typingElem) typingElem.remove();

      const errorHTML = `
        <div class="ai-msg assistant">
          <div class="ai-msg-bubble" style="border-color:#FCA5A5; background:#FEF2F2; color:#991B1B;">
            <i class="fa-solid fa-triangle-exclamation"></i> ${escapeHTML(err.message)}
          </div>
          <div class="ai-msg-meta">
            Error
          </div>
        </div>
      `;
      chatBody.insertAdjacentHTML('beforeend', errorHTML);
    } finally {
      isRequestPending = false;
      if (sendBtn) sendBtn.disabled = false;
      chatBody.scrollTop = chatBody.scrollHeight;
    }
  }

  // Global helper: Copy AI Draft directly to Announcement Modal on dashboard.html
  window.applyAIDraftToAnnouncement = function () {
    const user = getAuthUser();
    if (!user || user.role !== 'admin') {
      alert('Announcement creation requires HR Admin access.');
      return;
    }

    // Extract last AI message text
    const lastAIMsg = chatHistory.filter(m => m.sender === 'assistant').pop();
    let title = 'Important Announcement';
    let content = 'Please be informed regarding our latest company updates.';

    if (lastAIMsg && lastAIMsg.text) {
      const titleMatch = lastAIMsg.text.match(/\*\*Title:\*\*\s*(.+)/i);
      if (titleMatch && titleMatch[1]) {
        title = titleMatch[1].trim();
      }

      const contentMatch = lastAIMsg.text.match(/\*\*Content:\*\*\s*([\s\S]+?)(?=\n---\n|$)/i);
      if (contentMatch && contentMatch[1]) {
        content = contentMatch[1].trim();
      }
    }

    // Check if openAnnouncementModal or announcement input exists on current page
    const titleInput = document.getElementById('announcementTitle') || document.querySelector('input[name="announcement_title"]');
    const contentInput = document.getElementById('announcementContent') || document.querySelector('textarea[name="announcement_content"]');

    if (typeof openAnnouncementModal === 'function') {
      openAnnouncementModal();
    } else {
      // Trigger modal click if button exists
      const createAnnBtn = document.querySelector('[onclick*="openAnnouncementModal"]') || document.querySelector('[onclick*="Announcement"]');
      if (createAnnBtn) createAnnBtn.click();
    }

    setTimeout(() => {
      if (titleInput) titleInput.value = title;
      if (contentInput) contentInput.value = content;
    }, 150);

    // Minimize drawer
    toggleDrawer();
  };

  // Initialize when DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectWidgetDOM);
  } else {
    injectWidgetDOM();
  }
})();
