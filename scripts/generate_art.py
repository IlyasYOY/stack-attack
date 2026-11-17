"""Original workshop pixel art, hand drawn here; no reference image pixels used."""
from pathlib import Path
from random import Random
from PIL import Image, ImageColor, ImageDraw
ROOT = Path(__file__).resolve().parents[1] / 'art'
ROOT.mkdir(exist_ok=True)
INK = '#102733'

CRATE_SIZE = 48

# Face, plank seam, grain highlight, rail, rail highlight, brace, brace highlight.
# The atlas follows the ten numbered crates in the workshop concept.
CRATE_PALETTES = (
    ("#bc792f", "#805026", "#d59443", "#d28b3f", "#ffcc7d", "#e29a49", "#ffce83"),
    ("#dba45d", "#a06f3a", "#edbb74", "#e7a75e", "#ffe0a1", "#efb870", "#ffdda3"),
    ("#aa6539", "#79442d", "#c27d4f", "#b77543", "#e9a873", "#c47b4e", "#eeb28a"),
    ("#b7744f", "#824a37", "#cb8864", "#c58760", "#edb898", "#d28762", "#fbc1a0"),
    ("#aa8152", "#785c41", "#c09866", "#bc9360", "#e9c896", "#c8a170", "#f1d3a4"),
    ("#c48336", "#845125", "#da9a47", "#d58c3d", "#ffd283", "#e09b45", "#ffd27e"),
    ("#bf7c35", "#865228", "#d99346", "#cf8a3e", "#fbc776", "#dd9b4c", "#ffd38b"),
    ("#b39166", "#826b4d", "#ccb18a", "#c6a377", "#f0d4a6", "#cbb08a", "#f2d7af"),
    ("#985c35", "#70432d", "#b07148", "#a96b3e", "#dc9d68", "#b6794d", "#e6a878"),
    ("#d39b50", "#986333", "#e9b36a", "#dfa255", "#ffda91", "#e5ad63", "#ffda95"),
)


def crate_bolt(draw, x, y):
    draw.rectangle((x - 2, y - 2, x + 2, y + 2), fill="#253640")
    draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill="#849092")
    draw.line((x - 1, y - 1, x, y - 1), fill="#e6dcc6")
    draw.point((x + 1, y + 1), fill="#556369")


def wood_grain(base, accent, amount):
    return tuple(round(a + (b - a) * amount)
                 for a, b in zip(ImageColor.getrgb(base), ImageColor.getrgb(accent)))


def crate_boards(draw, face, seam, grain, variant, horizontal):
    def line(u1, v1, u2, v2, shade):
        coordinates = (v1, u1, v2, u2) if horizontal else (u1, v1, u2, v2)
        draw.line(coordinates, fill=shade)

    rng = Random(26419 + variant)
    shadow_grain = wood_grain(face, seam, 0.5)
    light_grain = wood_grain(face, grain, 0.8)
    draw.rectangle((6, 7, 41, 40), fill=face)
    # Keep grain in the boards. The horizontal crate uses the same shading
    # turned along its planks, while the outside frame keeps a fixed light.
    for edge in (7, 15, 23, 31, 39):
        line(edge, 7, edge, 40, seam)
        line(edge + 1, 8, edge + 1, 39, light_grain)
        for _ in range(5):
            across = edge + rng.randrange(2, 7)
            length = rng.randrange(3, 9)
            along = rng.randrange(8, 41 - length)
            line(across, along, across, along + length, rng.choice((face, shadow_grain, light_grain)))


def crate_knot(draw, x, y, seam, face, grain):
    draw.ellipse((x - 2, y - 3, x + 2, y + 3), fill=seam)
    draw.ellipse((x - 1, y - 2, x + 1, y + 1), fill=face)
    draw.point((x, y - 1), fill=seam)
    draw.point((x - 1, y + 2), fill=grain)


def crate_brace(draw, face, bevel, shadow, descending):
    def path(points):
        return [(47 - x, y) for x, y in points] if descending else points

    draw.polygon(path([(4, 37), (37, 4), (44, 4), (44, 11), (11, 44), (4, 44)]), fill=shadow)
    draw.polygon(path([(5, 37), (38, 4), (43, 5), (43, 9), (10, 42), (5, 42)]), fill=face)
    draw.line(path([(6, 37), (38, 5)]), fill=bevel, width=2)
    draw.line(path([(10, 41), (43, 8)]), fill=shadow)


