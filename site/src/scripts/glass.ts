/**
 * The page's "desktop wallpaper" and its Liquid Glass, drawn together in one WebGL2 canvas.
 *
 * Why one canvas: the usual web trick (backdrop-filter: url(#svg-filter)) only refracts in Chromium,
 * and most Slinky visitors use Safari. Because we draw the wallpaper ourselves, the shader can bend it
 * directly wherever there's glass, and it looks the same in every browser.
 *
 * - Wallpaper: a mesh gradient. Five moving colour points blended by inverse distance, with a gentle
 *   swirl and fine grain. Written for Slinky, after the technique in Paper's MeshGradient
 *   (paper-design/shaders, Apache-2.0).
 * - Glass: every element with `data-glass` is a rounded rectangle the shader knows about. Inside it the
 *   wallpaper is refracted through a convex squircle bezel, frosted, split slightly by colour at the
 *   rim, and lit from the upper left. The technique follows Kube's "Liquid Glass in CSS and SVG" and
 *   Shu Ding's liquid-glass demo, reworked as a fragment shader.
 *
 * Elements: `data-glass="window" | "panel" | "capsule"` (sets bezel and strength). Opacity is read from
 * the element so glass fades with it. Up to 16 visible shapes.
 */

const MAX = 16;

const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
uniform vec2 uRes;        // canvas size, device px
uniform float uDpr;
uniform float uTime;
uniform float uDark;
uniform vec3 uC[5];
uniform vec4 uRect[${MAX}];  // x, y, w, h in CSS px (viewport, y down)
uniform vec4 uMeta[${MAX}];  // radius, bezel, strength, opacity
uniform int uCount;
out vec4 outColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 wallpaper(vec2 p) {
  vec2 view = uRes / uDpr;
  float aspect = view.x / view.y;
  vec2 q = vec2(p.x / view.x * aspect, p.y / view.y);
  float t = uTime * 0.045;
  q += 0.07 * vec2(sin(q.y * 2.2 + t * 1.7), cos(q.x * 1.9 - t * 1.3));
  vec3 acc = vec3(0.0);
  float wsum = 0.0;
  // Anchored like the testamentmade mesh cards (14%/16%, 86%/14%, 80%/86%, 16%/84%, 52%/48%), each drifting a little.
  vec2 anchor[5] = vec2[5](vec2(0.14, 0.16), vec2(0.86, 0.14), vec2(0.80, 0.86), vec2(0.16, 0.84), vec2(0.52, 0.48));
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    vec2 a = anchor[i];
    vec2 c = vec2(a.x * aspect, a.y)
      + vec2(0.10 * aspect * sin(t * (0.9 + 0.17 * fi) + fi * 1.9),
             0.09 * cos(t * (0.7 + 0.13 * fi) + fi * 2.7));
    float d = distance(q, c);
    float w = 1.0 / pow(d + 0.04, 2.8);
    acc += uC[i] * w;
    wsum += w;
  }
  return acc / wsum;
}

