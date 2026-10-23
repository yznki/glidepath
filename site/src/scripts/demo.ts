// The live popover: a Wallet-style stack of glass cards. Click a card to open it, hold to post a held
// review, swipe a held card to discard it. Fixture data only; no links out of the demo.
import { gsap } from 'gsap';

type Verdict = 'approve' | 'changes';
type Card = {
  id: number;
  name: string;
  repo: string;
  n: number;
  title: string;
  verdict: Verdict;
  reason: string;
  held: boolean;
  gone?: boolean;
};

const FIXTURES: Card[] = [
  { id: 1, name: 'Mara', repo: 'lumen/web', n: 482, title: 'Cache invoice PDFs at the edge', verdict: 'changes', reason: 'One finding left: the cache key does not include the tenant.', held: true },
  { id: 2, name: 'Devon', repo: 'lumen/ios', n: 139, title: 'Move auth tokens to the keychain', verdict: 'changes', reason: 'The token is still logged when refresh fails.', held: true },
  { id: 3, name: 'Sol', repo: 'lumen/api', n: 911, title: 'Paginate the orders endpoint', verdict: 'approve', reason: 'Cursor logic is correct, and the backfill script is safe to rerun.', held: true },
  { id: 4, name: 'Kenji', repo: 'lumen/api', n: 907, title: 'Retry webhook delivery with backoff', verdict: 'changes', reason: 'Backoff never caps, so a dead endpoint is retried forever.', held: false },
  { id: 5, name: 'Ines', repo: 'lumen/ios', n: 136, title: 'Dark mode for settings', verdict: 'approve', reason: 'Uses the theme tokens; snapshots updated.', held: false },
];

const HEAD = 66;
const CARD = 64;
const OPEN = 232;
const STRIP = 56;
const WORD: Record<Verdict, string> = { approve: 'Approved', changes: 'Changes' };
const HOLD_MS = 900;

