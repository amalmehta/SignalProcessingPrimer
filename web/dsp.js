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

// ---------- Colour & gamma (Lesson 13) ----------

export const TRANSFERS = ['sRGB', 'Power 2.2', 'BT.1886 (2.4)'];

/** Linear light → stored value. */
export function encodeTransfer(name, l) {
  l = Math.min(Math.max(l, 0), 1);
  switch (name) {
    case 'sRGB': return l <= 0.0031308 ? 12.92 * l : 1.055 * l ** (1 / 2.4) - 0.055;
    case 'Power 2.2': return l ** (1 / 2.2);
    case 'BT.1886 (2.4)': return l ** (1 / 2.4);
    default: return l;                                   // 'Linear'
  }
}

/** Stored value → linear light. */
export function decodeTransfer(name, v) {
  v = Math.min(Math.max(v, 0), 1);
  switch (name) {
    case 'sRGB': return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    case 'Power 2.2': return v ** 2.2;
    case 'BT.1886 (2.4)': return v ** 2.4;
    default: return v;
  }
}

export function quantizeUnit(v, bits) { const levels = 2 ** bits - 1; return Math.round(Math.min(Math.max(v, 0), 1) * levels) / levels; }

/** Linear-light ramp 0→1 stored at `bits` through `transfer`; returns the light the display emits. */
export function storedRamp(count, bits, transfer) {
  return Array.from({ length: count }, (_, i) => decodeTransfer(transfer, quantizeUnit(encodeTransfer(transfer, i / Math.max(count - 1, 1)), bits)));
}

/** Distinct codes covering linear light below `limit`. */
export function codesBelow(limit, bits, transfer) { return Math.floor(encodeTransfer(transfer, limit) * (2 ** bits - 1)) + 1; }

// Y′CbCr, BT.601 full range (JPEG).
export function toYCbCr(r, g, b) {
  return [0.299 * r + 0.587 * g + 0.114 * b, -0.168736 * r - 0.331264 * g + 0.5 * b, 0.5 * r - 0.418688 * g - 0.081312 * b];
}
export function toRGB(y, cb, cr) { return [y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb]; }

export const SUBSAMPLING = { '4:4:4': [1, 1], '4:2:2': [2, 1], '4:2:0': [2, 2] };
export const samplesPerPixel = mode => { const [w, h] = SUBSAMPLING[mode]; return 1 + 2 / (w * h); };

/** img: {width, height, r, g, b} (R′G′B′ 0…1). Returns {image, y, cb, cr}. */
export function subsample(img, mode) {
  const n = img.width * img.height, y = new Float32Array(n), cb = new Float32Array(n), cr = new Float32Array(n);
  for (let i = 0; i < n; i++) [y[i], cb[i], cr[i]] = toYCbCr(img.r[i], img.g[i], img.b[i]);
  const [bw, bh] = SUBSAMPLING[mode];
  if (bw * bh > 1) {
    for (let by = 0; by < img.height; by += bh) for (let bx = 0; bx < img.width; bx += bw) {
      const idx = [];
      for (let dy = 0; dy < bh && by + dy < img.height; dy++) for (let dx = 0; dx < bw && bx + dx < img.width; dx++) idx.push((by + dy) * img.width + bx + dx);
      const sb = idx.reduce((s, i) => s + cb[i], 0) / idx.length, sr = idx.reduce((s, i) => s + cr[i], 0) / idx.length;
      for (const i of idx) { cb[i] = sb; cr[i] = sr; }
    }
  }
  const out = { width: img.width, height: img.height, r: new Float32Array(n), g: new Float32Array(n), b: new Float32Array(n) };
  for (let i = 0; i < n; i++) {
    const [r, g, b] = toRGB(y[i], cb[i], cr[i]);
    out.r[i] = Math.min(Math.max(r, 0), 1); out.g[i] = Math.min(Math.max(g, 0), 1); out.b[i] = Math.min(Math.max(b, 0), 1);
  }
  return { image: out, y, cb, cr };
}

/** 'Result' | 'Y′ (luma)' | 'Cb (blue − luma)' | 'Cr (red − luma)'. */
export function channelView(channel, { image, y, cb, cr }) {
  if (channel === 'Result') return image;
  const n = y.length, out = { width: image.width, height: image.height, r: new Float32Array(n), g: new Float32Array(n), b: new Float32Array(n) };
  for (let i = 0; i < n; i++) {
    const [r, g, b] = channel.startsWith('Y') ? [y[i], y[i], y[i]] : channel.startsWith('Cb') ? toRGB(0.5, cb[i], 0) : toRGB(0.5, 0, cr[i]);
    out.r[i] = Math.min(Math.max(r, 0), 1); out.g[i] = Math.min(Math.max(g, 0), 1); out.b[i] = Math.min(Math.max(b, 0), 1);
  }
  return out;
}

