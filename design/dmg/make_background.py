#!/usr/bin/env python3
"""The DMG install window background (shipped: the "light" style with the "coil" pattern).

Slinky on the left, Applications on the right, a dotted arc between them, and a faint Slinky coil arching
behind, on a flat soft off-white. No text: the arrow says it.

What Finder allows (tested on macOS 26, 2026-10-17):
- A background picture is one fixed image. It can't follow light/dark mode.
- With a picture, Finder draws icon labels BLACK in both modes. So dark backgrounds are out.
- Transparent parts of a picture are filled with WHITE, even in dark mode. So "system background
  plus a pattern" isn't possible.
- Only Finder's plain default background follows the mode, and it can't show any art.

Usage: python3 make_background.py [style] [out_dir] [pattern]. With no arguments it writes the shipped
files next to this script. Other styles and patterns are kept for comparison.
"""
import pathlib, subprocess

W, H = 600, 380
LEFT, RIGHT, Y = 160, 440, 178

import math

def asterisk(cx, cy, r):
    """Three strokes through the center, tilted -8 degrees like the icon."""
    parts = []
    for i in range(3):
        a = math.radians(90 + i * 60 - 8)
        dx, dy = r * math.cos(a), r * math.sin(a)
        parts.append(f"M {cx + dx:.2f} {cy - dy:.2f} L {cx - dx:.2f} {cy + dy:.2f}")
    return " ".join(parts)

import sys

# Palettes: ground gradient (top, middle, bottom), sheen, asterisk color + opacity, arrow color.
PALETTES = {
    "glacier":  dict(top="#6F98BE", mid="#557EA3", bottom="#456E93", sheen=0.30, star="#FFFFFF", star_op=0.30, arrow="#FFFFFF"),
    "dark":     dict(top="#26282C", mid="#1D1F22", bottom="#17181B", sheen=0.06, star="#FFFFFF", star_op=0.10, arrow="#FFFFFF"),
    "light":    dict(top="#F7F8FA", mid="#F7F8FA", bottom="#F7F8FA", sheen=0.0, star="#8E8E93", star_op=1.0, arrow="#8E8E93", mult=2.1),
    "blue":     dict(top="#4A7AA3", mid="#4A7AA3", bottom="#4A7AA3", sheen=0.0, star="#FFFFFF", star_op=1.0, arrow="#FFFFFF"),
    "night":    dict(top="#1E1F22", mid="#1E1F22", bottom="#1E1F22", sheen=0.0, star="#FFFFFF", star_op=1.0, arrow="#FFFFFF", mult=1.3),
    "clear":    dict(top="none", mid="none", bottom="none", sheen=0.0, star="#8E8E93", star_op=1.0, arrow="#8E8E93", mult=2.6),
    "graphite": dict(top="#86898F", mid="#76797F", bottom="#6A6D73", sheen=0.16, star="#FFFFFF", star_op=0.16, arrow="#FFFFFF"),
}
STYLE = sys.argv[1] if len(sys.argv) > 1 else "light"
P = PALETTES[STYLE]
PATTERN = sys.argv[3] if len(sys.argv) > 3 else "coil"

import random

def clear(x, y, pad=0):
    """Keep asterisks off the icons, their labels and the arrow."""
    for cx in (LEFT, RIGHT):
        if ((x - cx) / (92 + pad)) ** 2 + ((y - (Y + 14)) / (96 + pad)) ** 2 < 1:
            return False
    return not (LEFT + 70 - pad < x < RIGHT - 70 + pad and Y - 70 - pad < y < Y + 10 + pad)

def scatter():
    """A sparse, irregular sprinkle at different sizes and strengths: snowfall, not wallpaper.
    Seeded, so it's the same every build."""
    rng = random.Random(7)
    placed, out = [], []
    tries = 0
    while len(placed) < 34 and tries < 6000:
        tries += 1
        x, y = rng.uniform(-6, W + 6), rng.uniform(-6, H + 6)
        r = rng.choice([3.2, 3.6, 4.2, 5, 6, 7.5, 9.5])
        if not clear(x, y, r): continue
        if any((x - px) ** 2 + (y - py) ** 2 < (42 + r + pr) ** 2 for px, py, pr in placed): continue
        placed.append((x, y, r))
        op = rng.uniform(0.10, 0.26)
        out.append(f'<path d="{asterisk(x, y, r)}" fill="none" stroke="#FFFFFF" stroke-opacity="{op:.2f}" stroke-width="{max(1.3, r * 0.34):.2f}" stroke-linecap="round"/>')
    return "\n  ".join(out)

