// Website shell: loads the shared course.json, renders lessons, runs quizzes, and keeps
// progress + settings in this browser's storage. Mirrors the Mac app's behaviour.
import { DEMOS, testCard, imageFromCanvas, colourCard, rgbFromCanvas } from './demos.js';

const FS = 44100;
const ISSUES_URL = 'https://github.com/amalmehta/SignalProcessingPrimer/issues/new';
const $ = (sel, root = document) => root.querySelector(sel);

// ---------- storage (per-browser; never required for the page to work) ----------
const store = {
  get(key, fallback) { try { const v = localStorage.getItem(`spp.${key}`); return v == null ? fallback : JSON.parse(v); } catch { return fallback; } },
  set(key, value) { try { localStorage.setItem(`spp.${key}`, JSON.stringify(value)); } catch { /* storage unavailable */ } },
};
const DEFAULT_PREFS = { textSize: 'Medium', volume: 0.5, toneSeconds: 1.5, passMark: 2, showExplanations: true };
const prefs = { ...DEFAULT_PREFS, ...store.get('prefs', {}) };
let progress = { completed: [], bestScores: {}, lastLessonID: null, ...store.get('progress', {}) };
const saveProgress = () => store.set('progress', progress);
const savePrefs = () => { store.set('prefs', prefs); applyPrefs(); };
const TEXT_SIZES = { Small: 15, Medium: 17, Large: 19, 'Extra Large': 22 };
function applyPrefs() { document.documentElement.style.setProperty('--read-size', `${TEXT_SIZES[prefs.textSize] || 17}px`); }

// ---------- audio ----------
let audio, current;
function play(samples) {
  stop();
  audio ??= new (window.AudioContext || window.webkitAudioContext)();
  if (audio.state === 'suspended') audio.resume();
  const buf = audio.createBuffer(1, samples.length, FS), ch = buf.getChannelData(0), fade = Math.min(441, samples.length >> 1);
  for (let i = 0; i < samples.length; i++) ch[i] = Math.max(-1, Math.min(1, samples[i])) * Math.min(1, Math.min(i, samples.length - 1 - i) / Math.max(fade, 1));
  const src = audio.createBufferSource(), gain = audio.createGain();
  gain.gain.value = prefs.volume;
  src.buffer = buf; src.connect(gain).connect(audio.destination); src.start();
  current = src;
}
function stop() { try { current?.stop(); } catch { /* already stopped */ } current = null; }

// ---------- demo image (test card or the viewer's own photo, this session only) ----------
let customImage = null, customColour = null, cardCache = null, colourCardCache = null;
const imageListeners = new Set();
const demoCtx = {
  fs: FS, play, stop,
  toneCount: () => Math.round(FS * prefs.toneSeconds),
  getImage: async () => customImage || (cardCache ??= testCard()),
  getColourImage: async () => customColour || (colourCardCache ??= colourCard()),
  onImage(fn) { imageListeners.add(fn); return () => imageListeners.delete(fn); },
};

// ---------- markdown-lite (bold, italic, code) ----------
const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const md = s => esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/(^|[^*])\*(?!\s)(.+?)\*/g, '$1<em>$2</em>').replace(/`(.+?)`/g, '<code>$1</code>');

// ---------- course ----------
let course, lessons = [], cleanup = null;
const moduleOf = l => course.modules.find(m => m.lessons.includes(l));
const number = l => lessons.indexOf(l) + 1;
const MODULE_GLYPH = { foundations: '∿', frequency: '▥', filtering: '⫶', picture: '▣' };

