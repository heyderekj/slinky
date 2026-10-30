/**
 * The page's small interactive demos. Every value is fake (EXAMPLE), nothing touches the real clipboard
 * except the install commands, and everything honors Reduced Motion.
 */
const still = () => document.documentElement.classList.contains('fmb-still') || matchMedia('(prefers-reduced-motion: reduce)').matches;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, still() ? 0 : ms));
const $ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => root.querySelector<T>(sel as string) as T | null;
const $$ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => Array.from(root.querySelectorAll<T>(sel));

function toast(root: Element | null, text: string) {
  const t = root?.querySelector<HTMLElement>('[data-toast]');
  if (!t) return;
  const label = t.querySelector('[data-toast-text]');
  if (label) label.textContent = text;
  t.classList.add('is-on');
  clearTimeout((t as any)._timer);
  (t as any)._timer = setTimeout(() => t.classList.remove('is-on'), 2400);
}

/** Things fade up as they scroll into view, and demos start when visible. */
function onVisible(el: Element, fn: () => void, threshold = 0.35) {
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { fn(); io.disconnect(); }
  }, { threshold });
  io.observe(el);
}

function reveals() {
  for (const el of $$('.reveal')) onVisible(el, () => el.classList.add('is-in'), 0.15);
}

/** Copy buttons on the hero cards: a green checkmark and a toast, like the app. */
function copyButtons() {
  for (const b of $$<HTMLButtonElement>('[data-copy]')) {
    b.addEventListener('click', () => {
      b.classList.add('is-done');
      setTimeout(() => b.classList.remove('is-done'), 1400);
      toast(b.closest('.mac'), `Copied ${b.dataset.copy}. The clipboard clears in 60 seconds.`);
    });
  }
}

/** All Items: a click (or Return) on a row shows its details in the panel, like the app. */
function libraryRows() {
  for (const lib of $$('[data-lib]')) {
    const rows = $$<HTMLElement>('[data-lib-row]', lib);
    const select = (row: HTMLElement) => {
      for (const r of rows) {
        r.classList.toggle('is-on', r === row);
        r.setAttribute('aria-selected', r === row ? 'true' : 'false');
      }
      for (const p of $$<HTMLElement>('[data-lib-pane]', lib)) p.hidden = p.dataset.libPane !== row.dataset.libRow;
    };
    for (const row of rows) {
      row.addEventListener('click', () => select(row));
      row.addEventListener('keydown', (e) => {
        const i = rows.indexOf(row);
        if (e.key === 'ArrowDown' && rows[i + 1]) { e.preventDefault(); rows[i + 1].focus(); select(rows[i + 1]); }
        if (e.key === 'ArrowUp' && rows[i - 1]) { e.preventDefault(); rows[i - 1].focus(); select(rows[i - 1]); }
      });
    }
  }
}

/** Recovery codes cross themselves off. */
function codeSets() {
  for (const set of $$('[data-codeset]')) {
    const left = $('[data-left]', set);
    for (const code of $$<HTMLButtonElement>('[data-code]', set)) {
      code.addEventListener('click', () => {
        if (code.classList.contains('is-used')) return;
        code.classList.add('is-used');
        code.insertAdjacentHTML('beforeend', '<svg class="tick" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M9.4 16.6 4.8 12l-1.6 1.6 6.2 6.2L21 8.2l-1.6-1.6L9.4 16.6Z"/></svg>');
        const n = Math.max(0, Number(left?.textContent ?? 0) - 1);
        if (left) {
          left.textContent = String(n);
          left.parentElement?.classList.toggle('is-low', n <= 3);
        }
        toast(set.closest('.mac'), `Copied and marked as used. ${n} left.`);
      });
    }
  }
}

/** Add Item: paste, the characters turn into dots, then Slinky says what it found. */
/**
 * Guided feature rows: each step opens its scene on the desktop. While the row is on screen the steps
 * advance every few seconds; a click or the arrow keys take over, and Reduce Motion turns advancing off.
 * Opening a scene sends it "scene:show" so a demo inside can play again.
 */
