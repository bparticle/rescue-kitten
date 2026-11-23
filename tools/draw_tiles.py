"""Draw the level tileset from sprites/tiles/materials.json. Run with Python and Pillow.

Writes sprites/tiles/tileset.png and its atlas layout. Edit this source and regenerate.

Blob variants use a 4-bit neighbour mask: N=1, E=2, S=4, W=8 (bit set = same-group neighbour).
Area variants append diagonal cutouts to the original sixteen cardinal combinations.
Orient variants run east-west, then north-south.
"""

import json
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TILES = ROOT / 'sprites' / 'tiles'
S = 16
N, E, SO, W = 1, 2, 4, 8

# Every tile colour comes from here so the packed palette stays small.
C = {
    'ink': (35, 31, 32), 'shadow': (60, 52, 44),
    'sand': (216, 194, 143), 'sand_d': (196, 172, 120), 'sand_l': (232, 214, 168),
    'grout': (102, 96, 86), 'cob': (150, 144, 132), 'cob_d': (128, 122, 112), 'cob_l': (176, 170, 156),
    'asph': (74, 74, 76), 'asph_d': (60, 60, 63), 'asph_l': (92, 92, 94), 'paint': (224, 192, 80),
    'plank': (160, 112, 63), 'plank_d': (140, 96, 52), 'plank_l': (186, 138, 84), 'seam': (98, 66, 36),
    'flag': (143, 138, 128), 'flag_d': (118, 113, 104), 'flag_l': (166, 161, 150),
    'chk_l': (216, 208, 192), 'chk_d': (122, 110, 98),
    'rug': (140, 58, 50), 'rug_d': (108, 42, 38), 'gold': (200, 160, 80),
    'shal': (88, 150, 164), 'shal_l': (132, 186, 196), 'shal_d': (70, 124, 140),
    'deep': (47, 95, 120), 'deep_l': (66, 120, 146), 'deep_d': (36, 74, 96),
    'stone': (141, 138, 131), 'stone_d': (118, 115, 108), 'stone_l': (170, 166, 156), 'mortar': (88, 85, 80),
    'brick': (164, 85, 63), 'brick_d': (138, 68, 50), 'brick_l': (190, 110, 84), 'bmortar': (107, 74, 60),
    'log': (138, 96, 56), 'log_d': (112, 78, 44), 'log_l': (166, 122, 76), 'log_k': (78, 54, 32),
    'face': (70, 64, 58), 'face_b': (92, 52, 40), 'face_w': (84, 58, 34),
    'glass': (159, 208, 220), 'glass_l': (224, 244, 248), 'frame': (107, 74, 42),
    'bag': (184, 160, 112), 'bag_d': (150, 128, 88), 'bag_k': (110, 94, 62),
    'fence': (150, 104, 60), 'fence_d': (104, 70, 40),
    'leaf': (82, 128, 66), 'leaf_d': (58, 96, 50), 'leaf_l': (120, 164, 90), 'leaf_k': (40, 68, 38),
    'crate': (176, 128, 70), 'crate_d': (128, 90, 48),
    'barrel': (184, 64, 44), 'barrel_d': (130, 44, 34), 'barrel_l': (226, 112, 80), 'hazard': (236, 196, 72),
    'rock': (130, 126, 118), 'rock_d': (96, 92, 86), 'rock_l': (168, 164, 154),
    'wire': (90, 90, 96), 'wire_l': (170, 172, 180),
    'flame': (235, 110, 49), 'flame_l': (255, 208, 120), 'ember': (180, 56, 40),
    'scorch': (52, 40, 36), 'scorch_l': (78, 62, 52),
    'red': (178, 72, 58), 'red_d': (150, 58, 46), 'red_k': (100, 38, 30), 'red_l': (204, 102, 80),
    'slate': (92, 102, 114), 'slate_d': (74, 84, 96), 'slate_k': (48, 54, 64), 'slate_l': (124, 136, 148),
    'thatch': (200, 164, 88), 'thatch_d': (170, 136, 70), 'thatch_k': (122, 94, 46), 'thatch_l': (226, 196, 120),
    'tin': (168, 176, 180), 'tin_d': (128, 136, 142), 'tin_k': (84, 90, 96), 'rust': (154, 90, 56),
}