def bloom():
    """A few large asterisks bleeding off the corners, like a brand graphic."""
    spots = [(34, 26, 74, 0.10), (590, 372, 118, 0.09), (566, 4, 46, 0.08), (18, 366, 40, 0.08), (300, 404, 30, 0.06)]
    return "\n  ".join(
        f'<path d="{asterisk(x, y, r)}" fill="none" stroke="#FFFFFF" stroke-opacity="{op}" stroke-width="{r * 0.3:.1f}" stroke-linecap="round"/>'
        for x, y, r, op in spots)

# Soft light under the icons, only for the gradient styles. The flat blue stays flat.
POOLS = "" if STYLE in ("blue", "night", "clear", "light") else (f'<ellipse cx="{LEFT}" cy="{Y}" rx="96" ry="84" fill="url(#pool)"/>'
                                    f'<ellipse cx="{RIGHT}" cy="{Y}" rx="96" ry="84" fill="url(#pool)"/>')

def ink(op):
    """Mark color and opacity for the current palette (gray marks need more opacity than white)."""
    return P["star"], min(1.0, op * P.get("mult", 1.0))

def coil():
    """A slinky mid-walk: rings along one big arch, each ring tilted to the curve."""
    out = []
    n = 70
    for i in range(n + 1):
        t = i / n
        x = -40 + t * (W + 80)
        y = 26 + 0.0034 * (x - W / 2) ** 2
        slope = 2 * 0.0034 * (x - W / 2)
        angle = math.degrees(math.atan(slope))
        c, o = ink(0.11)
        out.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="7" ry="30" transform="rotate({angle:.1f} {x:.1f} {y:.1f})" '
                   f'fill="none" stroke="{c}" stroke-opacity="{o:.2f}" stroke-width="1.4"/>')
    return "\n  ".join(out)

def contours():
    """Soft topographic lines, like a map of a glacier."""
    out = []
    rng = random.Random(3)
    waves = [(rng.uniform(0.006, 0.014), rng.uniform(0, 6.3), rng.uniform(8, 22)) for _ in range(3)]
    for k in range(-2, 17):
        base = k * 26
        pts = []
        for xi in range(0, W + 11, 10):
            y = base + sum(a * math.sin(xi * f + ph + k * 0.35) for f, ph, a in waves)
            pts.append(f"{xi},{y:.1f}")
        c, o = ink(0.07 + 0.05 * (k % 3 == 0))
        out.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{c}" stroke-opacity="{o:.2f}" stroke-width="1.1"/>')
    return "\n  ".join(out)

def env():
    """Slinky's idea as texture: rows of KEY=•••••••• in faint monospace, staggered."""
    names = ["STRIPE_SECRET_KEY", "OPENAI_API_KEY", "DATABASE_URL", "RESEND_API_KEY", "GITHUB_TOKEN", "ANTHROPIC_API_KEY",
             "SUPABASE_SECRET_KEY", "AWS_SECRET_ACCESS_KEY", "VERCEL_TOKEN", "SLACK_BOT_TOKEN"]
    out = []
    rng = random.Random(11)
    for row in range(16):
        y = 14 + row * 25
        x = -rng.randint(0, 140)
        line = ""
        while len(line) < 120:
            line += names[rng.randrange(len(names))] + "=" + "•" * rng.randint(8, 16) + "    "
        out.append(f'<text x="{x}" y="{y}" font-family="SF Mono, Menlo, monospace" font-size="12" fill="#FFFFFF" fill-opacity="0.075">{line}</text>')
    return "\n  ".join(out)

