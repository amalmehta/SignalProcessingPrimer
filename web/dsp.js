// Pure signal-processing routines for the website — a port of the Mac app's DSP.swift / ImageDSP.swift.
// Everything works on Float32Array / plain arrays so it can be plotted, played or tested in Node.

export const TAU = 2 * Math.PI;

// ---------- Generating signals ----------

export function tone(waveform, frequency, amplitude, sampleRate, count, phase = 0) {
  const out = new Float32Array(count);
  for (let n = 0; n < count; n++) {
    const cycles = frequency * n / sampleRate + phase / TAU;
    const p = cycles - Math.floor(cycles);
    let v;
    switch (waveform) {
      case 'square': v = p < 0.5 ? 1 : -1; break;
      case 'sawtooth': v = 2 * p - 1; break;
      case 'triangle': v = p < 0.5 ? 4 * p - 1 : 3 - 4 * p; break;
      default: v = Math.sin(TAU * p);
    }
    out[n] = amplitude * v;
  }
  return out;
}

export const sine = (f, a, fs, n) => tone('sine', f, a, fs, n);

/** partials: [{frequency, amplitude, phase?}] */
export function mix(partials, sampleRate, count) {
  const out = new Float32Array(count);
  for (const p of partials) {
    if (!p.amplitude) continue;
    const w = TAU * p.frequency / sampleRate, ph = p.phase || 0;
    for (let n = 0; n < count; n++) out[n] += p.amplitude * Math.sin(w * n + ph);
  }
  return out;
}

export function chirp(f0, f1, sampleRate, count) {
  const k = (f1 - f0) / (count / sampleRate);
  const out = new Float32Array(count);
  for (let n = 0; n < count; n++) { const t = n / sampleRate; out[n] = Math.sin(TAU * (f0 * t + 0.5 * k * t * t)); }
  return out;
}

/** Deterministic white noise in -1…1 (mulberry32), so plots don't flicker between redraws. */
export function noise(count, seed = 42) {
  let a = seed >>> 0;
  const out = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    out[i] = (((t ^ (t >>> 14)) >>> 0) / 4294967296) * 2 - 1;
  }
  return out;
}

export function add(a, b, gainB = 1) {
  const out = new Float32Array(a.length);
  for (let i = 0; i < a.length; i++) out[i] = a[i] + gainB * (b[i] || 0);
  return out;
}

export function scale(x, g) { return x.map(v => v * g); }

export function peak(x) { let m = 0; for (const v of x) m = Math.max(m, Math.abs(v)); return m; }

export function normalized(x, target = 0.9) { const m = peak(x); return m > 0 ? scale(x, target / m) : x; }

// ---------- Sampling & quantization ----------

export function aliasedFrequency(f, fs) {
  const r = f % fs;
  return r > fs / 2 ? fs - r : r;
}

export function quantize(x, bits, dither = false) {
  const levels = 2 ** (bits - 1), lsb = 1 / levels;
  const d = dither ? noise(x.length, 7) : null;
  return x.map((v, i) => {
    const s = v + (d ? d[i] * lsb : 0);
    return Math.min(Math.max(Math.round(s * levels) / levels, -1), 1 - lsb);
  });
}

export function snr(reference, processed) {
  let ps = 0, pn = 0;
  for (let i = 0; i < reference.length; i++) { ps += reference[i] ** 2; pn += (reference[i] - processed[i]) ** 2; }
  return pn === 0 ? Infinity : 10 * Math.log10(ps / pn);
}

// ---------- Windows ----------

export const WINDOWS = ['Rectangular', 'Hann', 'Hamming', 'Blackman'];

export function windowCoefficients(name, n) {
  const w = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const x = TAU * i / n;            // periodic (DFT-even) windows, as vDSP produces
    switch (name) {
      case 'Hann': w[i] = 0.5 - 0.5 * Math.cos(x); break;
      case 'Hamming': w[i] = 0.54 - 0.46 * Math.cos(x); break;
      case 'Blackman': w[i] = 0.42 - 0.5 * Math.cos(x) + 0.08 * Math.cos(2 * x); break;
      default: w[i] = 1;
    }
  }
  return w;
}

// ---------- Fourier ----------

/** In-place iterative radix-2 FFT on separate real/imag arrays (length must be a power of two). */
export function fft(re, im) {
  const n = re.length;
  if (n & (n - 1)) throw new Error('FFT length must be a power of two');
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -TAU / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const a = i + k, b = a + len / 2;
        const tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr;
        re[b] = re[a] - tr; im[b] = im[a] - ti; re[a] += tr; im[a] += ti;
        const ncr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = ncr;
      }
    }
  }
}

