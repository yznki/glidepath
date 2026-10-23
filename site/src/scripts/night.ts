// Page driver. One clock (the GSAP ticker) drives Lenis, the scene, the card and every readout.
// The only scroll input is ScrollTrigger on the descent section, which feeds drive.target.
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';
import { createScene, camPose, cardPose, fixPose, type Scene } from './scene';
import { setupDemo } from './demo';

gsap.registerPlugin(ScrollTrigger);

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const mobile = matchMedia('(max-width: 900px)').matches;
const params = new URLSearchParams(location.search);
const stillMode = params.has('still'); // used once to export the hero still (see scripts/still.mjs)

// Fix anchors: scroll progress where each fix passes, and the altitude readout there.
const FIXES = [
  { at: 0.12, ft: 2400, stage: 'Gathering' },
  { at: 0.37, ft: 1600, stage: 'Reviewing' },
  { at: 0.62, ft: 800, stage: 'Checking' },
  { at: 1, ft: 0, stage: 'Landing' },
];
const ALT = [
  [0, 3000],
  ...FIXES.map((f) => [f.at, f.ft] as [number, number]),
];
const altitude = (p: number) => {
  for (let i = 1; i < ALT.length; i++) {
    const [p1, a1] = ALT[i];
    const [p0, a0] = ALT[i - 1];
    if (p <= p1) return a0 + ((a1 - a0) * (p - p0)) / (p1 - p0);
  }
  return 0;
};
// The active fix is the next one ahead: its copy and stage word show until the aircraft passes it.
const activeFix = (p: number) => {
  for (let k = 0; k < FIXES.length; k++) if (p < FIXES[k].at - 1e-6) return k;
  return FIXES.length - 1;
};

const $ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => root.querySelector<T>(sel);
const $$ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) =>
  Array.from(root.querySelectorAll<T>(sel));

const html = document.documentElement;
const drive = { p: 0, target: 0, t: 0, intro: 0, visible: true };
let scene: Scene | null = null;
let introStart = -1;

// Reduced motion: no Lenis, no GL, no scrub. Everything is visible and static (CSS handles the rest).
let lenis: Lenis | null = null;
if (!reduced && !stillMode) {
  lenis = new Lenis({ lerp: 0.1, wheelMultiplier: 1, touchMultiplier: 1.2, anchors: true });
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add((time) => lenis?.raf(time * 1000));
  gsap.ticker.lagSmoothing(0);
}

function setupScene(descent: HTMLElement, hero: HTMLElement) {
  if (reduced) return;
  const host = $('#gl');
  if (!host) return;
  scene = createScene(host, mobile);
  if (!scene) return;
  html.classList.add('gl-on');
  addEventListener('resize', () => scene?.resize(), { passive: true });
  // Render only while the hero or the descent is on screen.
  ScrollTrigger.create({
    trigger: hero,
    start: 'top bottom',
    endTrigger: descent,
    end: 'bottom top',
    onToggle: (s) => (drive.visible = s.isActive),
  });
}

