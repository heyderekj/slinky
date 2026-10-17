"""Generates the Slinky app icon (light + dark). Tweak the constants and rerun."""
import math

ARC_CX, ARC_CY, ARC_R = 500, 639, 330   # arch center and radius
AST_R, W = 72, 52                       # asterisk arm length, arm thickness
TILT = -8                               # degrees, family-style slight tilt
RIM = (4, 5)                            # crisp rim light offset (light from upper left)
INNER = (-6, -7)                        # inner shadow offset

def ast(cx, cy, r, rot):
    s = ''
    for i in range(3):
        a = math.radians(rot + i * 60)
        s += f'M{cx+r*math.cos(a):.1f} {cy+r*math.sin(a):.1f}L{cx-r*math.cos(a):.1f} {cy-r*math.sin(a):.1f}'
    return s

D = ''
for i in range(5):
    t = 180 - 180 * i / 4
    th = math.radians(t)
    D += ast(ARC_CX + ARC_R * math.cos(th), ARC_CY - ARC_R * math.sin(th), AST_R, 90 - t + i * 15)
T = f'rotate({TILT} 512 512)'

def P(stroke, extra='', tr=''):
    return f'<path d="{D}" transform="{tr}{T}" fill="none" stroke="{stroke}" stroke-width="{W}" stroke-linecap="round"{extra}/>'

def icon(p):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>
<linearGradient id="bg" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="{p['bg0']}"/><stop offset="1" stop-color="{p['bg1']}"/></linearGradient>
<radialGradient id="frost" cx="0.2" cy="0.06" r="0.85"><stop offset="0" stop-color="{p['glow']}" stop-opacity="{p['glowo']}"/><stop offset="1" stop-color="{p['glow']}" stop-opacity="0"/></radialGradient>
<linearGradient id="glass" gradientUnits="userSpaceOnUse" x1="250" y1="300" x2="760" y2="800"><stop offset="0" stop-color="{p['g0']}"/><stop offset="1" stop-color="{p['g1']}"/></linearGradient>
<filter id="sh" x="-20%" y="-20%" width="150%" height="160%"><feDropShadow dx="12" dy="17" stdDeviation="15" flood-color="{p['sh']}" flood-opacity="{p['sho']}"/></filter>
<filter id="blur" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="2"/></filter>
<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">{P('#fff')}</mask>
<mask id="notUL" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/>{P('#000', '', f'translate({INNER[0]} {INNER[1]}) ')}</mask>
<mask id="notDR" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/>{P('#000', '', f'translate({RIM[0]} {RIM[1]}) ')}</mask>
</defs>
<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#frost)"/>
<rect x="6" y="6" width="1012" height="1012" fill="none" stroke="{p['edge']}" stroke-width="12" stroke-opacity="{p['edgeo']}"/>
{P(p['g1'], ' filter="url(#sh)"')}
<g mask="url(#m)">
  {P('url(#glass)')}
  <g filter="url(#blur)"><rect width="1024" height="1024" fill="{p['inner']}" fill-opacity="{p['innero']}" mask="url(#notUL)"/></g>
  <g><rect width="1024" height="1024" fill="{p['hi']}" fill-opacity="{p['hio']}" mask="url(#notDR)"/></g>
</g></svg>'''

LIGHT = dict(bg0='#f8fcff', bg1='#d6e7f4', glow='#ffffff', glowo='.95', edge='#ffffff', edgeo='.95',
             g0='#e6f0f8', g1='#cbdeed', sh='#4f7698', sho='.3', inner='#6f97b8', innero='.45', hi='#ffffff', hio='1')
DARK = dict(bg0='#1a222a', bg1='#06080a', glow='#5d7387', glowo='.25', edge='#ffffff', edgeo='.06',
            g0='#4a5866', g1='#2f3a45', sh='#000000', sho='.7', inner='#05080b', innero='.55', hi='#a9bccb', hio='.55')

if __name__ == '__main__':
    open('slinky-icon-ice-light.svg', 'w').write(icon(LIGHT))
    open('slinky-icon-ice-dark.svg', 'w').write(icon(DARK))
    gap = 2 * ARC_R * math.sin(math.radians(22.5)) - 2 * (AST_R + W / 2)
    print(f'gap between neighbours ≈ {gap:.0f}px of 1024 ({gap/1024*64:.1f}px at 64px)')
