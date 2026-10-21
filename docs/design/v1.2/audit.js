// Layout audit: box edges off the 4px grid, ragged right edges in rows, text under 11px, overflow.
(function () {
  const win = document.querySelector('.win').getBoundingClientRect();
  const out = [];
  document.querySelectorAll('.win *').forEach(el => {
    const r = el.getBoundingClientRect(); if (!r.width || !r.height) return;
    const cs = getComputedStyle(el);
    if (parseFloat(cs.fontSize) < 11 && el.textContent.trim() && el.children.length === 0) out.push('small text: ' + el.textContent.trim().slice(0, 30));
    if (el.scrollWidth > el.clientWidth + 1 && cs.overflow !== 'hidden' && !/t|m/.test(el.className) && el.children.length) out.push('overflow: ' + el.className);
    if (r.right > win.right + 0.5 || r.bottom > win.bottom + 0.5) {
      if (!el.closest('.field') && !el.closest('svg')) out.push(`outside window: ${el.tagName}.${el.className} ${Math.round(r.right - win.left)},${Math.round(r.bottom - win.top)}`);
    }
  });
  const ck = sel => document.querySelectorAll(sel).forEach(el => {
    const r = el.getBoundingClientRect(), x = r.left - win.left, y = r.top - win.top, b = r.bottom - win.top;
    [...(/btn|h1/.test(sel) ? [] : [['x', x]]), ['y', y], ['bottom', b]].forEach(([k, v]) => { if (Math.abs(v - Math.round(v / 4) * 4) > 0.6) out.push(`off-grid ${k}=${v.toFixed(1)} ${sel}`); });
  });
  ['h1', '.panel', '.row', '.btn', '.seg', '.sec', '.it', '.rp', '.chk', '.bar', '.verdict', '.cm', '.day', '.brand', '.nav a', '.titlerow'].forEach(ck);
  const pre = document.createElement('pre'); pre.id = 'audit'; pre.textContent = [...new Set(out)].join('\n') || 'clean';
  document.body.appendChild(pre);
})();