function setupDescent(descent: HTMLElement) {
  const fixEls = $$<HTMLElement>('[data-fix]', descent);
  const labels = $$<HTMLElement>('[data-label]', descent);
  const rails = $$<HTMLElement>('[data-rail]', descent);
  const card = $<HTMLElement>('[data-card]', descent);
  const stageEl = $<HTMLElement>('[data-card-stage]', descent);
  const callersEl = $<HTMLElement>('[data-card-callers]', descent);
  const findings = $$<HTMLElement>('[data-finding]', descent);
  const altEl = $<HTMLElement>('[data-alt]', descent);
  const verdictEl = $<HTMLElement>('[data-card-verdict]', descent);
  let active = -1;
  let altShown = -1;
  let verdictLanded = false;

  ScrollTrigger.create({
    trigger: descent,
    start: 'top top',
    end: 'bottom bottom',
    onUpdate: (s) => (drive.target = s.progress),
  });

  const setActive = (k: number) => {
    if (k === active) return;
    active = k;
    fixEls.forEach((el, i) => el.classList.toggle('is-active', i === k));
    rails.forEach((el, i) => el.classList.toggle('is-current', i === k));
    labels.forEach((el, i) => el.classList.toggle('is-current', i === k));
    if (stageEl) stageEl.textContent = FIXES[k].stage;
  };

  const frame = () => {
    const p = drive.p;
    const k = activeFix(p);
    setActive(k);

    // Altitude readout (live).
    if (altEl) {
      const ft = Math.round(altitude(p) / 10) * 10;
      if (ft !== altShown) {
        altShown = ft;
        altEl.textContent = `${ft.toLocaleString('en-US')} FT`;
      }
    }

    // Card state: callers tick up while gathering; findings appear during review; one is dropped at check.
    if (callersEl) {
      const n = Math.round(14 * Math.min(1, p / 0.12));
      callersEl.textContent = `${n} callers`;
    }
    findings.forEach((el, i) => {
      const on = p >= 0.14 + i * 0.07;
      el.classList.toggle('is-on', on);
      el.classList.toggle('is-dropped', i === 1 && p >= 0.42);
    });
    if (verdictEl) {
      const landed = p >= 0.62;
      if (landed !== verdictLanded) {
        verdictLanded = landed;
        verdictEl.classList.toggle('is-changes', landed);
        verdictEl.textContent = landed ? 'Changes' : 'Pending';
      }
    }

    if (!drive.visible || !scene) return;

    // Card: a world point projected each frame, so it stays on the same path as the camera.
    if (card) {
      const c = cardPose(p);
      const s = scene.project(c.x, c.y, c.z);
      // Phones: a smaller card, sitting lower so the copy keeps the top of the screen.
      const k = mobile ? 0.8 : 1;
      const scale = k * Math.min(1.2, Math.max(0.42, 90 / s.depth));
      const lift = mobile ? window.innerHeight * 0.14 : 0;
      const bob = Math.sin(drive.t * 0.9) * 2; // idle drift, a few pixels
      card.style.transform = `translate3d(${s.x - 160 * scale}px, ${s.y - 110 * scale + bob + lift}px, 0) scale(${scale})`;
    }
    // Runway-side labels: placed where each fix sits, hidden once the aircraft has passed it.
    labels.forEach((el, i) => {
      const f = fixPose(FIXES[i].at);
      const s = scene!.project(f.x, f.y, f.z);
      const dist = camPose(p).z - f.z;
      // Fades in as the label comes up the runway, out as the aircraft nears it.
      const fade = s.ahead ? Math.max(0, Math.min(1, (dist - 6) / 10, (64 - dist) / 24)) : 0;
      el.style.transform = `translate3d(${s.x}px, ${s.y}px, 0)`;
      el.style.opacity = String(fade);
    });
  };

  return frame;
}

function setupCurrentGauges() {
  // Gauges fill when they reach the viewport (CSS does the animation; without JS they are full).
  $$<HTMLElement>('[data-gauge]').forEach((el) => {
    if (reduced) return;
    ScrollTrigger.create({ trigger: el, start: 'top 85%', once: true, onEnter: () => el.classList.add('is-in') });
  });
}

function setupChecklist() {
  $$<HTMLElement>('[data-check]').forEach((el) => {
    if (reduced) return el.classList.add('is-ticked');
    ScrollTrigger.create({
      trigger: el,
      start: 'top 55%',
      once: true,
      onEnter: () => el.classList.add('is-ticked'),
    });
  });
}

function setupReveals() {
  if (reduced) return;
  $$<HTMLElement>('[data-reveal]').forEach((el) => {
    ScrollTrigger.create({ trigger: el, start: 'top 90%', once: true, onEnter: () => el.classList.add('is-in') });
  });
}

function setupGallery(gallery: HTMLElement) {
  const track = $<HTMLElement>('[data-gallery]', gallery);
  if (!track || reduced || mobile) return;
  gsap.fromTo(
    track,
    { rotateY: -9 },
    { rotateY: 9, ease: 'none', scrollTrigger: { trigger: gallery, start: 'top bottom', end: 'bottom top', scrub: true } },
  );
  // Pointer tilt on the hovered frame (fine pointers only).
  if (matchMedia('(hover: hover) and (pointer: fine)').matches) {
    $$<HTMLElement>('[data-tilt]', gallery).forEach((el) => {
      const rx = gsap.quickTo(el, 'rotateX', { duration: 0.8, ease: 'expo.out' });
      const ry = gsap.quickTo(el, 'rotateY', { duration: 0.8, ease: 'expo.out' });
      el.addEventListener('pointermove', (e) => {
        const r = el.getBoundingClientRect();
        rx((0.5 - (e.clientY - r.top) / r.height) * 12);
        ry(((e.clientX - r.left) / r.width - 0.5) * 12);
      });
      el.addEventListener('pointerleave', () => {
        rx(0);
        ry(0);
      });
    });
  }
}