export function psnrRGB(a, b) {
  let se = 0;
  for (let i = 0; i < a.r.length; i++) se += (a.r[i] - b.r[i]) ** 2 + (a.g[i] - b.g[i]) ** 2 + (a.b[i] - b.b[i]) ** 2;
  const mse = se / (a.r.length * 3);
  return mse === 0 ? Infinity : 10 * Math.log10(1 / mse);
}

export function centreCropRGB(img) {
  const w = img.width >> 1, h = img.height >> 1, x0 = img.width >> 2, y0 = img.height >> 2;
  const out = { width: w, height: h, r: new Float32Array(w * h), g: new Float32Array(w * h), b: new Float32Array(w * h) };
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y0 + y) * img.width + x0 + x, o = y * w + x;
    out.r[o] = img.r[i]; out.g[o] = img.g[i]; out.b[o] = img.b[i];
  }
  return out;
}

// ---------- White balance (Lesson 13) — all maths in linear light ----------

export const WB_REFERENCE = 6500;   // renders neutral with unity gains

/** CIE 1931 xy of a black body (Kim et al. cubic fit, 1667–25000 K). */
export function planckianXY(kelvin) {
  const t = Math.min(Math.max(kelvin, 1667), 25000), t2 = t * t, t3 = t2 * t;
  const x = t <= 4000 ? -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
                      : -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390;
  const x2 = x * x, x3 = x2 * x;
  const y = t <= 2222 ? -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683
          : t <= 4000 ? -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867
          : 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483;
  return [x, y];
}

/** Tint (−100 green … +100 magenta, as in Lightroom/Premiere) → Duv: +100 is −0.02 (magenta), −100 is +0.02 (green). */
export const duv = tint => -tint / 100 * 0.02;

/** xy of light at `kelvin`, moved off the Planckian locus along its normal (in CIE 1960 uv) by the tint. */
export function lightXY(kelvin, tint = 0) {
  if (!tint) return planckianXY(kelvin);
  const uv = k => { const [x, y] = planckianXY(k), d = -2 * x + 12 * y + 3; return [4 * x / d, 6 * y / d]; };
  const p = uv(kelvin), a = uv(kelvin - 10), b = uv(kelvin + 10);
  let nu = -(b[1] - a[1]), nv = b[0] - a[0];
  const len = Math.hypot(nu, nv); nu /= len; nv /= len;
  if (nv < 0) { nu = -nu; nv = -nv; }                 // positive Duv points towards green
  const d = duv(tint), u = p[0] + d * nu, v = p[1] + d * nv, den = 2 * u - 8 * v + 4;
  return [3 * u / den, 2 * v / den];
}

function rawRGB([x, y]) {
  const X = x / y, Z = (1 - x - y) / y;
  return [Math.max(3.2406 * X - 1.5372 - 0.4986 * Z, 0.001), Math.max(-0.9689 * X + 1.8758 + 0.0415 * Z, 0.001), Math.max(0.0557 * X - 0.2040 + 1.0570 * Z, 0.001)];
}
const REF_RGB = rawRGB(planckianXY(WB_REFERENCE));

/** Linear-sRGB colour of light at `kelvin` and `tint`, scaled so 6,500 K / tint 0 is [1, 1, 1] and green is 1. */
export function illuminant(kelvin, tint = 0) {
  const c = rawRGB(lightXY(kelvin, tint)), r = c[0] / REF_RGB[0], g = c[1] / REF_RGB[1], b = c[2] / REF_RGB[2];
  return [r / g, 1, b / g];
}

export function gainsForKelvin(kelvin, tint = 0) { const l = illuminant(kelvin, tint); return [1 / l[0], 1, 1 / l[2]]; }
export function gainsForNeutral([r, g, b]) { return [g / Math.max(r, 1e-6), 1, g / Math.max(b, 1e-6)]; }

