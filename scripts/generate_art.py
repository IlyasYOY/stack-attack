"""Original workshop pixel art, hand drawn here; no reference image pixels used."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[1] / 'art'
ROOT.mkdir(exist_ok=True)
INK = '#102733'

def bolt(d, x, y):
    d.rectangle((x - 2, y - 2, x + 2, y + 2), fill='#45555c')
    d.rectangle((x - 1, y - 1, x + 1, y + 1), fill='#e6d5ad')
    d.point((x + 1, y + 1), fill='#8d8878')
for kind in ['copper', 'teal', 'violet']:
    image = Image.new('RGBA', (48, 48))
    d = ImageDraw.Draw(image)
    d.rectangle((0, 0, 47, 47), fill=INK)
    if kind == 'copper':
        d.rectangle((2, 2, 45, 45), fill='#633c2b')
        for x in range(4, 44, 9):
            d.rectangle((x, 5, x + 7, 41), fill='#b97035')
            d.line((x + 1, 6, x + 1, 40), fill='#d28a45')
            d.line((x + 7, 8, x + 7, 39), fill='#804b2a')
            d.line((x + 3, 16, x + 3, 24), fill='#a65e2f')
            d.line((x + 4, 29, x + 4, 35), fill='#dc944e')
        for box in [(2, 2, 45, 8), (2, 39, 45, 45), (2, 8, 7, 39), (40, 8, 45, 39)]:
            d.rectangle(box, fill='#d08b43')
        d.line((3, 3, 44, 3), fill='#ffe1a1', width=2)
        d.line((3, 40, 44, 40), fill='#edb96e')
        d.rectangle((3, 44, 45, 46), fill='#523a2e')
        d.polygon([(4, 37), (37, 4), (44, 4), (44, 10), (11, 43), (4, 43)], fill='#68422c')
        d.polygon([(5, 37), (38, 4), (43, 5), (43, 9), (10, 42), (5, 42)], fill='#d9954d')
        d.line((7, 37, 39, 5), fill='#f5c178', width=2)
        d.line((10, 41, 43, 8), fill='#a76030')
    elif kind == 'teal':
        d.rectangle((2, 2, 45, 45), fill='#254a53')
        d.rectangle((5, 5, 42, 42), fill='#367b80')
        for x in [14, 25, 36]:
            d.line((x, 7, x, 40), fill='#285c65')
            d.line((x + 1, 8, x + 1, 39), fill='#4c9291')
        for a, b in [((6, 6), (41, 41)), ((6, 41), (41, 6))]:
            d.line((*a, *b), fill='#183d4b', width=9)
            d.line((a[0], a[1] - 1, b[0], b[1] - 1), fill='#88b9ae', width=5)
            d.line((a[0], a[1] + 2, b[0], b[1] + 2), fill='#457b7d', width=2)
        for box in [(2, 2, 45, 7), (2, 40, 45, 45), (2, 7, 7, 40), (40, 7, 45, 40)]:
            d.rectangle(box, fill='#638e8d')
        d.line((3, 3, 44, 3), fill='#c0d7c0', width=2)
        d.line((3, 41, 44, 41), fill='#a6c6b1')
        d.rectangle((3, 45, 46, 46), fill='#254552')
    else:
        d.rectangle((2, 2, 45, 45), fill='#4c4358')
        d.rectangle((5, 5, 42, 42), fill='#89748c')
        d.rectangle((7, 7, 40, 40), fill='#675b76')
        for y in [12, 20, 28]:
            d.rectangle((10, y, 37, y + 4), fill='#263344')
            d.line((11, y - 1, 36, y - 1), fill='#b8a1af')
            d.line((12, y + 4, 36, y + 4), fill='#a28a9b')
        d.rectangle((2, 2, 45, 6), fill='#a08b9e')
        d.line((4, 3, 43, 3), fill='#d8c7c3')
        d.rectangle((3, 41, 45, 45), fill='#77677f')
        d.line((34, 34, 40, 39), fill='#e1ad4b', width=3)
        d.line((37, 34, 32, 39), fill='#e1ad4b', width=2)
    for x, y in [(5, 5), (42, 5), (5, 42), (42, 42)]:
        bolt(d, x, y)
    image.save(ROOT / f'crate_{kind}.png')
for frame in ['idle', 'walk', 'jump', 'push']:
    for equipped in [False, True]:
        image = Image.new('RGBA', (32, 48))
        d = ImageDraw.Draw(image)
        d.rectangle((9, 37, 23, 41), fill=INK)
        if frame == 'walk':
            legs = [(8, 40, 13, 45), (20, 41, 25, 46)]
            boots = [(6, 44, 14, 47), (20, 45, 27, 47)]
        elif frame == 'jump':
            legs = [(7, 39, 13, 43), (19, 39, 25, 43)]
            boots = [(5, 42, 14, 45), (19, 42, 27, 45)]
        else:
            legs = [(10, 40, 14, 46), (18, 40, 22, 46)]
            boots = [(8, 45, 15, 47), (18, 45, 25, 47)]
        for box in legs:
            d.rectangle(box, fill='#254a57')
            d.line((box[0] + 1, box[1], box[0] + 1, box[3]), fill='#4b7880')
        for box in boots:
            d.rectangle(box, fill='#172a34')
            d.line((box[0] + 1, box[1], box[2] - 1, box[1]), fill='#a17b50')
        d.rectangle((8, 24, 23, 39), fill=INK)
        d.rectangle((10, 25, 21, 36), fill='#dfcba0')
        d.rectangle((11, 26, 13, 34), fill='#fff0bf')
        d.rectangle((20, 26, 21, 35), fill='#a49c84')
        d.line((16, 26, 16, 34), fill='#9f9274')
        d.point((17, 29), fill='#765e40')
        d.point((17, 33), fill='#765e40')
        d.rectangle((9, 36, 22, 39), fill='#584532')
        d.rectangle((14, 36, 18, 39), fill='#d9aa55')
        d.rectangle((15, 37, 17, 38), fill='#705237')
        d.rectangle((6, 26, 9, 35), fill='#ac936d')
        d.rectangle((7, 27, 8, 32), fill='#e2cfa0')
        arm = (23, 28, 28, 34) if frame == 'push' else (22, 27, 25, 36)
        d.rectangle(arm, fill='#9a825f')
        d.rectangle((arm[0], arm[1], arm[2] - 1, arm[1] + 3), fill='#d4c59f')
        d.rectangle((arm[0], arm[3] - 1, min(31, arm[2] + 1), arm[3] + 3), fill='#f1bb83')
        d.line((arm[0], arm[3] + 3, min(31, arm[2] + 1), arm[3] + 3), fill='#81573f')
        d.rectangle((8, 21, 23, 25), fill='#8f4232')
        d.rectangle((9, 22, 22, 24), fill='#e97843')
        d.line((10, 22, 21, 22), fill='#ffb46b')
        d.polygon([(7, 23), (8, 24), (5, 29), (3, 28)], fill='#b95536')
        d.rectangle((5, 10, 26, 21), fill=INK)
        d.rectangle((7, 11, 24, 20), fill='#f0ba84')
        d.rectangle((6, 14, 8, 18), fill='#c17c58')
        d.line((10, 20, 23, 20), fill='#ad6d4c')
        d.rectangle((13, 15, 14, 17), fill='#1a2c32')
        d.rectangle((22, 15, 23, 17), fill='#1a2c32')
        d.rectangle((25, 15, 27, 18), fill='#e5a674')
        d.point((18, 19), fill='#b67352')
        d.rectangle((7, 1, 23, 4), fill=INK)
        d.rectangle((5, 4, 25, 10), fill=INK)
        d.rectangle((8, 2, 21, 3), fill='#5ea9a3')
        d.rectangle((6, 5, 24, 9), fill='#277b82')
        d.line((8, 4, 21, 4), fill='#77c1b1')
        d.rectangle((7, 9, 28, 11), fill='#123f50')
        d.line((9, 9, 27, 9), fill='#65b0a7')
        for x in [13, 21]:
            d.rectangle((x, 5, x + 5, 9), fill='#634934')
            d.rectangle((x + 1, 5, x + 4, 8), fill='#d1a159')
            d.rectangle((x + 2, 6, x + 3, 7), fill='#e5f2da')
        d.rectangle((19, 6, 20, 7), fill='#987047')
        if equipped:
            d.rectangle((0, 31, 3, 39), fill=INK)
            d.rectangle((9, 31, 12, 39), fill=INK)
            d.rectangle((2, 38, 10, 42), fill=INK)
            d.rectangle((1, 32, 3, 38), fill='#d74338')
            d.rectangle((9, 32, 11, 38), fill='#a82e33')
            d.rectangle((3, 38, 9, 40), fill='#d74338')
            d.line((3, 38, 9, 38), fill='#ff8160')
            d.rectangle((1, 30, 3, 33), fill='#d8e0c9')
            d.rectangle((9, 30, 11, 33), fill='#a7c5be')
        d.rectangle((9, 28, 12, 30) if equipped else (6, 29, 9, 32), fill='#f2be88')
        image.save(ROOT / f"hero_{frame}{('' if equipped else '_bare')}.png")
image = Image.new('RGBA', (10, 18))
d = ImageDraw.Draw(image)
d.rectangle((0, 0, 9, 17), fill=INK)
d.rectangle((1, 1, 8, 16), fill='#c89859')
d.rectangle((2, 2, 7, 15), fill='#67aaa3')
d.line((3, 4, 3, 13), fill='#fff0c0')
image.save(ROOT / 'slider_knob.png')
image = Image.new('RGBA', (16, 16))
d = ImageDraw.Draw(image)
for x in [2, 10]:
    d.rectangle((x, 2, x + 4, 14), fill='#102733')
    d.rectangle((x, 1, x + 3, 12), fill='#f4e3ba')
    d.line((x, 1, x + 3, 1), fill='#fff2cb')
image.save(ROOT / 'pause_icon.png')