def wooden_crate(variant, palette):
    face, seam, grain, rail, bevel, brace, brace_bevel = palette
    image = Image.new('RGBA', (CRATE_SIZE, CRATE_SIZE), INK)
    draw = ImageDraw.Draw(image)
    draw.rectangle((2, 2, 45, 45), fill=seam)
    crate_boards(draw, face, seam, grain, variant, horizontal=variant == 6)
    if variant == 1:
        crate_knot(draw, 13, 16, seam, face, grain)
    elif variant == 4:
        draw.line([(9, 20), (14, 16), (18, 15)], fill=grain, width=2)
        draw.line([(30, 36), (35, 33), (39, 29)], fill=grain, width=2)
    elif variant == 5:
        crate_knot(draw, 13, 15, seam, face, grain)
        crate_knot(draw, 35, 34, seam, face, grain)
    elif variant == 9:
        draw.line([(12, 23), (11, 27), (13, 30), (12, 34), (14, 37)], fill=grain, width=2)
        draw.line([(35, 9), (34, 13), (36, 17), (35, 20), (37, 23)], fill=grain, width=2)
        draw.line([(26, 12), (27, 16), (26, 18)], fill=grain)

    for bounds in ((2, 2, 45, 7), (2, 40, 45, 45), (2, 8, 6, 39), (41, 8, 45, 39)):
        draw.rectangle(bounds, fill=rail)
    draw.line((3, 3, 44, 3), fill=bevel, width=2)
    draw.line((3, 8, 3, 40), fill=bevel)
    draw.line((4, 40, 43, 40), fill=bevel)
    draw.line((44, 8, 44, 40), fill=seam)
    draw.line((3, 44, 44, 44), fill="#5b3a2d")
    draw.line((3, 45, 44, 45), fill=seam)
    crate_brace(draw, brace, brace_bevel, seam, descending=variant in (2, 7, 9))
    for x, y in ((5, 5), (42, 5), (5, 42), (42, 42)):
        crate_bolt(draw, x, y)
    return image


crate_atlas = Image.new('RGBA', (CRATE_SIZE * len(CRATE_PALETTES), CRATE_SIZE))
for variant_index, variant_palette in enumerate(CRATE_PALETTES):
    crate_atlas.paste(wooden_crate(variant_index, variant_palette), (variant_index * CRATE_SIZE, 0))
crate_atlas.save(ROOT / 'crate_wood_variants.png')


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

GLOVE_RED = '#bf4936'
GLOVE_LIGHT = '#e8774b'
GLOVE_SHADE = '#83362e'
GLOVE_BRASS = '#cb8f46'
GLOVE_RIM = '#f7cc76'


def draw_worn_gloves(d, frame):
    # The cuffs and fingers cover the bare hands. The arms still fit the same
    # sprite bounds and the glove pixels stay above or clear of the boot art.
    d.rectangle((6, 29, 9, 32), fill=GLOVE_SHADE)
    d.line((6, 29, 9, 29), fill=GLOVE_RIM)
    d.line((6, 30, 9, 30), fill=GLOVE_BRASS)
    d.line((7, 31, 8, 31), fill=GLOVE_RED)
    d.point((6, 32), fill=INK)
    if frame in ('push', 'grab'):
        d.polygon([(23, 32), (25, 30), (28, 28), (30, 28), (31, 29),
                   (31, 35), (29, 37), (23, 37)], fill=INK)
        d.polygon([(24, 32), (27, 30), (30, 29), (30, 35),
                   (29, 36), (24, 36)], fill=GLOVE_RED)
        d.line((25, 32, 28, 30), fill=GLOVE_LIGHT)
        d.line((28, 32, 30, 32), fill=GLOVE_SHADE)
        d.line((28, 34, 30, 34), fill=GLOVE_SHADE)
        d.line((24, 32, 24, 36), fill=GLOVE_BRASS)
        d.point((24, 33), fill='#ffe392' if frame == 'grab' else GLOVE_RIM)
    else:
        d.rectangle((22, 33, 25, 34), fill=GLOVE_BRASS)
        d.line((22, 33, 24, 33), fill=GLOVE_RIM)
        d.rectangle((22, 35, 26, 39), fill=INK)
        d.rectangle((23, 35, 25, 38), fill=GLOVE_RED)
        d.line((23, 35, 25, 35), fill=GLOVE_LIGHT)
        d.point((26, 36), fill=GLOVE_SHADE)


