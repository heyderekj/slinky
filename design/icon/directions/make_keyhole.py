"""Keyhole icon: one big glass asterisk with a recessed keyhole. Variants differ in keyhole shape/placement."""
import math
from make_directions import BG, doc, glass, ast_path

T = 'rotate(-8 512 512)'
BIG = ast_path(512, 512, 270, 90)

def bigast(p, tr):
    return f'<path d="{BIG}" transform="{tr}{T}" fill="none" stroke="{p}" stroke-width="150" stroke-linecap="round"/>'

def keyhole_classic(cy, r, slot_top, slot_bot, slot_h):
    """Circle on top, flared slot below, one closed outline."""
    cx = 512
    dx = slot_top / 2
    dy = math.sqrt(r * r - dx * dx)
    y0 = cy + dy
    return (f'M{cx-slot_bot/2:.1f} {y0+slot_h:.1f} L{cx-dx:.1f} {y0:.1f} '
            f'A{r} {r} 0 1 1 {cx+dx:.1f} {y0:.1f} L{cx+slot_bot/2:.1f} {y0+slot_h:.1f} Z')

def keyhole_rounded(cy, r, slot_w, slot_h):
    """Modern keyhole: circle plus a round-ended slot (SF Symbols feel)."""
    cx = 512
    dx = slot_w / 2
    dy = math.sqrt(r * r - dx * dx)
    y0 = cy + dy
    yb = y0 + slot_h
    return (f'M{cx-dx:.1f} {y0:.1f} A{r} {r} 0 1 1 {cx+dx:.1f} {y0:.1f} '
            f'L{cx+dx:.1f} {yb:.1f} A{dx} {dx} 0 0 1 {cx-dx:.1f} {yb:.1f} Z')

def build(hole, depth=1.0):
    d, b = glass('k', bigast)
    d += ('<linearGradient id="holeg" gradientUnits="userSpaceOnUse" x1="440" y1="400" x2="590" y2="640">'
          '<stop offset="0" stop-color="#1f3f5e"/><stop offset="1" stop-color="#4f7fa8"/></linearGradient>'
          f'<mask id="hole" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/><path d="{hole}" transform="{T}" fill="#000"/></mask>'
          f'<mask id="inhole" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><path d="{hole}" transform="{T}" fill="#fff"/></mask>'
          f'<mask id="shadeTL" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/><path d="{hole}" transform="translate({10*depth:.0f} {12*depth:.0f}) {T}" fill="#000"/></mask>'
          f'<mask id="litBR" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/><path d="{hole}" transform="translate(-3 -4) {T}" fill="#000"/></mask>')
    b = (f'<g mask="url(#hole)">{b}</g>'
         f'<g mask="url(#inhole)"><path d="{hole}" transform="{T}" fill="url(#holeg)"/>'
         f'<g filter="url(#blur)"><rect width="1024" height="1024" fill="#0b1b2a" fill-opacity=".55" mask="url(#shadeTL)"/></g>'
         f'<rect width="1024" height="1024" fill="#ffffff" fill-opacity=".85" mask="url(#litBR)"/></g>')
    return doc(d, b)

VARIANTS = {
    'K1-centered':  keyhole_classic(cy=474, r=54, slot_top=46, slot_bot=88, slot_h=118),
    'K2-rounded':   keyhole_rounded(cy=468, r=56, slot_w=50, slot_h=104),
    'K3-small-deep': keyhole_classic(cy=486, r=42, slot_top=36, slot_bot=66, slot_h=90),
}
if __name__ == '__main__':
    for k, hole in VARIANTS.items():
        open(f'slinky-keyhole-{k}.svg', 'w').write(build(hole, depth=1.3 if 'deep' in k else 1.0))
    print(', '.join(VARIANTS))
