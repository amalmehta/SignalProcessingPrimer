// Small SVG line chart: shared x axis, optional log x, dashed reference series, legend for ≥ 2 series,
// and a hover crosshair with a tooltip. Colors come from CSS tokens so both themes work.

const SVGNS = 'http://www.w3.org/2000/svg';
const el = (name, attrs = {}, parent) => {
  const n = document.createElementNS(SVGNS, name);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
  if (parent) parent.appendChild(n);
  return n;
};

export function fmt(v) {
  const a = Math.abs(v);
  if (a >= 1000) return v.toLocaleString(undefined, { maximumFractionDigits: 0 });
  if (a >= 100) return v.toFixed(0);
  if (a >= 1) return v.toFixed(2).replace(/\.?0+$/, '');
  return v.toFixed(3).replace(/\.?0+$/, '') || '0';
}

function niceTicks(lo, hi, count = 5) {
  const span = hi - lo || 1, raw = span / count, mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map(m => m * mag).find(s => span / s <= count) || mag * 10;
  const ticks = [];
  for (let t = Math.ceil(lo / step) * step; t <= hi + step * 1e-9; t += step) ticks.push(+t.toPrecision(12));
  return ticks;
}

function logTicks(lo, hi) {
  const ticks = [];
  for (let e = Math.floor(Math.log10(lo)); e <= Math.ceil(Math.log10(hi)); e++) { const t = 10 ** e; if (t >= lo && t <= hi) ticks.push(t); }
  return ticks;
}

/**
 * series: [{name, points: [[x, y], …], color: 'var(--s1)', dashed?, dots?}]
 * opts: {xLabel, yLabel, yDomain?, xDomain?, xLog?, height?}
 */
export class LinePlot {
  constructor(container, opts = {}) {
    this.opts = { height: 220, ...opts };
    this.root = document.createElement('figure');
    this.root.className = 'plot';
    container.appendChild(this.root);
    this.svg = el('svg', { role: 'img' }, this.root);
    this.legend = document.createElement('figcaption');
    this.legend.className = 'legend';
    this.root.appendChild(this.legend);
    this.tip = document.createElement('div');
    this.tip.className = 'tip'; this.tip.hidden = true;
    this.root.appendChild(this.tip);
    this.series = [];
    new ResizeObserver(() => this.draw()).observe(this.root);
  }

  update(series, opts) {
    this.series = series;
    if (opts) Object.assign(this.opts, opts);
    this.draw();
  }

