const params = new URLSearchParams(location.search);
const domain = params.get('domain') || '';
const label = params.get('label') || domain;
const category = params.get('category') || 'regular';
const originalUrl = params.get('original') || '';

const JUDGE_TIME = 120; // 2-minute limit to argue with judge
let judgeTimer = null;

// --- Init ---

(async () => {
  const reachable = await sendMsg({ type: 'ping' });
  if (!reachable) {
    show('offline');
    hide('loading');
    return;
  }

  if (category === 'strict') {
    initJudge();
  } else {
    initProblem();
  }
})();

// --- Helpers ---

function sendMsg(msg) {
  return chrome.runtime.sendMessage(msg);
}

function show(id) { document.getElementById(id).classList.remove('hidden'); }
function hide(id) { document.getElementById(id).classList.add('hidden'); }
function el(id) { return document.getElementById(id); }

// --- Timer ---

function startTimer() {
  let remaining = JUDGE_TIME;
  const display = el('judge-timer');
  display.textContent = formatTime(remaining);
  display.classList.remove('hidden');

  judgeTimer = setInterval(() => {
    remaining--;
    display.textContent = formatTime(remaining);
    if (remaining <= 30) display.style.color = '#f87171';
    if (remaining <= 0) {
      clearInterval(judgeTimer);
      judgeTimer = null;
      autoDeny();
    }
  }, 1000);
}

function stopTimer() {
  if (judgeTimer) {
    clearInterval(judgeTimer);
    judgeTimer = null;
  }
  el('judge-timer').classList.add('hidden');
}

function formatTime(s) {
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${m}:${String(sec).padStart(2, '0')}`;
}

function autoDeny() {
  hide('judge-section');
  showResult(false, 'Time expired — access denied automatically.');
}

// --- Judge Flow ---

function initJudge() {
  hide('loading');
  show('judge-section');
  el('judge-domain').textContent = label;
  startTimer();

  const textarea = el('argument');
  const submit = el('judge-submit');

  textarea.addEventListener('input', () => {
    submit.disabled = textarea.value.trim().length === 0;
  });
  textarea.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (!submit.disabled) submit.click();
    }
  });

  submit.addEventListener('click', async () => {
    stopTimer();
    submit.disabled = true;
    submit.textContent = 'Judging...';

    const result = await sendMsg({
      type: 'judge',
      appName: label,
      argument: textarea.value.trim()
    });

    if (result.allowed) {
      hide('judge-section');
      showResult(true, result.reason);
      setTimeout(() => { location.href = originalUrl; }, 2000);
    } else {
      hide('judge-section');
      showResult(false, result.reason);
    }
  });
}

// --- Problem Flow ---

async function initProblem() {
  el('problem-domain').textContent = label;

  const problem = await sendMsg({ type: 'getProblem' });
  hide('loading');

  if (problem.error) {
    showResult(false, problem.error);
    return;
  }

  show('problem-section');
  el('problem-text').textContent = problem.problem;
  el('topic-label').textContent = `Topic: ${problem.topic}`;

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

  submit.addEventListener('click', async () => {
    submit.disabled = true;
    submit.textContent = 'Verifying...';

    const result = await sendMsg({
      type: 'verify',
      problem,
      answer: input.value.trim()
    });

    sendMsg({
      type: 'reportHistory',
      topic: problem.topic,
      correct: result.correct
    });

    if (result.correct) {
      showResult(true, 'Correct! Redirecting...');
      hide('problem-section');
      setTimeout(() => { location.href = originalUrl; }, 2000);
    } else {
      showResult(false, result.explanation || 'Incorrect answer.');
      hide('problem-section');
    }
  });

  input.focus();
}

// --- Result ---

function showResult(success, message) {
  show('result-section');
  stopTimer();
  const icon = el('result-icon');
  const title = el('result-title');
  const box = el('result-box');

  if (success) {
    icon.textContent = '✅';
    title.textContent = 'Access Granted';
    box.className = 'result success';
  } else {
    icon.textContent = '🚫';
    title.textContent = 'Access Denied';
    box.className = 'result fail';
  }
  box.textContent = message;
  box.classList.remove('hidden');

  el('result-close').addEventListener('click', () => {
    if (success && originalUrl) {
      location.href = originalUrl;
    } else {
      history.back();
    }
  });
}