function renderSidebar(activeId) {
  const nav = $('#lesson-nav');
  nav.replaceChildren(...course.modules.map(m => {
    const sec = document.createElement('section');
    sec.innerHTML = `<h2><span aria-hidden="true">${MODULE_GLYPH[m.id] || '•'}</span>${esc(m.title)}</h2>`;
    const ol = document.createElement('ol');
    for (const l of m.lessons) {
      const done = progress.completed.includes(l.id);
      const li = document.createElement('li');
      li.innerHTML = `<a href="#${l.id}" ${l.id === activeId ? 'aria-current="page"' : ''}><span class="num">${String(number(l)).padStart(2, '0')}</span><span class="t">${esc(l.title)}</span>${done ? '<span class="done" title="Completed" aria-label="Completed">✓</span>' : ''}</a>`;
      ol.appendChild(li);
    }
    sec.appendChild(ol);
    return sec;
  }));
  const n = progress.completed.length;
  $('#progress-text').textContent = `${n} of ${lessons.length} lessons complete`;
  $('#progress-bar').value = n; $('#progress-bar').max = lessons.length;
}

function renderWelcome() {
  const resume = lessons.find(l => l.id === progress.lastLessonID);
  $('#main').innerHTML = `
    <article class="welcome">
      <p class="eyebrow">A hands-on course · ${lessons.length} lessons · ${course.modules.length} modules</p>
      <h1>Signal Processing Primer</h1>
      <p class="lede">The maths behind audio, images, video and film. Every lesson has something to play with and listen to, and a short quiz.</p>
      <div class="modules">${course.modules.map(m => `
        <section><h2><span aria-hidden="true">${MODULE_GLYPH[m.id]}</span>${esc(m.title)}</h2>
        <ol>${m.lessons.map(l => `<li><a href="#${l.id}"><span class="num">${String(number(l)).padStart(2, '0')}</span><span><b>${esc(l.title)}</b><small>${esc(l.summary)}</small></span></a></li>`).join('')}</ol></section>`).join('')}
      </div>
      <a class="btn primary" href="#${(resume || lessons[0]).id}">${resume ? `Continue: ${esc(resume.title)}` : 'Start Lesson 1'}</a>
    </article>`;
  document.title = 'Signal Processing Primer';
}

function renderLesson(l) {
  progress.lastLessonID = l.id; saveProgress();
  const mod = moduleOf(l), next = lessons[number(l)];
  const main = $('#main');
  main.innerHTML = `<article class="lesson">
    <header><p class="eyebrow">${esc(mod.title)} · Lesson ${number(l)} of ${lessons.length}</p><h1>${esc(l.title)}</h1><p class="lede">${esc(l.summary)}</p></header>
    <div class="blocks"></div>
    <section class="quiz" aria-labelledby="quiz-h"></section>
    ${next ? `<nav class="next"><a class="btn" href="#${next.id}">Next: ${esc(next.title)} →</a></nav>` : ''}
  </article>`;
  const blocks = $('.blocks', main);
  for (const b of l.blocks) {
    let node;
    switch (b.type) {
      case 'text': node = Object.assign(document.createElement('p'), { innerHTML: md(b.text) }); break;
      case 'heading': node = Object.assign(document.createElement('h2'), { textContent: b.text }); break;
      case 'equation':
        node = document.createElement('figure'); node.className = 'eq';
        node.innerHTML = `<code>${esc(b.text)}</code>${b.caption ? `<figcaption>${esc(b.caption)}</figcaption>` : ''}`; break;
      case 'bullets':
        node = document.createElement('ul'); node.innerHTML = b.items.map(i => `<li>${md(i)}</li>`).join(''); break;
      case 'inPractice':
        node = document.createElement('aside'); node.className = 'practice';
        node.innerHTML = `<h3><span class="tag">In practice</span>${esc(b.title)}</h3><p>${md(b.body)}</p>`; break;
      case 'demo': {
        node = document.createElement('section'); node.className = 'demo'; node.id = 'demo';
        node.innerHTML = `<h3><span class="tag">Try it</span>${esc(l.demoCaption)}</h3>`;
        const host = document.createElement('div'); host.className = 'demo-body'; node.appendChild(host);
        cleanup = DEMOS[l.demo]?.(host, demoCtx) || null;
        break;
      }
      default: continue;
    }
    blocks.appendChild(node);
  }
  renderQuiz(l, $('.quiz', main));
  document.title = `${l.title} · Signal Processing Primer`;
}