  draw() {
    const W = this.root.clientWidth || 600, H = this.opts.height, { xLog } = this.opts;
    const m = { l: 52, r: 12, t: 12, b: 40 };
    const svg = this.svg;
    svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
    svg.setAttribute('width', W); svg.setAttribute('height', H);
    svg.setAttribute('aria-label', `${this.opts.yLabel} against ${this.opts.xLabel}`);
    svg.replaceChildren();

    const all = this.series.flatMap(s => s.points);
    if (!all.length) return;
    const xs = all.map(p => p[0]), ys = all.map(p => p[1]);
    let [x0, x1] = this.opts.xDomain || [Math.min(...xs), Math.max(...xs)];
    let [y0, y1] = this.opts.yDomain || (() => { const lo = Math.min(...ys), hi = Math.max(...ys), pad = Math.max((hi - lo) * 0.08, 1e-3); return [lo - pad, hi + pad]; })();
    if (x1 === x0) x1 = x0 + 1;
    const pw = W - m.l - m.r, ph = H - m.t - m.b;
    const sx = xLog ? x => m.l + (Math.log10(x) - Math.log10(x0)) / (Math.log10(x1) - Math.log10(x0)) * pw
                    : x => m.l + (x - x0) / (x1 - x0) * pw;
    const sy = y => m.t + (1 - (Math.min(Math.max(y, y0), y1) - y0) / (y1 - y0)) * ph;
    this.scale = { sx, x0, x1, m, pw, xLog };

    const grid = el('g', { class: 'grid' }, svg);
    for (const t of niceTicks(y0, y1)) {
      el('line', { x1: m.l, x2: W - m.r, y1: sy(t), y2: sy(t) }, grid);
      el('text', { x: m.l - 6, y: sy(t) + 4, 'text-anchor': 'end' }, grid).textContent = fmt(t);
    }
    for (const t of xLog ? logTicks(x0, x1) : niceTicks(x0, x1, Math.max(2, Math.floor(pw / 90)))) {
      el('line', { x1: sx(t), x2: sx(t), y1: m.t, y2: H - m.b, class: 'v' }, grid);
      el('text', { x: sx(t), y: H - m.b + 16, 'text-anchor': 'middle' }, grid).textContent = fmt(t);
    }
    el('text', { x: m.l + pw / 2, y: H - 4, 'text-anchor': 'middle', class: 'axis-label' }, svg).textContent = this.opts.xLabel;
    el('text', { x: 12, y: m.t + ph / 2, 'text-anchor': 'middle', class: 'axis-label', transform: `rotate(-90 12 ${m.t + ph / 2})` }, svg).textContent = this.opts.yLabel;

    const clip = `clip${Math.random().toString(36).slice(2)}`;
    el('rect', { x: m.l, y: m.t, width: pw, height: ph }, el('clipPath', { id: clip }, svg));
    const marks = el('g', { 'clip-path': `url(#${clip})` }, svg);
    for (const s of this.series) {
      const pts = s.points.filter(p => !xLog || p[0] > 0).map(p => `${sx(p[0]).toFixed(1)},${sy(p[1]).toFixed(1)}`).join(' ');
      el('polyline', { points: pts, fill: 'none', stroke: s.color, 'stroke-width': s.dashed ? 1.5 : 2,
        'stroke-dasharray': s.dashed ? '4 3' : 'none', 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }, marks);
      if (s.dots) for (const p of s.points) el('circle', { cx: sx(p[0]), cy: sy(p[1]), r: 3.5, fill: s.color, stroke: 'var(--surface)', 'stroke-width': 1.5 }, marks);
    }
    this.cross = el('line', { y1: m.t, y2: H - m.b, class: 'cross', visibility: 'hidden' }, svg);

    this.legend.replaceChildren();
    this.legend.hidden = this.series.length < 2;
    for (const s of this.series) {
      const item = document.createElement('span');
      item.innerHTML = `<i style="border-top:2px ${s.dashed ? 'dashed' : 'solid'} ${s.color}"></i>`;
      item.append(s.name);
      this.legend.appendChild(item);
    }

    const hit = el('rect', { x: m.l, y: m.t, width: pw, height: ph, fill: 'transparent' }, svg);
    hit.addEventListener('pointermove', e => this.hover(e));
    hit.addEventListener('pointerleave', () => { this.tip.hidden = true; this.cross.setAttribute('visibility', 'hidden'); });
  }

  hover(e) {
    const { sx, x0, x1, m, pw, xLog } = this.scale;
    const rect = this.svg.getBoundingClientRect();
    const frac = (e.clientX - rect.left - m.l) / pw;
    const x = xLog ? 10 ** (Math.log10(x0) + frac * (Math.log10(x1) - Math.log10(x0))) : x0 + frac * (x1 - x0);
    const rows = this.series.map(s => {
      let best = s.points[0];
      for (const p of s.points) if (Math.abs(p[0] - x) < Math.abs(best[0] - x)) best = p;
      return `<div><i style="background:${s.color}"></i>${this.series.length > 1 ? s.name + ': ' : ''}<b>${fmt(best[1])}</b></div>`;
    });
    this.tip.innerHTML = `<div class="tip-x">${this.opts.xLabel}: ${fmt(x)}</div>${rows.join('')}`;
    this.tip.hidden = false;
    const cx = sx(x);
    this.cross.setAttribute('x1', cx); this.cross.setAttribute('x2', cx); this.cross.setAttribute('visibility', 'visible');
    const left = Math.min(Math.max(cx + 10, 0), this.root.clientWidth - this.tip.offsetWidth - 4);
    this.tip.style.left = `${cx + 10 + this.tip.offsetWidth > this.root.clientWidth ? cx - this.tip.offsetWidth - 10 : left}px`;
  }
}

/** Time-domain series from samples, decimated; x in milliseconds. */
export function wave(name, x, fs, color, extra = {}) {
  return { name, color, points: decimatePairs(x).map(([i, v]) => [i / fs * 1000, v]), ...extra };
}

function decimatePairs(x, target = 600) {
  const step = Math.max(Math.floor(x.length / target), 1), out = [];
  for (let i = 0; i < x.length; i += step) out.push([i, x[i]]);
  return out;
}