def blank():
    return Image.new('RGBA', (S, S), (0, 0, 0, 0))


def put(img, x, y, color):
    if 0 <= x < S and 0 <= y < S:
        img.putpixel((x, y), C[color] + (255,))


def rect(img, x, y, w, h, color):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            put(img, xx, yy, color)


def disc(img, cx, cy, r, color):
    for y in range(S):
        for x in range(S):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                put(img, x, y, color)


def speckle(img, rng, colors, count, region=(0, 0, S, S)):
    x0, y0, x1, y1 = region
    for _ in range(count):
        put(img, rng.randrange(x0, x1), rng.randrange(y0, y1), rng.choice(colors))


# ---------------------------------------------------------------- ground

def sand(rng):
    img = blank()
    rect(img, 0, 0, S, S, 'sand')
    speckle(img, rng, ['sand_d', 'sand_l'], 26)
    return img


def cobblestone(rng):
    img = blank()
    rect(img, 0, 0, S, S, 'grout')
    for row in range(4):
        offset = (row % 2) * 2
        for col in range(-1, 4):
            x, y = col * 4 + offset, row * 4
            tone = rng.choice(['cob', 'cob', 'cob_d'])
            rect(img, x + 1, y + 1, 3, 3, tone)
            put(img, x + 1, y + 1, 'cob_l')
            put(img, x + 2, y + 1, 'cob_l')
    return img


def road(rng):
    img = blank()
    rect(img, 0, 0, S, S, 'asph')
    speckle(img, rng, ['asph_d', 'asph_l'], 22)
    return img


def road_line(rng, vertical):
    img = road(rng)
    if vertical:
        rect(img, 7, 2, 2, 8, 'paint')
    else:
        rect(img, 2, 7, 8, 2, 'paint')
    return img


def wood_floor(rng):
    img = blank()
    for row in range(4):
        y = row * 4
        tone = ['plank', 'plank_d', 'plank', 'plank_l'][(row + rng.randrange(2)) % 4]
        rect(img, 0, y, S, 3, tone)
        rect(img, 0, y + 3, S, 1, 'seam')
        joint = (row * 7 + 3) % S
        rect(img, joint, y, 1, 3, 'seam')
        put(img, (joint + 3) % S, y + 1, 'seam')
    return img


def stone_floor(rng):
    img = blank()
    rect(img, 0, 0, S, S, 'flag_d')
    for (x, y) in ((0, 0), (8, 0), (0, 8), (8, 8)):
        rect(img, x + 1, y + 1, 7, 7, rng.choice(['flag', 'flag', 'flag_l']))
        put(img, x + 1, y + 1, 'flag_l')
    speckle(img, rng, ['flag_d'], 4)
    return img


def tile_floor(rng):
    img = blank()
    for y in range(4):
        for x in range(4):
            light = (x + y) % 2 == 0
            rect(img, x * 4, y * 4, 4, 4, 'chk_l' if light else 'chk_d')
            if light and rng.random() < 0.32:
                put(img, x * 4 + 1, y * 4 + 2, 'flag')
    return img


def rug(rng):
    img = blank()
    rect(img, 0, 0, S, S, 'rug')
    for i in range(4):
        put(img, 7 - i, 4 + i, 'gold'); put(img, 8 + i, 4 + i, 'gold')
        put(img, 7 - i, 11 - i, 'gold'); put(img, 8 + i, 11 - i, 'gold')
    return img


