const SYNC_HOST = 'http://127.0.0.1:14923';

async function init() {
  const [reachable, blocklist, grants] = await Promise.all([
    checkReachable(),
    fetchBlocklist(),
    activeGrants(),
  ]);

  updateStatus(reachable);
  renderGrants(grants);
  renderBlocklist(blocklist || []);
}

async function checkReachable() {
  try {
    const res = await fetch(`${SYNC_HOST}/ping`);
    return res.ok;
  } catch { return false; }
}

async function fetchBlocklist() {
  try {
    const res = await fetch(`${SYNC_HOST}/blocklist`);
    if (!res.ok) throw new Error('unreachable');
    return await res.json();
  } catch {
    const cached = await chrome.storage.local.get('blocklist');
    return cached.blocklist || [];
  }
}

/// Domains currently unlocked by a passed gatekeeper, with time left.
async function activeGrants() {
  const stored = await chrome.storage.session.get('grants');
  const grants = stored.grants || {};
  const now = Date.now();
  return Object.entries(grants)
    .filter(([, expiry]) => expiry > now)
    .map(([domain, expiry]) => ({ domain, minutes: Math.ceil((expiry - now) / 60000) }));
}

function updateStatus(reachable) {
  document.getElementById('status-word').textContent = reachable ? 'Sitting' : 'Adjourned';
  document.getElementById('status-mark').className = `mark ${reachable ? 'on' : 'off'}`;
  document.getElementById('status-line').innerHTML = reachable
    ? 'The court is <b>in session</b>. Blocked sites are gated.'
    : 'The court is <b>not sitting</b>. Start the Blocker app to restore the gate.';
}

function renderGrants(grants) {
  const note = document.getElementById('granted-note');
  if (!grants.length) return;
  const soonest = grants.reduce((a, b) => (a.minutes < b.minutes ? a : b));
  note.textContent =
    grants.length === 1
      ? `leave granted · ${soonest.domain} · ${soonest.minutes}m remaining`
      : `leave granted · ${grants.length} sites · ${soonest.minutes}m remaining`;
  note.classList.remove('hidden');
}

function renderBlocklist(blocklist) {
  const container = document.getElementById('blocklist');
  const count = document.getElementById('count');
  const websites = (blocklist || []).filter((t) => t && t.domain);

  if (websites.length === 0) {
    container.replaceChildren(
      Object.assign(document.createElement('p'), {
        className: 'none',
        textContent: 'The docket is empty.',
      })
    );
    return;
  }

  count.textContent = `${websites.length} entries`;

  const nodes = [];
  websites.forEach((t, index) => {
    const strict = t.category === 'strict';

    const row = document.createElement('div');
    row.className = 'row';

    const no = document.createElement('span');
    no.className = 'no';
    no.textContent = String(index + 1).padStart(2, '0');

    const who = document.createElement('div');
    who.className = 'who';
    const name = document.createElement('div');
    name.className = 'name';
    name.textContent = t.label || t.domain;
    const host = document.createElement('div');
    host.className = 'host';
    host.textContent = t.domain;
    who.append(name, host);

    const tag = document.createElement('span');
    tag.className = `tag ${strict ? 'seal' : 'quiet'}`;
    tag.textContent = strict ? 'Judge' : 'Exam';

    row.append(no, who, tag);
    nodes.push(row);

    if (index < websites.length - 1) {
      const rule = document.createElement('div');
      rule.className = 'rule-faint';
      nodes.push(rule);
    }
  });

  container.replaceChildren(...nodes);
}

chrome.storage.local.get('lastSync').then(({ lastSync }) => {
  if (!lastSync) return;
  const mins = Math.floor((Date.now() - lastSync) / 60000);
  document.getElementById('sync-label').textContent =
    mins < 1 ? 'synced just now' : `synced ${mins}m ago`;
});

init();