/** Nearest {kelvin, tint} to a measured light colour (coarse grid, then refined). */
export function estimateLight([r, g, b]) {
  const tr = Math.log(r / Math.max(g, 1e-9)), tb = Math.log(b / Math.max(g, 1e-9));
  const err = (k, t) => { const l = illuminant(k, t); return (Math.log(l[0]) - tr) ** 2 + (Math.log(l[2]) - tb) ** 2; };
  let best = { kelvin: WB_REFERENCE, tint: 0 }, bestErr = Infinity;
  const search = (k0, k1, dk, t0, t1, dt) => {
    for (let k = k0; k <= k1; k += dk) for (let t = t0; t <= t1; t += dt) { const e = err(k, t); if (e < bestErr) { bestErr = e; best = { kelvin: k, tint: t }; } }
  };
  search(2000, 10000, 100, -100, 100, 5);
  search(best.kelvin - 100, best.kelvin + 100, 10, best.tint - 5, best.tint + 5, 1);
  return best;
}
export const estimateKelvin = c => estimateLight(c).kelvin;

function applyGains(img, [gr, gg, gb]) {
  const n = img.r.length, out = { width: img.width, height: img.height, r: new Float32Array(n), g: new Float32Array(n), b: new Float32Array(n) };
  const enc = v => encodeTransfer('sRGB', v), dec = v => decodeTransfer('sRGB', v);
  for (let i = 0; i < n; i++) { out.r[i] = enc(dec(img.r[i]) * gr); out.g[i] = enc(dec(img.g[i]) * gg); out.b[i] = enc(dec(img.b[i]) * gb); }
  return out;
}
/** The scene as the sensor records it under light at `kelvin`. Images are sRGB-encoded R′G′B′. */
// Exposure is set so the light's strongest channel is 1 (like auto-exposure), so white never clips.
export const captureUnder = (img, kelvin, tint = 0) => { const l = illuminant(kelvin, tint), m = Math.max(...l); return applyGains(img, l.map(v => v / m)); };
export const correctWith = (captured, gains) => applyGains(captured, gains);

/** Gray world: the scene's average linear colour, assumed to be the light. */
export function grayWorld(img) {
  const s = [0, 0, 0];
  for (let i = 0; i < img.r.length; i++) {
    s[0] += decodeTransfer('sRGB', img.r[i]); s[1] += decodeTransfer('sRGB', img.g[i]); s[2] += decodeTransfer('sRGB', img.b[i]);
  }
  return s;
}

/** Mean linear colour in a (2·radius+1)² square: the eyedropper. */
export function sampleLinear(img, x, y, radius = 2) {
  const s = [0, 0, 0];
  for (let yy = Math.max(y - radius, 0); yy <= Math.min(y + radius, img.height - 1); yy++) {
    for (let xx = Math.max(x - radius, 0); xx <= Math.min(x + radius, img.width - 1); xx++) {
      const i = yy * img.width + xx;
      s[0] += decodeTransfer('sRGB', img.r[i]); s[1] += decodeTransfer('sRGB', img.g[i]); s[2] += decodeTransfer('sRGB', img.b[i]);
    }
  }
  return s;
}

const CHECKER = [0x735244, 0xC29682, 0x627A9D, 0x576C43, 0x8580B1, 0x67BDAA, 0xD67E2C, 0x505BA6, 0xC15A63, 0x5E3C6C, 0x9DBC40, 0xE0A32E,
  0x383D96, 0x469449, 0xAF363C, 0xE7C71F, 0xBB5695, 0x0885A1, 0xF3F3F2, 0xC8C8C8, 0xA0A0A0, 0x7A7A79, 0x555555, 0x343434];

/** 6×4 colour-checker chart (published sRGB approximations), bottom row neutral. */
export function checkerChart(width = 360) {
  const cell = Math.floor(width / 6), gap = Math.max(Math.floor(cell / 12), 2), height = cell * 4, n = width * height;
  const img = { width, height, r: new Float32Array(n).fill(0.1), g: new Float32Array(n).fill(0.1), b: new Float32Array(n).fill(0.1) };
  CHECKER.forEach((v, k) => {
    const cx = (k % 6) * cell, cy = Math.floor(k / 6) * cell;
    for (let y = cy + gap; y < cy + cell - gap; y++) for (let x = cx + gap; x < Math.min(cx + cell - gap, width); x++) {
      const i = y * width + x; img.r[i] = ((v >> 16) & 255) / 255; img.g[i] = ((v >> 8) & 255) / 255; img.b[i] = (v & 255) / 255;
    }
  });
  return img;
}

/** Centre of the "neutral 6.5" patch (bottom row, third from left). */
export function grayPatchCentre(width = 360) { const cell = Math.floor(width / 6); return [2 * cell + (cell >> 1), 3 * cell + (cell >> 1)]; }

// ---------- Gamuts (Lesson 13) ----------

export const GAMUTS = [
  { name: 'Rec.709 / sRGB', corners: [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]] },
  { name: 'DCI-P3', corners: [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]] },
  { name: 'Rec.2020', corners: [[0.708, 0.292], [0.170, 0.797], [0.131, 0.046]] },
];
export const D65 = [0.3127, 0.3290];

