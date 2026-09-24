const {
  db,
  getAllEmployees,
  getAllApplicants,
  getAllAnnouncements,
  getOnboardingStats,
  getDashboardStats
} = require('./database');

// Helper to gather complete live context from database for AI prompt grounding
function getLiveDatabaseContext(user) {
  try {
    const dashboardStats = getDashboardStats() || {};
    const employees = getAllEmployees() || [];
    const applicants = getAllApplicants() || [];
    const announcements = getAllAnnouncements() || [];

    // Department breakdown
    const deptMap = {};
    employees.forEach(emp => {
      const dept = emp.department || 'General';
      deptMap[dept] = (deptMap[dept] || 0) + 1;
    });

    // Onboarding task summary
    let onboardingSummary = [];
    try {
      onboardingSummary = db.prepare(`
        SELECT e.name, e.department, ot.task, ot.status, ot.due_date
        FROM onboarding_tasks ot
        JOIN employees e ON ot.employee_id = e.id
        WHERE ot.status != 'Completed'
        ORDER BY ot.id DESC
        LIMIT 10
      `).all();
    } catch (e) {
      onboardingSummary = [];
    }

    return {
      stats: dashboardStats,
      employeeCount: employees.length,
      employeesSummary: employees.slice(0, 15).map(e => ({
        id: e.employee_id,
        name: e.name,
        dept: e.department,
        role: e.role,
        status: e.status
      })),
      departments: deptMap,
      applicantsCount: applicants.length,
      applicantsSummary: applicants.slice(0, 10).map(a => ({
        name: a.name,
        position: a.position,
        status: a.status,
        date: a.applied_date
      })),
      onboardingPending: onboardingSummary,
      recentAnnouncements: announcements.slice(0, 5).map(a => ({
        title: a.title,
        author: a.author,
        date: a.created_at
      })),
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
        department: user.department,
        position: user.position
      }
    };
  } catch (err) {
    console.error('Error fetching live DB context for AI:', err.message);
    return { user };
  }
}

// Format system prompt for Gemini
function buildSystemInstruction(liveContext) {
  return `You are "Aura", an intelligent AI Assistant integrated into HRMS Pro (Human Resource Management System).
You assist both HR Managers (admins) and Employees with HR queries, database statistics, policy information, and drafting content.

CURRENT USER CONTEXT:
- Name: ${liveContext.user.name || 'User'}
- Email: ${liveContext.user.email || 'Unknown'}
- Role: ${liveContext.user.role === 'admin' ? 'HR Manager / Administrator' : 'Employee'}
- Department: ${liveContext.user.department || 'N/A'}
- Position: ${liveContext.user.position || 'N/A'}

LIVE DATABASE SNAPSHOT:
- Total Employees: ${liveContext.employeeCount || 0}
- Active Employees: ${liveContext.stats.activeEmployees || 0}
- On Leave Employees: ${liveContext.stats.onLeaveEmployees || 0}
- Total Applicants: ${liveContext.applicantsCount || 0}
- Departments: ${JSON.stringify(liveContext.departments || {})}
- Sample Roster: ${JSON.stringify(liveContext.employeesSummary || [])}
- Pending Onboarding Tasks: ${JSON.stringify(liveContext.onboardingPending || [])}
- Recent Announcements: ${JSON.stringify(liveContext.recentAnnouncements || [])}

COMPANY POLICIES & GUIDELINES:
- Regular Work Hours: Monday to Friday, 8:00 AM - 5:00 PM (1-hour lunch break).
- Paid Time Off (PTO): 15 days vacation leave, 10 days sick leave per year for regular employees.
- Probation Period: 6 months for new hires with 30-day, 60-day, and 90-day reviews.
- Payroll Cycle: Semi-monthly (15th and 30th/31st of every month).
- Support Contact: hr-support@hrmspro.com

INSTRUCTIONS:
1. Provide accurate, helpful, professional, and friendly answers.
2. Use markdown (bold, bullet points, numbered lists, tables where helpful).
3. If asked to draft an announcement, draft it clearly with a title and structured content.
4. Keep answers clean, concise, and structured.
5. If the user asks about live system data, use the provided LIVE DATABASE SNAPSHOT.`;
}