function guided() {
  const DUR = 6500;
  for (const row of $$('[data-guided]')) {
    const steps = $$<HTMLButtonElement>('[data-step]', row);
    const scenes = $$('[data-scene]', row);
    let at = 0;
    let timer = 0;
    let inView = false;
    row.style.setProperty('--g-dur', `${DUR}ms`);
    const schedule = () => {
      clearTimeout(timer);
      const playing = inView && !still();
      row.classList.toggle('is-playing', playing);
      if (playing) timer = window.setTimeout(() => open((at + 1) % steps.length), DUR);
    };
    const open = (n: number, focus = false) => {
      at = n;
      steps.forEach((s, k) => {
        const on = k === n;
        s.classList.toggle('is-on', on);
        s.setAttribute('aria-selected', String(on));
        s.tabIndex = on ? 0 : -1;
        // Restart the progress line.
        const bar = s.querySelector<HTMLElement>('.g-step__bar');
        if (bar) { bar.style.animation = 'none'; void bar.offsetWidth; bar.style.animation = ''; }
      });
      scenes.forEach((sc, k) => {
        const on = k === n;
        sc.classList.toggle('is-on', on);
        sc.hidden = !on;
        if (on) sc.dispatchEvent(new CustomEvent('scene:show'));
      });
      if (focus) steps[n].focus();
      schedule();
    };
    steps.forEach((s, k) => {
      s.addEventListener('click', () => open(k));
      s.addEventListener('keydown', (e) => {
        const d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return;
        e.preventDefault();
        open((at + d + steps.length) % steps.length, true);
      });
    });
    // Hovering the row holds the current step, so it doesn't change while someone is reading or trying the demo.
    row.addEventListener('pointerenter', () => { inView = false; schedule(); });
    row.addEventListener('pointerleave', () => { inView = true; schedule(); });
    new IntersectionObserver(([e]) => { inView = e.isIntersecting && !row.matches(':hover'); schedule(); }, { threshold: 0.45 }).observe(row);
  }
}

function addItem() {
  $$('[data-additem]').forEach(addItemDemo);
}

function addItemDemo(panel: HTMLElement) {
  const slab = $('[data-slab]', panel)!;
  const placeholder = $('[data-placeholder]', panel)!;
  const filled = $('[data-filled]', panel)!;
  const value = $('[data-value]', panel)!;
  const steps = $$('[data-step]', panel);
  const full = value.textContent ?? '';
  const head = 'sk-proj-';
  const tail = full.slice(-4);
  const middle = full.slice(head.length, -4);
  let run = 0;

  async function play() {
    const me = ++run;
    panel!.classList.remove('is-ready');
    steps.forEach((s) => s.classList.remove('is-in'));
    slab.classList.add('is-empty');
    placeholder.hidden = false;
    filled.hidden = true;
    value.textContent = full;
    await sleep(700);
    if (me !== run) return;
    // The paste lands.
    slab.classList.remove('is-empty');
    placeholder.hidden = true;
    filled.hidden = false;
    await sleep(380);
    for (let i = 1; i <= middle.length; i += Math.max(1, Math.round(middle.length / 26))) {
      if (me !== run) return;
      value.textContent = head + '•'.repeat(i) + middle.slice(i) + tail;
      await sleep(22);
    }
    value.textContent = head + '••••••••••••' + tail;
    await sleep(200);
    steps[0]?.classList.add('is-in');
    await sleep(260);
    steps[1]?.classList.add('is-in');
    await sleep(240);
    panel!.classList.add('is-ready');
  }
  onVisible(panel, play);
  panel.parentElement?.querySelector('[data-replay]')?.addEventListener('click', play);
  panel.closest('[data-scene]')?.addEventListener('scene:show', play);
}