def halftone():
    """One big Slinky asterisk, drawn in fine dots behind everything."""
    out = []
    cx, cy, R, half = W / 2, H / 2 + 6, 230, 34
    arms = []
    for i in range(3):
        a = math.radians(90 + i * 60 - 8)
        arms.append(((cx + R * math.cos(a), cy - R * math.sin(a)), (cx - R * math.cos(a), cy + R * math.sin(a))))
    def dist(px, py, a, b):
        (ax, ay), (bx, by) = a, b
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(px - (ax + t * dx), py - (ay + t * dy))
    step = 9
    for gy in range(0, H + step, step):
        for gx in range(0, W + step, step):
            x = gx + (step / 2 if (gy // step) % 2 else 0)
            d = min(dist(x, gy, a, b) for a, b in arms)
            if d < half:
                r = 1.9 * (1 - d / half) ** 0.6 + 0.3
                c, o = ink(0.16)
                out.append(f'<circle cx="{x:.1f}" cy="{gy}" r="{r:.2f}" fill="{c}" fill-opacity="{o:.2f}"/>')
    return "\n  ".join(out)

ART = {"scatter": scatter, "bloom": bloom, "coil": coil, "contours": contours, "env": env, "halftone": halftone}.get(PATTERN, lambda: "")()

# A staggered grid: each 44 x 44 tile holds two asterisks, offset half a tile.
TILE = 44
STAR = asterisk(11, 11, 4.6) + " " + asterisk(33, 33, 4.6)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="ground" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="{P['top']}"/>
      <stop offset="0.55" stop-color="{P['mid']}"/>
      <stop offset="1" stop-color="{P['bottom']}"/>
    </linearGradient>
    <radialGradient id="light" cx="0.18" cy="0.0" r="0.75">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="{P['sheen']}"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="pool" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <pattern id="stars" width="{TILE}" height="{TILE}" patternUnits="userSpaceOnUse">
      <path d="{STAR}" fill="none" stroke="{P['star']}" stroke-width="1.7" stroke-linecap="round"/>
    </pattern>
    <!-- Faded in the middle: clear where the icons and words are, the pattern showing toward the edges. -->
    <radialGradient id="fade" cx="{W/2}" cy="{H/2}" r="{W * 0.6}" gradientUnits="userSpaceOnUse"
                    gradientTransform="translate({W/2} {H/2}) scale(1 0.7) translate({-W/2} {-(H/2)})">
      <stop offset="0.6" stop-color="#000000"/>
      <stop offset="0.97" stop-color="#FFFFFF"/>
    </radialGradient>
    <mask id="edges" maskUnits="userSpaceOnUse" x="0" y="0" width="{W}" height="{H}">
      <rect width="{W}" height="{H}" fill="url(#fade)"/>
    </mask>
    <marker id="head" viewBox="0 0 10 10" refX="6.5" refY="5" markerWidth="6.2" markerHeight="6.2" orient="auto">
      <path d="M1.5 1.5 L7 5 L1.5 8.5" fill="none" stroke="{P['arrow']}" stroke-opacity="0.9" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>
    </marker>
  </defs>

  {"" if STYLE == "clear" else f'<rect width="{W}" height="{H}" fill="url(#ground)"/><rect width="{W}" height="{H}" fill="url(#light)"/>'}

  <!-- Slinky asterisks (the icon's -8 degree tilt) -->
  {ART if PATTERN != "grid" else f'<rect width="{W}" height="{H}" fill="url(#stars)" opacity="{P["star_op"]}"/>'}

  <!-- Soft light under each icon -->
  {POOLS}

  <!-- The arrow: one easy arc, dotted like something on its way -->
  <path d="M {LEFT + 82} {Y - 6} C {LEFT + 120} {Y - 46}, {RIGHT - 120} {Y - 46}, {RIGHT - 84} {Y - 6}"
        fill="none" stroke="{P['arrow']}" stroke-opacity="0.85" stroke-width="2.6" stroke-linecap="round"
        stroke-dasharray="0.1 9" marker-end="url(#head)"/>

</svg>
'''

here = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path(__file__).parent
here.mkdir(parents=True, exist_ok=True)
(here / "dmg-background.svg").write_text(svg)
for scale, name in [(1, "dmg-background.png"), (2, "dmg-background@2x.png")]:
    subprocess.run(["rsvg-convert", "-w", str(W * scale), "-h", str(H * scale), "-o", str(here / name), str(here / "dmg-background.svg")], check=True)
subprocess.run(["tiffutil", "-cathidpicheck", str(here / "dmg-background.png"), str(here / "dmg-background@2x.png"),
                "-out", str(here / "dmg-background.tiff")], check=True, capture_output=True)
print("wrote dmg-background.png, @2x and the combined dmg-background.tiff")
