const SYNC_HOST = 'http://127.0.0.1:14923';

async function init() {
  const [reachable, blocklist] = await Promise.all([
    checkReachable(),
    fetchBlocklist()
  ]);

  updateStatus(reachable);
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
    if (!res.ok) return [];
    return res.json();
  } catch {
    const cached = await chrome.storage.local.get('blocklist');
    return cached.blocklist || [];
  }
}

function updateStatus(reachable) {
  const el = document.getElementById('status');
  const dot = document.getElementById('status-dot');
  const text = document.getElementById('status-text');

  if (reachable) {
    el.className = 'status connected';
    dot.className = 'dot green';
    text.textContent = 'Connected to macOS app';
  } else {
    el.className = 'status disconnected';
    dot.className = 'dot red';
    text.textContent = 'macOS app not running';
  }
}

function renderBlocklist(blocklist) {
  const container = document.getElementById('blocklist');
  const websites = (blocklist || []).filter(t => {
    return t.kind && t.kind.website;
  });

  if (websites.length === 0) {
    container.innerHTML = '<p class="empty">No blocked websites</p>';
    return;
  }

  container.innerHTML = websites.map(t => {
    const domain = t.kind.website.domain;
    const label = t.displayName || domain;
    const cat = (t.category === 'strict') ? 'strict' : 'regular';
    return `
      <div class="item">
        <span>${escapeHtml(label)}</span>
        <span class="tag ${cat}">${cat}</span>
      </div>`;
  }).join('');
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

init();
