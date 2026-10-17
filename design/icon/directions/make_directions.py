"""Five alternative Slinky icon directions in the shared glass language (light from upper left)."""
import math

BG = '''<linearGradient id="bg" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="#f8fcff"/><stop offset="1" stop-color="#d6e7f4"/></linearGradient>
<radialGradient id="frost" cx="0.2" cy="0.06" r="0.85"><stop offset="0" stop-color="#ffffff" stop-opacity=".95"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>
<linearGradient id="glass" gradientUnits="userSpaceOnUse" x1="250" y1="250" x2="780" y2="820"><stop offset="0" stop-color="#f3f8fc"/><stop offset="1" stop-color="#cfe1ef"/></linearGradient>
<linearGradient id="glassT" gradientUnits="userSpaceOnUse" x1="250" y1="250" x2="780" y2="820"><stop offset="0" stop-color="#ffffff" stop-opacity=".78"/><stop offset="1" stop-color="#cfe1ef" stop-opacity=".55"/></linearGradient>
<filter id="sh" x="-30%" y="-30%" width="170%" height="180%"><feDropShadow dx="12" dy="17" stdDeviation="15" flood-color="#4f7698" flood-opacity=".3"/></filter>
<filter id="blur" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="2"/></filter>
<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3.5"/></filter>'''
INK = '#5f8fb8'

