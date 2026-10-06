// The interactive demos (one per lesson). Each is `build(host, ctx)` → optional cleanup function.
// ctx: { fs, play(samples), stop(), toneCount(), getImage(), getColourImage(): Promise<img>, onImage(fn) }
import * as D from './dsp.js';
import { LinePlot, wave, fmt } from './plot.js';

const S1 = 'var(--s1)', S2 = 'var(--s2)', REF = 'var(--muted)';
const hz = f => (f >= 1000 ? `${(f / 1000).toFixed(2)} kHz` : `${Math.round(f)} Hz`);

// ---------- tiny UI kit ----------
let uid = 0;
function h(tag, attrs = {}, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') n.className = v; else if (k.startsWith('on')) n.addEventListener(k.slice(2), v); else n.setAttribute(k, v);
  }
  n.append(...kids.flat().filter(k => k != null));
  return n;
}
function slider(label, { min, max, step = 'any', value, format = v => fmt(v) }, onChange) {
  const id = `c${++uid}`, out = h('output', { for: id });
  const input = h('input', { type: 'range', id, min, max, step, value });
  const sync = () => { out.textContent = format(+input.value); };
  input.addEventListener('input', () => { sync(); onChange(+input.value); });
  sync();
  const wrap = h('div', { class: 'ctl' }, h('label', { for: id }, h('span', {}, label), out), input);
  wrap.set = v => { input.value = v; sync(); };
  wrap.get = () => +input.value;
  return wrap;
}
function select(label, options, value, onChange) {
  const id = `c${++uid}`;
  const s = h('select', { id }, options.map(o => { const [v, t] = Array.isArray(o) ? o : [o, o]; const opt = h('option', { value: v }, t); if (String(v) === String(value)) opt.selected = true; return opt; }));
  s.addEventListener('change', () => onChange(s.value));
  const wrap = h('div', { class: 'ctl' }, h('label', { for: id }, h('span', {}, label)), s);
  wrap.set = v => { s.value = v; };
  return wrap;
}
function toggle(label, value, onChange) {
  const id = `c${++uid}`, input = h('input', { type: 'checkbox', id, role: 'switch' });
  input.checked = value;
  input.addEventListener('change', () => onChange(input.checked));
  return h('div', { class: 'ctl ctl-toggle' }, input, h('label', { for: id }, label));
}
function readouts() {
  const row = h('div', { class: 'readouts' });
  row.set = items => row.replaceChildren(...items.map(([label, value, tone]) =>
    h('div', { class: `readout${tone ? ' ' + tone : ''}` }, h('b', {}, value), h('span', {}, label))));
  return row;
}
const row = (...kids) => h('div', { class: 'row' }, kids);
const playBtn = (label, ctx, make) => h('button', { class: 'btn', type: 'button', onclick: () => ctx.play(make()) }, h('span', { 'aria-hidden': 'true' }, '▶'), ` ${label}`);
const stopBtn = ctx => h('button', { class: 'btn ghost', type: 'button', onclick: () => ctx.stop() }, '■ Stop');
const plotBox = (host, opts) => new LinePlot(host, opts);

function imageCanvas(label) {
  const canvas = h('canvas', { class: 'img' });
  const fig = h('figure', { class: 'imgfig' }, canvas, h('figcaption', {}, label));
  fig.draw = (img, caption) => {
    canvas.width = img.width; canvas.height = img.height;
    const c = canvas.getContext('2d'), data = c.createImageData(img.width, img.height);
    img.pixels.forEach((v, i) => { const b = Math.round(Math.min(Math.max(v, 0), 1) * 255); data.data.set([b, b, b, 255], i * 4); });
    c.putImageData(data, 0, 0);
    if (caption) fig.querySelector('figcaption').textContent = caption;
  };
  return fig;
}

/** Procedural test card: gradients, stripes, checkerboard, circles, text. */
export function testCard(size = 320) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  const g = c.getContext('2d'), s = size;
  const grad = g.createLinearGradient(0, 0, 0, s); grad.addColorStop(0, '#595959'); grad.addColorStop(1, '#d9d9d9');
  g.fillStyle = grad; g.fillRect(0, 0, s, s);
  const cell = s / 16; g.fillStyle = '#0d0d0d';
  for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) if ((i + j) % 2 === 0) g.fillRect(s * 0.06 + i * cell, s * 0.69 + j * cell, cell, cell);
  for (let i = 0; i < 20; i++) { g.fillStyle = i % 2 ? '#000' : '#fff'; g.fillRect(s * 0.55 + i * s * 0.02, s * 0.69, s * 0.02, s * 0.25); }
  g.fillStyle = '#f2f2f2'; g.beginPath(); g.arc(s * 0.275, s * 0.375, s * 0.175, 0, D.TAU); g.fill();
  g.strokeStyle = '#1a1a1a'; g.lineWidth = s * 0.015; g.beginPath(); g.arc(s * 0.715, s * 0.385, s * 0.165, 0, D.TAU); g.stroke();
  g.fillStyle = '#fff'; g.font = `bold ${s * 0.09}px system-ui, sans-serif`; g.fillText('SIGNAL', s * 0.2, s * 0.13);
  return imageFromCanvas(c);
}

export function imageFromCanvas(c, maxSide = 360) {
  const k = Math.min(1, maxSide / Math.max(c.width, c.height));
  const w = Math.max(8, Math.round(c.width * k)), hgt = Math.max(8, Math.round(c.height * k));
  const t = document.createElement('canvas'); t.width = w; t.height = hgt;
  const g = t.getContext('2d'); g.drawImage(c, 0, 0, w, hgt);
  const d = g.getImageData(0, 0, w, hgt).data, px = new Float32Array(w * hgt);
  for (let i = 0; i < px.length; i++) px[i] = (0.2126 * d[i * 4] + 0.7152 * d[i * 4 + 1] + 0.0722 * d[i * 4 + 2]) / 255;
  return D.makeImage(w, hgt, px);
}

/** Colour version: {width, height, r, g, b} with R′G′B′ in 0…1. */
export function rgbFromCanvas(c, maxSide = 360) {
  const k = Math.min(1, maxSide / Math.max(c.width, c.height));
  const w = Math.max(8, Math.round(c.width * k)), hgt = Math.max(8, Math.round(c.height * k));
  const t = document.createElement('canvas'); t.width = w; t.height = hgt;
  const g = t.getContext('2d'); g.drawImage(c, 0, 0, w, hgt);
  const d = g.getImageData(0, 0, w, hgt).data, n = w * hgt;
  const img = { width: w, height: hgt, r: new Float32Array(n), g: new Float32Array(n), b: new Float32Array(n) };
  for (let i = 0; i < n; i++) { img.r[i] = d[i * 4] / 255; img.g[i] = d[i * 4 + 1] / 255; img.b[i] = d[i * 4 + 2] / 255; }
  return img;
}

