const SYNC_HOST = 'http://127.0.0.1:14923';
const BLOCKLIST_TTL_MS = 30_000;
const DEFAULT_UNBLOCK_MINUTES = 30;

// In-memory cache. The service worker can be torn down at any time, so
// chrome.storage is the durable copy and this is just the fast path.
let cache = { blocklist: null, fetchedAt: 0, profile: null };

// --- Sync with macOS app ---

async function fetchBlocklist({ force = false } = {}) {
  const fresh = Date.now() - cache.fetchedAt < BLOCKLIST_TTL_MS;
  if (!force && cache.blocklist && fresh) return cache.blocklist;

  try {
    const res = await fetch(`${SYNC_HOST}/blocklist`);
    if (!res.ok) throw new Error('not reachable');
    const data = await res.json();
    cache.blocklist = data;
    cache.fetchedAt = Date.now();
    await chrome.storage.local.set({ blocklist: data, lastSync: Date.now() });
    return data;
  } catch {
    if (cache.blocklist) return cache.blocklist;
    const cached = await chrome.storage.local.get('blocklist');
    cache.blocklist = cached.blocklist || [];
    return cache.blocklist;
  }
}

async function fetchProfile() {
  try {
    const res = await fetch(`${SYNC_HOST}/profile`);
    if (!res.ok) throw new Error('not reachable');
    const data = await res.json();
    cache.profile = data;
    await chrome.storage.local.set({ profile: data });
    return data;
  } catch {
    if (cache.profile) return cache.profile;
    const cached = await chrome.storage.local.get('profile');
    cache.profile = cached.profile || null;
    return cache.profile;
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

// --- Domain matching ---

function normalizeHostname(hostname) {
  return hostname.toLowerCase().replace(/^www\./, '');
}

// A blocked "youtube.com" must also cover m.youtube.com and music.youtube.com,
// but must NOT cover notyoutube.com.
function findBlocked(hostname, blocklist) {
  const host = normalizeHostname(hostname);
  return (blocklist || []).find((t) => {
    if (!t || !t.domain) return false;
    const domain = normalizeHostname(t.domain);
    return host === domain || host.endsWith(`.${domain}`);
  });
}

// --- Access grants ---
//
// Without these, passing the gatekeeper would redirect back to the blocked URL,
// which would immediately re-trigger the gatekeeper: an inescapable loop.
// Grants live in session storage, so they clear when the browser restarts.

async function getGrants() {
  const stored = await chrome.storage.session.get('grants');
  const grants = stored.grants || {};
  const now = Date.now();
  let changed = false;
  for (const [domain, expiry] of Object.entries(grants)) {
    if (expiry <= now) {
      delete grants[domain];
      changed = true;
    }
  }
  if (changed) await chrome.storage.session.set({ grants });
  return grants;
}

async function isGranted(hostname) {
  const grants = await getGrants();
  const host = normalizeHostname(hostname);
  return Object.keys(grants).some(
    (domain) => host === domain || host.endsWith(`.${domain}`)
  );
}

async function grantAccess(domain) {
  const profile = cache.profile || (await fetchProfile());
  const minutes = profile?.unblockDurationMinutes || DEFAULT_UNBLOCK_MINUTES;
  const grants = await getGrants();
  grants[normalizeHostname(domain)] = Date.now() + minutes * 60_000;
  await chrome.storage.session.set({ grants });
  return { ok: true, minutes };
}

// --- Navigation blocking ---

chrome.webNavigation.onBeforeNavigate.addListener(async (details) => {
  if (details.frameId !== 0) return; // only top-level

  let url;
  try {
    url = new URL(details.url);
  } catch {
    return;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;

  const hostname = normalizeHostname(url.hostname);

  if (await isGranted(hostname)) return;

  const blocklist = await fetchBlocklist();
  const target = findBlocked(hostname, blocklist);
  if (!target) return;

  const category = target.category || 'regular';
  const gatekeeperUrl =
    chrome.runtime.getURL('gatekeeper.html') +
    `?domain=${encodeURIComponent(target.domain)}` +
    `&label=${encodeURIComponent(target.label || target.domain)}` +
    `&category=${encodeURIComponent(category)}` +
    `&original=${encodeURIComponent(details.url)}`;

  chrome.tabs.update(details.tabId, { url: gatekeeperUrl });
});

// --- Periodic sync (the service worker does not stay alive on its own) ---

chrome.alarms.create('sync', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync') {
    fetchBlocklist({ force: true });
    fetchProfile();
  }
});

// --- Message handling from gatekeeper page ---

const handlers = {
  judge: (msg) => judgeRequest(msg.appName, msg.argument),
  getProblem: () => getProblem(),
  verify: (msg) => verifyAnswer(msg.problem, msg.answer),
  reportHistory: (msg) => reportHistory(msg.topic, msg.correct),
  grantAccess: (msg) => grantAccess(msg.domain),
  ping: () => isMacAppReachable(),
};

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  const handler = handlers[msg?.type];
  if (!handler) return;
  // Always resolve: an unhandled rejection here leaves the gatekeeper page
  // waiting forever on a promise that never settles.
  Promise.resolve()
    .then(() => handler(msg))
    .then(sendResponse)
    .catch((err) => sendResponse({ error: String(err?.message || err) }));
  return true;
});

async function postJSON(path, payload) {
  const res = await fetch(`${SYNC_HOST}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(data?.error || `Blocker app returned ${res.status}`);
  }
  return data;
}

async function judgeRequest(appName, argument) {
  return postJSON('/judge', { app_name: appName, argument });
}

async function getProblem() {
  const res = await fetch(`${SYNC_HOST}/problem`);
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    return { error: data?.error || `Blocker app returned ${res.status}` };
  }
  return data;
}

async function verifyAnswer(problem, answer) {
  return postJSON('/verify', {
    problem_text: problem.problem,
    expected_answer: problem.answer,
    answer_type: problem.answerType,
    tolerance: problem.tolerance,
    topic: problem.topic,
    answer,
  });
}

async function reportHistory(topic, correct) {
  return postJSON('/history', { topic, correct });
}

// Sync on startup
fetchBlocklist({ force: true });
fetchProfile();
