const SYNC_HOST = 'http://127.0.0.1:14923';

// --- Sync with macOS app ---

async function fetchBlocklist() {
  try {
    const res = await fetch(`${SYNC_HOST}/blocklist`);
    if (!res.ok) throw new Error('not reachable');
    const data = await res.json();
    await chrome.storage.local.set({ blocklist: data, lastSync: Date.now() });
    return data;
  } catch {
    const cached = await chrome.storage.local.get('blocklist');
    return cached.blocklist || [];
  }
}

async function fetchProfile() {
  try {
    const res = await fetch(`${SYNC_HOST}/profile`);
    if (!res.ok) throw new Error('not reachable');
    const data = await res.json();
    await chrome.storage.local.set({ profile: data });
    return data;
  } catch {
    const cached = await chrome.storage.local.get('profile');
    return cached.profile || null;
  }
}

async function isMacAppReachable() {
  try {
    const res = await fetch(`${SYNC_HOST}/ping`);
    return res.ok;
  } catch {
    return false;
  }
}

// --- Domain check ---

function findBlocked(hostname, blocklist) {
  return (blocklist || []).find(t => {
    if (t.kind && t.kind.website) {
      return t.kind.website.domain === hostname;
    }
    return false;
  });
}

// --- Navigation blocking ---

chrome.webNavigation.onBeforeNavigate.addListener(async (details) => {
  if (details.frameId !== 0) return; // only top-level

  const url = new URL(details.url);
  const hostname = url.hostname.replace(/^www\./, '');

  const blocklist = await fetchBlocklist();
  const target = findBlocked(hostname, blocklist);
  if (!target) return;

  const category = target.category || 'regular';
  const gatekeeperUrl = chrome.runtime.getURL('gatekeeper.html') +
    `?domain=${encodeURIComponent(hostname)}` +
    `&label=${encodeURIComponent(target.displayName || hostname)}` +
    `&category=${encodeURIComponent(category)}` +
    `&original=${encodeURIComponent(details.url)}`;

  chrome.tabs.update(details.tabId, { url: gatekeeperUrl });
});

// --- Message handling from gatekeeper page ---

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === 'judge') {
    judgeRequest(msg.appName, msg.argument).then(sendResponse);
    return true;
  }
  if (msg.type === 'getProblem') {
    getProblem().then(sendResponse);
    return true;
  }
  if (msg.type === 'verify') {
    verifyAnswer(msg.problem, msg.answer).then(sendResponse);
    return true;
  }
  if (msg.type === 'reportHistory') {
    reportHistory(msg.topic, msg.correct).then(sendResponse);
    return true;
  }
  if (msg.type === 'ping') {
    isMacAppReachable().then(sendResponse);
    return true;
  }
});

async function judgeRequest(appName, argument) {
  const res = await fetch(`${SYNC_HOST}/judge`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ app_name: appName, argument })
  });
  return res.json();
}

async function getProblem() {
  const res = await fetch(`${SYNC_HOST}/problem`);
  if (!res.ok) return { error: 'API key not configured' };
  return res.json();
}

async function verifyAnswer(problem, answer) {
  const res = await fetch(`${SYNC_HOST}/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      problem_text: problem.problem,
      expected_answer: problem.answer,
      answer_type: problem.answerType,
      tolerance: problem.tolerance,
      topic: problem.topic,
      answer
    })
  });
  return res.json();
}

async function reportHistory(topic, correct) {
  const res = await fetch(`${SYNC_HOST}/history`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ topic, correct })
  });
  return res.json();
}

// Sync on startup
fetchBlocklist();
fetchProfile();