/** Colour test card: colour bars, a hue sweep, red text on blue, 1-px red/green stripes, a skin-tone patch. */
export function colourCard(size = 320) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  const g = c.getContext('2d'), s = size;
  const bars = ['#bfbfbf', '#bfbf00', '#00bfbf', '#00bf00', '#bf00bf', '#bf0000', '#0000bf'];
  bars.forEach((col, i) => { g.fillStyle = col; g.fillRect(i * s / 7, 0, s / 7 + 1, s * 0.32); });
  for (let x = 0; x < s; x++) { g.fillStyle = `hsl(${x / s * 360} 80% 52%)`; g.fillRect(x, s * 0.32, 1, s * 0.18); }
  g.fillStyle = '#0d1aa6'; g.fillRect(0, s * 0.5, s * 0.55, s * 0.5);
  g.fillStyle = '#f21a1a'; g.font = `bold ${s * 0.06}px system-ui, sans-serif`;   // inside the centre crop
  g.fillText('CHROMA', s * 0.27, s * 0.6); g.fillText('4:2:0', s * 0.27, s * 0.7);
  for (let x = Math.floor(s * 0.55); x < s; x++) { g.fillStyle = x % 2 ? '#268c33' : '#cc3333'; g.fillRect(x, s * 0.5, 1, s * 0.25); }
  g.fillStyle = '#db9e80'; g.fillRect(s * 0.55, s * 0.75, s * 0.45, s * 0.25);
  return rgbFromCanvas(c);
}

function rgbCanvas(label) {
  const canvas = h('canvas', { class: 'img' });
  const fig = h('figure', { class: 'imgfig' }, canvas, h('figcaption', {}, label));
  fig.draw = (img, caption) => {
    canvas.width = img.width; canvas.height = img.height;
    const c = canvas.getContext('2d'), data = c.createImageData(img.width, img.height);
    for (let i = 0; i < img.r.length; i++) data.data.set([img.r[i] * 255, img.g[i] * 255, img.b[i] * 255, 255], i * 4);
    c.putImageData(data, 0, 0);
    if (caption) fig.querySelector('figcaption').textContent = caption;
  };
  return fig;
}

// ---------- Lesson 1: sine mixer ----------
function sineMixer(host, ctx) {
  let f0 = 220, amps = [1, 0, 0, 0, 0, 0, 0, 0], signs = Array(8).fill(1);
  const partials = () => amps.map((a, i) => ({ frequency: f0 * (i + 1), amplitude: a * signs[i] }));
  const plot = () => p.update([wave('Mix', D.mix(partials(), ctx.fs, Math.floor(ctx.fs * 2 / f0)), ctx.fs, S1)]);
  const recipes = {
    'Pure sine': n => [n === 1 ? 1 : 0, 1], 'Square-ish': n => [n % 2 ? 1 / n : 0, 1],
    'Sawtooth-ish': n => [1 / n, n % 2 ? 1 : -1], 'Triangle-ish': n => [n % 2 ? 1 / (n * n) : 0, n % 4 === 1 ? 1 : -1],
  };
  const bars = amps.map((a, i) => slider(`${i + 1}×`, { min: 0, max: 1, step: 0.01, value: a, format: v => v.toFixed(2) }, v => { amps[i] = v; recipe.set('Custom'); plot(); }));
  const recipe = select('Recipe', [...Object.keys(recipes), 'Custom'], 'Pure sine', name => {
    if (!recipes[name]) return;
    amps.forEach((_, i) => { [amps[i], signs[i]] = recipes[name](i + 1); bars[i].set(amps[i]); });
    plot();
  });
  host.append(
    row(slider('Fundamental', { min: 55, max: 880, value: f0, format: hz }, v => { f0 = v; plot(); }), recipe),
    h('div', { class: 'harmonics', role: 'group', 'aria-label': 'Harmonic amplitudes' }, h('div', { class: 'eyebrow' }, 'Harmonic amplitudes'), h('div', { class: 'harmonic-grid' }, bars)));
  const p = plotBox(host, { xLabel: 'Time (ms)', yLabel: 'Amplitude', yDomain: [-2, 2] });
  host.append(row(playBtn('Play', ctx, () => D.normalized(D.mix(partials(), ctx.fs, ctx.toneCount()), 0.6)), stopBtn(ctx)));
  plot();
}

// ---------- Lesson 2: aliasing ----------
function aliasing(host, ctx) {
  let fs = 8000, f = 1000;
  const ro = readouts();
  const freq = slider('Input tone', { min: 50, max: 2 * fs, value: f, format: hz }, v => { f = v; draw(); });
  const draw = () => {
    const a = D.aliasedFrequency(f, fs), folds = (f % fs) > fs / 2, ok = Math.abs(a - f) < 0.5;
    ro.set([['Nyquist (fs / 2)', hz(fs / 2)], ['Frequency the samples contain', hz(a)], ['', ok ? '✓ Captured faithfully' : '⚠ Aliased', ok ? 'good' : 'warn']]);
    const N = 24, dur = N / fs, fine = 480, sign = folds ? -1 : 1;
    const curve = (fr, sg = 1) => Array.from({ length: fine }, (_, i) => { const t = dur * i / fine; return [t * 1000, sg * Math.sin(D.TAU * fr * t)]; });
    p.update([
      { name: 'True signal', points: curve(f), color: REF, dashed: true },
      { name: 'Reconstructed from samples', points: curve(a, sign), color: S2, dashed: true },
      { name: 'Samples', points: Array.from({ length: N + 1 }, (_, n) => [n / fs * 1000, Math.sin(D.TAU * f * n / fs)]), color: S1, dots: true },
    ]);
    trueBtn.disabled = f > 20000;
  };
  const trueBtn = playBtn('Play the true tone', ctx, () => D.sine(f, 0.5, ctx.fs, ctx.toneCount()));
  host.append(row(select('Sample rate', [[8000, '8 kHz (telephone)'], [16000, '16 kHz'], [44100, '44.1 kHz (CD)']], fs, v => {
    fs = +v; f = Math.min(f, 2 * fs); freq.querySelector('input').max = 2 * fs; freq.set(f); draw();
  }), freq), ro);
  const p = plotBox(host, { xLabel: 'Time (ms)', yLabel: 'Amplitude', yDomain: [-1.2, 1.2] });
  host.append(row(playBtn('Play what was recorded', ctx, () => D.sine(D.aliasedFrequency(f, fs), 0.5, ctx.fs, ctx.toneCount())), trueBtn, stopBtn(ctx)));
  draw();
}

// ---------- Lesson 3: quantization ----------
function quantization(host, ctx) {
  let bits = 4, dither = false, level = 0.5;
  const src = n => D.sine(220, level, ctx.fs, n);
  const ro = readouts();
  const draw = () => {
    const shown = src(Math.floor(ctx.fs * 2 / 220)), long = src(16384);
    ro.set([['Levels available', (2 ** bits).toLocaleString()], ['Theoretical dynamic range', `${(6.02 * bits + 1.76).toFixed(0)} dB`],
      ['Measured signal-to-noise', `${D.snr(long, D.quantize(long, bits, dither)).toFixed(1)} dB`]]);
    p.update([wave('Original', shown, ctx.fs, S2, { dashed: true }), wave('Quantized', D.quantize(shown, bits, dither), ctx.fs, S1)]);
  };
  host.append(row(
    slider('Bit depth', { min: 1, max: 16, step: 1, value: bits, format: v => `${v} bits` }, v => { bits = v; draw(); }),
    slider('Signal level', { min: 0.02, max: 0.95, step: 0.01, value: level, format: v => `${(20 * Math.log10(v)).toFixed(0)} dBFS` }, v => { level = v; draw(); }),
    toggle('Dither', dither, v => { dither = v; draw(); })), ro);
  const p = plotBox(host, { xLabel: 'Time (ms)', yLabel: 'Amplitude', yDomain: [-1, 1] });
  host.append(row(playBtn('Play original', ctx, () => src(ctx.toneCount())), playBtn('Play quantized', ctx, () => D.quantize(src(ctx.toneCount()), bits, dither)), stopBtn(ctx)));
  draw();
}