/** Quick Access: type to filter, arrows to move, Return to copy. ⌥⌘K or K focuses it. */
function quickAccess() {
  const qa = $('[data-quick]');
  if (!qa) return;
  const input = $<HTMLInputElement>('[data-quick-input]', qa)!;
  const items = $$('[data-quick-item]', qa);
  const previewName = $('[data-preview-name]', qa);
  let sel = 0;
  const visible = () => items.filter((i) => !i.hidden);
  function render() {
    const v = visible();
    sel = Math.min(sel, Math.max(0, v.length - 1));
    items.forEach((i) => i.classList.remove('is-on'));
    v[sel]?.classList.add('is-on');
    if (previewName && v[sel]) previewName.textContent = v[sel].querySelector('div > div')?.textContent ?? '';
  }
  input.addEventListener('input', () => {
    const q = input.value.trim().toLowerCase();
    for (const i of items) i.hidden = !!q && !(i.dataset.name ?? '').includes(q);
    sel = 0;
    render();
  });
  input.addEventListener('keydown', (e) => {
    const v = visible();
    if (e.key === 'ArrowDown') { sel = Math.min(sel + 1, v.length - 1); render(); e.preventDefault(); }
    if (e.key === 'ArrowUp') { sel = Math.max(sel - 1, 0); render(); e.preventDefault(); }
    if (e.key === 'Enter' && v[sel]) {
      const name = v[sel].querySelector('div > div')?.textContent ?? 'it';
      const codes = name.includes('codes');
      toast(qa, codes ? 'Copied the next code and crossed it off. 7 left.' : e.metaKey ? `Copied ${name}=… The clipboard clears in 60 seconds.` : `Copied ${name}. The clipboard clears in 60 seconds.`);
    }
    if (e.key === 'Escape') { input.value = ''; input.dispatchEvent(new Event('input')); input.blur(); }
  });
  items.forEach((i, n) => i.addEventListener('click', () => { input.focus(); sel = visible().indexOf(i); render(); }));
  addEventListener('keydown', (e) => {
    const typing = (e.target as HTMLElement)?.closest('input, textarea');
    if ((e.altKey && e.metaKey && e.key.toLowerCase() === 'k') || (!typing && e.key === 'k' && !e.metaKey && !e.ctrlKey && !e.altKey)) {
      e.preventDefault();
      qa.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'center' });
      setTimeout(() => input.focus({ preventScroll: true }), still() ? 0 : 450);
    }
  });
}

/** Every lock switch locks its window: frost spreads from the switch, then the lock screen. */
function locks() {
  for (const sw of $$<HTMLButtonElement>('[data-lock-switch]')) {
    const demo = sw.closest('[data-lockdemo]');
    const spans = $$('span', sw);
    sw.addEventListener('click', () => {
      if (!demo) {
        // The hero window: flip the switch and say so, the way the app does before locking.
        sw.classList.toggle('is-locked');
        spans.forEach((s, i) => s.classList.toggle('is-on', sw.classList.contains('is-locked') ? i === 1 : i === 0));
        if (sw.classList.contains('is-locked')) {
          toast(sw.closest('.mac'), 'Locked. Try the lock demo further down the page.');
          setTimeout(() => { sw.classList.remove('is-locked'); spans.forEach((s, i) => s.classList.toggle('is-on', i === 0)); }, 1600);
        }
        return;
      }
      lock(demo, sw, spans);
    });
  }
  for (const b of $$('[data-unlock]')) {
    b.addEventListener('click', async () => {
      const demo = b.closest('[data-lockdemo]')!;
      const sw = $<HTMLButtonElement>('[data-lock-switch]', demo)!;
      const icon = $('[data-curtain-icon]', demo);
      if (icon) icon.innerHTML = icon.innerHTML.replace('M12 2a5 5 0 0 1 5 5v3', 'M16 2a5 5 0 0 1 5 5v2');
      await sleep(350);
      demo.classList.add('is-opening');
      demo.classList.remove('is-locked');
      sw.classList.remove('is-locked');
      $$('span', sw).forEach((s, i) => s.classList.toggle('is-on', i === 0));
      await sleep(750);
      demo.classList.remove('is-opening');
    });
  }
  function lock(demo: Element, sw: HTMLElement, spans: HTMLElement[]) {
    if (demo.classList.contains('is-locked')) return;
    sw.classList.add('is-locked');
    spans.forEach((s, i) => s.classList.toggle('is-on', i === 1));
    demo.classList.add('is-locked');
  }
}