float sdRound(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float shapeD(vec2 p, int i) {
  vec4 r = uRect[i];
  vec2 hs = r.zw * 0.5;
  return sdRound(p - (r.xy + hs), hs, min(uMeta[i].x, min(hs.x, hs.y)));
}

void main() {
  vec2 p = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y) / uDpr;   // CSS px, y down
  vec3 col = wallpaper(p);

  // A soft shadow under the larger glass, so it floats.
  float shade = 0.0;
  for (int i = 0; i < ${MAX}; i++) {
    if (i >= uCount) break;
    if (uMeta[i].y < 14.0) continue;
    float ds = shapeD(p - vec2(0.0, 14.0), i);
    shade = max(shade, exp(-max(ds, 0.0) / 34.0) * 0.14 * uMeta[i].w);
  }
  col *= 1.0 - shade * (uDark > 0.5 ? 0.9 : 0.55);

  // The topmost shape this pixel is inside (later elements are on top).
  int hit = -1;
  float hd = 1e6;
  for (int i = 0; i < ${MAX}; i++) {
    if (i >= uCount) break;
    float d = shapeD(p, i);
    if (d < 0.75) { hit = i; hd = d; }
  }

  if (hit >= 0) {
    vec4 m = uMeta[hit];
    float e = 1.0;
    vec2 n = normalize(vec2(shapeD(p + vec2(e, 0.0), hit) - shapeD(p - vec2(e, 0.0), hit),
                            shapeD(p + vec2(0.0, e), hit) - shapeD(p - vec2(0.0, e), hit)) + 1e-6);
    float bezel = m.y;
    float t = clamp(-hd / bezel, 0.0, 1.0);   // 0 at the rim, 1 past the bezel
    float edge = 1.0 - t;
    // Convex squircle profile: flat in the middle, bending hard at the rim.
    float slope = pow(edge, 2.4);
    vec2 off = n * slope * m.z;

    // Frosted refraction: a few taps around the bent sample point.
    float f = 5.0 + 3.0 * edge;
    vec3 g = wallpaper(p + off) * 0.36
           + wallpaper(p + off + vec2(f, 0.0)) * 0.16 + wallpaper(p + off - vec2(f, 0.0)) * 0.16
           + wallpaper(p + off + vec2(0.0, f)) * 0.16 + wallpaper(p + off - vec2(0.0, f)) * 0.16;
    // Colour fringing at the rim.
    if (edge > 0.04) {
      g.r = mix(g.r, wallpaper(p + off * 1.08).r, 0.35 * edge);
      g.b = mix(g.b, wallpaper(p + off * 0.92).b, 0.35 * edge);
    }
    // Glass tint: a little white in light mode, a little smoke in dark mode.
    g = uDark > 0.5 ? mix(g, vec3(0.05, 0.06, 0.08), 0.12) : mix(g, vec3(1.0), 0.09);

    // Light from the upper left: a specular rim, and a softer shade on the far side.
    vec2 L = normalize(vec2(-0.55, -0.83));
    float lit = max(dot(n, L), 0.0);
    float spec = pow(lit, 2.5) * pow(edge, 8.0) * (uDark > 0.5 ? 0.25 : 0.38);
    float under = pow(max(dot(n, -L), 0.0), 2.0) * pow(edge, 8.0) * 0.06;
    float rim = smoothstep(1.4, 0.0, -hd) * (uDark > 0.5 ? 0.12 : 0.22);
    g += spec + rim;
    g -= under;

    float a = smoothstep(0.75, -0.75, hd) * m.w;
    col = mix(col, g, a);
  }

  col += (hash(gl_FragCoord.xy + fract(uTime) * 61.0) - 0.5) * 0.018;   // fine grain, no banding
  outColor = vec4(col, 1.0);
}`;

type Shape = { el: HTMLElement; bezel: number; strength: number; radius: number };

const KIND: Record<string, { bezel: number; strength: number }> = {
  window: { bezel: 20, strength: 13 },
  panel: { bezel: 16, strength: 11 },
  capsule: { bezel: 10, strength: 7 },
};

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.trim().replace('#', '');
  const v = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}

export function startGlass(canvas: HTMLCanvasElement) {
  const root = document.documentElement;
  const gl = new URLSearchParams(location.search).has('noGL') ? null : canvas.getContext('webgl2', { antialias: false, premultipliedAlpha: false });
  if (!gl) {
    root.classList.add('no-gl');
    return;
  }

  function compile(type: number, src: string) {
    const s = gl!.createShader(type)!;
    gl!.shaderSource(s, src);
    gl!.compileShader(s);
    if (!gl!.getShaderParameter(s, gl!.COMPILE_STATUS)) throw new Error(gl!.getShaderInfoLog(s) ?? 'shader');
    return s;
  }
  let program: WebGLProgram;
  try {
    program = gl.createProgram()!;
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERT));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) ?? 'link');
  } catch (err) {
    console.warn('Slinky glass: falling back to CSS', err);
    root.classList.add('no-gl');
    return;
  }
  gl.useProgram(program);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const aPos = gl.getAttribLocation(program, 'aPos');
  gl.enableVertexAttribArray(aPos);
  gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

  const u = (n: string) => gl.getUniformLocation(program, n);
  const uRes = u('uRes'), uDpr = u('uDpr'), uTime = u('uTime'), uDark = u('uDark'), uC = u('uC');
  const uRect = u('uRect'), uMeta = u('uMeta'), uCount = u('uCount');

  root.classList.add('gl');
  let dirty = true;   // redraw needed (set by scroll, resize, colour scheme and DOM changes)

  const dark = matchMedia('(prefers-color-scheme: dark)');
  const still = matchMedia('(prefers-reduced-motion: reduce)');
  function palette() {
    const cs = getComputedStyle(root);
    const colors = ['--c1', '--c2', '--c3', '--c4', '--c5'].flatMap((v) => hexToRgb(cs.getPropertyValue(v) || '#88aacc'));
    gl!.uniform3fv(uC, new Float32Array(colors));
    gl!.uniform1f(uDark, dark.matches ? 1 : 0);
  }
  palette();
  dark.addEventListener('change', () => { palette(); dirty = true; });

  let shapes: Shape[] = [];
  function collect() {
    shapes = Array.from(document.querySelectorAll<HTMLElement>('[data-glass]')).map((el) => {
      const k = KIND[el.dataset.glass ?? 'panel'] ?? KIND.panel;
      return { el, ...k, radius: parseFloat(getComputedStyle(el).borderTopLeftRadius) || 16 };
    });
  }
  collect();
  new MutationObserver(() => { collect(); dirty = true; }).observe(document.body, { subtree: true, childList: true, attributeFilter: ['data-glass'] });

  const rects = new Float32Array(MAX * 4);
  const metas = new Float32Array(MAX * 4);
  let dpr = 1;
  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 1.75);
    // The canvas's own CSS size, not innerWidth: on phones the two can differ.
    const w = Math.round((canvas.clientWidth || innerWidth) * dpr), h = Math.round((canvas.clientHeight || innerHeight) * dpr);
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
    gl!.viewport(0, 0, w, h);
    gl!.uniform2f(uRes, w, h);
    gl!.uniform1f(uDpr, dpr);
    for (const s of shapes) s.radius = parseFloat(getComputedStyle(s.el).borderTopLeftRadius) || s.radius;
    dirty = true;
  }
  addEventListener('resize', resize);
  resize();

  // If animation frames are being held back (a background or throttled tab), redraw from scroll itself.
  let lastFrame = 0;
  addEventListener('scroll', () => {
    dirty = true;
    if (performance.now() - lastFrame > 120) frame(performance.now());
  }, { passive: true });

  const start = performance.now();
  const frozen = 12.0;   // a nice moment, used when motion is reduced
  let scheduled = false;
  function schedule() { if (!scheduled) { scheduled = true; requestAnimationFrame((t) => { scheduled = false; frame(t); }); } }
  function frame(now: number) {
    lastFrame = performance.now();
    if (document.hidden) { schedule(); return; }
    const moving = !still.matches;
    if (moving || dirty) {
      let n = 0;
      for (const s of shapes) {
        if (n >= MAX) break;
        const r = s.el.getBoundingClientRect();
        if (r.width < 2 || r.bottom < -40 || r.top > (canvas.clientHeight || innerHeight) + 40) continue;
        // Fade with the element and with the section it reveals inside.
        const section = s.el.closest<HTMLElement>('.reveal');
        const op = parseFloat(getComputedStyle(s.el).opacity) * (section ? parseFloat(getComputedStyle(section).opacity) : 1);
        if (op < 0.02) continue;
        rects.set([r.left, r.top, r.width, r.height], n * 4);
        metas.set([s.radius, s.bezel, s.strength, op], n * 4);
        n++;
      }
      gl!.uniform4fv(uRect, rects);
      gl!.uniform4fv(uMeta, metas);
      gl!.uniform1i(uCount, n);
      gl!.uniform1f(uTime, moving ? (now - start) / 1000 + frozen : frozen);
      gl!.drawArrays(gl!.TRIANGLES, 0, 3);
      dirty = false;
    }
    schedule();
  }
  // Draw the first frame right away, so the wallpaper is there even before (or without) animation frames.
  dirty = true;
  frame(performance.now());

  canvas.addEventListener('webglcontextlost', (e) => { e.preventDefault(); root.classList.remove('gl'); root.classList.add('no-gl'); });
  // Elements that animate their size or position mark the frame dirty while they move.
  addEventListener('transitionrun', () => { dirty = true; });
  addEventListener('animationstart', () => { dirty = true; });
  setInterval(() => { if (still.matches) dirty = true; }, 250);
}
