// Mirrors Tests/DSPTests.swift so the website and the Mac app compute the same things.
// Run: node --test web/tests/
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as D from '../dsp.js';

const fs = 44100;
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, `${msg ?? ''} expected ${b} ± ${tol}, got ${a}`);

test('aliased frequency folds about Nyquist', () => {
  near(D.aliasedFrequency(1000, 8000), 1000, 1e-9);
  near(D.aliasedFrequency(30000, 44100), 14100, 1e-9);
  near(D.aliasedFrequency(9000, 8000), 1000, 1e-9);
});

test('FFT peak lands on the right bin with the right amplitude', () => {
  const n = 4096, bin = 100;
  const m = D.magnitudeSpectrum(D.sine(bin * fs / n, 0.5, fs, n));
  assert.equal(m.indexOf(Math.max(...m)), bin);
  near(m[bin], 0.5, 1e-3);
});

test('Hann window reduces leakage for a between-bin tone', () => {
  const x = D.sine(10.5, 1, 128, 128);
  const rect = D.decibels(D.magnitudeSpectrum(x, 'Rectangular')), hann = D.decibels(D.magnitudeSpectrum(x, 'Hann'));
  assert.ok(hann[50] < rect[50] - 30);
});

test('quantization SNR rises about 6 dB per bit', () => {
  const x = D.sine(997, 0.9, fs, 16384);
  const s8 = D.snr(x, D.quantize(x, 8)), s12 = D.snr(x, D.quantize(x, 12));
  near(s12 - s8, 24, 3); near(s8, 6.02 * 8 + 1.76, 3);
});

test('convolution matches its definition; sparse equals dense', () => {
  assert.deepEqual(Array.from(D.convolve([1, 2, 3, 4, 5], [1, 0.5, 0.25])), [1, 2.5, 4.25, 6, 7.75]);
  const x = D.noise(300);
  const dense = D.convolve(x, D.echoKernel(40, 0.5)), sparse = D.sparseConvolve(x, [[0, 1], [40, 0.5]]);
  dense.forEach((v, i) => near(v, sparse[i], 1e-5));
});

test('biquad low-pass: flat passband, −3 dB at cutoff, −40 dB/decade', () => {
  const lp = D.biquad('Low-pass', 1000, Math.SQRT1_2, 0, fs);
  near(lp.responseDB(20), 0, 0.1); near(lp.responseDB(1000), -3, 0.2);
  assert.ok(lp.responseDB(10000) < -38);
  near(D.biquad('Peak EQ', 3000, 1, 9, fs).responseDB(3000), 9, 0.05);
});

test('high-pass removes a low tone', () => {
  const out = D.biquad('High-pass', 2000, Math.SQRT1_2, 0, fs).process(D.sine(100, 1, fs, 8192));
  const rms = a => Math.sqrt(a.reduce((s, v) => s + v * v, 0) / a.length);
  assert.ok(rms(out.slice(2000)) < 0.01 * Math.SQRT1_2);
});

test('compressor static curve and gain reduction', () => {
  const c = D.compressor({ thresholdDB: -20, ratio: 4, attackMs: 5, releaseMs: 100 });
  assert.equal(c.outputLevel(-30), -30); assert.equal(c.outputLevel(-8), -17);
  const x = D.drumLoop(fs, 1);
  const { output, gainDB } = D.compressor({ thresholdDB: -24, ratio: 8, attackMs: 1, releaseMs: 80 }).process(x, fs);
  assert.ok(Math.min(...gainDB) < -6);
  assert.ok(D.peak(output) < D.peak(x));
});

test('DCT round trip is lossless and a flat block is all DC', () => {
  const block = Array.from({ length: 64 }, (_, i) => ((i * 37) % 255) - 128);
  D.idct8x8(D.dct8x8(block)).forEach((v, i) => near(v, block[i], 1e-6));
  const c = D.dct8x8(Array(64).fill(10));
  near(c[0], 80, 1e-9);
  assert.ok(Math.max(...Array.from(c.slice(1), Math.abs)) < 1e-9);
});

test('JPEG: lower quality → more zeros, lower PSNR', () => {
  const w = 64, img = D.makeImage(w, w, Float32Array.from({ length: w * w }, (_, i) => ((i % w) > 32 ? 0.9 : 0.1) * (0.5 + 0.5 * Math.sin(i / 50))));
  const hi = D.jpegRoundTrip(img, 90), lo = D.jpegRoundTrip(img, 10);
  assert.ok(lo.zeroFraction > hi.zeroFraction); assert.ok(hi.psnr > lo.psnr);
});

test('blur keeps flat regions, Sobel finds edges', () => {
  const flat = D.makeImage(16, 16, new Float32Array(256).fill(0.5));
  D.applyKernel('Gaussian blur', 2, flat).pixels.forEach(v => near(v, 0.5, 1e-5));
  const step = D.makeImage(16, 16, Float32Array.from({ length: 256 }, (_, i) => (i % 16 >= 8 ? 1 : 0.5)));
  const e = D.applyKernel('Edges (Sobel magnitude)', 1, step);
  assert.ok(D.px(e, 8, 8) > 0.5); near(D.px(e, 2, 8), 0, 1e-6);
});

test('spectrogram of a chirp rises', () => {
  const cols = D.spectrogram(D.chirp(500, 8000, fs, fs), 1024, 512);
  assert.equal(cols[0].length, 513);
  const argmax = c => c.indexOf(Math.max(...c));
  assert.ok(argmax(cols.at(-1)) > argmax(cols[0]) * 5);
});

test('wagon wheel: 3 rev/s, 8 spokes, 24 fps looks frozen; 2 rev/s looks backwards', () => {
  near(D.apparentWheelSpeed(3, 24, 8), 0, 1e-9);
  near(D.apparentWheelSpeed(2, 24, 8), -1, 1e-9);
});

test('shared course.json is well formed', () => {
  const course = JSON.parse(readFileSync(new URL('../../content/course.json', import.meta.url)));
  const lessons = course.modules.flatMap(m => m.lessons);
  assert.equal(course.modules.length, 4); assert.equal(lessons.length, 12);
  assert.equal(new Set(lessons.map(l => l.demo)).size, 12, 'every demo used once');
  assert.equal(new Set(lessons.map(l => l.id)).size, 12, 'unique lesson ids');
  for (const l of lessons) {
    assert.equal(l.blocks.filter(b => b.type === 'demo').length, 1, l.id);
    assert.ok(l.blocks.some(b => b.type === 'inPractice'), `${l.id} needs an In practice box`);
    for (const q of l.quiz) assert.ok(q.answer >= 0 && q.answer < q.choices.length, l.id);
  }
});