// ---------- Lesson 4: spectrum ----------
function spectrum(host, ctx) {
  const f = [440, 1320, 3000], a = [0.8, 0.4, 0]; let noiseLvl = 0, shape = 'sine';
  const N = 4096, binHz = ctx.fs / N, maxBin = Math.floor(6000 / binHz);
  const signal = n => {
    let x = new Float32Array(n);
    for (let i = 0; i < 3; i++) if (a[i] > 0) x = D.add(x, D.tone(i === 0 ? shape : 'sine', f[i], a[i], ctx.fs, n));
    return noiseLvl > 0 ? D.add(x, D.noise(n), noiseLvl) : x;
  };
  const draw = () => {
    const x = signal(N), mags = D.decibels(D.magnitudeSpectrum(x, 'Hann'), -90);
    pt.update([wave('Signal', x.subarray(0, 441), ctx.fs, S2)]);
    pf.update([{ name: 'Spectrum', color: S1, points: Array.from({ length: maxBin }, (_, i) => [(i + 1) * binHz, mags[i + 1]]) }]);
  };
  const tones = [0, 1, 2].map(i => row(h('div', { class: 'tone-label' }, `Tone ${i + 1}`),
    slider('Frequency', { min: 50, max: 5500, value: f[i], format: hz }, v => { f[i] = v; draw(); }),
    slider('Amplitude', { min: 0, max: 1, step: 0.01, value: a[i], format: v => v.toFixed(2) }, v => { a[i] = v; draw(); })));
  host.append(...tones, row(
    select('Tone 1 shape', [['sine', 'Sine'], ['square', 'Square'], ['sawtooth', 'Sawtooth'], ['triangle', 'Triangle']], shape, v => { shape = v; draw(); }),
    slider('Noise', { min: 0, max: 0.5, step: 0.01, value: 0, format: v => v.toFixed(2) }, v => { noiseLvl = v; draw(); })));
  const pair = h('div', { class: 'pair' }); host.append(pair);
  const pt = plotBox(pair, { xLabel: 'Time (ms)', yLabel: 'Amplitude' });
  const pf = plotBox(pair, { xLabel: 'Frequency (Hz)', yLabel: 'Level (dB)', yDomain: [-90, 0] });
  host.append(row(playBtn('Play', ctx, () => D.normalized(signal(ctx.toneCount()), 0.6)), stopBtn(ctx),
    h('small', { class: 'note' }, `FFT size ${N.toLocaleString()} · bins every ${binHz.toFixed(1)} Hz · Hann window`)));
  draw();
}

// ---------- Lesson 5: windowing ----------
function windowing(host, ctx) {
  let bin = 10, win = 'Rectangular', quiet = true; const N = 128;
  const ro = readouts();
  const binSlider = slider('Tone position (bins)', { min: 6, max: 14, step: 0.01, value: bin, format: v => v.toFixed(2) }, v => { bin = v; draw(); });
  const draw = () => {
    const x = D.add(D.sine(bin, 1, N, N), D.sine(30, quiet ? 0.003 : 0, N, N));
    const spec = D.decibels(D.magnitudeSpectrum(x, win), -100), w = D.windowCoefficients(win, N);
    ro.set([['Whole cycles in the frame', Math.abs(bin - Math.round(bin)) < 1e-9 ? 'Yes' : 'No'], ['Leakage far from the tone (bins 45+)', `${Math.max(...spec.slice(45)).toFixed(0)} dB`]]);
    pt.update([{ name: 'Window', color: S2, dashed: true, points: Array.from(w, (v, i) => [i, v]) },
      { name: 'Windowed signal', color: S1, points: Array.from(x, (v, i) => [i, v * w[i]]) }]);
    pf.update([{ name: 'Spectrum', color: S1, dots: true, points: spec.map((v, i) => [i, v]) }]);
  };
  host.append(row(binSlider, select('Window', D.WINDOWS, win, v => { win = v; draw(); }), toggle('Quiet tone at bin 30 (−50 dB)', quiet, v => { quiet = v; draw(); })),
    row(ro, h('button', { class: 'btn ghost', type: 'button', onclick: () => { bin = Math.round(bin); binSlider.set(bin); draw(); } }, 'Snap to a bin'),
      h('button', { class: 'btn ghost', type: 'button', onclick: () => { bin = Math.floor(bin) + 0.5; binSlider.set(bin); draw(); } }, 'Halfway between bins')));
  const pair = h('div', { class: 'pair' }); host.append(pair);
  const pt = plotBox(pair, { xLabel: 'Sample', yLabel: 'Amplitude', yDomain: [-1.05, 1.05] });
  const pf = plotBox(pair, { xLabel: 'Bin', yLabel: 'Level (dB)', yDomain: [-100, 0] });
  draw();
}

// ---------- Lesson 6: spectrogram ----------
function spectrogramDemo(host, ctx) {
  let source = 'melody', n = 1024, x; const SECONDS = 2, MAXHZ = 8000;
  const make = () => {
    const fs = ctx.fs, count = Math.floor(fs * SECONDS);
    if (source === 'sweep') return D.scale(D.chirp(100, 7500, fs, count), 0.6);
    if (source === 'clicks') {
      const y = D.mix([{ frequency: 600, amplitude: 0.25 }, { frequency: 680, amplitude: 0.25 }, { frequency: 3000, amplitude: 0.15 }], fs, count);
      for (let c = Math.floor(fs * 0.1); c < count - 1; c += Math.floor(fs * 0.3)) { y[c] += 0.9; y[c + 1] -= 0.6; }
      return y;
    }
    const notes = [262, 330, 392, 523, 392, 330, 294, 262], per = Math.floor(count / notes.length), fade = fs * 0.005, out = new Float32Array(per * notes.length);
    notes.forEach((f, i) => {
      const t = D.mix([1, 2, 3, 4, 5, 6].map(k => ({ frequency: f * k, amplitude: 0.3 / k })), fs, per);
      for (let j = 0; j < per; j++) out[i * per + j] = t[j] * Math.min(1, j / fade, (per - j) / fade) * Math.exp(-j / fs * 4);
    });
    return out;
  };
  const ro = readouts(), canvas = h('canvas', { class: 'spectro', role: 'img' });
  const draw = () => {
    x = make();
    const hop = Math.max(n / 4, Math.floor(x.length / 600)), cols = D.spectrogram(x, n, hop), binHz = ctx.fs / n;
    ro.set([['Time per column (window length)', `${(n / ctx.fs * 1000).toFixed(1)} ms`], ['Frequency resolution', `${binHz.toFixed(1)} Hz`]]);
    const hgt = Math.min(Math.floor(MAXHZ / binHz), n / 2), w = cols.length, ramp = readRamp();
    canvas.width = w; canvas.height = hgt;
    const g = canvas.getContext('2d'), img = g.createImageData(w, hgt);
    cols.forEach((col, cx) => { for (let r = 0; r < hgt; r++) {
      const t = Math.min(Math.max((col[hgt - r] + 90) / 90, 0), 1) * (ramp.length - 1), i = Math.min(Math.floor(t), ramp.length - 2), fr = t - i;
      const o = (r * w + cx) * 4; for (let c = 0; c < 3; c++) img.data[o + c] = ramp[i][c] + (ramp[i + 1][c] - ramp[i][c]) * fr; img.data[o + 3] = 255;
    } });
    g.putImageData(img, 0, 0);
    canvas.setAttribute('aria-label', `Spectrogram, ${n}-sample window`);
  };
  host.append(row(select('Signal', [['sweep', 'Rising sweep'], ['clicks', 'Clicks + steady tones'], ['melody', 'Melody with harmonics']], source, v => { source = v; draw(); }),
    select('Window size', [64, 128, 256, 512, 1024, 2048, 4096], n, v => { n = +v; draw(); })), ro,
    h('div', { class: 'spectro-wrap' },
      h('div', { class: 'yaxis' }, h('span', {}, '8 kHz'), h('span', {}, '4 kHz'), h('span', {}, '0')),
      h('div', { class: 'spectro-main' }, canvas, h('div', { class: 'xaxis' }, h('span', {}, '0 s'), h('span', {}, 'Time'), h('span', {}, `${SECONDS} s`))),
      h('div', { class: 'scale' }, h('span', {}, '0 dB'), h('i', { class: 'ramp' }), h('span', {}, '−90 dB'))),
    row(playBtn('Play signal', ctx, () => x), stopBtn(ctx)));
  draw();
  const mq = matchMedia('(prefers-color-scheme: dark)'), redraw = () => draw();
  mq.addEventListener('change', redraw);
  const mo = new MutationObserver(redraw); mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  return () => { mq.removeEventListener('change', redraw); mo.disconnect(); };
}