def hero_frame(frame, rocket_boots=False, helmet=False, gloves=False):
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
    if frame not in ('mallet_windup', 'mallet_strike'):
        arm = (23, 28, 28, 34) if frame in ('push', 'grab') else (22, 27, 25, 36)
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
    if frame == 'mallet_windup':
        d.polygon([(21, 27), (24, 23), (24, 15), (30, 15), (31, 21),
                   (28, 28), (25, 32), (21, 31)], fill=INK)
        d.polygon([(22, 27), (26, 22), (29, 23), (26, 28), (24, 30), (22, 30)], fill='#d4c59f')
        d.polygon([(25, 16), (29, 16), (30, 20), (28, 23), (26, 22), (25, 20)], fill='#f1bb83')
    elif frame == 'mallet_strike':
        d.polygon([(21, 26), (25, 27), (27, 30), (30, 29), (31, 31),
                   (31, 37), (26, 37), (21, 32)], fill=INK)
        d.polygon([(22, 27), (25, 28), (27, 32), (26, 35), (22, 32)], fill='#d4c59f')
        d.rectangle((27, 31, 30, 36), fill='#f1bb83')
        d.line((28, 35, 30, 35), fill='#b47855')
    if gloves:
        draw_worn_gloves(d, frame)
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

gloves_atlas = Image.new('RGBA', (160, 192))
for row, (boots, helmet) in enumerate(((False, False), (True, False), (False, True), (True, True))):
    for column, frame in enumerate([*frames, 'grab']):
        gloves_atlas.paste(hero_frame(frame, rocket_boots=boots, helmet=helmet, gloves=True),
                          (column * 32, row * 48))
gloves_atlas.save(ROOT / 'hero_work_gloves.png')

mallet_atlas = Image.new('RGBA', (64, 192))
for row, (boots, helmet) in enumerate(((False, False), (True, False), (False, True), (True, True))):
    for column, frame in enumerate(('mallet_windup', 'mallet_strike')):
        mallet_atlas.paste(hero_frame(frame, rocket_boots=boots, helmet=helmet), (column * 32, row * 48))
mallet_atlas.save(ROOT / 'hero_mallet.png')

mallet = Image.new('RGBA', (32, 32))
d = ImageDraw.Draw(mallet)
# Dark outline, reddish ash handle and a brass heel.
d.polygon([(11, 15), (20, 15), (20, 25), (21, 25), (21, 29),
           (19, 31), (12, 31), (10, 29), (10, 25), (11, 25)], fill=INK)
d.rectangle((13, 16, 18, 28), fill='#854332')
d.rectangle((13, 17, 14, 26), fill='#c7734b')
d.line((16, 19, 16, 26), fill='#a85637')
d.rectangle((12, 27, 19, 29), fill='#c6893d')
d.line((12, 27, 19, 27), fill='#f7ce78')
d.line((19, 28, 19, 29), fill='#80512c')
# A horizontal laminated wooden head with raised bands and pin heads.
d.polygon([(1, 5), (5, 1), (25, 1), (30, 5), (30, 15), (26, 19),
           (5, 19), (1, 15)], fill=INK)
d.polygon([(3, 6), (6, 3), (25, 3), (28, 6), (28, 15), (25, 17),
           (6, 17), (3, 15)], fill='#a45b32')