/** The four kinds: each example pill turns into dots and slips into the icon, and the heading follows. */
function kinds() {
  const box = $('[data-kinds]');
  const head = document.getElementById('kinds-head');
  const pill = $('[data-pill]', box ?? document);
  if (!box || !head || !pill) return;
  const label = pill.querySelector('small')!;
  const value = $('[data-pill-value]', pill)!;
  const samples = [
    { label: 'API key', value: 'sk_live_EXAMPLE4f2a', keep: [8, 4], head: 'A safe home for your API keys.' },
    { label: 'Project variable', value: 'RESEND_API_KEY=re_EXAMPLE7d0e', keep: [15, 0], head: 'Your app’s secrets, out of its files.' },
    { label: 'Recovery codes', value: 'a1b2c-3d4e5  f6a7b-8c9d0', keep: [0, 0], head: 'Backup codes, ready when you’re locked out.' },
    { label: 'Recovery key', value: 'R7KQ-EXAM-PLE0-0000', keep: [5, 0], head: 'Recovery keys, safe for the day you need them.' },
  ];
  let i = 0;
  async function loop() {
    for (;;) {
      const s = samples[i % samples.length];
      label.textContent = s.label;
      value.textContent = s.value;
      head!.style.opacity = '0';
      await sleep(250);
      head!.textContent = s.head;
      head!.style.opacity = '1';
      pill!.style.transition = 'none';
      pill!.style.transform = 'translateY(150px) scale(1)';
      pill!.style.opacity = '0';
      void pill!.offsetWidth;
      pill!.style.transition = '';
      pill!.style.opacity = '1';
      pill!.style.transform = 'translateY(122px)';
      await sleep(900);
      const [front, back] = s.keep;
      const chars = s.value.split('');
      for (let n = front; n < chars.length - back; n++) {
        if (chars[n] === '-' || chars[n] === ' ' || chars[n] === '_') continue;
        chars[n] = '•';
        value.textContent = chars.join('');
        await sleep(26);
      }
      await sleep(700);
      pill!.style.transform = 'translateY(20px) scale(0.2)';
      pill!.style.opacity = '0';
      await sleep(1300);
      i++;
      if (still()) return;
    }
  }
  onVisible(box, loop, 0.4);
}

/** The staircase nod plays once, when it scrolls into view. */
function stairs() {
  const s = $('[data-stairs]');
  if (s) onVisible(s, () => s.classList.add('is-in'), 0.6);
}

/** Fathom events, named like Dinky's and Binky's. A page without Fathom (blocked, offline) just skips them. */
function track(name: string) {
  try { (window as any).fathom?.trackEvent(name); } catch { /* analytics never breaks the page */ }
}

/** Download opens the install steps (the download still starts). */
function install() {
  const modal = $('[data-install]');
  if (!modal) return;
  const open = () => { modal.classList.add('is-open'); $('[data-close-install]', modal)?.focus(); };
  const close = () => modal.classList.remove('is-open');
  for (const a of $$('[data-download]')) a.addEventListener('click', () => { track(a.dataset.track ?? 'Download macOS'); setTimeout(open, 300); });
  for (const b of $$('[data-open-install]')) b.addEventListener('click', () => { track('install_modal_from_version'); open(); });
  for (const a of $$<HTMLAnchorElement>('.modal__fallback a')) a.addEventListener('click', () => track(a.dataset.track ?? 'Download macOS install-fallback'));
  $('[data-close-install]', modal)?.addEventListener('click', close);
  modal.addEventListener('click', (e) => { if (e.target === modal) close(); });
  addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
  for (const tab of $$<HTMLButtonElement>('[data-tab]', modal)) {
    tab.addEventListener('click', () => {
      track('install_modal_tab_' + tab.dataset.tab);
      for (const t of $$<HTMLButtonElement>('[data-tab]', modal)) t.setAttribute('aria-selected', String(t === tab));
      for (const p of $$('[data-panel]', modal)) p.hidden = p.dataset.panel !== tab.dataset.tab;
    });
  }
  copyCommands(modal);
}