def water(rng, base, light, dark):
    img = blank()
    rect(img, 0, 0, S, S, base)
    for _ in range(4):
        x, y = rng.randrange(0, 12), rng.randrange(1, 15)
        rect(img, x, y, rng.randrange(3, 5), 1, light)
    speckle(img, rng, [dark], 8)
    return img


# ---------------------------------------------------------------- walls

def wall_texture(kind, rng):
    img = blank()
    if kind == 'stone':
        rect(img, 0, 0, S, S, 'mortar')
        y = 0
        while y < S:
            h = rng.choice([3, 4])
            x = -rng.randrange(0, 4)
            while x < S:
                w = rng.choice([4, 5, 6])
                rect(img, x + 1, y + 1, w - 1, h - 1, rng.choice(['stone', 'stone', 'stone_d', 'stone_l']))
                x += w
            y += h
    elif kind == 'brick':
        rect(img, 0, 0, S, S, 'bmortar')
        for row in range(5):
            offset = 3 if row % 2 else 0
            for col in range(-1, 3):
                rect(img, col * 6 + offset + 1, row * 3 + 1, 5, 2, rng.choice(['brick', 'brick', 'brick_d', 'brick_l']))
    else:
        for row in range(4):
            y = row * 4
            rect(img, 0, y, S, 4, rng.choice(['log', 'log_d']))
            rect(img, 0, y, S, 1, 'log_l')
            rect(img, 0, y + 3, S, 1, 'log_k')
            put(img, rng.randrange(2, 14), y + 2, 'log_k')
    return img


def arm_boxes(mask, span):
    lo, hi = 8 - span, 8 + span
    yield 0 if mask & W else lo, lo, S if mask & E else hi, hi
    if mask & (N | SO):
        yield lo, 0 if mask & N else lo, hi, S if mask & SO else hi


def strip(texture, mask, span, edge, light, face=None):
    pixels = {(x, y) for left, top, right, bottom in arm_boxes(mask, span)
              for y in range(top, bottom) for x in range(left, right)}
    img = blank()

    def outside(x, y):
        if (x, y) in pixels:
            return False
        side = N if y < 0 else SO if y >= S else W if x < 0 else E if x >= S else 0
        return not mask & side

    for x, y in pixels:
        if outside(x, y + 1) or outside(x - 1, y) or outside(x + 1, y):
            put(img, x, y, edge)
        elif outside(x, y - 1):
            put(img, x, y, light)
        elif face and outside(x, y + 2):
            put(img, x, y, face)
        else:
            img.putpixel((x, y), texture.getpixel((x, y)))
    return img


def wall(kind, mask, rng):
    if kind == 'metal':
        texture = blank()
        rect(texture, 0, 0, S, S, 'tin')
        for x in (0, 4, 8, 12):
            rect(texture, x, 0, 1, S, 'tin_d')
            for y in (0, 8):
                put(texture, x + 1, y, 'slate_k')
        return strip(texture, mask, 3, 'tin_k', 'slate_l', 'slate_d')
    face, light = {'stone': ('face', 'stone_l'), 'brick': ('face_b', 'brick_l'),
                   'wood': ('face_w', 'log_l')}[kind]
    return strip(wall_texture(kind, rng), mask, 3, 'ink', light, face)


def aperture(vertical, sill):
    img = blank()
    for x in (0, 13):
        rect(img, x, 5, 3, 6, 'ink')
        rect(img, x, 5, 3, 1, 'plank_l')
        rect(img, x, 6, 3, 3, 'frame')
    if sill:
        rect(img, 3, 9, 10, 2, 'face')
        rect(img, 3, 9, 10, 1, 'stone_l')
        for x in (5, 10):
            rect(img, x, 5, 1, 4, 'frame')
    else:
        rect(img, 3, 9, 10, 1, 'plank_d')
    return img.transpose(Image.Transpose.TRANSPOSE) if vertical else img