d.polygon([(3, 6), (6, 4), (25, 4), (28, 6), (25, 7), (6, 7)], fill='#d58d4e')
d.line((3, 9, 28, 9), fill='#713f2e')
d.line((3, 10, 28, 10), fill='#cf8244')
d.line((3, 13, 28, 13), fill='#713f2e')
d.line((3, 14, 28, 14), fill='#bf743d')
d.line((6, 16, 25, 16), fill='#81492d')
d.line((13, 6, 20, 6), fill='#eeaf65')
d.line((12, 11, 15, 11), fill='#e79a56')
d.line((17, 15, 20, 15), fill='#d68a49')
for left in (6, 22):
    d.rectangle((left - 1, 2, left + 4, 17), fill='#654328')
    d.rectangle((left, 2, left + 3, 17), fill='#ca8c3f')
    d.line((left, 3, left, 16), fill='#f4bd63')
    d.line((left, 2, left + 3, 2), fill='#ffe3a2')
    for y in (6, 13):
        d.rectangle((left + 1, y, left + 2, y + 1), fill='#6c4b34')
        d.point((left + 1, y), fill='#fff0b0')
mallet.save(ROOT / 'wooden_mallet.png')

# A broken half of the head and a splintered handle preserve the material palette.
mallet_pieces = Image.new('RGBA', (60, 16))
seam = (16, 17, 18, 16, 15, 17, 19, 18, 16, 15, 17, 16, 14, 13, 15, 16)
head = mallet.crop((0, 2, 32, 18))
for y, split in enumerate(seam):
    for x in range(32):
        pixel = head.getpixel((x, y))
        if pixel[3]:
            destination = x if x < split else x + 8
            mallet_pieces.putpixel((destination, y), pixel)
d = ImageDraw.Draw(mallet_pieces)
d.polygon([(50, 2), (54, 0), (53, 4), (54, 6), (54, 14), (52, 15), (48, 15),
           (46, 13), (47, 5)], fill=INK)
d.polygon([(50, 3), (52, 2), (51, 5), (53, 7), (52, 12), (48, 12), (49, 6)], fill='#a85637')
d.line((49, 6, 49, 11), fill='#e29862')
d.line((48, 12, 53, 12), fill='#f7ce78')
d.line((48, 13, 52, 13), fill='#c6893d')
mallet_pieces.save(ROOT / 'mallet_fragments.png')

icon = Image.new('RGBA', (32, 32))
icon.paste(HELMET, (-1, 8))
icon.save(ROOT / 'helmet.png')


def glove_icon(closed=False):
    icon = Image.new('RGBA', (32, 32))
    d = ImageDraw.Draw(icon)
    if closed:
        d.polygon([(7, 13), (7, 8), (10, 6), (13, 6), (15, 4), (19, 4),
                   (21, 5), (24, 5), (26, 7), (27, 10), (27, 17), (25, 21),
                   (22, 24), (12, 25), (7, 21), (5, 16)], fill=INK)
        d.polygon([(8, 15), (9, 9), (11, 8), (14, 8), (16, 6), (19, 6),
                   (21, 7), (24, 7), (25, 10), (25, 17), (23, 21),
                   (20, 24), (13, 23), (9, 20), (7, 16)], fill=GLOVE_RED)
        d.polygon([(10, 9), (14, 9), (16, 7), (19, 7), (21, 8), (24, 8),
                   (25, 10), (24, 12), (11, 13)], fill=GLOVE_LIGHT)
        for x, top, bottom in [(13, 9, 13), (17, 7, 14), (21, 8, 14)]:
            d.line((x, top, x, bottom), fill=GLOVE_SHADE)
        d.line([(10, 13), (13, 13), (16, 16), (19, 16), (21, 15), (24, 15)],
               fill=GLOVE_SHADE, width=2)
        d.line([(9, 15), (12, 15), (15, 18), (15, 20)], fill=GLOVE_LIGHT)
        d.line([(10, 20), (14, 22), (21, 22), (24, 19)], fill=GLOVE_SHADE)
    else:
        d.polygon([(4, 16), (6, 14), (9, 14), (11, 16), (10, 7), (12, 5), (15, 5),
                   (16, 6), (16, 3), (18, 1), (21, 2), (22, 5), (24, 4), (27, 6),
                   (27, 9), (29, 9), (30, 11), (29, 18), (26, 25), (24, 27), (12, 27),
                   (9, 24), (5, 21)], fill=INK)
        d.polygon([(6, 17), (7, 16), (9, 16), (13, 19), (12, 7), (14, 7), (16, 16),
                   (18, 15), (18, 4), (19, 3), (20, 4), (21, 15), (22, 15), (23, 7),
                   (24, 6), (25, 7), (24, 16), (25, 17), (27, 11), (28, 11), (28, 15),
                   (26, 21), (24, 26), (13, 25), (9, 22)], fill=GLOVE_RED)
        d.line([(6, 17), (9, 17), (13, 21)], fill=GLOVE_LIGHT)
        d.line((13, 8, 14, 13), fill=GLOVE_LIGHT)
        d.line((19, 4, 19, 12), fill=GLOVE_LIGHT)
        d.line((24, 7, 23, 13), fill=GLOVE_LIGHT)
        d.line([(14, 18), (16, 16), (21, 16), (24, 18)], fill=GLOVE_SHADE)
        d.line([(10, 22), (15, 24), (23, 24), (25, 22)], fill=GLOVE_SHADE)
    cuff_y = 23 if closed else 25
    d.polygon([(11, cuff_y), (23, cuff_y), (25, cuff_y + 1), (25, cuff_y + 4),
               (23, cuff_y + 5), (12, cuff_y + 5), (10, cuff_y + 4), (10, cuff_y + 1)], fill=INK)
    d.rectangle((11, cuff_y + 1, 24, cuff_y + 3), fill=GLOVE_BRASS)
    d.line((12, cuff_y + 1, 23, cuff_y + 1), fill=GLOVE_RIM)
    for x in (13, 21):
        d.point((x, cuff_y + 3), fill='#8c532e')
        d.point((x, cuff_y + 2), fill='#ffdc90')
    return icon