/** Single-sided magnitude spectrum, bins 0…n/2. A sine of amplitude A peaks at ≈ A. */
export function magnitudeSpectrum(x, windowName = 'Rectangular') {
  const n = x.length, w = windowCoefficients(windowName, n);
  const re = new Float64Array(n), im = new Float64Array(n);
  let wsum = 0;
  for (let i = 0; i < n; i++) { re[i] = x[i] * w[i]; wsum += w[i]; }
  fft(re, im);
  const gain = 2 / wsum, out = new Float32Array(n / 2 + 1);
  for (let k = 0; k <= n / 2; k++) out[k] = Math.hypot(re[k], im[k]) * gain * (k === 0 ? 0.5 : 1);
  return out;
}

export function decibels(mags, floor = -100) {
  return Array.from(mags, m => Math.max(20 * Math.log10(Math.max(m, 1e-12)), floor));
}

/** STFT: one dB column (bins 0…n/2) per frame, Hann window. */
export function spectrogram(x, n, hop) {
  const cols = [];
  for (let s = 0; s + n <= x.length; s += Math.max(hop, 1)) cols.push(decibels(magnitudeSpectrum(x.subarray(s, s + n), 'Hann')));
  return cols;
}

// ---------- Convolution & filtering ----------

/** Causal convolution trimmed to the input length: y[n] = Σ h[k] x[n−k]. */
export function convolve(x, h) {
  const y = new Float32Array(x.length);
  for (let n = 0; n < x.length; n++) {
    let acc = 0;
    for (let k = 0; k < h.length && k <= n; k++) acc += h[k] * x[n - k];
    y[n] = acc;
  }
  return y;
}

/** taps: [[delay, gain], …] — the fast path for sparse impulse responses like echoes. */
export function sparseConvolve(x, taps) {
  const y = new Float32Array(x.length);
  for (const [d, g] of taps) for (let n = d; n < x.length; n++) y[n] += g * x[n - d];
  return y;
}

export const movingAverageKernel = len => new Float32Array(Math.max(len, 1)).fill(1 / Math.max(len, 1));

export function gaussianKernel(len) {
  const n = Math.max(len, 1), sigma = Math.max(n / 6, 0.5), mid = (n - 1) / 2;
  const k = Array.from({ length: n }, (_, i) => Math.exp(-((i - mid) ** 2) / (2 * sigma * sigma)));
  const sum = k.reduce((a, b) => a + b, 0);
  return Float32Array.from(k, v => v / sum);
}

export function echoKernel(delay, gain) { const k = new Float32Array(delay + 1); k[0] = 1; k[delay] = gain; return k; }

export const BIQUAD_KINDS = ['Low-pass', 'High-pass', 'Band-pass', 'Peak EQ', 'Notch'];

/** RBJ "Audio EQ Cookbook" biquad. */
export function biquad(kind, cutoff, q, gainDB, fs) {
  const w0 = TAU * cutoff / fs, cw = Math.cos(w0), alpha = Math.sin(w0) / (2 * q), A = 10 ** (gainDB / 40);
  let b, a;
  switch (kind) {
    case 'High-pass': b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]; a = [1 + alpha, -2 * cw, 1 - alpha]; break;
    case 'Band-pass': b = [alpha, 0, -alpha]; a = [1 + alpha, -2 * cw, 1 - alpha]; break;
    case 'Notch': b = [1, -2 * cw, 1]; a = [1 + alpha, -2 * cw, 1 - alpha]; break;
    case 'Peak EQ': b = [1 + alpha * A, -2 * cw, 1 - alpha * A]; a = [1 + alpha / A, -2 * cw, 1 - alpha / A]; break;
    default: b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]; a = [1 + alpha, -2 * cw, 1 - alpha];
  }
  const f = { b0: b[0] / a[0], b1: b[1] / a[0], b2: b[2] / a[0], a1: a[1] / a[0], a2: a[2] / a[0] };
  f.responseDB = hz => {
    const w = TAU * hz / fs;
    const nr = f.b0 + f.b1 * Math.cos(w) + f.b2 * Math.cos(2 * w), ni = -(f.b1 * Math.sin(w) + f.b2 * Math.sin(2 * w));
    const dr = 1 + f.a1 * Math.cos(w) + f.a2 * Math.cos(2 * w), di = -(f.a1 * Math.sin(w) + f.a2 * Math.sin(2 * w));
    return 10 * Math.log10(Math.max((nr * nr + ni * ni) / (dr * dr + di * di), 1e-20));
  };
  f.process = x => {
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    return x.map(xn => {
      const y = f.b0 * xn + f.b1 * x1 + f.b2 * x2 - f.a1 * y1 - f.a2 * y2;
      x2 = x1; x1 = xn; y2 = y1; y1 = y;
      return y;
    });
  };
  return f;
}