def sandbags(mask, rng):
    texture = blank()
    rect(texture, 0, 0, S, S, 'bag_k')
    for y in range(0, S, 4):
        for x in range(-8 + (y % 8), S, 8):
            rect(texture, x + 1, y, 6, 3, 'bag')
            rect(texture, x + 2, y, 3, 1, 'sand_l')
            rect(texture, x + 2, y + 2, 4, 1, 'bag_d')
    return strip(texture, mask, 4, 'bag_k', 'bag_d')


def fence(mask, rng):
    texture = blank()
    rect(texture, 0, 0, S, S, 'fence')
    for x, y in ((6, 6), (9, 6), (6, 9), (9, 9)):
        put(texture, x, y, 'plank_l')
    for left, top, right, bottom in arm_boxes(mask, 3):
        if right - left > bottom - top:
            rect(texture, left, 7, right - left, 2, 'fence_d')
        else:
            rect(texture, 7, top, 2, bottom - top, 'fence_d')
    rect(texture, 6, 6, 4, 4, 'seam')
    rect(texture, 6, 6, 4, 2, 'plank_l')
    return strip(texture, mask, 3, 'fence_d', 'fence')


def hedge(mask, rng):
    texture = blank()
    rect(texture, 0, 0, S, S, 'leaf')
    for _ in range(21):
        x, y = rng.randrange(-1, S), rng.randrange(-1, S)
        rect(texture, x, y, 2, 2, rng.choice(['leaf_d', 'leaf_l', 'leaf']))
    return strip(texture, mask, 5, 'leaf_k', 'leaf_l', 'leaf_d')


def crate(rng):
    tone = rng.choice(['crate', 'crate', 'plank', 'plank_d'])
    img = blank()
    rect(img, 3, 14, 12, 2, 'shadow')
    rect(img, 2, 2, 12, 12, 'ink')
    rect(img, 3, 3, 10, 10, tone)
    for i in range(10):
        put(img, 3 + i, 3 + i, 'crate_d'); put(img, 12 - i, 3 + i, 'crate_d')
    rect(img, 3, 3, 10, 1, 'plank_l')
    rect(img, 3, 12, 10, 1, 'crate_d')
    return img


def barrel(rng):
    img = blank()
    disc(img, 8.5, 9.5, 6, 'shadow')
    disc(img, 8, 8, 6, 'ink')
    disc(img, 8, 8, 5, 'barrel')
    disc(img, 8, 8, 3, 'barrel_d')
    put(img, rng.choice([6, 7, 9, 10]), 7, 'barrel_l')
    disc(img, 8, 8, 2, 'barrel')
    rect(img, 4, 5, 2, 1, 'barrel_l')
    for x in (6, 8, 10):
        put(img, x, 12, 'hazard'); put(img, x + 1, 11, 'hazard')
    return img


def rock(rng):
    img = blank()
    disc(img, 9, 10, 6.5, 'shadow')
    disc(img, 8, 8, 6.5, 'ink')
    disc(img, 8, 8, 5.5, 'rock')
    disc(img, 9, 10, 3.5, 'rock_d')
    disc(img, rng.choice([5, 6, 7]), rng.choice([5, 6, 7]), 2.5, 'rock_l')
    put(img, 10, 7, 'rock_d')
    return img


def tree(rng):
    img = blank()
    disc(img, 9, 10, 7.5, 'shadow')
    disc(img, 8, 8, 7.5, 'leaf_k')
    disc(img, 8, 8, 6.5, 'leaf_d')
    disc(img, 7, 7, 5, 'leaf')
    disc(img, 6, 6, 2.5, 'leaf_l')
    speckle(img, rng, ['leaf_d', 'leaf_l'], 10, (3, 3, 13, 13))
    return img


def bush(rng):
    img = blank()
    disc(img, 8, 9, 5.5, 'leaf_k')
    disc(img, 8, 8, 5, 'leaf')
    disc(img, 5, 10, 3, 'leaf')
    disc(img, 11, 10, 3, 'leaf_d')
    speckle(img, rng, ['leaf_l', 'leaf_d'], 8, (4, 4, 12, 12))
    return img