function readRamp() {
  const cs = getComputedStyle(document.documentElement);
  return Array.from({ length: 8 }, (_, i) => {
    const hex = cs.getPropertyValue(`--ramp-${i}`).trim().replace('#', '');
    return [0, 2, 4].map(k => parseInt(hex.slice(k, k + 2), 16) || 0);
  });
}

// ---------- audio sources ----------
const SOURCES = [['noisyTone', 'Noisy tone'], ['whiteNoise', 'White noise'], ['sawtooth', 'Sawtooth bass'], ['drums', 'Drum loop']];
function source(kind, n, fs) {
  switch (kind) {
    case 'whiteNoise': return D.scale(D.noise(n), 0.4);
    case 'sawtooth': return D.tone('sawtooth', 110, 0.4, fs, n);
    case 'drums': return D.scale(D.drumLoop(fs, n / fs), 0.8);
    default: return D.add(D.sine(220, 0.5, fs, n), D.noise(n), 0.25);
  }
}

// ---------- Lesson 7: convolution ----------
function convolution(host, ctx) {
  let kind = 'avg', len = 21, delayMs = 180, gain = 0.5, src = 'noisyTone';
  const isEcho = () => kind === 'echo' || kind === 'multi';
  const taps = () => { const d = Math.round(delayMs / 1000 * ctx.fs); return kind === 'echo' ? [[0, 1], [d, gain]] : Array.from({ length: 7 }, (_, k) => [d * k, gain ** k]); };
  const kernel = () => (kind === 'gauss' ? D.gaussianKernel(len) : D.movingAverageKernel(len));
  const proc = x => (isEcho() ? D.sparseConvolve(x, taps()) : D.convolve(x, kernel()));
  const lenCtl = slider('Kernel length (taps)', { min: 1, max: 101, step: 2, value: len, format: v => `${v} taps` }, v => { len = v; draw(); });
  const echoCtl = row(slider('Delay', { min: 40, max: 400, value: delayMs, format: v => `${Math.round(v)} ms` }, v => { delayMs = v; draw(); }),
    slider('Echo gain', { min: 0.1, max: 0.9, step: 0.01, value: gain, format: v => v.toFixed(2) }, v => { gain = v; draw(); }));
  const srcCtl = select('Input', SOURCES, src, v => { src = v; draw(); });
  const draw = () => {
    lenCtl.hidden = isEcho(); echoCtl.hidden = !isEcho();
    if (isEcho()) {
      pk.update([{ name: 'Impulse response', color: S1, points: taps().flatMap(([d, g]) => { const ms = d / ctx.fs * 1000; return [[ms, 0], [ms, g], [ms, 0]]; }) }], { xLabel: 'Delay (ms)' });
      const x = source(src, ctx.fs * 2, ctx.fs), y = proc(x), env = s => D.envelope(s, 400).map((v, i) => [i * 2 / 400, v]);
      ps.update([{ name: 'Input', color: S2, dashed: true, points: env(x) }, { name: 'Output', color: S1, points: env(y) }], { xLabel: 'Time (s)', yLabel: 'Envelope' });
    } else {
      pk.update([{ name: 'Impulse response', color: S1, dots: true, points: Array.from(kernel(), (v, i) => [i, v]) }], { xLabel: 'Tap' });
      const x = source(src, 1600, ctx.fs);
      ps.update([wave('Input', x, ctx.fs, S2, { dashed: true }), wave('Output', proc(x), ctx.fs, S1)], { xLabel: 'Time (ms)', yLabel: 'Amplitude' });
    }
  };
  host.append(row(select('Kernel', [['avg', 'Moving average'], ['gauss', 'Gaussian'], ['echo', 'Echo'], ['multi', 'Repeating echo']], kind, v => {
    kind = v; src = isEcho() ? 'drums' : 'noisyTone'; srcCtl.set(src); draw();
  }), srcCtl), lenCtl, echoCtl);
  const pair = h('div', { class: 'pair narrow-first' }); host.append(pair);
  const pk = plotBox(pair, { xLabel: 'Tap', yLabel: 'Weight' });
  const ps = plotBox(pair, { xLabel: 'Time (ms)', yLabel: 'Amplitude' });
  host.append(row(playBtn('Play input', ctx, () => source(src, ctx.toneCount(), ctx.fs)), playBtn('Play convolved', ctx, () => D.normalized(proc(source(src, ctx.toneCount(), ctx.fs)), 0.8)), stopBtn(ctx)));
  draw();
}

