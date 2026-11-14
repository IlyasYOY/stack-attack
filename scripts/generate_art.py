#!/usr/bin/env python3
"""Hand-authored original pixel sprites. Re-run with Pillow; no borrowed assets."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / 'art'
ROOT.mkdir(exist_ok=True)
for name, mid, light, dark in [
    ('copper', '#b86737', '#f7c575', '#56374a'),
    ('teal', '#438f85', '#a9d8ac', '#284d62'),
    ('violet', '#7c648f', '#d3a0b0', '#413652'),
]:
    image = Image.new('RGBA', (24, 24))
    d = ImageDraw.Draw(image)
    d.rectangle((0, 0, 23, 23), fill='#172333')
    d.rectangle((1, 1, 22, 22), fill=dark)
    d.rectangle((2, 2, 21, 20), fill=mid)
    d.rectangle((3, 3, 20, 4), fill=light)
    for x in [7, 15]:
        d.line((x, 5, x, 19), fill=dark)
    for i in range(16):
        d.rectangle((4+i, 5+i, 5+i, 6+i), fill=dark)
        d.point((4+i, 4+i), fill=light)
    for x,y in [(3,3),(20,3),(3,20),(20,20)]:
        d.point((x,y),fill='#f7de9e')
    d.rectangle((5, 19, 18, 20), fill=dark)
    image.save(ROOT / f'crate_{name}.png')

for frame in ['idle', 'walk']:
    image = Image.new('RGBA', (14, 22))
    d = ImageDraw.Draw(image)
    outline='#1d2638'; skin='#f6c28e'; shade='#bf826f'
    d.rectangle((3,0,10,2),fill=outline)
    d.rectangle((2,2,11,6),fill=outline)
    d.rectangle((3,1,10,4),fill='#3e8d94')
    d.rectangle((2,3,12,4),fill='#77c3b2')
    d.rectangle((4,5,10,8),fill=skin)
    d.rectangle((3,6,4,7),fill=shade)
    d.point((9,6),fill=outline)
    d.rectangle((3,9,10,16),fill=outline)
    d.rectangle((4,10,9,15),fill='#d5a249')
    d.rectangle((4,10,5,14),fill='#f5d578')
    d.rectangle((2,10,3,14),fill='#e6ae65')
    d.rectangle((10,11,11,14),fill='#a86e46')
    d.rectangle((2,14,3,15),fill=skin)
    d.rectangle((10,14,11,15),fill=skin)
    d.rectangle((3,9,10,10),fill='#b95161')
    d.rectangle((0,10,3,11),fill='#dc7a78')
    if frame=='idle':
        d.rectangle((4,17,6,20),fill='#477984')
        d.rectangle((8,17,10,20),fill='#325369')
        d.rectangle((3,20,6,21),fill=outline)
        d.rectangle((8,20,11,21),fill=outline)
    else:
        d.rectangle((3,17,5,19),fill='#477984')
        d.rectangle((9,17,11,20),fill='#325369')
        d.rectangle((2,19,5,20),fill=outline)
        d.rectangle((9,20,12,21),fill=outline)
    image.save(ROOT / f'hero_{frame}.png')

image = Image.new("RGBA", (10, 18))
d = ImageDraw.Draw(image)
d.rectangle((0, 0, 9, 17), fill="#152b36")
d.rectangle((1, 1, 8, 16), fill="#d7a45a")
d.rectangle((2, 2, 7, 15), fill="#8dc6ac")
d.line((3, 4, 3, 13), fill="#f4e3ba")
image.save(ROOT / "slider_knob.png")