open_glove = glove_icon()
glove_controls = Image.new('RGBA', (64, 32))
glove_controls.paste(open_glove, (0, 0))
glove_controls.paste(glove_icon(closed=True), (32, 0))
glove_controls.save(ROOT / 'glove_controls.png')

glove_pair = Image.new('RGBA', (38, 32))
glove_pair.paste(open_glove.resize((20, 24), Image.Resampling.NEAREST), (0, 5))
glove_pair.paste(open_glove.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                 .resize((20, 24), Image.Resampling.NEAREST), (18, 2))
glove_pair.save(ROOT / 'work_gloves.png')

glove_fragments = Image.new('RGBA', (36, 8))
d = ImageDraw.Draw(glove_fragments)
d.polygon([(0, 5), (3, 2), (8, 1), (11, 4), (9, 7), (2, 7)], fill=INK)
d.polygon([(2, 5), (4, 3), (8, 2), (10, 4), (8, 6), (3, 6)], fill=GLOVE_RED)
d.line([(3, 5), (7, 3), (9, 4)], fill=GLOVE_LIGHT)
d.polygon([(13, 2), (16, 1), (20, 1), (23, 3), (23, 6), (19, 7), (15, 7), (13, 6)], fill=INK)
d.polygon([(14, 3), (17, 2), (21, 3), (22, 4), (22, 5), (19, 6), (15, 6), (14, 5)], fill=GLOVE_BRASS)
d.line([(15, 3), (17, 2), (20, 3)], fill=GLOVE_RIM)
d.line((17, 5, 20, 5), fill='#8c532e')
d.polygon([(27, 5), (29, 3), (32, 2), (34, 4), (34, 6), (29, 7)], fill=INK)
d.polygon([(29, 5), (32, 3), (33, 5), (30, 6)], fill=GLOVE_SHADE)
d.point((31, 4), fill=GLOVE_RED)
glove_fragments.save(ROOT / 'glove_fragments.png')


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


# Workshop equipment overlays share the hero frame and its contact points.
def bare_arm(draw, contour, muscle, fold, light):
    draw.polygon(contour, fill=INK)
    draw.polygon(muscle, fill='#efa36d')
    draw.line(fold, fill='#bd704b', width=2)
    draw.line(light, fill='#ffd398', width=2)