/** Copy buttons beside a command: Copied for a moment. */
function copyCommands(root: ParentNode) {
  for (const b of $$<HTMLButtonElement>('[data-copy-cmd]', root)) {
    b.addEventListener('click', async () => {
      const code = b.parentElement?.querySelector('code')?.textContent ?? '';
      try { await navigator.clipboard.writeText(code); b.textContent = 'Copied'; } catch { b.textContent = 'Select it'; }
      setTimeout(() => { b.textContent = 'Copy'; }, 1800);
    });
  }
}

/** "macOS blocked Slinky": the fix for people who already downloaded it, opened from the FAQ. */
function helpModal() {
  const modal = $('[data-help]');
  if (!modal) return;
  const open = () => { modal.classList.add('is-open'); $('[data-close-help]', modal)?.focus(); track('help_modal_from_faq'); };
  const close = () => modal.classList.remove('is-open');
  for (const b of $$('[data-open-help]')) b.addEventListener('click', open);
  $('[data-close-help]', modal)?.addEventListener('click', close);
  modal.addEventListener('click', (e) => { if (e.target === modal) close(); });
  addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
  copyCommands(modal);
}

/** GitHub star count, and the family's star burst on hover. */
function stars() {
  const link = $('[data-stars]');
  if (!link) return;
  const count = $('[data-star-count]', link);
  fetch('https://api.github.com/repos/heyderekj/slinky')
    .then((r) => (r.ok ? r.json() : null))
    .then((d) => { if (d && typeof d.stargazers_count === 'number') $$('[data-star-count]').forEach((c) => { c.textContent = d.stargazers_count.toLocaleString(); }); })
    .catch(() => {});
  let last = 0;
  link.addEventListener('pointerenter', () => {
    if (still() || Date.now() - last < 900) return;
    last = Date.now();
    const r = link.getBoundingClientRect();
    const n = 10;
    for (let k = 0; k < n; k++) {
      const s = document.createElement('span');
      s.className = 'star-burst';
      s.textContent = '★';
      s.style.left = `${r.left + r.width / 2}px`;
      s.style.top = `${r.top + r.height / 2}px`;
      document.body.appendChild(s);
      const a = (Math.PI * 2 * k) / n + Math.random() * 0.5;
      const d = 34 + Math.random() * 30;
      s.animate([
        { transform: 'translate(-50%,-50%) scale(0.4)', opacity: 1 },
        { transform: `translate(calc(-50% + ${Math.cos(a) * d}px), calc(-50% + ${Math.sin(a) * d - 12}px)) scale(1) rotate(${Math.random() * 180}deg)`, opacity: 0 },
      ], { duration: 700 + Math.random() * 300, easing: 'cubic-bezier(.22,1,.36,1)' }).onfinish = () => s.remove();
    }
  });
}

/** The family Dock, the macOS way: icons grow with the pointer's distance (a smooth falloff across
 *  neighbours), the Dock widens so they push apart, and clicking another app bounces it before going. */