// CIE 1931 2° chromaticities of monochromatic light, 380–700 nm in 5 nm steps.
const SPECTRAL = [
  0.1741, 0.0050, 0.1740, 0.0050, 0.1738, 0.0049, 0.1736, 0.0049, 0.1733, 0.0048, 0.1730, 0.0048, 0.1726, 0.0048, 0.1721, 0.0048,
  0.1714, 0.0051, 0.1703, 0.0058, 0.1689, 0.0069, 0.1669, 0.0086, 0.1644, 0.0109, 0.1611, 0.0138, 0.1566, 0.0177, 0.1510, 0.0227,
  0.1440, 0.0297, 0.1355, 0.0399, 0.1241, 0.0578, 0.1096, 0.0868, 0.0913, 0.1327, 0.0687, 0.2007, 0.0454, 0.2950, 0.0235, 0.4127,
  0.0082, 0.5384, 0.0039, 0.6548, 0.0139, 0.7502, 0.0389, 0.8120, 0.0743, 0.8338, 0.1142, 0.8262, 0.1547, 0.8059, 0.1929, 0.7816,
  0.2296, 0.7543, 0.2658, 0.7243, 0.3016, 0.6923, 0.3373, 0.6589, 0.3731, 0.6245, 0.4087, 0.5896, 0.4441, 0.5547, 0.4788, 0.5202,
  0.5125, 0.4866, 0.5448, 0.4544, 0.5752, 0.4242, 0.6029, 0.3965, 0.6270, 0.3725, 0.6482, 0.3514, 0.6658, 0.3340, 0.6801, 0.3197,
  0.6915, 0.3083, 0.7006, 0.2993, 0.7079, 0.2920, 0.7140, 0.2859, 0.7190, 0.2809, 0.7230, 0.2770, 0.7260, 0.2740, 0.7283, 0.2717,
  0.7300, 0.2700, 0.7311, 0.2689, 0.7320, 0.2680, 0.7327, 0.2673, 0.7334, 0.2666, 0.7340, 0.2660, 0.7344, 0.2656, 0.7346, 0.2654,
  0.7347, 0.2653];

/** Chromaticity of pure light at `nm` (linear interpolation of the CIE table). */
export function spectralXY(nm) {
  const f = (Math.min(Math.max(nm, 380), 700) - 380) / 5, i = Math.min(Math.floor(f), 63), t = f - i;
  return [SPECTRAL[2 * i] + (SPECTRAL[2 * i + 2] - SPECTRAL[2 * i]) * t, SPECTRAL[2 * i + 1] + (SPECTRAL[2 * i + 3] - SPECTRAL[2 * i + 1]) * t];
}

/** Spectral locus, 380–700 nm; closing it back to 380 nm draws the line of purples. */
export const LOCUS = Array.from({ length: SPECTRAL.length / 2 }, (_, i) => [SPECTRAL[2 * i], SPECTRAL[2 * i + 1]]);

export function inPolygon([px, py], poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [ax, ay] = poly[i], [bx, by] = poly[j];
    if ((ay > py) !== (by > py) && px < (bx - ax) * (py - ay) / (by - ay) + ax) inside = !inside;
  }
  return inside;
}
function nearEdge([px, py], poly, tol = 1e-4) {
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [ax, ay] = poly[j], [bx, by] = poly[i], dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
    const t = len2 ? Math.min(Math.max(((px - ax) * dx + (py - ay) * dy) / len2, 0), 1) : 0;
    if (Math.hypot(ax + t * dx - px, ay + t * dy - py) <= tol) return true;
  }
  return false;
}
/** Points on an edge or corner count as inside (a primary is in its own gamut). */
export const gamutContains = (g, p) => inPolygon(p, g.corners) || nearEdge(p, g.corners);
export const isVisible = p => inPolygon(p, LOCUS) || nearEdge(p, LOCUS);

/** Nearest displayable sRGB colour for a chromaticity: clip negatives, scale so the largest channel is 1. */
export function chromaToSRGB([x, y]) {
  const X = x / y, Z = (1 - x - y) / y;
  const lin = [3.2406 * X - 1.5372 - 0.4986 * Z, -0.9689 * X + 1.8758 + 0.0415 * Z, 0.0557 * X - 0.2040 + 1.0570 * Z].map(v => Math.max(v, 0));
  const m = Math.max(...lin, 1e-9);
  return lin.map(v => encodeTransfer('sRGB', v / m));
}