// ---------- Lesson 8: filter designer ----------
function filterDesigner(host, ctx) {
  let kind = 'Low-pass', logF = 3, q = 0.707, gain = 9, src = 'whiteNoise';
  const coeffs = h('code', { class: 'coeffs' });
  const gainCtl = slider('Gain', { min: -18, max: 18, step: 0.5, value: gain, format: v => `${v > 0 ? '+' : ''}${v} dB` }, v => { gain = v; draw(); });
  const flt = () => D.biquad(kind, 10 ** logF, q, gain, ctx.fs);
  const draw = () => {
    const f = flt(); gainCtl.hidden = kind !== 'Peak EQ';
    p.update([{ name: 'Frequency response', color: S1, points: Array.from({ length: 241 }, (_, i) => { const x = 20 * 1000 ** (i / 240); return [x, Math.max(f.responseDB(x), -48)]; }) }]);
    coeffs.textContent = `b = [${[f.b0, f.b1, f.b2].map(v => v.toFixed(4)).join(', ')}]   a = [1, ${f.a1.toFixed(4)}, ${f.a2.toFixed(4)}]`;
  };
  host.append(row(select('Type', D.BIQUAD_KINDS, kind, v => { kind = v; draw(); }), select('Input', SOURCES, src, v => { src = v; })),
    row(slider('Cutoff / centre', { min: Math.log10(20), max: Math.log10(20000), step: 0.001, value: logF, format: v => hz(10 ** v) }, v => { logF = v; draw(); }),
      slider('Q', { min: 0.3, max: 12, step: 0.01, value: q, format: v => v.toFixed(2) }, v => { q = v; draw(); }), gainCtl));
  const p = plotBox(host, { xLabel: 'Frequency (Hz, log scale)', yLabel: 'Gain (dB)', yDomain: [-48, 24], xDomain: [20, 20000], xLog: true, height: 240 });
  host.append(row(playBtn('Play input', ctx, () => source(src, ctx.toneCount(), ctx.fs)), playBtn('Play filtered', ctx, () => flt().process(source(src, ctx.toneCount(), ctx.fs))), stopBtn(ctx), coeffs));
  draw();
}

// ---------- Lesson 9: compressor ----------
function compressorDemo(host, ctx) {
  const P = { thresholdDB: -18, ratio: 4, attackMs: 5, releaseMs: 120, makeupDB: 6 }, SECONDS = 2;
  const ro = readouts();
  const loop = s => D.scale(D.drumLoop(ctx.fs, s), 0.9);
  const draw = () => {
    const c = D.compressor(P), x = loop(SECONDS), { output, gainDB } = c.process(x, ctx.fs);
    const env = s => D.envelope(s, 500).map((v, i) => [i * SECONDS / 500, Math.max(20 * Math.log10(Math.max(v, 1e-6)), -48)]);
    ro.set([['Max gain reduction', `${Math.min(...gainDB).toFixed(1)} dB`]]);
    pc.update([{ name: '1 : 1', color: REF, dashed: true, points: [[-48, -48], [0, 0]] },
      { name: 'Compressor', color: S1, points: Array.from({ length: 49 }, (_, i) => [i - 48, c.outputLevel(i - 48)]) }]);
    pe.update([{ name: 'Before', color: S2, dashed: true, points: env(x) }, { name: 'After', color: S1, points: env(output) }]);
  };
  const s = (label, key, o) => slider(label, { ...o, value: P[key] }, v => { P[key] = v; draw(); });
  host.append(h('div', { class: 'grid3' },
    s('Threshold', 'thresholdDB', { min: -40, max: 0, step: 0.5, format: v => `${v} dB` }),
    s('Ratio', 'ratio', { min: 1, max: 20, step: 0.1, format: v => `${v.toFixed(1)} : 1` }),
    s('Make-up gain', 'makeupDB', { min: 0, max: 24, step: 0.5, format: v => `+${v} dB` }),
    s('Attack', 'attackMs', { min: 0.1, max: 80, step: 0.1, format: v => `${v.toFixed(1)} ms` }),
    s('Release', 'releaseMs', { min: 10, max: 600, step: 1, format: v => `${v} ms` }), ro));
  const pair = h('div', { class: 'pair narrow-first' }); host.append(pair);
  const pc = plotBox(pair, { xLabel: 'Input (dBFS)', yLabel: 'Output (dBFS)', yDomain: [-48, 24], xDomain: [-48, 0] });
  const pe = plotBox(pair, { xLabel: 'Time (s)', yLabel: 'Peak level (dBFS)', yDomain: [-48, 12] });
  host.append(row(playBtn('Play before', ctx, () => loop(4)), playBtn('Play after', ctx, () => D.compressor(P).process(loop(4), ctx.fs).output), stopBtn(ctx),
    h('small', { class: 'note' }, 'Output above 0 dBFS clips — lower the make-up gain if you hear distortion.')));
  draw();
}

// ---------- Lesson 10: image kernels ----------
function imageKernels(host, ctx) {
  let kernel = 'Gaussian blur', strength = 2, img, token = 0;
  const before = imageCanvas('Original'), after = imageCanvas(kernel), matrix = h('div', { class: 'kernel' });
  const strengthCtl = slider('Strength', { min: 1, max: 4, step: 1, value: strength, format: v => String(v) }, v => { strength = v; draw(); });
  const draw = async () => {
    const my = ++token;
    img = await ctx.getImage(); before.draw(img);
    strengthCtl.classList.toggle('dim', !['Box blur', 'Gaussian blur', 'Sharpen'].includes(kernel));
    const k = D.kernelMatrix(kernel, strength);
    matrix.replaceChildren(h('div', { class: 'eyebrow' }, 'Kernel'), k.length <= 3
      ? h('div', { class: 'kgrid', style: `grid-template-columns:repeat(${k[0].length},auto)` }, k.flat().map(v => h('span', {}, Number.isInteger(v) ? String(v) : v.toFixed(2))))
      : h('p', {}, `${k.length} × ${k.length} weights summing to 1 — each output pixel averages ${k.length ** 2} neighbours.`));
    await new Promise(r => setTimeout(r));          // let the UI paint before the heavy loop
    if (my !== token) return;
    after.draw(D.applyKernel(kernel, strength, img), kernel);
  };
  host.append(row(select('Kernel', D.IMAGE_KERNELS, kernel, v => { kernel = v; draw(); }), strengthCtl),
    h('div', { class: 'images' }, before, after, matrix));
  draw();
  return ctx.onImage(draw);
}

// ---------- Lesson 11: JPEG ----------
function jpeg(host, ctx) {
  let quality = 30, zoom = false, token = 0;
  const ro = readouts(), before = imageCanvas('Original'), after = imageCanvas('After DCT → quantize → inverse DCT');
  const crop = im => { const w = im.width >> 1, hh = im.height >> 1, x0 = im.width >> 2, y0 = im.height >> 2, p = new Float32Array(w * hh);
    for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) p[y * w + x] = D.px(im, x0 + x, y0 + y); return D.makeImage(w, hh, p); };
  const draw = async () => {
    const my = ++token, img = await ctx.getImage();
    before.draw(zoom ? crop(img) : img);
    await new Promise(r => setTimeout(r));
    if (my !== token) return;
    const r = D.jpegRoundTrip(img, quality);
    after.draw(zoom ? crop(r.image) : r.image);
    ro.set([['Coefficients quantized to zero', `${(r.zeroFraction * 100).toFixed(0)}%`], ['Quality (PSNR, higher is better)', `${r.psnr.toFixed(1)} dB`], ['Block size', '8 × 8']]);
  };
  host.append(row(slider('JPEG quality', { min: 1, max: 100, step: 1, value: quality, format: v => String(v) }, v => { quality = v; draw(); }),
    toggle('Zoom 2× on centre', zoom, v => { zoom = v; draw(); })), ro, h('div', { class: 'images two' }, before, after));
  draw();
  return ctx.onImage(draw);
}

