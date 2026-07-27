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

async function guardNavigation(details) {
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
}

// These handlers are async, so the page can start loading before the blocklist
// lookup finishes — long enough for a video to autoplay behind the gate.
// onBeforeNavigate usually wins the race; onCommitted is the backstop for when
// it doesn't, and for redirects that land on a blocked host.
chrome.webNavigation.onBeforeNavigate.addListener(guardNavigation);
chrome.webNavigation.onCommitted.addListener((details) => {
  // Our own gatekeeper page commits too — don't gate the gate.
  if (details.url.startsWith(chrome.runtime.getURL(''))) return;
  guardNavigation(details);
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
  judge: (msg) => judgeRequest(msg.appName, msg.argument, msg.domain),
  getProblem: (msg) => getProblem(msg.domain),
  verify: (msg) => verifyAnswer(msg.problem, msg.answer, msg.domain),
  reportHistory: (msg) => reportHistory(msg.topic, msg.correct),
  grantAccess: (msg) => grantAccess(msg.domain),
  cooldown: (msg) => checkCooldown(msg.domain),
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
    // A cooldown is a normal outcome, not a failure — pass it through with its
    // countdown so the page can show a timer instead of a bare error.
    if (res.status === 429) {
      return { error: data?.error || 'Cooling down.', cooldownSeconds: data?.cooldown_seconds || 0 };
    }
    throw new Error(data?.error || `Blocker app returned ${res.status}`);
  }
  return data;
}

async function judgeRequest(appName, argument, domain) {
  return postJSON('/judge', { app_name: appName, argument, domain });
}

async function getProblem(domain) {
  const res = await fetch(`${SYNC_HOST}/problem?domain=${encodeURIComponent(domain || '')}`);
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    return {
      error: data?.error || `Blocker app returned ${res.status}`,
      cooldownSeconds: res.status === 429 ? data?.cooldown_seconds || 0 : 0,
    };
  }
  return data;
}

async function checkCooldown(domain) {
  try {
    const res = await fetch(`${SYNC_HOST}/cooldown?domain=${encodeURIComponent(domain || '')}`);
    if (!res.ok) return { seconds: 0 };
    return await res.json();
  } catch {
    return { seconds: 0 };
  }
}

async function verifyAnswer(problem, answer, domain) {
  return postJSON('/verify', {
    problem_text: problem.problem,
    expected_answer: problem.answer,
    answer_type: problem.answerType,
    tolerance: problem.tolerance,
    topic: problem.topic,
    domain,
    answer,
  });
}

async function reportHistory(topic, correct) {
  return postJSON('/history', { topic, correct });
}

// Sync on startup
fetchBlocklist({ force: true });
fetchProfile();