def doc(defs, body):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>{BG}{defs}</defs>
<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#frost)"/>
<rect x="6" y="6" width="1012" height="1012" fill="none" stroke="#fff" stroke-width="12" stroke-opacity=".95"/>{body}</svg>'''

def glass(key, frag, paint='url(#glass)', rim=(4, 5), inner=(-6, -7), shadow=True, rim_op='1', inner_op='.42'):
    """frag(paint, tr) -> svg string for the shape painted with `paint`, translated by `tr`."""
    defs = (f'<mask id="{key}m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">{frag("#fff", "")}</mask>'
            f'<mask id="{key}ul" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/>{frag("#000", f"translate({inner[0]} {inner[1]}) ")}</mask>'
            f'<mask id="{key}dr" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/>{frag("#000", f"translate({rim[0]} {rim[1]}) ")}</mask>')
    body = (f'<g filter="url(#sh)">{frag("#dbe8f3", "")}</g>' if shadow else '')
    body += (f'<g mask="url(#{key}m)">{frag(paint, "")}'
             f'<g filter="url(#blur)"><rect width="1024" height="1024" fill="#6f97b8" fill-opacity="{inner_op}" mask="url(#{key}ul)"/></g>'
             f'<rect width="1024" height="1024" fill="#fff" fill-opacity="{rim_op}" mask="url(#{key}dr)"/></g>')
    return defs, body

def ast_path(cx, cy, r, rot):
    s = ''
    for i in range(3):
        a = math.radians(rot + i * 60)
        s += f'M{cx+r*math.cos(a):.1f} {cy+r*math.sin(a):.1f}L{cx-r*math.cos(a):.1f} {cy-r*math.sin(a):.1f}'
    return s

out = {}

# 1. Password field: a glass pill holding five ice asterisks and a cursor.
T1 = 'rotate(-8 512 512)'
pill = lambda p, tr: f'<rect x="152" y="392" width="720" height="240" rx="120" transform="{tr}{T1}" fill="{p}"/>'
d, b = glass('p', pill)
stars = ''.join(ast_path(286 + i * 102, 512, 34, 90) for i in range(5))
b += f'<path d="{stars}" transform="{T1}" fill="none" stroke="{INK}" stroke-width="15" stroke-linecap="round"/>'
b += f'<rect x="806" y="456" width="14" height="112" rx="7" transform="{T1}" fill="{INK}" fill-opacity=".55"/>'
out['1-field'] = doc(d, b)

# 2. Glass Slinky: translucent coils walking in an arch, bunched at the feet.
rings = []
n = 15
for i in range(n):
    u = i / (n - 1)
    u = 0.5 - 0.5 * math.cos(math.pi * u)            # bunch coils near both feet
    t = math.radians(180 - 180 * u)
    cx, cy = 512 + 300 * math.cos(t), 690 - 330 * math.sin(t)
    ang = math.degrees(math.atan2(-math.sin(t) * 330, math.cos(t) * 300))  # radial direction
    rings.append((cx, cy, ang))
def coils(p, tr):
    return ''.join(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="24" ry="104" transform="{tr}rotate(-6 512 512) rotate({a+90:.1f} {x:.1f} {y:.1f})" fill="none" stroke="{p}" stroke-width="20"/>' for x, y, a in rings)
d, b = glass('s', coils, paint='url(#glassT)', inner_op='.5')
out['2-glass-slinky'] = doc(d, b)

# 3. Ice cube (cold storage): a rounded glass cube with an asterisk frozen inside.
T3 = 'rotate(-6 512 512)'
top = 'M512 238 L770 362 L512 486 L254 362 Z'
left = 'M254 362 L512 486 L512 790 L254 666 Z'
right = 'M512 486 L770 362 L770 666 L512 790 Z'
inside = ast_path(512, 560, 120, 90)
cube_shape = lambda p, tr: f'<path d="{top}{left}{right}" transform="{tr}{T3}" fill="{p}" stroke="{p}" stroke-width="44" stroke-linejoin="round"/>'
d, b = glass('c', cube_shape, paint='url(#glassT)')
b += f'<g transform="{T3}"><path d="{inside}" fill="none" stroke="{INK}" stroke-opacity=".55" stroke-width="52" stroke-linecap="round" filter="url(#soft)"/>'
b += f'<path d="{left}" fill="#ffffff" fill-opacity=".18"/><path d="{right}" fill="#7fa6c6" fill-opacity=".16"/><path d="{top}" fill="#ffffff" fill-opacity=".45"/>'
b += f'<path d="M254 362 L512 486 L770 362 M512 486 L512 790" fill="none" stroke="#ffffff" stroke-opacity=".9" stroke-width="6" stroke-linecap="round"/></g>'
out['3-ice-cube'] = doc(d, b)

# 4. Layers: three translucent glass cards stacked in depth, the front one masked with *****.
cards = [(-64, -70, '.6'), (-32, -35, '.8'), (0, 0, '1')]
d_all, b_all = '', ''
for k, (dx, dy, op) in enumerate(cards):
    shape = lambda p, tr, dx=dx, dy=dy: f'<rect x="{262+dx}" y="{364+dy}" width="560" height="380" rx="70" transform="{tr}rotate(-8 512 512)" fill="{p}"/>'
    d, b = glass(f'l{k}', shape, paint='url(#glassT)')
    d_all += d; b_all += f'<g opacity="{op}">{b}</g>'
stars = ''.join(ast_path(382 + i * 80, 592, 28, 90) for i in range(5))
b_all += f'<path d="{stars}" transform="rotate(-8 512 512)" fill="none" stroke="{INK}" stroke-width="13" stroke-linecap="round"/>'
out['4-layers'] = doc(d_all, b_all)

# 5. Keyhole: one big glass asterisk with a keyhole cut through its middle.
T5 = 'rotate(-8 512 512)'
big = ast_path(512, 512, 270, 90)
keyhole = 'M456 640 L486 466 A62 62 0 1 1 538 466 L568 640 Z'
def bigast(p, tr):
    return f'<path d="{big}" transform="{tr}{T5}" fill="none" stroke="{p}" stroke-width="150" stroke-linecap="round"/>'
d, b = glass('k', bigast)
d += f'<mask id="hole" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/><path d="{keyhole}" transform="{T5}" fill="#000"/></mask>'
d += '<linearGradient id="holeg" gradientUnits="userSpaceOnUse" x1="0" y1="400" x2="0" y2="650"><stop offset="0" stop-color="#2f557a"/><stop offset="1" stop-color="#5f8fb8"/></linearGradient>'
b = f'<g mask="url(#hole)">{b}</g><path d="{keyhole}" transform="{T5}" fill="url(#holeg)"/><path d="{keyhole}" transform="translate(4 5) {T5}" fill="none" stroke="#ffffff" stroke-opacity=".8" stroke-width="4"/>'
out['5-keyhole'] = doc(d, b)

for k, v in out.items():
    open(f'slinky-dir-{k}.svg', 'w').write(v)
print(', '.join(out))