def barbed_wire(rng):
    img = blank()
    for x in range(S):
        y = 5 + (x % 4 if x % 8 < 4 else 3 - x % 4)
        put(img, x, y, 'wire')
        put(img, x, y + 6, 'wire')
        if x % 4 == 1:
            put(img, x, y - 1, 'wire_l'); put(img, x, y + 5, 'wire_l')
    rect(img, 2, 3, 1, 11, 'log_k'); rect(img, 13, 3, 1, 11, 'log_k')
    return img


def fire_pit(rng):
    img = blank()
    for i in range(16):
        import math
        a = i / 16 * 2 * math.pi
        put(img, round(8 + math.cos(a) * 6.5 - 0.5), round(8 + math.sin(a) * 6.5 - 0.5), 'rock')
    disc(img, 8, 8, 4.5, 'scorch')
    disc(img, 8, 9, 3.5, 'ember')
    disc(img, 8, 8, 2.5, 'flame')
    rect(img, rng.choice([6, 7, 8]), rng.choice([4, 5]), 2, 4, 'flame')
    rect(img, 7, 7, 2, 3, 'flame_l')
    return img


def debris(rng, colors, count, size):
    img = blank()
    for _ in range(count):
        x, y = rng.randrange(1, 14), rng.randrange(1, 14)
        w, h = rng.randrange(1, size + 1), rng.randrange(1, size + 1)
        rect(img, x, y, w, h, rng.choice(colors))
    return img


def scorch(rng):
    img = blank()
    for y in range(S):
        for x in range(S):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d < 4.5 or (d < 7.5 and rng.random() < (7.5 - d) / 4):
                put(img, x, y, 'scorch' if d < 5 or rng.random() < 0.6 else 'scorch_l')
    return img


# ---------------------------------------------------------------- roofs

ROOF = {
    'roof-red': ('red', 'red_d', 'red_k', 'red_l'),
    'roof-slate': ('slate', 'slate_d', 'slate_k', 'slate_l'),
    'roof-thatch': ('thatch', 'thatch_d', 'thatch_k', 'thatch_l'),
    'roof-tin': ('tin', 'tin_d', 'tin_k', 'tin'),
}


def roof(material, rng):
    base, dark, edge, light = ROOF[material]
    img = blank()
    if material == 'roof-tin':
        for x in range(S):
            rect(img, x, 0, 1, S, base if x % 4 else dark)
        speckle(img, rng, ['rust'], 5)
    elif material == 'roof-thatch':
        rect(img, 0, 0, S, S, base)
        for _ in range(28):
            x, y = rng.randrange(S), rng.randrange(S)
            rect(img, x, y, 1, rng.randrange(2, 4), rng.choice([dark, light, edge]))
    else:
        for row in range(4):
            y = row * 4
            rect(img, 0, y, S, 3, base)
            rect(img, 0, y + 3, S, 1, dark)
            offset = 2 if row % 2 else 0
            for x in range(offset, S, 4):
                put(img, x, y + 2, dark)
                put(img, x + 1, y, light)
    return img


# Cardinal bits describe connected sides. Diagonal bits describe a missing corner
# only when both adjacent sides are connected. These are the 47 distinct shapes.
CORNERS = ((N | E, 16), (E | SO, 32), (SO | W, 64), (W | N, 128))
AREA_MASKS = list(range(16))
for mask in range(16):
    for cutouts in range(16, 256, 16):
        if all(not cutouts & bit or mask & sides == sides for sides, bit in CORNERS):
            AREA_MASKS.append(mask | cutouts)


def edge_distance(mask, x, y):
    n, e, s, w = y, S - 1 - x, S - 1 - y, x
    edges = [distance for distance, bit in ((n, N), (e, E), (s, SO), (w, W)) if not mask & bit]
    for (sides, bit), (first, second) in zip(CORNERS, ((n, e), (e, s), (s, w), (w, n))):
        if mask & bit or not mask & sides:
            edges.append(first + second - 2)
    return min(edges, default=S)