def bare_arms(frame):
    image = Image.new('RGBA', (32, 48))
    draw = ImageDraw.Draw(image)
    bare_arm(draw, [(7, 24), (11, 26), (11, 31), (9, 35), (10, 38),
                    (8, 40), (4, 39), (3, 35), (3, 29), (5, 25)],
             [(7, 25), (10, 27), (10, 31), (8, 35), (9, 38), (5, 38),
              (4, 35), (4, 29), (6, 26)],
             [(9, 30), (6, 33), (7, 36)], [(6, 27), (5, 31)])
    if frame == 'push':
        bare_arm(draw, [(20, 25), (25, 25), (27, 27), (28, 29), (31, 27),
                        (31, 38), (26, 38), (22, 36), (18, 32), (18, 28)],
                 [(20, 26), (24, 26), (26, 28), (27, 31), (30, 29), (30, 36),
                  (27, 37), (23, 35), (19, 32), (19, 28)],
                 [(20, 32), (24, 34), (28, 34), (29, 32)],
                 [(21, 28), (24, 29), (25, 32)])
        draw.line((29, 31, 31, 30), fill='#ffd398')
        draw.point((30, 34), fill='#ffebbb')
    else:
        bare_arm(draw, [(22, 24), (26, 25), (29, 28), (30, 33), (29, 35),
                        (30, 38), (28, 41), (23, 40), (21, 37), (21, 34),
                        (19, 31), (19, 28)],
                 [(22, 25), (26, 26), (28, 28), (29, 33), (28, 35), (29, 38),
                  (27, 40), (24, 39), (22, 37), (22, 34), (20, 31), (20, 28)],
                 [(27, 28), (27, 31), (24, 33), (25, 36), (27, 37)],
                 [(22, 27), (21, 30), (23, 32)])
        draw.line((25, 38, 27, 38), fill='#ffd398')
    return image


EQUIPMENT_BOOT_PIXELS = {
    'speed_boots': (
        '.#######.....',
        '#HCCCCCC#....',
        '#hcccccT#....',
        '#LcccttT#....',
        '#ccTttbb#....',
        '#Tttbbbc#....',
        '#tbBccct##...',
        '#bBcccttCH#..',
        '#BCtttTCCCH#.',
        '#CCTTCCHHHc#.',
        '#hhcccccttt#.',
        '#Mmmmmmmmmm#.',
        '.##########..',
    ),
    'spring_boots': (
        '..######.....',
        '.#Haaaaa#....',
        '.#aarrrr#....',
        '.#amarr#.....',
        '.#arrr#......',
        '.#arrR##.....',
        '.#arRRaa###..',
        '.#rRaaaaaaH#.',
        '.#Hbbbbbbbb#.',
        '.##########..',
        '..#MMmmM#....',
        '.#mMMMmmM#...',
        '.#MMmmMMM#...',
        '..########...',
    )
}
EQUIPMENT_BOOT_PALETTE = {
    '#': INK, 'H': '#fbdfa2', 'h': '#8accad',
    'C': '#58b8aa', 'c': '#258681', 'T': '#166370', 't': '#16535e',
    'L': '#a1e2bd', 'b': '#c18142', 'B': '#f7cb78', 'M': '#d2ddd6',
    'm': '#72868a', 'a': '#ae542f', 'r': '#793e2d', 'R': '#96503b',
}
EQUIPMENT_FOOT_POSITIONS = {
    'idle': ((6, 38), (16, 38)),
    'walk': ((4, 38), (18, 38)),
    'jump': ((3, 36), (18, 36)),
}


def draw_equipment_boot(draw, item, at):
    for y, row in enumerate(EQUIPMENT_BOOT_PIXELS[item]):
        for x, pixel in enumerate(row):
            if pixel != '.':
                draw.point((at[0] + x, at[1] + y), fill=EQUIPMENT_BOOT_PALETTE[pixel])


def equipment_boots(frame, item):
    image = Image.new('RGBA', (32, 48))
    rows = EQUIPMENT_BOOT_PIXELS[item]
    boot = Image.new('RGBA', (len(rows[0]), len(rows)))
    draw_equipment_boot(ImageDraw.Draw(boot), item, (0, 0))
    boot = boot.resize((boot.width, 10), Image.Resampling.NEAREST)
    for at in reversed(EQUIPMENT_FOOT_POSITIONS.get(frame, EQUIPMENT_FOOT_POSITIONS['idle'])):
        image.alpha_composite(boot, at)
    return image