// ---------- Dynamics ----------

export function compressor({ thresholdDB, ratio, attackMs, releaseMs, makeupDB = 0 }) {
  const outputLevel = db => (db <= thresholdDB ? db : thresholdDB + (db - thresholdDB) / ratio) + makeupDB;
  const process = (x, fs) => {
    const att = Math.exp(-1 / (attackMs * 0.001 * fs)), rel = Math.exp(-1 / (releaseMs * 0.001 * fs));
    let env = 0;
    const out = new Float32Array(x.length), gains = new Float32Array(x.length);
    for (let i = 0; i < x.length; i++) {
      const level = Math.abs(x[i]);
      env = level > env ? att * env + (1 - att) * level : rel * env + (1 - rel) * level;
      const inDB = 20 * Math.log10(Math.max(env, 1e-6));
      const reduction = Math.min(0, outputLevel(inDB) - makeupDB - inDB);
      gains[i] = reduction;
      out[i] = x[i] * 10 ** ((reduction + makeupDB) / 20);
    }
    return { output: out, gainDB: gains };
  };
  return { outputLevel, process };
}

/** Synthetic drum loop: alternating loud kicks and quiet ghost hits every 250 ms. */
export function drumLoop(fs, seconds) {
  const count = Math.floor(fs * seconds), out = new Float32Array(count), bed = noise(count, 3);
  const every = Math.floor(fs * 0.25), louds = [1, 0.18, 0.55, 0.12];
  for (let i = 0, start = 0; start < count; i++, start += every) {
    const loud = louds[i % 4], len = Math.min(Math.floor(fs * 0.2), count - start);
    for (let n = 0; n < len; n++) {
      const t = n / fs;
      const body = Math.sin(TAU * (55 + 90 * Math.exp(-t * 30)) * t) * Math.exp(-t * 18);
      out[start + n] += loud * (0.8 * body + 0.2 * bed[start + n] * Math.exp(-t * 60));
    }
  }
  return out;
}

/** Peak per block, for plotting long signals compactly. */
export function envelope(x, blocks) {
  const size = Math.max(Math.floor(x.length / blocks), 1), out = [];
  for (let s = 0; s < x.length; s += size) out.push(peak(x.subarray ? x.subarray(s, s + size) : x.slice(s, s + size)));
  return out;
}

/** ~target evenly spaced [index, value] pairs so charts stay fast. */
export function decimate(x, target = 600) {
  const step = Math.max(Math.floor(x.length / target), 1), out = [];
  for (let i = 0; i < x.length; i += step) out.push([i, x[i]]);
  return out;
}

// ---------- Images (grayscale, row-major, 0…1) ----------

export function makeImage(width, height, pixels) { return { width, height, pixels }; }

export function px(img, x, y) {                     // clamp-to-edge
  const cx = Math.min(Math.max(x, 0), img.width - 1), cy = Math.min(Math.max(y, 0), img.height - 1);
  return img.pixels[cy * img.width + cx];
}

export const IMAGE_KERNELS = ['Original', 'Box blur', 'Gaussian blur', 'Sharpen', 'Edges (Sobel X)', 'Edges (Sobel magnitude)', 'Emboss'];

export function kernelMatrix(name, strength) {
  switch (name) {
    case 'Box blur': { const n = 2 * strength + 1; return Array.from({ length: n }, () => Array(n).fill(1 / (n * n))); }
    case 'Gaussian blur': { const g = gaussianKernel(4 * strength + 1); return Array.from(g, a => Array.from(g, b => a * b)); }
    case 'Sharpen': { const a = strength * 0.5; return [[0, -a, 0], [-a, 1 + 4 * a, -a], [0, -a, 0]]; }
    case 'Edges (Sobel X)': case 'Edges (Sobel magnitude)': return [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]];
    case 'Emboss': return [[-2, -1, 0], [-1, 1, 1], [0, 1, 2]];
    default: return [[1]];
  }
}