function dock() {
  const d = $('[data-dock]');
  if (!d) return;
  const apps = $$<HTMLAnchorElement>('.dock__app', d);
  // On this Mac the Dock opens the other sites' local servers, so switching can be tried before they're live.
  if (location.hostname === 'localhost') {
    const ports: Record<string, number> = { dinky: 4343, binky: 4342, slinky: 4329 };
    for (const a of apps) {
      const m = a.hostname.match(/^(dinky|binky|slinky)files\.com$/);
      if (m) a.href = `http://localhost:${ports[m[1]]}/`;
    }
  }
  // On the preview copies (dinky-preview.pages.dev and friends), the Dock moves between the previews.
  if (/^(dinky|binky|slinky)-preview\.pages\.dev$/.test(location.hostname)) {
    for (const a of apps) {
      const m = a.hostname.match(/^(dinky|binky|slinky)files\.com$/);
      if (m) a.href = `https://${m[1]}-preview.pages.dev/`;
    }
  }
  let centers: number[] = [];
  const set = (a: HTMLElement, m: number) => a.style.setProperty('--mag', m.toFixed(3));
  if (matchMedia('(hover: hover)').matches) {
    d.addEventListener('pointerenter', () => {
      apps.forEach((a) => set(a, 1));
      centers = apps.map((a) => { const r = a.getBoundingClientRect(); return r.left + r.width / 2; });
    });
    d.addEventListener('pointermove', (e) => {
      if (still() || !centers.length) return;
      d.classList.add('is-tracking');
      apps.forEach((a, i) => {
        const t = Math.max(0, 1 - Math.abs(e.clientX - centers[i]) / 150);
        set(a, 1 + 0.62 * Math.pow(Math.sin((t * Math.PI) / 2), 1.8));
      });
    });
    d.addEventListener('pointerleave', () => {
      d.classList.remove('is-tracking');
      apps.forEach((a) => set(a, 1));
    });
  }
  // Switching apps should feel like turning a page: connect to the other sites early, fetch them as the
  // pointer reaches the Dock, and go the moment one is clicked. The bounce plays while the next page loads.
  const others = apps.filter((a) => !a.classList.contains('is-current'));
  for (const a of others) {
    const l = document.createElement('link');
    l.rel = 'preconnect';
    l.href = new URL(a.href).origin;
    document.head.append(l);
  }
  if (HTMLScriptElement.supports?.('speculationrules')) {
    // Chrome: prefetch on hover or press of a Dock icon.
    const s = document.createElement('script');
    s.type = 'speculationrules';
    s.textContent = JSON.stringify({ prefetch: [{ where: { selector_matches: '.dock__app:not(.is-current)' }, eagerness: 'moderate' }] });
    document.head.append(s);
  } else {
    // Firefox honours prefetch links. (Safari has neither yet, so it gets the early connection only.)
    let warmed = false;
    const warm = () => {
      if (warmed) return;
      warmed = true;
      for (const a of others) {
        const l = document.createElement('link');
        l.rel = 'prefetch';
        l.href = a.href;
        document.head.append(l);
      }
    };
    d.addEventListener('pointerenter', warm);
    d.addEventListener('focusin', warm);
    d.addEventListener('touchstart', warm, { passive: true });
  }
  for (const a of others) {
    a.addEventListener('click', (e) => {
      if (still() || e.metaKey || e.ctrlKey || e.shiftKey) return;
      a.classList.add('is-launching');
    });
  }
  // Coming back with the Back button restores this page as it was left; settle the bounce.
  addEventListener('pageshow', (e) => { if (e.persisted) others.forEach((a) => a.classList.remove('is-launching')); });
}

/** Menu bar clocks show the real day and time, the way macOS writes it ("Fri Oct 17  9:41 AM"). */
function clocks() {
  const els = $$('[data-clock]');
  if (!els.length) return;
  const tick = () => {
    const d = new Date();
    const day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).replace(',', '');
    const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    // The day hides on small phones (CSS), leaving the time, as the iPhone status bar does.
    for (const el of els) el.innerHTML = `<span class="mb-day">${day}\u00a0\u00a0</span>${time}`;
  };
  tick();
  setInterval(tick, 15_000);
}

/** The nav waits until the hero's buttons are out of view, then slides down. */
function navReveal() {
  const nav = $('.nav');
  const cta = $('.hero__actions');
  if (!nav || !cta) { nav?.classList.remove('is-tucked'); return; }
  new IntersectionObserver(([e]) => nav.classList.toggle('is-tucked', e.isIntersecting), { rootMargin: '-60px 0px 0px 0px' }).observe(cta);
}

