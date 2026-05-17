const params = new URLSearchParams(location.search);
const domain = params.get('domain') || '';
const label = params.get('label') || domain;
const category = params.get('category') || 'regular';
const originalUrl = params.get('original') || '';

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

// --- Judge Flow ---

function initJudge() {
  hide('loading');
  show('judge-section');
  el('judge-domain').textContent = label;

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
    submit.disabled = true;
    submit.textContent = 'Judging...';

    const result = await sendMsg({
      type: 'judge',
      appName: label,
      argument: textarea.value.trim()
    });

    if (result.allowed) {
      showResult(true, result.reason);
      hide('judge-section');
    } else {
      showResult(false, result.reason);
      hide('judge-section');
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
      showResult(true, 'Correct! Redirecting to your page...');
      hide('problem-section');
      setTimeout(() => { location.href = originalUrl; }, 1500);
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
      // Go back or close tab
      history.back();
    }
  });
}