def shape_surface(texture, mask, trim):
    for y in range(S):
        for x in range(S):
            distance = edge_distance(mask, x, y)
            if distance < 0:
                texture.putpixel((x, y), (0, 0, 0, 0))
            elif distance < len(trim):
                put(texture, x, y, trim[distance])
    return texture


def area(mid, mask):
    rng = random.Random(mid)
    if mid in ROOF:
        _, dark, edge, light = ROOF[mid]
        # Outer lip, recessed gutter, and an inner flashing highlight.
        return shape_surface(roof(mid, rng), mask, ('ink', edge, light, dark))
    draws = {
        'sand': (sand, ('sand_d',)),
        'cobblestone': (cobblestone, ('grout', 'cob_l')),
        'road': (road, ('asph_d', 'asph_l', 'asph_d')),
        'road-worn': (cracked_road, ('asph_d', 'asph_l', 'asph_d')),
        'gravel': (gravel, ('sand_d', 'grout')),
        'rug': (rug, ('rug_d', 'gold', 'rug_d', 'gold')),
        'shallow-water': (lambda r: water(r, 'shal', 'shal_l', 'shal_d'), ('sand_d', 'shal_l')),
        'deep-water': (lambda r: water(r, 'deep', 'deep_l', 'deep_d'), ('shal_d', 'deep_l')),
    }
    draw, trim = draws[mid]
    return shape_surface(draw(rng), mask, trim)


def cracked_road(rng):
    img = road(rng)
    for x, y in ((4, 3), (5, 4), (6, 4), (6, 5), (7, 6), (8, 6), (8, 7),
                 (9, 8), (10, 8), (11, 9), (10, 10), (11, 11)):
        put(img, x, y, 'ink')
        put(img, x + 1, y, 'asph_l')
    return img


def gravel(rng):
    img = blank()
    rect(img, 0, 0, S, S, 'cob_d')
    for _ in range(46):
        rect(img, rng.randrange(S), rng.randrange(S), rng.choice([1, 2]), 1,
             rng.choice(['grout', 'cob', 'cob_l', 'sand_d']))
    return img


def bridge(rng):
    img = wood_floor(rng)
    for x in (0, 15):
        rect(img, x, 0, 1, S, 'log_k')
        for y in (1, 9):
            put(img, x, y, 'wire_l')
    return img


def lane(mask):
    img = blank()
    if mask == E | W:
        rect(img, 4, 7, 8, 2, 'paint')
    elif mask == N | SO:
        rect(img, 7, 4, 2, 8, 'paint')
    else:
        if mask & N: rect(img, 7, 3, 2, 6, 'paint')
        if mask & E: rect(img, 7, 7, 6, 2, 'paint')
        if mask & SO: rect(img, 7, 7, 2, 6, 'paint')
        if mask & W: rect(img, 3, 7, 6, 2, 'paint')
        if not mask: rect(img, 6, 7, 4, 2, 'paint')
    return img


def roof_detail(mid):
    img = blank()
    if mid == 'roof-skylight':
        rect(img, 3, 3, 11, 11, 'shadow')
        rect(img, 2, 2, 11, 11, 'slate_k')
        rect(img, 3, 3, 9, 9, 'tin')
        rect(img, 4, 4, 7, 7, 'shal_d')
        for x, y in ((5, 9), (6, 8), (7, 7), (8, 6), (9, 5), (6, 9), (7, 8)):
            put(img, x, y, 'glass')
        rect(img, 4, 7, 7, 1, 'tin_k')
    elif mid == 'roof-vent':
        rect(img, 5, 5, 8, 8, 'shadow')
        rect(img, 4, 4, 8, 8, 'slate_k')
        rect(img, 5, 5, 6, 6, 'tin')
        for y in (6, 8, 10):
            rect(img, 6, y, 4, 1, 'tin_k')
    else:
        rect(img, 0, 6, S, 5, 'slate_k')
        rect(img, 0, 7, S, 2, 'tin_d')
        rect(img, 0, 7, S, 1, 'tin')
        put(img, 0, 8, 'slate_k')
        if mid == 'roof-ridge-ns':
            img = img.transpose(Image.Transpose.TRANSPOSE)
    return img