/** What the hero menu bar (public/family-menubar.js) asks Slinky's page to do. */
function menubarActions() {
  const hero = $('#hero-window');
  const toggleSidebar = () => hero?.classList.toggle('mac--nosb');
  if (hero) $$('.mac__sbtoggle, .mac__toolbar .sb', hero).forEach((b) => b.addEventListener('click', toggleSidebar));
  const smooth = (el: Element | null) => el?.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'center' });
  document.addEventListener('menubar:action', (e) => {
    const action = (e as CustomEvent<{ action: string }>).detail.action;
    if (action === 'lock') {
      const demo = $('[data-mb-window]');
      const sw = demo && $<HTMLButtonElement>('[data-lock-switch]', demo);
      if (demo && sw && !demo.classList.contains('is-locked')) sw.click();
    }
    if (action === 'toggle-sidebar') toggleSidebar();
    if (action === 'add-item') { const r = $('[data-guided]'); smooth(r); $<HTMLButtonElement>('[data-step]', r!)?.click(); }
    if (action === 'new-project') smooth($$('.e-row')[0] ?? null);
    if (action === 'quick-access') { smooth($('[data-quick]')); setTimeout(() => $<HTMLInputElement>('[data-quick-input]')?.focus({ preventScroll: true }), 500); }
    if (action === 'import') smooth($('#also-heading'));
  });
}

/**
 * Sharing (2.0): the Share panel (pick people, then the file is ready), adding someone by comparing codes, and a
 * shared project's people, where removing someone lists the keys to replace. Each resets when its scene opens.
 * With Reduce Motion nothing advances on its own; the controls still work.
 */
