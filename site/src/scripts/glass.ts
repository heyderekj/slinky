/**
 * Liquid Glass, Jhey Tompkins' way (codepen jh3y/EajLxJV, MIT, Copyright (c) Jhey).
 *
 * Each [data-glass] element gets its own SVG filter, used as its backdrop-filter. The filter displaces
 * what's behind the element with a generated map: a red gradient across, a blue gradient down, and a
 * blurred grey block in the middle that cancels the displacement. So the bending happens only in a thin
 * band at the rim and the middle stays perfectly clear. Red, green and blue are displaced by slightly
 * different amounts for a little colour fringing, then screened back together.
 *
 * Chromium draws SVG filters as backdrop-filters; Safari and Firefox don't yet. There the glass stays
 * clear with the same crisp inset edge (site.css), a touch of saturation and no bending.
 */

const SVG = 'http://www.w3.org/2000/svg';

// Jhey's "dock" preset, per kind: scale (how far the rim bends) and border (band width as a share of
// the short side). The grey block that keeps the middle clear is his: 50% lightness, 0.93 alpha, blurred.
const KIND: Record<string, { scale: number; border: number }> = {
  window: { scale: -160, border: 0.06 },
  panel: { scale: -180, border: 0.07 },
  capsule: { scale: -120, border: 0.12 },
};
const CHANNEL = { r: 0, g: 10, b: 20 };

function displacementMap(w: number, h: number, radius: number, border: number) {
  const b = Math.min(w, h) * (border * 0.5);
  const blur = Math.min(11, Math.min(w, h) * 0.12);
  const svg = `<svg xmlns="${SVG}" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">
    <defs>
      <linearGradient id="red" x1="100%" y1="0%" x2="0%" y2="0%"><stop offset="0%" stop-color="#000"/><stop offset="100%" stop-color="red"/></linearGradient>
      <linearGradient id="blue" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0%" stop-color="#000"/><stop offset="100%" stop-color="blue"/></linearGradient>
    </defs>
    <rect x="0" y="0" width="${w}" height="${h}" fill="black"/>
    <rect x="0" y="0" width="${w}" height="${h}" rx="${radius}" fill="url(#red)"/>
    <rect x="0" y="0" width="${w}" height="${h}" rx="${radius}" fill="url(#blue)" style="mix-blend-mode:difference"/>
    <rect x="${b}" y="${b}" width="${w - b * 2}" height="${h - b * 2}" rx="${radius}" fill="hsl(0 0% 50% / 0.93)" style="filter:blur(${blur}px)"/>
  </svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}

function channel(scale: number, matrix: string, result: string) {
  return `<feDisplacementMap in="SourceGraphic" in2="map" xChannelSelector="R" yChannelSelector="B" scale="${scale}" result="d${result}"/>
    <feColorMatrix in="d${result}" type="matrix" values="${matrix}" result="${result}"/>`;
}

export function startGlass() {
  const root = document.documentElement;
  const brands = (navigator as Navigator & { userAgentData?: { brands: { brand: string }[] } }).userAgentData?.brands ?? [];
  const refracts = brands.some((b) => /Chromium/i.test(b.brand)) && !new URLSearchParams(location.search).has('clear');
  root.classList.add(refracts ? 'glass-refract' : 'glass-clear');
  if (!refracts) return;

  const holder = document.createElementNS(SVG, 'svg');
  holder.setAttribute('aria-hidden', 'true');
  holder.setAttribute('style', 'position:absolute;width:0;height:0;overflow:hidden');
  const defs = document.createElementNS(SVG, 'defs');
  holder.appendChild(defs);
  document.body.appendChild(holder);

  let count = 0;
  const build = (el: HTMLElement) => {
    const w = Math.round(el.offsetWidth), h = Math.round(el.offsetHeight);
    if (w < 4 || h < 4) return;
    const k = KIND[el.dataset.glass ?? 'panel'] ?? KIND.panel;
    const radius = Math.min(parseFloat(getComputedStyle(el).borderTopLeftRadius) || 16, Math.min(w, h) / 2);
    const id = el.dataset.glassId ?? (el.dataset.glassId = `lg${count++}`);
    let filter = defs.querySelector<SVGFilterElement>(`#${id}`);
    if (!filter) {
      filter = document.createElementNS(SVG, 'filter') as SVGFilterElement;
      filter.id = id;
      filter.setAttribute('color-interpolation-filters', 'sRGB');
      defs.appendChild(filter);
    }
    filter.innerHTML = `
      <feImage x="0" y="0" width="100%" height="100%" result="map" href="${displacementMap(w, h, radius, k.border)}"/>
      ${channel(k.scale + CHANNEL.r, '1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0', 'red')}
      ${channel(k.scale + CHANNEL.g, '0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0', 'green')}
      ${channel(k.scale + CHANNEL.b, '0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0', 'blue')}
      <feBlend in="red" in2="green" mode="screen" result="rg"/>
      <feBlend in="rg" in2="blue" mode="screen" result="output"/>
      <feGaussianBlur in="output" stdDeviation="0.7"/>`;
    el.style.backdropFilter = `url(#${id}) saturate(1.5) brightness(1.08)`;
  };

  const ro = new ResizeObserver((entries) => entries.forEach((e) => build(e.target as HTMLElement)));
  const watch = () => document.querySelectorAll<HTMLElement>('[data-glass]').forEach((el) => {
    if (!el.dataset.glassId) { el.dataset.glassId = `lg${count++}`; ro.observe(el); }
  });
  watch();
  new MutationObserver(watch).observe(document.body, { subtree: true, childList: true });
}