def lamp_hat():
    image = Image.new('RGBA', (32, 16))
    draw = ImageDraw.Draw(image)
    draw.polygon([(2, 11), (4, 7), (6, 4), (9, 2), (12, 0), (20, 0), (24, 2),
                  (27, 5), (28, 8), (31, 9), (31, 12), (28, 14), (11, 14),
                  (5, 15), (2, 13)], fill=INK)
    draw.polygon([(4, 11), (6, 7), (8, 4), (12, 2), (19, 1), (24, 3), (27, 6),
                  (28, 9), (24, 11), (5, 13)], fill='#227e82')
    draw.polygon([(6, 9), (8, 5), (12, 3), (17, 2), (20, 3), (17, 5), (15, 6),
                  (14, 9), (11, 10)], fill='#59b8a8')
    draw.line([(9, 5), (13, 3), (17, 2)], fill='#a9e0ba')
    draw.line([(4, 12), (12, 11), (20, 10), (24, 10)], fill='#123e52', width=2)
    draw.line([(5, 13), (14, 12), (22, 12), (27, 13), (29, 12)], fill='#75b9ab')
    draw.rectangle((9, 10, 11, 12), fill='#cf9a57')
    draw.point((10, 10), fill='#ffde94')
    draw.polygon([(19, 5), (22, 3), (27, 3), (30, 5), (31, 8), (29, 11),
                  (26, 13), (22, 12), (19, 10)], fill=INK)
    draw.polygon([(20, 6), (23, 4), (27, 4), (29, 6), (30, 8), (28, 11),
                  (26, 12), (23, 11), (20, 9)], fill='#b47837')
    draw.polygon([(22, 6), (24, 5), (27, 5), (29, 7), (29, 9), (27, 11),
                  (24, 11), (22, 9)], fill='#ffd976')
    draw.rectangle((24, 6, 27, 9), fill='#fff0ae')
    draw.line((25, 6, 26, 6), fill='#fff9dd')
    return image


def break_lamp_hat(helmet):
    result = Image.new('RGBA', (40, 16))
    crack = [17, 17, 16, 16, 15, 15, 16, 16, 14, 14, 13, 13, 12, 12, 12, 12]
    for y, seam in enumerate(crack):
        for x in range(32):
            pixel = helmet.getpixel((x, y))
            if not pixel[3]:
                continue
            target_x = x if x < seam else 20 + x - 12
            result.putpixel((target_x, y), pixel)
        for x, target in ((seam - 1, seam - 1), (seam, 20 + seam - 12)):
            if helmet.getpixel((x, y))[3]:
                result.putpixel((target, y), (16, 39, 51, 255))
    return result


lamp = lamp_hat()
hat_icon = Image.new('RGBA', (32, 32))
hat_icon.paste(lamp, (0, 9))
hat_icon.save(ROOT / 'lamp_helmet.png')
break_lamp_hat(lamp).save(ROOT / 'lamp_helmet_fragments.png')

for item in EQUIPMENT_BOOT_PIXELS:
    icon = Image.new('RGBA', (32, 32))
    draw = ImageDraw.Draw(icon)
    draw_equipment_boot(draw, item, (15, 10))
    draw_equipment_boot(draw, item, (4, 6))
    icon.save(ROOT / f'{item}.png')

arms_icon = Image.new('RGBA', (32, 32))
arm = bare_arms('idle').crop((19, 24, 31, 42))
arms_icon.paste(arm.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (3, 7))
arms_icon.paste(arm, (17, 7))
arms_icon.save(ROOT / 'strong_arms.png')

bonus_overlay = Image.new('RGBA', (160, 192))
for column, frame in enumerate([*frames, 'grab']):
    at = column * 32
    bonus_overlay.paste(bare_arms(frame), (at, 0))
    bonus_overlay.paste(equipment_boots(frame, 'speed_boots'), (at, 48))
    bonus_overlay.paste(equipment_boots(frame, 'spring_boots'), (at, 96))
    bonus_overlay.paste(lamp, (at, 144))
bonus_overlay.save(ROOT / 'hero_bonus_gear.png')