// ---------- Lesson 12: frame rate & shutter ----------
function frameRate(host, ctx) {
  let rps = 2, fps = 24, angle = 180; const SPOKES = 8, start = performance.now();
  const canvas = h('canvas', { class: 'wheel', width: 520, height: 520, role: 'img', 'aria-label': 'Spinning wheel as filmed by the camera' });
  const ro = readouts();
  const speed = slider('Wheel speed', { min: 0, max: 8, step: 0.125, value: rps, format: v => `${v.toFixed(2)} rev/s` }, v => { rps = v; info(); });
  const fpsCtl = select('Frame rate', [12, 24, 25, 30, 60].map(v => [v, `${v} fps`]), fps, v => { fps = +v; info(); });
  const angleCtl = slider('Shutter angle', { min: 1, max: 360, step: 1, value: angle, format: v => `${v}°` }, v => { angle = v; info(); });
  const info = () => {
    const app = D.apparentWheelSpeed(rps, fps, SPOKES);
    const verdict = rps === 0 ? ['Stationary', ''] : Math.abs(app) < 0.01 ? ['❄ Appears frozen', 'warn'] : app < 0 ? ['↺ Appears to spin backwards', 'warn']
      : Math.abs(app - rps) > 0.01 ? ['Appears slower than it is', 'warn'] : ['✓ Looks correct', 'good'];
    ro.set([['Exposure per frame', `1/${Math.round(360 / angle * fps)} s`], ['Looks like it turns at', `${app.toFixed(2)} rev/s`], ['', verdict[0], verdict[1]]]);
  };
  const preset = (label, r, f, a) => h('button', { class: 'link', type: 'button', onclick: () => { rps = r; fps = f; angle = a; speed.set(r); fpsCtl.set(f); angleCtl.set(a); info(); } }, label);
  host.append(row(speed, fpsCtl, angleCtl), ro, h('div', { class: 'wheel-wrap' }, canvas, h('div', { class: 'presets' }, h('div', { class: 'eyebrow' }, 'Try these'),
    preset('Frozen: 3 rev/s at 24 fps', 3, 24, 180), preset('Backwards: 2.75 rev/s at 24 fps', 2.75, 24, 45),
    preset('Same speed, 60 fps', 2.75, 60, 180), preset('Heavy blur: 360° shutter', 1.5, 24, 360),
    h('p', { class: 'note' }, `The wheel has ${SPOKES} identical spokes, so any rotation that's a multiple of 1/${SPOKES} revolution per frame looks like standing still.`))));
  info();
  const g = canvas.getContext('2d'); let raf;
  const frame = now => {
    const t = (now - start) / 1000, ft = Math.floor(t * fps) / fps, W = canvas.width, c = W / 2, r = W / 2 - 14;
    const cs = getComputedStyle(document.documentElement);
    g.clearRect(0, 0, W, W);
    g.strokeStyle = cs.getPropertyValue('--muted').trim(); g.lineWidth = 8; g.beginPath(); g.arc(c, c, r, 0, D.TAU); g.stroke();
    const exposure = angle / 360 / fps, subs = Math.max(1, Math.round(angle / 10));
    g.globalAlpha = Math.min(1, 1.6 / Math.sqrt(subs)); g.strokeStyle = cs.getPropertyValue('--s1').trim(); g.lineWidth = 10; g.lineCap = 'round';
    for (let s = 0; s < subs; s++) {
      const base = D.TAU * rps * (ft + exposure * s / subs);
      g.beginPath();
      for (let k = 0; k < SPOKES; k++) { const a = base + D.TAU * k / SPOKES; g.moveTo(c, c); g.lineTo(c + r * Math.cos(a), c + r * Math.sin(a)); }
      g.stroke();
    }
    g.globalAlpha = 1; g.fillStyle = cs.getPropertyValue('--muted').trim(); g.beginPath(); g.arc(c, c, 18, 0, D.TAU); g.fill();
    raf = requestAnimationFrame(frame);
  };
  raf = requestAnimationFrame(frame);
  return () => cancelAnimationFrame(raf);
}


// ---------- Lesson 13: colour & gamma ----------
function colourGamma(host, ctx) {
  const body = h('div', { class: 'demo-body' });
  const tabs = h('div', { class: 'segmented four', role: 'radiogroup', 'aria-label': 'Part' });
  let off = null;
  const show = part => {
    off?.(); off = null; body.replaceChildren();
    off = { gamma: () => gammaPart(body), chroma: () => chromaPart(body, ctx), wb: () => whiteBalancePart(body, ctx), gamut: () => gamutPart(body) }[part]();
  };
  const group = `part${++uid}`;
  [['gamma', 'Gamma'], ['chroma', 'Chroma subsampling'], ['wb', 'White balance'], ['gamut', 'Gamut']].forEach(([value, label], i) => {
    const id = `c${++uid}`, input = h('input', { type: 'radio', name: group, id, value });
    if (!i) input.checked = true;
    input.addEventListener('change', () => show(input.value));
    tabs.append(h('label', { for: id }, input, h('span', {}, label)));
  });
  host.append(tabs, body);
  show('gamma');
  return () => off?.();
}

function gammaPart(host) {
  let transfer = 'sRGB', bits = 5;
  const ro = readouts(), strips = h('div', { class: 'ramps' });
  const strip = (label, t, b) => {
    const c = h('canvas', { class: 'ramp-strip', width: 512, height: 1, role: 'img', 'aria-label': label });
    const g = c.getContext('2d'), img = g.createImageData(512, 1);
    D.storedRamp(512, b, t).forEach((l, i) => { const v = D.encodeTransfer('sRGB', l) * 255; img.data.set([v, v, v, 255], i * 4); });
    g.putImageData(img, 0, 0);
    return h('div', {}, h('div', { class: 'ramp-label' }, label), c);
  };
  const draw = () => {
    ro.set([['Codes for the darkest 10% of light, stored linearly', String(D.codesBelow(0.1, bits, 'Linear'))],
      [`…stored with ${transfer}`, String(D.codesBelow(0.1, bits, transfer))]]);
    p.update([{ name: 'Linear (no gamma)', color: REF, dashed: true, points: [[0, 0], [1, 1]] },
      { name: transfer, color: S1, points: Array.from({ length: 101 }, (_, i) => [i / 100, D.encodeTransfer(transfer, i / 100)]) }]);
    strips.replaceChildren(
      strip('Stored linearly — shadows band, highlights waste codes', 'Linear', bits),
      strip(`Stored with ${transfer} — steps look even`, transfer, bits),
      strip('Reference: smooth ramp (8-bit sRGB)', 'sRGB', 8),
      h('p', { class: 'note' }, `Each strip is the same ramp of light, dark to bright, after storing it at ${bits} bits.`));
  };
  host.append(row(select('Transfer function', D.TRANSFERS, transfer, v => { transfer = v; draw(); }),
    slider('Bit depth', { min: 2, max: 8, step: 1, value: bits, format: v => `${v} bits (${2 ** v} levels)` }, v => { bits = v; draw(); })), ro);
  const pair = h('div', { class: 'pair narrow-first' }); host.append(pair);
  const p = plotBox(pair, { xLabel: 'Linear light', yLabel: 'Stored value', yDomain: [0, 1], xDomain: [0, 1], height: 240 });
  pair.append(strips);
  draw();
  return null;
}