// Call Google Gemini 2.5 Flash API
async function callGemini(apiKey, message, history = [], systemInstruction = '') {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;

  // Map history format to Gemini API contents structure
  const contents = [];
  if (Array.isArray(history)) {
    history.forEach(item => {
      if (item.sender === 'user') {
        contents.push({ role: 'user', parts: [{ text: item.text }] });
      } else if (item.sender === 'assistant' || item.sender === 'ai') {
        contents.push({ role: 'model', parts: [{ text: item.text }] });
      }
    });
  }

  // Add current message
  contents.push({ role: 'user', parts: [{ text: message }] });

  const body = {
    system_instruction: {
      parts: [{ text: systemInstruction }]
    },
    contents: contents,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 1024
    }
  };

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Gemini API error (${response.status}): ${errorText}`);
  }

  const data = await response.json();
  const candidate = data.candidates?.[0];
  const responseText = candidate?.content?.parts?.[0]?.text;

  if (!responseText) {
    throw new Error('Gemini API returned empty response structure');
  }

  return responseText;
}

// Intelligent Fallback HR Engine (works 100% offline & without API keys)
function fallbackHREngine(message, liveContext) {
  const msg = message.toLowerCase().trim();
  const isAdmin = liveContext.user.role === 'admin';
  const userName = liveContext.user.name || 'there';

  // 1. Department Breakdown / Statistics
  if (msg.includes('department') || msg.includes('dept') || msg.includes('count by department')) {
    const depts = liveContext.departments || {};
    let deptLines = Object.entries(depts)
      .map(([d, c]) => `- **${d}**: ${c} employee${c > 1 ? 's' : ''}`)
      .join('\n');
    if (!deptLines) deptLines = '- No department data currently available.';

    return `### 📊 Department Roster Summary\nHere is the current distribution of employees across departments:\n\n${deptLines}\n\n**Total Employees:** ${liveContext.employeeCount}\n**Active:** ${liveContext.stats.activeEmployees || 0} | **On Leave:** ${liveContext.stats.onLeaveEmployees || 0}`;
  }

  // 2. Employee Roster / Search / Count
  if (msg.includes('employee') || msg.includes('roster') || msg.includes('staff') || msg.includes('who works')) {
    const emps = liveContext.employeesSummary || [];
    let empList = emps.map(e => `- **${e.name}** (${e.id}) — *${e.role || 'Staff'}* in **${e.dept}** [${e.status}]`).join('\n');
    if (!empList) empList = 'No employee records found.';

    return `### 👥 Employee Roster Overview\nThere are **${liveContext.employeeCount}** total registered employees in HRMS:\n\n${empList}\n\n*Need to edit or view full profile details? Use the **Employees** tab in your dashboard navigation.*`;
  }

  // 3. Applicants / Recruitment
  if (msg.includes('applicant') || msg.includes('candidate') || msg.includes('hiring') || msg.includes('recruit')) {
    const apps = liveContext.applicantsSummary || [];
    let appList = apps.map(a => `- **${a.name}** — ${a.position} (*Status: ${a.status}*, Applied: ${a.date})`).join('\n');
    if (!appList) appList = 'No current job applicants in the pipeline.';

    return `### 💼 Applicant & Hiring Pipeline\nTotal Applicants: **${liveContext.applicantsCount}**\n\n${appList}\n\n*Manage applications in the **Applicants** menu.*`;
  }

  // 4. Onboarding Status
  if (msg.includes('onboard') || msg.includes('checklist') || msg.includes('new hire')) {
    const pending = liveContext.onboardingPending || [];
    if (pending.length === 0) {
      return `### 🚀 Onboarding Status\nAll onboarding tasks are currently up-to-date! There are no pending incomplete onboarding items.`;
    }
    let pList = pending.map(p => `- **${p.name}** (${p.department}): *"${p.task}"* — Status: \`${p.status}\``).join('\n');
    return `### 🚀 Pending Onboarding Tasks\nHere are active onboarding checklist items requiring attention:\n\n${pList}\n\n*View full checklist in the **Onboarding** tab.*`;
  }

  // 5. Draft Announcement (Interactive Action)
  if (msg.includes('draft') || msg.includes('announcement') || msg.includes('notice') || msg.includes('write announcement')) {
    let title = 'Important Company Update';
    let topic = 'general updates';

    if (msg.includes('holiday') || msg.includes('vacation')) {
      title = 'Upcoming Company Holiday Notice';
      topic = 'holiday schedules';
    } else if (msg.includes('town hall') || msg.includes('meeting')) {
      title = 'Quarterly Town Hall Meeting Invitation';
      topic = 'town hall';
    } else if (msg.includes('policy')) {
      title = 'Updated Company Policy Reminder';
      topic = 'policy updates';
    }

    return `### 📢 Drafted Announcement\n\n**Title:** ${title}\n\n**Content:**\nDear Team,\n\nPlease be informed regarding our upcoming ${topic}. All team members are requested to review their schedules and reach out to HR if you have any questions.\n\nThank you for your dedication!\n\n*Best regards,*\n*HR Management Team*\n\n---\n*Click the button below to automatically load this draft into your Announcement creator!*`;
  }

  // 6. Policy: Leave / PTO / Vacation
  if (msg.includes('leave') || msg.includes('vacation') || msg.includes('pto') || msg.includes('sick')) {
    return `### 📅 Company Leave Policy & PTO\n\n1. **Vacation Leave (VL):** 15 days paid leave per calendar year.\n2. **Sick Leave (SL):** 10 days paid leave per calendar year.\n3. **Filing Process:** Submit leave requests at least 3 business days in advance via your department lead.\n4. **Emergency Sick Leave:** Notify your manager or HR before 9:00 AM on the day of absence.`;
  }

  // 7. Policy: Work Hours & Overtime
  if (msg.includes('hour') || msg.includes('time') || msg.includes('schedule') || msg.includes('overtime')) {
    return `### ⏰ Working Hours & Schedule Guidelines\n\n- **Standard Shift:** Monday through Friday, 8:00 AM – 5:00 PM.\n- **Lunch Break:** 12:00 PM – 1:00 PM (1 Hour).\n- **Core Hours:** All employees must be accessible between 10:00 AM and 4:00 PM.\n- **Overtime:** Overtime requires prior written approval from your Department Head.`;
  }

  // 8. Policy: Payroll / Salary
  if (msg.includes('payroll') || msg.includes('pay') || msg.includes('salary') || msg.includes('cut off')) {
    return `### 💳 Payroll & Salary Schedule\n\n- **Pay Periods:** Semi-monthly (1st–15th and 16th–end of month).\n- **Payout Dates:** 15th and 30th/31st of each month (or preceding Friday if landing on a weekend).\n- **Inquiries:** For payslip details or tax queries, email \`hr-payroll@hrmspro.com\`.`;
  }

  // 9. Greeting / Help
  if (msg.includes('hello') || msg.includes('hi') || msg.includes('hey') || msg.includes('help')) {
    return `Hello ${userName}! 👋 I am **Aura**, your HR AI Assistant.\n\nHere is how I can assist you today:\n${
      isAdmin
        ? `- 📊 **HR Analytics**: Ask for department summaries, employee counts, or recruitment progress.\n- 📢 **Draft Content**: Ask me to draft announcements, policy notes, or welcome emails.\n- 🚀 **Onboarding Tracker**: Check pending onboarding checklists.`
        : `- 📅 **Company Policies**: Inquire about leave rules, working hours, or payroll schedules.\n- 🚀 **Onboarding Info**: Review onboarding tasks and guidance.\n- 📢 **Announcements**: Catch up on company news.`
    }\n\nWhat would you like assistance with?`;
  }

  // General intelligent response
  return `### 🤖 Aura HR Assistant\nHello ${userName}! I reviewed your query: *"${message}"*.\n\n**Current System Quick Glance:**\n- Total Employees: **${liveContext.employeeCount}** (${liveContext.stats.activeEmployees || 0} active)\n- Registered Applicants: **${liveContext.applicantsCount}**\n- Your Role: **${liveContext.user.role === 'admin' ? 'HR Manager' : 'Employee'}** (${liveContext.user.department || 'General'})\n\nYou can ask me specific questions such as:\n- *"What is our department breakdown?"*\n- *"Draft an announcement about the upcoming company event"*\n- *"What are the company leave policies?"*\n- *"List all pending onboarding tasks"*`;
}

// Main processing function for Express route
async function processAIChat({ message, history = [], user }) {
  if (!message || typeof message !== 'string') {
    throw new Error('A valid message string is required.');
  }

  const liveContext = getLiveDatabaseContext(user);
  const apiKey = process.env.GEMINI_API_KEY;

  if (apiKey && apiKey.trim() !== '' && !apiKey.includes('YOUR_')) {
    try {
      const systemInstruction = buildSystemInstruction(liveContext);
      const geminiResponse = await callGemini(apiKey, message, history, systemInstruction);
      return {
        reply: geminiResponse,
        source: 'gemini-2.5-flash',
        userRole: user.role
      };
    } catch (err) {
      console.warn('Gemini API call failed, falling back to internal HR engine:', err.message);
    }
  }

  // Fallback HR AI engine if no key or error
  const fallbackReply = fallbackHREngine(message, liveContext);
  return {
    reply: fallbackReply,
    source: 'hr-ai-fallback',
    userRole: user.role
  };
}

module.exports = {
  processAIChat,
  getLiveDatabaseContext
};