export function convolve2D(img, k) {
  const kh = k.length, kw = k[0].length, oy = kh >> 1, ox = kw >> 1, out = new Float32Array(img.pixels.length);
  for (let y = 0; y < img.height; y++) for (let x = 0; x < img.width; x++) {
    let acc = 0;
    for (let j = 0; j < kh; j++) for (let i = 0; i < kw; i++) acc += k[j][i] * px(img, x + i - ox, y + j - oy);
    out[y * img.width + x] = acc;
  }
  return makeImage(img.width, img.height, out);
}

const clamp01 = v => Math.min(Math.max(v, 0), 1);

export function applyKernel(name, strength, img) {
  if (name === 'Original') return img;
  const r = convolve2D(img, kernelMatrix(name, strength));
  if (name === 'Edges (Sobel X)') return makeImage(img.width, img.height, r.pixels.map(v => clamp01(v * 0.5 + 0.5)));
  if (name === 'Edges (Sobel magnitude)') {
    const gy = convolve2D(img, [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]);
    return makeImage(img.width, img.height, r.pixels.map((v, i) => Math.min(Math.hypot(v, gy.pixels[i]), 1)));
  }
  if (name === 'Emboss') return makeImage(img.width, img.height, r.pixels.map(v => clamp01(v * 0.5)));
  return makeImage(img.width, img.height, r.pixels.map(clamp01));
}

// JPEG luminance quantization table (ITU T.81 Annex K).
export const JPEG_LUMA = [
  16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
  14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
  49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99];

const COS = Array.from({ length: 64 }, (_, i) => Math.cos((2 * Math.floor(i / 8) + 1) * (i % 8) * Math.PI / 16)); // [x*8+u]
const C = u => (u === 0 ? Math.SQRT1_2 : 1);

export function dct8x8(block) {
  const out = new Float64Array(64);
  for (let v = 0; v < 8; v++) for (let u = 0; u < 8; u++) {
    let s = 0;
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) s += block[y * 8 + x] * COS[x * 8 + u] * COS[y * 8 + v];
    out[v * 8 + u] = 0.25 * C(u) * C(v) * s;
  }
  return out;
}

export function idct8x8(coeffs) {
  const out = new Float64Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    let s = 0;
    for (let v = 0; v < 8; v++) for (let u = 0; u < 8; u++) s += C(u) * C(v) * coeffs[v * 8 + u] * COS[x * 8 + u] * COS[y * 8 + v];
    out[y * 8 + x] = 0.25 * s;
  }
  return out;
}

/** libjpeg's quality (1…100) → table scaling. */
export function quantTable(quality) {
  const q = Math.min(Math.max(quality, 1), 100), s = q < 50 ? 5000 / q : 200 - 2 * q;
  return JPEG_LUMA.map(v => Math.max(1, Math.floor((v * s + 50) / 100)));
}

/** Blockwise DCT → quantize → dequantize → inverse DCT. */
export function jpegRoundTrip(img, quality) {
  const table = quantTable(quality), out = Float32Array.from(img.pixels);
  let zeros = 0, total = 0;
  const block = new Float64Array(64);
  for (let by = 0; by < img.height; by += 8) for (let bx = 0; bx < img.width; bx += 8) {
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) block[y * 8 + x] = px(img, bx + x, by + y) * 255 - 128;
    const q = dct8x8(block).map((c, i) => Math.round(c / table[i]));
    q.forEach(v => { if (v === 0) zeros++; }); total += 64;
    const rec = idct8x8(q.map((v, i) => v * table[i]));
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
      if (bx + x < img.width && by + y < img.height) out[(by + y) * img.width + bx + x] = clamp01((rec[y * 8 + x] + 128) / 255);
    }
  }
  let mse = 0;
  for (let i = 0; i < out.length; i++) mse += (img.pixels[i] - out[i]) ** 2;
  mse /= out.length;
  return { image: makeImage(img.width, img.height, out), zeroFraction: zeros / total, psnr: mse === 0 ? Infinity : 10 * Math.log10(1 / mse) };
}

// ---------- Film ----------

/** How a wheel with `spokes` identical spokes appears to turn (rev/s, negative = backwards). */
export function apparentWheelSpeed(revsPerSecond, fps, spokes) {
  const adv = revsPerSecond * spokes / fps;
  return (adv - Math.round(adv)) * fps / spokes;
}