function setupFillButtons() {
  if (matchMedia('(pointer: coarse)').matches || reduced) return;
  $$<HTMLElement>('[data-fill]').forEach((btn) => {
    const fill = $<HTMLElement>('.btn__fill', btn);
    if (!fill) return;
    const at = (e: PointerEvent) => {
      const r = btn.getBoundingClientRect();
      return `${e.clientX - r.left}px ${e.clientY - r.top}px`;
    };
    // Left-to-right fill, as the hold-to-post liquid: in from the left, out to the right (280 ms).
    btn.addEventListener('pointerenter', () => {
      btn.classList.add('is-filled');
      gsap.fromTo(fill, { clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0% 0 0)', duration: 0.28, ease: 'power2.out', overwrite: true });
    });
    btn.addEventListener('pointerleave', () => {
      btn.classList.remove('is-filled');
      gsap.to(fill, { clipPath: 'inset(0 0 0 100%)', duration: 0.28, ease: 'power2.in', overwrite: true });
    });
  });
}

function setupCopy() {
  $$<HTMLButtonElement>('[data-copy]').forEach((btn) => {
    const label = $<HTMLElement>('.copy-label', btn) ?? btn;
    const text = label.textContent ?? 'Copy';
    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(btn.dataset.copy ?? '');
        label.textContent = 'Copied';
      } catch {
        label.textContent = 'Select the text';
      }
      setTimeout(() => (label.textContent = text), 1800);
    });
  });
}

function setupNav() {
  const nav = $('.nav');
  if (!nav || reduced) return;
  let last = 0;
  ScrollTrigger.create({
    start: 0,
    end: 'max',
    onUpdate: (s) => {
      const y = s.scroll();
      nav.classList.toggle('is-away', y > 160 && y > last && s.direction === 1);
      last = y;
    },
  });
}

function boot() {
  // Page-agnostic behaviour first (the 404 page has none of the home sections).
  setupFillButtons();
  setupCopy();
  setupNav();
  setupReveals();

  const hero = $<HTMLElement>('#hero');
  const descent = $<HTMLElement>('#descent');
  const gallery = $<HTMLElement>('#app');
  if (!hero || !descent) return;

  // Still-frame export: freeze the scene at the hero camera, no DOM motion.
  if (stillMode) {
    html.classList.add('still');
    const sc = createScene($('#gl')!, false);
    if (sc) {
      html.classList.add('gl-on');
      sc.resize();
      sc.render(0, 0, 1);
      (window as unknown as { __still?: boolean }).__still = true;
    }
    return;
  }

  setupScene(descent, hero);
  const frame = setupDescent(descent);
  setupCurrentGauges();
  setupChecklist();
  if (gallery) setupGallery(gallery);
  setupDemo();

  if (!reduced) {
    gsap.ticker.add((t, dt) => {
      drive.t = t;
      const k = 1 - Math.exp(-(dt / 1000) * 5);
      drive.p += (drive.target - drive.p) * k;
      if (Math.abs(drive.target - drive.p) < 0.0005) drive.p = drive.target;
      if (!scene) {
        frame?.();
        return;
      }
      // The approach lights switch on over the first 1.1 s (scene.ts intro gating).
      if (introStart < 0) introStart = t;
      const intro = Math.min(1, (t - introStart) / 1.1);
      drive.intro = intro;
      if (drive.visible) {
        scene.render(drive.p, t, intro);
      }
      frame?.();
    });
  }
  // Refresh ScrollTrigger once everything is in place (the fixed scene changes the descent height).
  requestAnimationFrame(() => ScrollTrigger.refresh());
  addEventListener('load', () => ScrollTrigger.refresh());
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