function chromaPart(host, ctx) {
  let mode = '4:2:0', channel = 'Result', zoom = true, token = 0;
  const ro = readouts(), before = rgbCanvas('Original (4:4:4)'), after = rgbCanvas('');
  const draw = async () => {
    const my = ++token, img = await ctx.getColourImage();
    before.draw(zoom ? D.centreCropRGB(img) : img);
    await new Promise(r => setTimeout(r));
    if (my !== token) return;
    const res = D.subsample(img, mode), view = D.channelView(channel, res), q = D.psnrRGB(img, res.image);
    after.draw(zoom ? D.centreCropRGB(view) : view, `${mode} · ${channel}`);
    ro.set([['Samples stored per pixel (4:4:4 = 3)', D.samplesPerPixel(mode).toFixed(1)], ['Data vs 4:4:4', `${Math.round(D.samplesPerPixel(mode) / 3 * 100)}%`],
      ['Quality (PSNR, higher is better)', Number.isFinite(q) && q < 90 ? `${q.toFixed(1)} dB` : 'lossless']]);
  };
  host.append(row(select('Subsampling', Object.keys(D.SUBSAMPLING), mode, v => { mode = v; draw(); }),
    select('Show', ['Result', 'Y′ (luma)', 'Cb (blue − luma)', 'Cr (red − luma)'], channel, v => { channel = v; draw(); }),
    toggle('Zoom 2× on centre', zoom, v => { zoom = v; draw(); })), ro, h('div', { class: 'images two' }, before, after));
  draw();
  return ctx.onImage(draw);
}

function whiteBalancePart(host, ctx) {
  let scene = 'chart', lightK = 3200, lightTint = 0, cameraK = 5600, cameraTint = 0, setting = 'manual', estimate = null, gains = D.gainsForKelvin(5600), lit, token = 0;
  const ro = readouts(), asLit = rgbCanvas('As lit, no correction (camera at 6,500 K)'), result = rgbCanvas('Camera result — click a gray area to balance on it');
  const k = v => `${Math.round(v).toLocaleString()} K`;
  const tn = v => (v === 0 ? '0' : `${v > 0 ? '+' : ''}${v} ${v < 0 ? 'green' : 'magenta'}`);
  const manual = () => { setting = 'manual'; gains = D.gainsForKelvin(cameraK, cameraTint); draw(); };
  const cam = slider('Camera white balance', { min: 2000, max: 10000, step: 50, value: cameraK, format: k }, v => { cameraK = v; manual(); });
  const camTint = slider('Camera tint', { min: -100, max: 100, step: 1, value: cameraTint, format: tn }, v => { cameraTint = v; manual(); });
  const light = slider('Scene light', { min: 2000, max: 10000, step: 50, value: lightK, format: k }, v => { lightK = v; draw(); });
  const lightTintCtl = slider('Light tint', { min: -100, max: 100, step: 1, value: lightTint, format: tn }, v => { lightTint = v; draw(); });
  const draw = async () => {
    const my = ++token;
    const src = scene === 'photo' && ctx.hasCustomImage() ? await ctx.getColourImage() : D.checkerChart();
    await new Promise(r => setTimeout(r));
    if (my !== token) return;
    lit = D.captureUnder(src, lightK, lightTint);
    const out = D.correctWith(lit, gains);
    asLit.draw(lit); result.draw(out);
    const rows = [['Camera setting', setting === 'manual' ? `${k(cameraK)}, tint ${tn(cameraTint)}` : `${setting === 'auto' ? 'Auto' : 'Picked'} ≈ ${k(estimate.kelvin)}, tint ${tn(estimate.tint)}`],
      ['Gains applied (R · G · B)', gains.map(g => `×${g.toFixed(2)}`).join(' · ')]];
    if (scene === 'chart') {
      const [px, py] = D.grayPatchCentre(out.width), i = py * out.width + px;
      rows.push(['Gray patch reads (R G B)', [out.r[i], out.g[i], out.b[i]].map(v => Math.round(v * 255)).join(' ')]);
    }
    ro.set(rows);
  };
  const neutral = (c, how) => { gains = D.gainsForNeutral(c); estimate = D.estimateLight(c); setting = how; draw(); };
  for (const fig of [asLit, result]) {
    const canvas = fig.querySelector('canvas');
    canvas.classList.add('pick');
    canvas.addEventListener('click', e => {
      if (!lit) return;
      const r = canvas.getBoundingClientRect();
      const x = Math.floor((e.clientX - r.left) / r.width * lit.width), y = Math.floor((e.clientY - r.top) / r.height * lit.height);
      neutral(D.sampleLinear(lit, Math.min(Math.max(x, 0), lit.width - 1), Math.min(Math.max(y, 0), lit.height - 1)), 'picked');
    });
  }
  const sceneSel = select('Scene', [['chart', 'Colour checker chart'], ['photo', 'Your photo (Settings → Images)']], scene, v => { scene = v; draw(); });
  const presets = h('div', { class: 'presets-row' }, h('span', { class: 'note' }, 'Light:'),
    // Fluorescent tubes sit above the black-body curve, so they read green.
    [['Candle', 2000, 0], ['Tungsten', 3200, 0], ['Fluorescent', 4000, -25], ['Daylight', 5600, 0], ['Overcast', 6500, 0], ['Shade', 8000, 0]].map(([name, v, t]) =>
      h('button', { class: 'link', type: 'button', onclick: () => { lightK = v; lightTint = t; light.set(v); lightTintCtl.set(t); draw(); } }, name)));
  host.append(row(sceneSel, presets), row(light, lightTintCtl), row(cam, camTint,
    h('button', { class: 'btn', type: 'button', onclick: () => lit && neutral(D.grayWorld(lit), 'auto') }, 'Auto (gray world)')),
    ro, h('div', { class: 'images two' }, asLit, result));
  draw();
  return ctx.onImage(draw);
}

// Categorical slots 1–3 plus a distinct dash per gamut, so lines never rely on colour alone.
const GAMUT_STYLE = [{ color: 'var(--s1)', dash: [] }, { color: 'var(--s2)', dash: [7, 4] }, { color: 'var(--s3)', dash: [2, 3] }];