export function setupDemo() {
  const host = document.querySelector<HTMLElement>('[data-demo]');
  if (!host) return;
  const cards: Card[] = FIXTURES.map((c) => ({ ...c }));
  let open: number | null = null;

  host.innerHTML = `
    <div class="pop glass" data-pop>
      <div class="pop__head">
        <span class="instr">Glidepath</span>
        <span class="instr" data-count aria-live="polite"></span>
      </div>
      <div class="pop__stack" data-stack></div>
    </div>`;
  const pop = host.querySelector<HTMLElement>('[data-pop]')!;
  const stack = host.querySelector<HTMLElement>('[data-stack]')!;
  const count = host.querySelector<HTMLElement>('[data-count]')!;

  const initials = (name: string) => name.slice(0, 2).toUpperCase();

  const build = (c: Card) => {
    // The card is a plain container. Its header is the one button (expands); the actions sit beside it.
    const el = document.createElement('div');
    el.className = 'card';
    el.dataset.id = String(c.id);
    el.innerHTML = `
      <div class="card__g">
        <button class="card__toggle" type="button" aria-expanded="false" aria-controls="card-${c.id}">
          <span class="card__row">
            <span class="card__av" aria-hidden="true">${initials(c.name)}</span>
            <span class="card__name">${c.name}</span>
            <span class="card__verdict"><i aria-hidden="true"></i><span></span></span>
          </span>
        </button>
        <div class="card__body" id="card-${c.id}">
          <h3>${c.title}</h3>
          <div class="card__meta"><span>#${c.n}</span><span>${c.repo}</span></div>
          <p class="card__why"></p>
          <div class="card__act">
            <button class="hold" type="button"><span class="liq" aria-hidden="true"></span><span class="hold__label">Hold to post</span></button>
            <button class="discard" type="button">Discard</button>
          </div>
        </div>
      </div>`;
    el.querySelector<HTMLElement>('.card__verdict span')!.textContent = WORD[c.verdict];
    el.querySelector<HTMLElement>('.card__why')!.textContent = c.reason;
    el.querySelector<HTMLElement>('.card__verdict')!.classList.add(c.verdict === 'changes' ? 'is-changes' : 'is-approve');
    if (!c.held) el.querySelector('.card__act')!.remove();
    bind(el, c);
    return el;
  };

  const layout = () => {
    const live = cards.filter((c) => !c.gone);
    const n = live.length;
    const strip = n > 1 ? Math.min(STRIP, 356 / (n - 1)) : 0;
    let j = 0;
    const first = !stack.dataset.laid;
    stack.dataset.laid = '1';
    live.forEach((c, i) => {
      const el = stack.querySelector<HTMLElement>(`[data-id="${c.id}"]`);
      if (!el) return;
      const isOpen = open === c.id;
      el.classList.toggle('is-open', isOpen);
      el.querySelector('.card__toggle')?.setAttribute('aria-expanded', String(isOpen));
      el.style.zIndex = String(isOpen ? 100 : i);
      let y: number;
      // The stack sits below the header (CSS inset), so offsets start at 0.
      if (open === null) y = i * strip;
      else if (isOpen) y = 0;
      else y = OPEN + 14 + Math.min(j, 5) * 7;
      if (open !== null && !isOpen) j++;
      if (isOpen && !first) gsap.fromTo(el.querySelector('.card__body'), { autoAlpha: 0, y: 8 }, { autoAlpha: 1, y: 0, duration: 0.45, delay: 0.08, ease: 'expo.out' });
      gsap.to(el, { y, duration: first ? 0 : 0.55, ease: 'back.out(1.15)', overwrite: 'auto' });
      el.dataset.y = String(y);
    });
    const hold = live.filter((c) => c.held).length;
    count.textContent = live.length === 0 ? 'All clear' : hold ? `${hold} ${hold === 1 ? 'draft' : 'drafts'} to post` : 'All posted';
    const height = live.length === 0 ? 170 : HEAD + (n - 1) * strip + CARD + 12 + (open !== null ? OPEN - CARD + 14 + 30 : 0);
    pop.style.height = `${Math.max(height, 180)}px`;
  };

  const toggle = (id: number) => {
    open = open === id ? null : id;
    layout();
  };

  const remove = (c: Card) => {
    c.gone = true;
    if (open === c.id) open = null;
    const el = stack.querySelector<HTMLElement>(`[data-id="${c.id}"]`);
    if (el) {
      gsap.to(el, { autoAlpha: 0, scale: 0.94, duration: 0.35, ease: 'power2.out', onComplete: () => el.remove() });
    }
    layout();
  };

  function bind(el: HTMLElement, c: Card) {
    const hold = el.querySelector<HTMLButtonElement>('.hold');
    const liq = el.querySelector<HTMLElement>('.liq');
    const discard = el.querySelector<HTMLButtonElement>('.discard');
    const label = el.querySelector<HTMLElement>('.hold__label');
    const toggleBtn = el.querySelector<HTMLButtonElement>('.card__toggle')!;
    let tween: gsap.core.Tween | null = null;
    const scale = () => gsap.getProperty(liq!, 'scaleX') as number;
    const press = () => {
      if (!liq || c.gone) return;
      tween?.kill();
      tween = gsap.to(liq, { scaleX: 1, duration: (1 - scale()) * (HOLD_MS / 1000), ease: 'none', onComplete: commit });
    };
    const release = () => {
      if (!liq) return;
      tween?.kill();
      tween = gsap.to(liq, { scaleX: 0, duration: scale() * 0.35 + 0.05, ease: 'power2.out' });
    };
    const commit = () => {
      if (label) label.textContent = 'Posted';
      hold?.classList.add('is-done');
      c.held = false;
      setTimeout(() => remove(c), 700);
    };
    if (hold) {
      hold.addEventListener('pointerdown', (e) => {
        e.stopPropagation();
        press();
      });
      ['pointerup', 'pointerleave', 'pointercancel'].forEach((t) => hold.addEventListener(t, release));
      hold.addEventListener('click', (e) => e.stopPropagation());
      hold.addEventListener('keydown', (e) => {
        if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) {
          e.preventDefault();
          press();
        }
      });
      hold.addEventListener('keyup', (e) => {
        if (e.key === ' ' || e.key === 'Enter') release();
      });
    }
    discard?.addEventListener('click', (e) => {
      e.stopPropagation();
      remove(c);
    });

    // A click on the header toggles the card. A swipe is not a click.
    let moved = false;
    toggleBtn.addEventListener('click', () => {
      if (moved) {
        moved = false;
        return;
      }
      toggle(c.id);
    });
    toggleBtn.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const live = cards.filter((x) => !x.gone);
        const i = live.indexOf(c);
        const next = live[(i + (e.key === 'ArrowDown' ? 1 : -1) + live.length) % live.length];
        stack.querySelector<HTMLButtonElement>(`[data-id="${next.id}"] .card__toggle`)?.focus();
      }
    });

    // Swipe a held card sideways to discard it.
    let drag: { x0: number; y0: number; dir: 'h' | 'v' | null; x: number } | null = null;
    el.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || (e.target as HTMLElement).closest('.hold, .discard')) return;
      drag = { x0: e.clientX, y0: e.clientY, dir: null, x: 0 };
    });
    el.addEventListener('pointermove', (e) => {
      if (!drag) return;
      const dx = e.clientX - drag.x0;
      const dy = e.clientY - drag.y0;
      if (!drag.dir && Math.hypot(dx, dy) > 10) drag.dir = Math.abs(dx) > Math.abs(dy) ? 'h' : 'v';
      if (drag.dir === 'h') {
        // Capture only once a swipe starts: capturing on pointerdown would retarget the header click.
        if (!moved) el.setPointerCapture(e.pointerId);
        moved = true;
        drag.x = dx;
        if (c.held) gsap.set(el, { x: dx });
      }
    });
    const up = () => {
      if (!drag) return;
      const d = drag;
      drag = null;
      if (d.dir === 'h' && c.held && Math.abs(d.x) > 110) {
        gsap.to(el, { x: Math.sign(d.x) * 420, autoAlpha: 0, duration: 0.45, ease: 'power3.in', onComplete: () => remove(c) });
        return;
      }
      if (d.dir === 'h') gsap.to(el, { x: 0, duration: 0.5, ease: 'expo.out', overwrite: 'auto' });
    };
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    el.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && open !== null) {
        open = null;
        layout();
        stack.querySelector<HTMLButtonElement>(`[data-id="${c.id}"] .card__toggle`)?.focus();
      }
    });
  }

  cards.forEach((c) => stack.appendChild(build(c)));
  layout();

  // Click outside the stack closes an open card.
  pop.addEventListener('pointerdown', (e) => {
    if (open !== null && !(e.target as HTMLElement).closest('.card, .pop__head')) {
      open = null;
      layout();
    }
  });
}
