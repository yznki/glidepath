// The Glidepath mark as SVG: striped disc, glide slot ending at the amber touchdown dot.
// t (0..1) moves the dot along the slot (1 = touchdown); stripes = count.
let _id = 0;
const LIGHT = new URLSearchParams(location.search).has('light');
if (LIGHT) document.documentElement.dataset.theme = 'light';
const INK = LIGHT ? '#111113' : '#F5F5F7', TRACK = LIGHT ? '#c9c9cf' : '#2c2c30', DONE = LIGHT ? '#111113' : '#F5F5F7';
function mark(size, opts = {}) {
  const { t = 1, n = 11, ink = INK, dot = '#FFB020', slot = true } = opts;
  const R = 512 * 0.62, cx = 512, cy = 512, p = 2 * R / n, h = p * 0.56, w = p * 1.35;
  const ang = 24, rad = ang * Math.PI / 180, ex = cx + R * 0.28, ey = cy + R * 0.30;
  const id = 'm' + (++_id);
  let stripes = '';
  for (let i = 0; i < n; i++) stripes += `<rect x="${cx - R}" y="${cy - R + p * (i + .5) - h / 2}" width="${2 * R}" height="${h}"/>`;
  // where the slot enters the disc: walk back from touchdown along the slot direction
  const dx = -Math.cos(rad), dy = -Math.sin(rad);
  const fx = ex - cx, fy = ey - cy, b = fx * dx + fy * dy, c = fx * fx + fy * fy - R * R;
  const s = -b + Math.sqrt(b * b - c);           // distance from touchdown back to the edge
  const px = ex + dx * s * (1 - t), py = ey + dy * s * (1 - t);
  return `<svg width="${size}" height="${size}" viewBox="${cx - R - 4} ${cy - R - 4} ${2 * R + 8} ${2 * R + 8}">
  <defs><mask id="${id}" maskUnits="userSpaceOnUse" x="-2000" y="-2000" width="6000" height="6000">
  <circle cx="${cx}" cy="${cy}" r="${R}" fill="#fff"/>
  ${slot ? `<rect x="-2000" y="${-w / 2}" width="${2000 + w / 2}" height="${w}" rx="${w / 2}" fill="#000" transform="translate(${ex} ${ey}) rotate(${ang})"/>` : ''}
  </mask></defs>
  <g mask="url(#${id})" fill="${ink}">${stripes}</g>
  ${slot ? `<circle cx="${px}" cy="${py}" r="${w * 0.3}" fill="${dot}"/>` : ''}</svg>`;
}
const ICON = {
  overview: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.2"/><path d="M3 6.5h10M2.4 9.5h11.2"/></svg>',
  reviews: '<svg viewBox="0 0 16 16"><path d="M3 4h10M3 8h10M3 12h6"/></svg>',
  repos: '<svg viewBox="0 0 16 16"><circle cx="4.5" cy="3.8" r="1.6"/><circle cx="4.5" cy="12.2" r="1.6"/><circle cx="11.5" cy="6" r="1.6"/><path d="M4.5 5.4v5.2M11.5 7.6c0 2.5-7 1.5-7 3"/></svg>',
  schedule: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.2"/><path d="M8 4.5V8l2.5 1.5"/></svg>',
  settings: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="2.2"/><path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M3.6 12.4 5 11M11 5l1.4-1.4"/></svg>',
};
function sidebar(active) {
  const items = [['overview', 'Overview'], ['reviews', 'Reviews', '3'], ['repos', 'Repos'], ['schedule', 'Schedule'], ['settings', 'Settings']];
  return `<div class="side"><div class="brand">${mark(22, { n: 7 })}<b>Glidepath</b></div>
  <div class="scope">2 repos · yznki</div>
  <nav class="nav">${items.map(([k, l, c]) => `<a class="${k === active ? 'on' : ''}">${ICON[k]}${l}${c ? `<span class="count">${c}</span>` : ''}</a>`).join('')}</nav>
  <div class="foot"><b>Next sweep 7:00 PM</b>in 2 h 41 min · v1.2.0</div></div>`;
}
document.querySelectorAll('[data-mark]').forEach(el => {
  el.innerHTML = mark(+el.dataset.mark, { t: el.dataset.t ? +el.dataset.t : 1, n: el.dataset.n ? +el.dataset.n : 11 });
});
document.querySelectorAll('[data-side]').forEach(el => { el.outerHTML = sidebar(el.dataset.side); });
// A full-width band of stripes continuous with the disc; the glide slot runs in from the far left.
function heroField(W, D, opts = {}) {
  const { n = 11, t = 1, faint = 0.07 } = opts;
  const id = 'f' + (++_id), H = D, cx = W / 2, cy = H / 2, R = D / 2, p = 2 * R / n, h = p * 0.56, w = p * 1.35;
  const ang = 24, rad = ang * Math.PI / 180, ex = cx + R * 0.28, ey = cy + R * 0.30;
  let stripes = '';
  for (let i = 0; i < n; i++) stripes += `<rect x="0" y="${p * (i + .5) - h / 2}" width="${W}" height="${h}"/>`;
  const slot = `<rect x="-3000" y="${-w / 2}" width="${3000 + w / 2}" height="${w}" rx="${w / 2}" fill="#000" transform="translate(${ex} ${ey}) rotate(${ang})"/>`;
  const dx = -Math.cos(rad), dy = -Math.sin(rad), fx = ex - cx, fy = ey - cy, b = fx * dx + fy * dy, c = fx * fx + fy * fy - R * R;
  const s = (-b + Math.sqrt(b * b - c)) * 1.6, px = ex + dx * s * (1 - t), py = ey + dy * s * (1 - t);
  return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" style="display:block;overflow:visible">
  <defs><linearGradient id="${id}g"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".3" stop-color="#fff" stop-opacity="${faint}"/><stop offset=".7" stop-color="#fff" stop-opacity="${faint}"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <mask id="${id}a" maskUnits="userSpaceOnUse" x="-3000" y="-3000" width="9000" height="9000"><rect width="${W}" height="${H}" fill="url(#${id}g)"/><circle cx="${cx}" cy="${cy}" r="${R + p * .6}" fill="#000"/>${slot}</mask>
  <mask id="${id}b" maskUnits="userSpaceOnUse" x="-3000" y="-3000" width="9000" height="9000"><circle cx="${cx}" cy="${cy}" r="${R}" fill="#fff"/>${slot}</mask></defs>
  <g mask="url(#${id}a)" fill="${INK}">${stripes}</g><g mask="url(#${id}b)" fill="${INK}">${stripes}</g>
  <circle cx="${px}" cy="${py}" r="${w * 0.3}" fill="#FFB020"/></svg>`;
}
document.querySelectorAll('[data-field]').forEach(el => {
  el.innerHTML = heroField(+el.dataset.field, +el.dataset.d, { t: el.dataset.t ? +el.dataset.t : 1 });
});
// Onboarding rail: the glide slope; step 1 sits on the pane's title line (y 148), the last step lands on the runway.
function approach(cur) {
  const steps = ['Welcome', 'Your tools', 'Repos', 'How to review', 'Schedule', 'First sweep'];
  const x0 = 48, y0 = 148, x1 = 248, y1 = 628, last = steps.length - 1;
  const pt = i => [x0 + (x1 - x0) * i / last, y0 + (y1 - y0) * i / last];
  const [cx, cy] = pt(cur);
  let svg = `<svg width="400" height="720"><line x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}" stroke="${TRACK}" stroke-width="2"/>
  <line x1="${x0}" y1="${y0}" x2="${cx}" y2="${cy}" stroke="${DONE}" stroke-width="2"/>
  <rect x="${x1 - 8}" y="${y1 + 18}" width="120" height="3" rx="1.5" fill="${cur === last ? DONE : TRACK}"/>`;
  steps.forEach((s, i) => { if (i !== cur) { const [x, y] = pt(i); svg += `<circle cx="${x}" cy="${y}" r="4" fill="${i < cur ? DONE : TRACK}"/>`; } });
  svg += `<circle cx="${cx}" cy="${cy}" r="14" fill="#FFB020" opacity=".16"/><circle cx="${cx}" cy="${cy}" r="7" fill="#FFB020"/></svg>`;
  const labels = steps.map((s, i) => { const [x, y] = pt(i); const cls = i < cur ? 'done' : i === cur ? 'cur' : '';
    return `<div class="stp ${cls}" style="left:${x + 20}px;top:${y - 9}px">${s}</div>`; }).join('');
  return svg + labels + `<div class="brand obrand">${mark(22, { n: 7 })}<b>Glidepath</b></div>`;
}
document.querySelectorAll('[data-approach]').forEach(el => { el.innerHTML = approach(+el.dataset.approach); });
