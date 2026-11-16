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
image = Image.new('RGBA', (48, 48))
d = ImageDraw.Draw(image)
d.rectangle((0, 0, 47, 47), fill=INK)
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
for x, y in [(5, 5), (42, 5), (5, 42), (42, 42)]:
    bolt(d, x, y)
image.save(ROOT / 'crate_wood.png')

ROCKET_BOOT_PIXELS = [
    ".######.....",
    "#bbbbbT#....",
    "#HssTTT#....",
    "#HsTTTd#....",
    "#HsTTTd#....",
    "#ssdddt####.",
    "#TTTddTbccH#",
    "#Hssssssssc#",
    ".##bccb####.",
    "..#too#.....",
    "..#toO#.....",
    ".#bocco#....",
    ".#cocoO#....",
    "..#####.....",
]
ROCKET_BOOT_PALETTE = {
    '#': INK,
    'H': '#d9e4ca',
    's': '#95c2b2',
    'T': '#62a79d',
    't': '#457b7a',
    'd': '#32595f',
    'b': '#8a5140',
    'c': '#e39a53',
    'o': '#b06543',
    'O': '#633c2b',
}


def draw_rocket_boot(draw, at):
    for y, row in enumerate(ROCKET_BOOT_PIXELS):
        for x, pixel in enumerate(row):
            if pixel != '.':
                draw.point((at[0] + x, at[1] + y), fill=ROCKET_BOOT_PALETTE[pixel])


HELMET_RIM_LIGHT = (255, 232, 97, 255)


def hard_hat():
    image = Image.new('RGBA', (32, 16))
    d = ImageDraw.Draw(image)
    d.polygon([(3, 12), (3, 10), (6, 8), (7, 5), (10, 2), (13, 1),
               (20, 1), (24, 2), (27, 5), (28, 8), (30, 9), (31, 12),
               (29, 13), (22, 12), (15, 12), (5, 14), (3, 13)], fill=INK)
    d.polygon([(7, 9), (8, 5), (11, 3), (14, 2), (20, 2), (24, 3),
               (26, 5), (27, 8), (22, 10), (10, 11)], fill='#ffdc20')
    d.polygon([(9, 6), (12, 3), (16, 2), (20, 2), (22, 3), (18, 3),
               (16, 4), (13, 4), (11, 6)], fill='#fff27f')
    d.line([(8, 8), (10, 7), (10, 6)], fill='#f4c00b')
    d.line([(13, 3), (16, 3)], fill='#fff8bd')
    d.polygon([(8, 9), (16, 8), (20, 8), (24, 7), (27, 8), (24, 10),
               (11, 11), (7, 12)], fill='#ad7308')
    d.polygon([(4, 11), (10, 9), (16, 8), (23, 8), (28, 9), (30, 10),
               (30, 11), (22, 10), (15, 10), (5, 13), (4, 13)], fill='#edb710')
    d.line([(5, 11), (10, 10), (16, 9), (23, 9), (28, 10)], fill=HELMET_RIM_LIGHT)
    d.polygon([(20, 5), (22, 3), (26, 3), (28, 5), (28, 8), (26, 10),
               (22, 10), (20, 8)], fill=INK)
    d.polygon([(21, 5), (23, 4), (26, 4), (27, 5), (27, 8), (25, 9),
               (22, 9), (21, 8)], fill='#9b542c')
    d.polygon([(22, 6), (23, 5), (26, 5), (26, 8), (23, 8), (22, 7)], fill='#ffbe49')
    d.rectangle((23, 5, 25, 7), fill='#ffdf83')
    d.line((23, 5, 24, 5), fill='#fff3be')
    return image


HELMET = hard_hat()


def hero_frame(frame, rocket_boots=False, helmet=False):
    image = Image.new('RGBA', (32, 48))
    d = ImageDraw.Draw(image)
    d.rectangle((9, 37, 23, 41), fill=INK)
    if frame == 'walk':
        legs = [(8, 40, 13, 45), (20, 41, 25, 46)]
        shoes = [(6, 44, 14, 47), (20, 45, 27, 47)]
        rocket_positions = [(3, 34), (17, 34)]
    elif frame == 'jump':
        legs = [(7, 39, 13, 43), (19, 39, 25, 43)]
        shoes = [(5, 42, 14, 45), (19, 42, 27, 45)]
        rocket_positions = [(3, 32), (17, 32)]
    else:
        legs = [(10, 40, 14, 46), (18, 40, 22, 46)]
        shoes = [(8, 45, 15, 47), (18, 45, 25, 47)]
        rocket_positions = [(5, 34), (16, 34)]
    for box in legs:
        d.rectangle(box, fill='#254a57')
        d.line((box[0] + 1, box[1], box[0] + 1, box[3]), fill='#4b7880')
    if rocket_boots:
        for at in rocket_positions:
            draw_rocket_boot(d, at)
    else:
        for box in shoes:
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
    if helmet:
        image.paste(HELMET, (0, 0), HELMET)
    else:
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
    d.rectangle((6, 29, 9, 32), fill='#f2be88')
    return image