function gamutPart(host) {
  let picked = [0.20, 0.70];
  const shown = new Set(D.GAMUTS.map(g => g.name));
  const XMAX = 0.8, YMAX = 0.9, PAD = 30, TOP = 8, RIGHT = 12, W = 380, H = Math.round(W * YMAX / XMAX);   // margins keep edge labels visible
  const CW = W + PAD + RIGHT, CH = H + 24 + TOP;
  const canvas = h('canvas', { class: 'gamut-diagram', width: CW * 2, height: CH * 2, role: 'img', 'aria-label': 'CIE 1931 chromaticity diagram with gamut triangles. Click or drag to pick a colour.' });
  const side = h('div', { class: 'gamut-side' });
  // Pre-render the coloured horseshoe once.
  const fill = document.createElement('canvas'); fill.width = W; fill.height = H;
  { const g = fill.getContext('2d'), img = g.createImageData(W, H);
    for (let r = 0; r < H; r++) for (let c = 0; c < W; c++) {
      const p = [(c + 0.5) / W * XMAX, (1 - (r + 0.5) / H) * YMAX];
      if (!D.isVisible(p)) continue;
      const rgb = D.chromaToSRGB(p), o = (r * W + c) * 4;
      img.data.set([rgb[0] * 255, rgb[1] * 255, rgb[2] * 255, 230], o);
    }
    g.putImageData(img, 0, 0); }
  const toPx = ([x, y]) => [PAD + x / XMAX * W, TOP + (1 - y / YMAX) * H];
  const draw = () => {
    const g = canvas.getContext('2d'), cs = getComputedStyle(document.documentElement), ink = cs.getPropertyValue('--muted').trim();
    g.setTransform(2, 0, 0, 2, 0, 0); g.clearRect(0, 0, CW, CH);
    g.drawImage(fill, PAD, TOP);
    g.font = '10px "IBM Plex Mono", monospace'; g.fillStyle = ink; g.strokeStyle = ink; g.textAlign = 'center';
    g.globalAlpha = 0.2;
    for (let i = 0; i <= 8; i++) { const x = PAD + i / 8 * W; g.beginPath(); g.moveTo(x, TOP); g.lineTo(x, TOP + H); g.stroke(); }
    for (let i = 0; i <= 9; i++) { const y = TOP + (1 - i / 9) * H; g.beginPath(); g.moveTo(PAD, y); g.lineTo(PAD + W, y); g.stroke(); }
    g.globalAlpha = 1;
    for (let i = 0; i <= 8; i++) g.fillText((i / 10).toFixed(1), PAD + i / 8 * W, TOP + H + 14);
    g.textAlign = 'right'; for (let i = 0; i <= 9; i++) g.fillText((i / 10).toFixed(1), PAD - 4, TOP + (1 - i / 9) * H + 3);
    g.beginPath(); D.LOCUS.forEach((p, i) => { const [x, y] = toPx(p); i ? g.lineTo(x, y) : g.moveTo(x, y); }); g.closePath(); g.lineWidth = 1; g.stroke();
    g.textAlign = 'center'; g.font = '9px "IBM Plex Mono", monospace';
    const [cx, cy] = toPx(D.D65);
    for (const nm of [460, 480, 490, 500, 520, 540, 560, 580, 600, 620]) {
      const [x, y] = toPx(D.spectralXY(nm)), dx = x - cx, dy = y - cy, len = Math.hypot(dx, dy) || 1;
      g.fillText(String(nm), x + dx / len * 14, y + dy / len * 10 + 3);
    }
    D.GAMUTS.forEach((gm, k) => {
      if (!shown.has(gm.name)) return;
      g.beginPath(); gm.corners.forEach((p, i) => { const [x, y] = toPx(p); i ? g.lineTo(x, y) : g.moveTo(x, y); }); g.closePath();
      g.lineJoin = 'round'; g.setLineDash([]); g.strokeStyle = 'rgba(0,0,0,0.55)'; g.lineWidth = 4.5; g.stroke();
      g.setLineDash(GAMUT_STYLE[k].dash); g.strokeStyle = cs.getPropertyValue(GAMUT_STYLE[k].color.slice(4, -1)).trim(); g.lineWidth = 2.5; g.stroke();
    });
    g.setLineDash([]);
    g.fillStyle = '#000'; g.beginPath(); g.arc(cx, cy, 3, 0, D.TAU); g.fill(); g.font = 'bold 10px system-ui'; g.textAlign = 'left'; g.fillText('D65', cx + 6, cy + 12);
    const [qx, qy] = toPx(picked);
    g.lineWidth = 3; g.strokeStyle = '#000'; g.beginPath(); g.arc(qx, qy, 8, 0, D.TAU); g.stroke();
    g.lineWidth = 1.5; g.strokeStyle = '#fff'; g.stroke();
    drawSide();
  };
  const drawSide = () => {
    const visible = D.isVisible(picked), rgb = D.chromaToSRGB(picked), in709 = D.gamutContains(D.GAMUTS[0], picked);
    side.replaceChildren(
      h('p', { class: 'note' }, 'Click or drag on the diagram to pick a colour.'),
      h('div', { class: 'readout' }, h('b', {}, `${picked[0].toFixed(3)}, ${picked[1].toFixed(3)}`), h('span', {}, 'Chromaticity (x, y)')),
      h('div', { class: 'gamut-list' }, D.GAMUTS.map((gm, k) => {
        const id = `c${++uid}`, cb = h('input', { type: 'checkbox', id });
        cb.checked = shown.has(gm.name);
        cb.addEventListener('change', () => { cb.checked ? shown.add(gm.name) : shown.delete(gm.name); draw(); });
        const inside = D.gamutContains(gm, picked);
        return h('div', { class: 'gamut-row' }, cb,
          h('label', { for: id }, h('i', { class: 'swatch-line', style: `border-top: 3px ${GAMUT_STYLE[k].dash.length ? (k === 1 ? 'dashed' : 'dotted') : 'solid'} ${GAMUT_STYLE[k].color}` }), gm.name),
          h('span', { class: inside ? 'in' : 'out' }, inside ? '✓ Inside' : '✗ Outside'));
      })),
      h('p', { class: visible ? '' : 'warn-text' }, visible ? '👁 A colour people can see' : 'Outside human vision: no real light has this colour'),
      h('div', { class: 'swatch-row' }, h('i', { class: 'swatch', style: `background: rgb(${rgb.map(v => Math.round(v * 255)).join(',')})` }),
        h('span', { class: 'note' }, in709 ? 'Shown exactly (inside sRGB).' : 'Shown as the nearest sRGB colour; the real colour is more saturated.')),
      h('div', { class: 'presets' }, h('div', { class: 'eyebrow' }, 'Try'),
        [['sRGB green', D.GAMUTS[0].corners[1]], ['P3 green', D.GAMUTS[1].corners[1]], ['Rec.2020 green (532 nm laser)', D.GAMUTS[2].corners[1]],
          ['Cyan 490 nm', D.spectralXY(490)], ['White (D65)', D.D65]].map(([name, p]) =>
          h('button', { class: 'link', type: 'button', onclick: () => { picked = p; draw(); } }, name))));
  };
  const pick = e => {
    const r = canvas.getBoundingClientRect(), sx = CW / r.width, sy = CH / r.height;
    const x = ((e.clientX - r.left) * sx - PAD) / W * XMAX, y = (1 - ((e.clientY - r.top) * sy - TOP) / H) * YMAX;
    picked = [Math.min(Math.max(x, 0), XMAX), Math.min(Math.max(y, 0.001), YMAX)]; draw();
  };
  canvas.addEventListener('pointerdown', e => { canvas.setPointerCapture(e.pointerId); pick(e); });
  canvas.addEventListener('pointermove', e => { if (e.buttons) pick(e); });
  host.append(h('div', { class: 'gamut-wrap' }, canvas, side));
  draw();
  const mq = matchMedia('(prefers-color-scheme: dark)'); mq.addEventListener('change', draw);
  const mo = new MutationObserver(draw); mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  return () => { mq.removeEventListener('change', draw); mo.disconnect(); };
}

export const DEMOS = {
  sineMixer, aliasing, quantization, spectrum, windowing, spectrogram: spectrogramDemo,
  convolution, filterDesigner, compressor: compressorDemo, imageKernels, jpeg, frameRate, colourGamma,
};