def planter(rng):
    img = hedge(0, rng)
    rect(img, 2, 4, 12, 9, 'frame')
    rect(img, 3, 5, 10, 6, 'leaf_k')
    rect(img, 4, 6, 8, 4, 'leaf')
    for x in (5, 8, 11):
        put(img, x, rng.choice([6, 8]), rng.choice(['gold', 'red_l']))
    rect(img, 2, 4, 12, 1, 'plank_l')
    return img


def variants(material):
    mid = material['id']
    auto = material.get('autotile')
    if material.get('detail'):
        return [roof_detail(mid)]
    if auto == 'area':
        return [area(mid, mask) for mask in AREA_MASKS]
    if auto == 'blob':
        if mid.endswith('-wall'):
            def draw(mask, rng):
                return wall(mid.split('-')[0], mask, rng)
        else:
            draw = {'sandbags': sandbags, 'wood-fence': fence, 'hedge': hedge}[mid]
        return [draw(mask, random.Random(f'{mid}-{mask}')) for mask in range(16)]
    if auto == 'orient':
        return [aperture(vertical, mid == 'window') for vertical in (False, True)]
    if auto == 'lane':
        # Preserve the first two slots for levels already exported to Lua.
        return [road_line(random.Random(mid), vertical) for vertical in (False, True)] + [
            lane(mask) for mask in range(16)]
    draw = {
        'wood-floor': wood_floor, 'stone-floor': stone_floor, 'tile-floor': tile_floor,
        'bridge-planks': bridge, 'planter': planter,
        'crate': crate, 'barrel': barrel, 'rock': rock, 'tree': tree, 'bush': bush,
        'barbed-wire': barbed_wire, 'fire-pit': fire_pit, 'scorch': scorch,
        'barbed-wire-ns': lambda r: barbed_wire(r).transpose(Image.Transpose.TRANSPOSE),
        'rubble': lambda r: debris(r, ['rock', 'rock_d', 'rock_l', 'mortar'], 14, 3),
        'splinters': lambda r: debris(r, ['plank', 'plank_d', 'seam'], 12, 2),
    }[mid]
    return [draw(random.Random(mid if i == 0 else f'{mid}-{i}'))
            for i in range(material.get('variants', 1))]


def main():
    spec = json.loads((TILES / 'materials.json').read_text(encoding='utf-8'))
    drawn = [(m, variants(m)) for m in spec['materials'] if 'terrain' not in m]
    columns = 16
    rows = sum((len(images) + columns - 1) // columns for _, images in drawn)
    sheet = Image.new('RGBA', (columns * S, rows * S))
    layout = {'image': 'tileset.png', 'tileSize': S, 'columns': columns,
              'areaMasks': AREA_MASKS, 'materials': {}}
    row = 0
    for material, images in drawn:
        for index, image in enumerate(images):
            sheet.paste(image, (index % columns * S, (row + index // columns) * S))
        layout['materials'][material['id']] = {'row': row, 'variants': len(images)}
        row += (len(images) + columns - 1) // columns
    sheet.save(TILES / 'tileset.png')
    (TILES / 'tiles-layout.json').write_text(json.dumps(layout, indent=2) + '\n')
    colors = {px[:3] for px in sheet.get_flattened_data() if px[3]}
    print(f'{len(drawn)} materials, {sum(len(v) for _, v in drawn)} tiles, {len(colors)} colours')


if __name__ == '__main__':
    main()