frames = ['idle', 'walk', 'jump', 'push']
atlas = Image.new('RGBA', (32 * len(frames), 48))
helmet_atlas = Image.new('RGBA', (32 * len(frames), 96))
for column, frame in enumerate(frames):
    hero_frame(frame).save(ROOT / f'hero_{frame}.png')
    atlas.paste(hero_frame(frame, rocket_boots=True), (column * 32, 0))
    for row, rocket_boots in enumerate((False, True)):
        helmet_atlas.paste(hero_frame(frame, rocket_boots=rocket_boots, helmet=True), (column * 32, row * 48))
atlas.save(ROOT / 'hero_rocket_boots.png')
helmet_atlas.save(ROOT / 'hero_helmet.png')

icon = Image.new('RGBA', (32, 32))
icon.paste(HELMET, (-1, 8))
icon.save(ROOT / 'helmet.png')


def draw_plank(image):
    d = ImageDraw.Draw(image)
    d.polygon([(1, 10), (14, 1), (16, 3), (18, 3), (17, 6), (19, 7),
               (17, 8), (16, 10), (13, 10), (4, 15), (2, 14)], fill=INK)
    d.polygon([(2, 10), (14, 2), (16, 4), (15, 6), (17, 7), (15, 9),
               (12, 9), (4, 14), (3, 13)], fill='#b97035')
    d.line([(3, 10), (14, 3), (15, 4)], fill='#f5c178')
    d.line([(5, 12), (12, 8), (15, 7)], fill='#df9654')
    d.line([(7, 9), (10, 7), (13, 6)], fill='#8c502c')
    d.point((4, 11), fill='#edb96e')


def break_hard_hat():
    halves = [Image.new('RGBA', (20, 16)), Image.new('RGBA', (20, 16))]
    crack = [19, 19, 18, 18, 17, 18, 16, 15, 16, 14, 13, 14, 13, 12, 12, 12]
    for y, seam in enumerate(crack):
        for x in range(3, 32):
            pixel = HELMET.getpixel((x, y))
            if not pixel[3]:
                continue
            if x < seam:
                halves[0].putpixel((x, y + 1), pixel)
            else:
                halves[1].putpixel((x - 12, y + 1), pixel)
        # A jagged rim shows through after the cap separates.
        if HELMET.getpixel((seam, y))[3]:
            halves[1].putpixel((seam - 12, y + 1), (16, 39, 51, 255))
        if HELMET.getpixel((seam - 1, y))[3]:
            halves[0].putpixel((seam - 1, y + 1), (16, 39, 51, 255))
            if y in (3, 4, 6, 9):
                halves[0].putpixel((seam - 2, y + 1), HELMET_RIM_LIGHT)
    return halves


fragments = Image.new('RGBA', (80, 32))
plank = Image.new('RGBA', (20, 16))
draw_plank(plank)
fragments.paste(plank, (0, 0))
fragments.paste(plank.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (20, 0))
d = ImageDraw.Draw(fragments)
d.polygon([(41, 7), (54, 1), (58, 5), (56, 13), (45, 15)], fill=INK)
d.polygon([(44, 7), (53, 3), (56, 6), (54, 11), (46, 13)], fill='#d9954d')
d.line([(44, 7), (53, 3), (55, 5)], fill='#f5c178', width=2)
d.polygon([(61, 5), (67, 1), (79, 6), (73, 15), (65, 12)], fill=INK)
d.polygon([(63, 6), (67, 3), (76, 7), (72, 12), (67, 11)], fill='#af662f')
d.line([(63, 6), (67, 3), (75, 6)], fill='#edb96e', width=2)
for index, half in enumerate(break_hard_hat()):
    fragments.paste(half, (index * 20, 16))
fragments.save(ROOT / 'helmet_fragments.png')

image = Image.new('RGBA', (32, 32))
d = ImageDraw.Draw(image)
draw_rocket_boot(d, (4, 6))
draw_rocket_boot(d, (17, 12))
image.save(ROOT / 'rocket_boots.png')

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
