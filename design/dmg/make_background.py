#!/usr/bin/env python3
"""The DMG window background: Slinky's icon on the left, Applications on the right, a gentle arrow
between, and one line saying what to do. Mid-tone glacier blue so Finder's icon labels read in both
light mode (black text) and dark mode (white text): the label row sits near luminance 0.19, about
4.5:1 against either. Window content is 600 x 380 pt; icons are centered at (160, 172) and (440, 172).

Renders dmg-background.png (1x) and dmg-background@2x.png, then release.sh combines them into a TIFF.
"""
import pathlib, subprocess

W, H = 600, 380
LEFT, RIGHT, Y = 160, 440, 172

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="ground" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#6F98BE"/>
      <stop offset="0.55" stop-color="#557EA3"/>
      <stop offset="1" stop-color="#456E93"/>
    </linearGradient>
    <radialGradient id="light" cx="0.18" cy="0.0" r="0.75">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.30"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="pool" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.38"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.08"/>
    </linearGradient>
    <linearGradient id="tray" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.13"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.04"/>
    </linearGradient>
    <marker id="head" viewBox="0 0 10 10" refX="6.5" refY="5" markerWidth="6.2" markerHeight="6.2" orient="auto">
      <path d="M1.5 1.5 L7 5 L1.5 8.5" fill="none" stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>
    </marker>
  </defs>

  <rect width="{W}" height="{H}" fill="url(#ground)"/>
  <rect width="{W}" height="{H}" fill="url(#light)"/>

  <!-- A frosted glass tray the two icons sit on -->
  <rect x="58" y="78" width="484" height="210" rx="34" fill="url(#tray)" stroke="url(#rim)" stroke-width="1"/>

  <!-- Soft light under each icon -->
  <ellipse cx="{LEFT}" cy="{Y}" rx="96" ry="84" fill="url(#pool)"/>
  <ellipse cx="{RIGHT}" cy="{Y}" rx="96" ry="84" fill="url(#pool)"/>

  <!-- The arrow: one easy arc, dotted like something on its way -->
  <path d="M {LEFT + 82} {Y - 6} C {LEFT + 120} {Y - 46}, {RIGHT - 120} {Y - 46}, {RIGHT - 84} {Y - 6}"
        fill="none" stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="2.6" stroke-linecap="round"
        stroke-dasharray="0.1 9" marker-end="url(#head)"/>

  <!-- What to do -->
  <text x="{W/2}" y="334" text-anchor="middle" font-family="SF Pro Display, SF Pro Text, Helvetica Neue, Helvetica, sans-serif"
        font-size="14" font-weight="500" fill="#FFFFFF" fill-opacity="0.92" letter-spacing="0.1">Drag Slinky into Applications</text>
  <text x="{W/2}" y="354" text-anchor="middle" font-family="SF Pro Text, Helvetica Neue, Helvetica, sans-serif"
        font-size="11" font-weight="400" fill="#FFFFFF" fill-opacity="0.62">Slinky keeps secrets out of files.</text>
</svg>
'''

here = pathlib.Path(__file__).parent
(here / "dmg-background.svg").write_text(svg)
for scale, name in [(1, "dmg-background.png"), (2, "dmg-background@2x.png")]:
    subprocess.run(["rsvg-convert", "-w", str(W * scale), "-h", str(H * scale), "-o", str(here / name), str(here / "dmg-background.svg")], check=True)
subprocess.run(["tiffutil", "-cathidpicheck", str(here / "dmg-background.png"), str(here / "dmg-background@2x.png"),
                "-out", str(here / "dmg-background.tiff")], check=True, capture_output=True)
print("wrote dmg-background.png, @2x and the combined dmg-background.tiff")