function sharing() {
  const names = (n: string[]) => (n.length < 2 ? n.join('') : `${n.slice(0, -1).join(', ')} and ${n[n.length - 1]}`);

  for (const panel of $$('[data-sharedemo]')) {
    const pick = $('[data-share-pick]', panel)!;
    const ready = $('[data-share-ready]', panel)!;
    const boxes = $$<HTMLInputElement>('[data-share-person]', panel);
    const go = $<HTMLButtonElement>('[data-share-go]', panel)!;
    let run = 0;
    const sync = () => { go.disabled = !boxes.some((b) => b.checked); };
    const show = (done: boolean) => { pick.hidden = done; ready.hidden = !done; };
    const make = () => {
      const who = names(boxes.filter((b) => b.checked).map((b) => b.value));
      $('[data-share-who]', panel)!.textContent = who;
      // The file says who it's from and for, never what's in it.
      $('[data-share-file]', panel)!.textContent = `From Alex Rivera for ${who}.slinkyshare`;
      show(true);
    };
    const reset = () => { boxes.forEach((b) => { b.checked = false; }); sync(); show(false); };
    async function play() {
      const me = ++run;
      reset();
      await sleep(900);
      if (me !== run) return;
      boxes[0].checked = true;
      sync();
      if (still()) return;
      await sleep(1300);
      if (me !== run) return;
      make();
    }
    // Someone trying it takes over from the autoplay.
    for (const type of ['pointerdown', 'keydown']) panel.addEventListener(type, () => { run++; });
    boxes.forEach((b) => b.addEventListener('change', sync));
    go.addEventListener('click', make);
    $('[data-share-done]', panel)?.addEventListener('click', reset);
    onVisible(panel, play);
    panel.closest('[data-scene]')?.addEventListener('scene:show', play);
  }

  for (const demo of $$('[data-peopledemo]')) {
    const compare = $('[data-person-compare]', demo)!;
    const list = $('[data-person-list]', demo)!;
    const ana = $('[data-person-ana]', demo)!;
    const count = $('[data-person-count]', demo)!;
    const msg = $('[data-person-msg]', demo)!;
    const reset = () => { compare.hidden = false; list.hidden = true; };
    for (const b of $$<HTMLButtonElement>('[data-person-answer]', demo)) {
      b.addEventListener('click', () => {
        // It Matches adds them with the code compared; It Doesn't Match adds nothing.
        const yes = b.dataset.personAnswer === 'yes';
        ana.hidden = !yes;
        msg.hidden = !yes;
        count.textContent = yes ? '3 people' : '2 people';
        compare.hidden = true;
        list.hidden = false;
      });
    }
    demo.closest('[data-scene]')?.addEventListener('scene:show', reset);
  }

  for (const demo of $$('[data-teamdemo]')) {
    const members = $('[data-team-members]', demo)!;
    const rotate = $('[data-team-rotate]', demo)!;
    const sub = $('[data-team-sub]', demo)!;
    const keys = $$<HTMLInputElement>('[data-team-key]', demo);
    const count = $('[data-team-count]', demo)!;
    const later = $('[data-team-later]', demo)!;
    const rows = $$('[data-member]', demo);
    const tally = () => {
      const n = keys.filter((k) => k.checked).length;
      count.textContent = `${n} of ${keys.length} done`;
      later.textContent = n === keys.length ? 'Done' : 'Later';
    };
    const subtitle = () => {
      const left = rows.filter((r) => !r.hidden).map((r) => r.dataset.member ?? '');
      sub.textContent = `12 variables · Shared with ${left.length === 1 ? left[0] : `${left.length} people`}`;
    };
    const reset = () => {
      rows.forEach((r) => { r.hidden = false; });
      keys.forEach((k) => { k.checked = false; });
      members.hidden = false;
      rotate.hidden = true;
      tally();
      subtitle();
    };
    for (const b of $$('[data-team-remove]', demo)) {
      b.addEventListener('click', () => {
        const row = b.closest<HTMLElement>('[data-member]')!;
        row.hidden = true;
        $('[data-team-who]', demo)!.textContent = row.dataset.member ?? '';
        subtitle();
        members.hidden = true;
        rotate.hidden = false;
      });
    }
    keys.forEach((k) => k.addEventListener('change', tally));
    later.addEventListener('click', () => { members.hidden = false; rotate.hidden = true; keys.forEach((k) => { k.checked = false; }); tally(); });
    demo.closest('[data-scene]')?.addEventListener('scene:show', reset);
  }

  // A project's Share menu: opens under its button, closes on a choice, a click elsewhere or Escape.
  for (const wrap of $$('[data-envshare]')) {
    const button = $<HTMLButtonElement>('.envshare', wrap)!;
    const menu = $('.envmenu', wrap)!;
    const set = (open: boolean) => { menu.hidden = !open; button.setAttribute('aria-expanded', String(open)); };
    button.addEventListener('click', (e) => { e.stopPropagation(); set(menu.hidden); });
    menu.addEventListener('click', (e) => { if ((e.target as HTMLElement).closest('button')) set(false); });
    document.addEventListener('click', (e) => { if (!wrap.contains(e.target as Node)) set(false); });
    addEventListener('keydown', (e) => { if (e.key === 'Escape') set(false); });
    wrap.closest('[data-scene]')?.addEventListener('scene:show', () => set(false));
  }

  // Share buttons elsewhere on the page (the hero's details pane, the project's Share menu) open the sharing row
  // at the right step, with what's being shared as the Share panel's subtitle.
  for (const el of $$('[data-share-jump]')) {
    el.addEventListener('click', () => {
      const panel = $('[data-sharedemo]');
      const what = el.dataset.shareWhat ?? el.closest('[data-lib-pane]')?.querySelector('.pane__name')?.textContent;
      if (panel && what) {
        $('[data-share-what]', panel)!.textContent = what;
        const list = $('[data-share-names]', panel)!;
        list.textContent = el.dataset.shareNames ?? '';
        list.hidden = !el.dataset.shareNames;
      }
      const tab = document.getElementById(`share-tab-${el.dataset.shareJump || 0}`);
      tab?.closest('[data-guided]')?.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'center' });
      tab?.click();
    });
  }
}

/** On touch screens there's no hover: "Tap to show", and a tap shows or hides the example value. */
function tapToShow() {
  if (matchMedia('(hover: hover)').matches) return;
  for (const v of $$('.card__value')) {
    const hint = v.querySelector('small');
    if (!hint || !v.querySelector('.shown')) continue;
    hint.textContent = 'Tap to show';
    v.addEventListener('click', () => {
      const on = v.classList.toggle('is-shown');
      hint.textContent = on ? 'Tap to hide' : 'Tap to show';
    });
  }
}

export function startDemos() {
  reveals();
  guided();
  copyButtons();
  libraryRows();
  helpModal();
  codeSets();
  addItem();
  quickAccess();
  locks();
  kinds();
  stairs();
  install();
  stars();
  dock();
  clocks();
  navReveal();
  menubarActions();
  sharing();
  tapToShow();
}
