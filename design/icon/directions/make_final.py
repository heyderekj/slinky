"""Final Slinky icon: glass asterisk with a rounded (K2) keyhole. Writes light + dark into design/icon/."""
from make_keyhole import build, keyhole_rounded

HOLE = keyhole_rounded(cy=440, r=62, slot_w=54, slot_h=118)

DARK_SWAPS = [
    ('stop-color="#f8fcff"', 'stop-color="#1a222a"'), ('stop-color="#d6e7f4"', 'stop-color="#06080a"'),
    ('stop-color="#ffffff" stop-opacity=".95"', 'stop-color="#5d7387" stop-opacity=".25"'),
    ('stroke="#fff" stroke-width="12" stroke-opacity=".95"', 'stroke="#fff" stroke-width="12" stroke-opacity=".06"'),
    ('stop-color="#f3f8fc"', 'stop-color="#4a5866"'), ('stop-color="#cfe1ef"/>', 'stop-color="#2f3a45"/>'),
    ('flood-color="#4f7698" flood-opacity=".3"', 'flood-color="#000000" flood-opacity=".7"'),
    ('stroke="#dbe8f3"', 'stroke="#2f3a45"'),
    ('fill="#6f97b8" fill-opacity=".42"', 'fill="#05080b" fill-opacity=".55"'),
    ('fill="#fff" fill-opacity="1"', 'fill="#a9bccb" fill-opacity=".55"'),
    ('stop-color="#1f3f5e"', 'stop-color="#020507"'), ('stop-color="#4f7fa8"', 'stop-color="#14202b"'),
    ('fill="#ffffff" fill-opacity=".85" mask="url(#litBR)"', 'fill="#a9bccb" fill-opacity=".45" mask="url(#litBR)"'),
]

if __name__ == '__main__':
    light = build(HOLE)
    dark = light
    for a, b in DARK_SWAPS:
        assert a in dark, a
        dark = dark.replace(a, b)
    open('../slinky-icon-keyhole-light.svg', 'w').write(light)
    open('../slinky-icon-keyhole-dark.svg', 'w').write(dark)
    print('wrote design/icon/slinky-icon-keyhole-light.svg and -dark.svg')
