const params = new URLSearchParams(location.search);
const domain = params.get('domain') || '';
const label = params.get('label') || domain;
const category = params.get('category') || 'regular';
const originalUrl = params.get('original') || '';

const JUDGE_TIME = 120; // 2-minute limit to argue with judge
let judgeTimer = null;

// --- Init ---

(async () => {
  el('docket').textContent = [
    `case ${caseNumber(domain)}`,
    label,
    category === 'strict' ? 'strict' : 'regular',
  ].join('  ·  ');

  const reachable = await sendMsg({ type: 'ping' });
  if (reachable !== true) {
    hide('loading');
    show('offline');
    return;
  }

  if (category === 'strict') {
    initJudge();
  } else {
    el('loading-text').textContent = 'Setting your question';
    initProblem();
  }
})();

// --- Helpers ---

// chrome.runtime.sendMessage rejects if the service worker is gone. Callers
// should never hang on that, so surface it as a normal error value instead.
async function sendMsg(msg) {
  try {
    return await chrome.runtime.sendMessage(msg);
  } catch (err) {
    return { error: String(err?.message || err) };
  }
}

function show(id) { document.getElementById(id).classList.remove('hidden'); }
function hide(id) { document.getElementById(id).classList.add('hidden'); }
function el(id) { return document.getElementById(id); }

/// Clerical fiction, but stable for a given site on a given day.
function caseNumber(seed) {
  let hash = 0;
  for (const ch of seed) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  const now = new Date();
  const mmdd = String(now.getMonth() + 1).padStart(2, '0') + String(now.getDate()).padStart(2, '0');
  return `№${mmdd}-${String(hash % 10000).padStart(4, '0')}`;
}

// Only leave this page for the original URL after the background worker has
// recorded a grant; otherwise the navigation bounces straight back here.
async function proceedToOriginal() {
  if (!originalUrl) return;
  await sendMsg({ type: 'grantAccess', domain });
  location.replace(originalUrl);
}

function leaveBlockedPage() {
  // history.back() would return to the blocked URL and re-trigger the gate.
  location.replace('about:blank');
}

// --- Clock ---

function startClock() {
  let remaining = JUDGE_TIME;
  const wrap = el('clock');
  const figure = el('clock-figure');
  const bar = el('clock-bar');
  wrap.classList.remove('hidden');

  const render = () => {
    const left = Math.max(remaining, 0);
    const m = Math.floor(left / 60);
    const s = left % 60;
    figure.textContent = `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    bar.style.transform = `scaleX(${left / JUDGE_TIME})`;
    wrap.classList.toggle('low', left <= 60 && left > 30);
    wrap.classList.toggle('critical', left <= 30);
  };

  render();
  judgeTimer = setInterval(() => {
    remaining--;
    render();
    if (remaining <= 0) {
      clearInterval(judgeTimer);
      judgeTimer = null;
      hide('judge-section');
      showVerdict(false, 'Time expired. Denied automatically.');
    }
  }, 1000);
}

function stopClock() {
  if (judgeTimer) {
    clearInterval(judgeTimer);
    judgeTimer = null;
  }
  el('clock').classList.add('hidden');
}

// --- Judge ---

function initJudge() {
  hide('loading');
  show('judge-section');
  el('judge-domain').textContent = label;
  startClock();

  const textarea = el('argument');
  const submit = el('judge-submit');
  textarea.focus();

  textarea.addEventListener('input', () => {
    submit.disabled = textarea.value.trim().length === 0;
  });
  textarea.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      if (!submit.disabled) submit.click();
    }
  });

  el('judge-give-up').addEventListener('click', leaveBlockedPage);

  submit.addEventListener('click', async () => {
    stopClock();
    submit.disabled = true;
    submit.textContent = 'Deliberating';

    const result = await sendMsg({
      type: 'judge',
      appName: label,
      argument: textarea.value.trim(),
    });

    hide('judge-section');

    if (result?.error) {
      showVerdict(false, result.error);
      return;
    }
    if (result?.allowed) {
      showVerdict(true, result.reason);
      setTimeout(proceedToOriginal, 2200);
    } else {
      showVerdict(false, result?.reason || 'Denied.');
    }
  });
}

// --- Examination ---

async function initProblem() {
  el('problem-domain').textContent = label;

  const problem = await sendMsg({ type: 'getProblem' });
  hide('loading');

  if (!problem || problem.error) {
    showVerdict(false, problem?.error || 'No question could be set.');
    return;
  }

  show('problem-section');
  el('problem-text').textContent = problem.problem;
  el('topic-label').textContent = problem.topic;
  if (typeof renderMathInElement !== 'undefined') {
    renderMathInElement(el('problem-text'), {
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '$', right: '$', display: false },
      ],
      throwOnError: false,
    });
  }

  const input = el('answer');
  const submit = el('problem-submit');

  input.addEventListener('input', () => {
    submit.disabled = input.value.trim().length === 0;
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (!submit.disabled) submit.click();
    }
  });

  el('problem-give-up').addEventListener('click', leaveBlockedPage);

  submit.addEventListener('click', async () => {
    submit.disabled = true;
    submit.textContent = 'Marking';

    const result = await sendMsg({
      type: 'verify',
      problem,
      answer: input.value.trim(),
    });

    if (!result || result.error) {
      // Recoverable: let them try again rather than stranding them.
      submit.textContent = 'Submit';
      submit.disabled = false;
      const err = el('problem-error');
      err.textContent = result?.error || 'Your answer could not be marked.';
      err.style.color = 'var(--seal)';
      err.classList.remove('hidden');
      return;
    }

    hide('problem-section');

    sendMsg({
      type: 'reportHistory',
      topic: problem.topic,
      correct: result.correct,
    });

    if (result.correct) {
      showVerdict(true, 'Correct. You may proceed.');
      setTimeout(proceedToOriginal, 1800);
    } else {
      showVerdict(false, result.explanation || 'Incorrect.');
    }
  });

  input.focus();
}

// --- Verdict ---

function showVerdict(granted, message) {
  stopClock();
  show('result-section');

  const stamp = el('result-stamp');
  stamp.className = `stamp ${granted ? 'granted' : 'denied'}`;
  stamp.textContent = granted ? 'Granted' : 'Denied';
  el('result-message').textContent = message;

  // Replace the node to drop any listener from a previous call.
  const close = el('result-close');
  const fresh = close.cloneNode(true);
  fresh.textContent = granted ? 'Proceed' : 'Close';
  close.replaceWith(fresh);
  fresh.addEventListener('click', () => {
    if (granted) {
      proceedToOriginal();
    } else {
      leaveBlockedPage();
    }
  });
  fresh.focus();
}