function renderQuiz(l, root) {
  const picks = Array(l.quiz.length).fill(null);
  let submitted = false;
  const required = Math.min(prefs.passMark, l.quiz.length);
  const draw = () => {
    const score = picks.filter((p, i) => p === l.quiz[i].answer).length;
    const done = progress.completed.includes(l.id);
    root.innerHTML = `<header><h2 id="quiz-h">Check your understanding</h2>${done ? '<span class="pill good">✓ Completed</span>' : ''}</header>
      ${l.quiz.map((q, i) => `<fieldset ${submitted ? 'disabled' : ''}><legend>${i + 1}. ${esc(q.prompt)}</legend>
        ${q.choices.map((c, k) => {
          const state = !submitted ? '' : k === q.answer ? 'right' : picks[i] === k ? 'wrong' : '';
          return `<label class="choice ${state}"><input type="radio" name="q-${l.id}-${i}" value="${k}" ${picks[i] === k ? 'checked' : ''}><span>${esc(c)}</span>${state === 'right' ? '<b aria-label="Correct answer">✓</b>' : state === 'wrong' ? '<b aria-label="Your answer, incorrect">✗</b>' : ''}</label>`;
        }).join('')}
        ${submitted && prefs.showExplanations ? `<p class="explain">${esc(q.explanation)}</p>` : ''}</fieldset>`).join('')}
      <div class="quiz-actions">${submitted
        ? `<p class="result">${score}/${l.quiz.length} — ${score >= required ? 'lesson complete!' : `you need ${required} to complete this lesson.`}</p><button class="btn" type="button" data-act="retry">Try again</button>`
        : `<button class="btn primary" type="button" data-act="check" ${picks.includes(null) ? 'disabled' : ''}>Check answers</button>`}</div>`;
  };
  root.addEventListener('change', e => {
    const m = e.target.name?.match(/-(\d+)$/); if (!m) return;
    picks[+m[1]] = +e.target.value; draw();
  });
  root.addEventListener('click', e => {
    const act = e.target.closest('[data-act]')?.dataset.act;
    if (act === 'check') {
      submitted = true;
      const score = picks.filter((p, i) => p === l.quiz[i].answer).length;
      progress.bestScores[l.id] = Math.max(score, progress.bestScores[l.id] || 0);
      if (score >= required && !progress.completed.includes(l.id)) progress.completed.push(l.id);
      saveProgress(); renderSidebar(l.id); draw();
    } else if (act === 'retry') { picks.fill(null); submitted = false; draw(); }
  });
  draw();
}

