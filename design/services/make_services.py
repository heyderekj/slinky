#!/usr/bin/env python3
"""Builds Slinky's service catalog from catalog.txt and the Simple Icons package (CC0).

Writes SlinkyCore/Sources/SlinkyCoreShared/Services.swift and one template image per logo in
Slinky/Assets.xcassets/Logos. Get the package with `npm pack simple-icons` and pass its folder:
    python3 design/services/make_services.py /path/to/package
"""
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
pkg = Path(sys.argv[1])
index = (pkg / 'index.mjs').read_text()
hexes = {}
# Every icon is an object with a slug and, later in the same object, its hex.
for body in re.split(r'(?=slug:")', index)[1:]:
    slug = re.match(r'slug:"([^"]+)"', body)
    hx = re.search(r'hex:"([0-9A-Fa-f]{6})"', body)
    if slug and hx:
        hexes[slug.group(1)] = hx.group(1).upper()

logos = ROOT / 'Slinky' / 'Assets.xcassets' / 'Logos'
shutil.rmtree(logos, ignore_errors=True)
logos.mkdir(parents=True)
(logos / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

def lst(field):
    field = field.strip()
    return [] if field in ('', '-') else [x.strip() for x in field.split(',') if x.strip()]

def swift_list(items):
    return '[' + ', '.join(json.dumps(i) for i in items) + ']'

rows, missing = [], []
for line in (Path(__file__).parent / 'catalog.txt').read_text().splitlines():
    if not line.strip() or line.startswith('#'):
        continue
    parts = [p.strip() for p in line.split('|')]
    sid, name, slug, domains, bundles = parts[:5]
    aliases = lst(parts[5]) if len(parts) > 5 else []
    svg = pkg / 'icons' / f'{slug}.svg'
    has_logo = slug != '-' and svg.exists()
    if slug != '-' and not has_logo:
        missing.append(slug)
    color = hexes.get(slug) if has_logo else None
    if has_logo:
        d = logos / f'logo-{sid}.imageset'
        d.mkdir()
        # Drop the <title> so nothing but the shape is in the app.
        (d / f'{sid}.svg').write_text(re.sub(r'<title>.*?</title>', '', svg.read_text()))
        (d / 'Contents.json').write_text(json.dumps({
            'images': [{'filename': f'{sid}.svg', 'idiom': 'universal'}],
            'info': {'author': 'xcode', 'version': 1},
            'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'},
        }, indent=2) + '\n')
    rows.append(f'        Service(id: {json.dumps(sid)}, name: {json.dumps(name)}, domains: {swift_list(lst(domains))}, '
                f'bundleIDs: {swift_list(lst(bundles))}, aliases: {swift_list(aliases)}, '
                f'color: {("0x" + color) if color else "nil"}, hasLogo: {"true" if has_logo else "false"}),')

out = ROOT / 'SlinkyCore' / 'Sources' / 'SlinkyCoreShared' / 'Services.swift'
template = (Path(__file__).parent / 'Services.swift.tpl').read_text()
out.write_text(template.replace('{{ROWS}}', '\n'.join(rows)))
print(f'{len(rows)} services, {sum("hasLogo: true" in r for r in rows)} logos', file=sys.stderr)
if missing:
    print('No Simple Icons logo for: ' + ', '.join(missing), file=sys.stderr)