function route() {
  stop(); cleanup?.(); cleanup = null;
  const id = location.hash.slice(1), l = lessons.find(x => x.id === id);
  l ? renderLesson(l) : renderWelcome();
  renderSidebar(l?.id);
  document.body.classList.remove('nav-open');
  $('#main').focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

// ---------- settings ----------
function openDialog(name) {
  const dlg = $(`#${name}`);
  if (name === 'settings') fillSettings();
  if (name === 'feedback') fillFeedback();
  if (!dlg.open) dlg.showModal();
}

function fillSettings() {
  $('#set-text').value = prefs.textSize;
  $('#set-explain').checked = prefs.showExplanations;
  $('#set-pass').value = String(prefs.passMark);
  $('#set-volume').value = prefs.volume;
  $('#set-tone').value = prefs.toneSeconds; $('#set-tone-out').textContent = `${prefs.toneSeconds.toFixed(1)} s`;
  $('#set-progress').textContent = `${progress.completed.length} of ${lessons.length}`;
  $('#set-image-name').textContent = customImage ? customImage.name : 'Built-in test card';
  $('#reset-confirm').hidden = true;
}

function wireSettings() {
  $('#set-text').addEventListener('change', e => { prefs.textSize = e.target.value; savePrefs(); });
  $('#set-explain').addEventListener('change', e => { prefs.showExplanations = e.target.checked; savePrefs(); });
  $('#set-pass').addEventListener('change', e => { prefs.passMark = +e.target.value; savePrefs(); });
  $('#set-volume').addEventListener('input', e => { prefs.volume = +e.target.value; savePrefs(); });
  $('#set-tone').addEventListener('input', e => { prefs.toneSeconds = +e.target.value; $('#set-tone-out').textContent = `${prefs.toneSeconds.toFixed(1)} s`; savePrefs(); });
  $('#set-test').addEventListener('click', () => play(Float32Array.from({ length: demoCtx.toneCount() }, (_, n) => 0.5 * Math.sin(2 * Math.PI * 440 * n / FS))));
  $('#set-image').addEventListener('change', e => {
    const file = e.target.files[0]; if (!file) return;
    const im = new Image();
    im.onload = () => {
      const c = document.createElement('canvas'); c.width = im.naturalWidth; c.height = im.naturalHeight;
      c.getContext('2d').drawImage(im, 0, 0);
      customImage = Object.assign(imageFromCanvas(c), { name: file.name });
      customColour = rgbFromCanvas(c);
      URL.revokeObjectURL(im.src); fillSettings(); imageListeners.forEach(fn => fn());
    };
    im.src = URL.createObjectURL(file);
  });
  $('#set-image-reset').addEventListener('click', () => { customImage = null; customColour = null; $('#set-image').value = ''; fillSettings(); imageListeners.forEach(fn => fn()); });
  $('#reset-ask').addEventListener('click', () => { $('#reset-confirm').hidden = false; });
  $('#reset-no').addEventListener('click', () => { $('#reset-confirm').hidden = true; });
  $('#reset-yes').addEventListener('click', () => {
    progress = { completed: [], bestScores: {}, lastLessonID: null }; saveProgress(); fillSettings(); route();
  });
}

// ---------- feedback ----------
function fillFeedback() {
  const l = lessons.find(x => x.id === location.hash.slice(1));
  $('#fb-about').textContent = l ? `About: ${l.title}` : 'About the course in general';
  updateIssueLink();
}
function feedbackText() {
  const kind = $('input[name="fb-kind"]:checked').value, l = lessons.find(x => x.id === location.hash.slice(1));
  return { title: `[${kind}] ${l ? l.title : 'General'} (website)`, body: $('#fb-text').value.trim() };
}
function updateIssueLink() {
  const { title, body } = feedbackText(), a = $('#fb-issue');
  a.href = `${ISSUES_URL}?${new URLSearchParams({ title, body })}`;
  a.toggleAttribute('aria-disabled', !body);
}
function wireFeedback() {
  $('#fb-text').addEventListener('input', updateIssueLink);
  document.querySelectorAll('input[name="fb-kind"]').forEach(r => r.addEventListener('change', updateIssueLink));
  $('#fb-issue').addEventListener('click', e => { if (!feedbackText().body) e.preventDefault(); });
  $('#fb-copy').addEventListener('click', async () => {
    const { title, body } = feedbackText(), status = $('#fb-status');
    try { await navigator.clipboard.writeText(`${title}\n\n${body}`); status.textContent = 'Copied.'; }
    catch { $('#fb-text').select(); status.textContent = 'Press ⌘C to copy the selected text.'; }
  });
}

// ---------- boot ----------
async function boot() {
  applyPrefs();
  document.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => openDialog(b.dataset.open)));
  document.querySelectorAll('dialog').forEach(d => {
    d.addEventListener('click', e => { if (e.target === d || e.target.closest('[data-close]')) d.close(); });
  });
  $('#nav-toggle').addEventListener('click', () => document.body.classList.toggle('nav-open'));
  document.addEventListener('keydown', e => {
    if ((e.metaKey || e.ctrlKey) && e.key === ',') { e.preventDefault(); openDialog('settings'); }
    if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key.toLowerCase() === 'f') { e.preventDefault(); openDialog('feedback'); }
  });
  wireSettings(); wireFeedback();
  try {
    course = await (await fetch('course.json')).json();
  } catch {
    $('#main').innerHTML = '<p class="error">The course content (course.json) could not be loaded. Serve this folder over HTTP — see docs/INSTRUCTIONS.md.</p>';
    return;
  }
  lessons = course.modules.flatMap(m => m.lessons);
  addEventListener('hashchange', route);
  route();
}
boot();
