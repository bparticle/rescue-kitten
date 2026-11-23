"""Author the hero walk sheets and effect sheets for the nine starter-arsenal weapons.

This writes PNG sources into sprites/. It was used to create the first pass of
that art. Once an artist touches the PNGs, edit them directly and run
tools/build_assets.py instead of rerunning this script.

    python tools/draw_new_weapon_art.py          # hero sheets + effect sheets
    python tools/draw_new_weapon_art.py --preview DIR   # also write upscaled previews and GIFs
"""

import json
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / 'sprites' / 'hero'
FX = ROOT / 'sprites' / 'effects'
CELL = 28
DIRS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
VEC = {'N': (0, -1), 'NE': (1, -1), 'E': (1, 0), 'SE': (1, 1),
       'S': (0, 1), 'SW': (-1, 1), 'W': (-1, 0), 'NW': (-1, -1)}

# Shared colors. The first block comes from the existing weapon icons so the
# held weapons and their effects read as the same objects as the pickups.
C = {
    'K': (35, 31, 32), 'd': (73, 72, 73), 'm': (119, 121, 114), 'p': (181, 180, 165),
    'w': (226, 215, 180), 'c': (112, 194, 194), 'C': (68, 116, 124), 'i': (186, 246, 230),
    'o': (221, 150, 78), 'y': (255, 208, 120), 'r': (206, 82, 65), 'R': (164, 61, 52),
    'v': (89, 75, 118), 'V': (143, 118, 183), 'u': (228, 191, 242),
    'g': (120, 136, 103), 'G': (179, 188, 137),
    # Effect-only tones.
    'W': (255, 247, 216), 'Y': (255, 230, 164), 'O': (235, 110, 49), 'b': (55, 46, 80),
    'n': (238, 252, 248), 'f': (149, 214, 222), 'F': (84, 152, 168), 'e': (52, 86, 99),
    'q': (205, 236, 255), 'x': (110, 92, 150), 'X': (176, 152, 214), 'z': (32, 26, 46),
    'a': (131, 114, 94), 'A': (181, 164, 132), 's': (98, 84, 69),
}

HERO_COLORS = {(35, 31, 32), (56, 85, 90), (42, 64, 67), (121, 81, 61), (90, 56, 43),
               (188, 129, 92), (152, 98, 73), (104, 133, 138), (215, 163, 122),
               (96, 93, 94), (56, 56, 58), (73, 72, 73)}
OUTLINE = (35, 31, 32)


def grid(rows):
    """ASCII rows -> {(x, y): rgb}. Periods are transparent."""
    out = {}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                out[x, y] = C[ch]
    return out


# ---------------------------------------------------------------- held weapons
# Each weapon is drawn facing east and south-east, muzzle at the far end.
# The other six directions are exact 90-degree turns or mirrors of these.
HELD = {
    'rail-rifle': {
        'base': 'assault-rifle',
        'E': [
            '.KKKK..........',
            'KdmwKKKKKKKKKKK',
            'KmdKiciiciicinK',
            'KdmdCCcCCcCCcKK',
            '.KKKKKKKKKKKKK.',
            '..KdK..........',
            '..KK...........',
        ],
        'SE': [
            '.KKK.........',
            'KdmwK........',
            'KmdmKK.......',
            '.KdKiKK......',
            '..KKCiKK.....',
            '...KKCiKK....',
            '....KKCcKK...',
            '.....KKCiKK..',
            '......KKCiKK.',
            '.......KKCnK.',
            '........KKKK.',
        ],
    },
    'arc-projector': {
        'base': 'assault-rifle',
        'E': [
            '.KKKKK...K.K.',
            'KmpwdKKKKiKiK',
            'KddCciicicCcK',
            'KKdmKKCKKKKK.',
            '..KKK.KK.....',
        ],
        'SE': [
            '.KKK.......',
            'KmpwK......',
            'KddCKK.....',
            '.KdcCKK....',
            '..KKicKK...',
            '...KKicKK..',
            '....KKicKK.',
            '.....KKCiiK',
            '......KKiK.',
            '.......KK..',
        ],
    },
    'cryo-sprayer': {
        'base': 'flamethrower',
        'E': [
            '..KKKKKK....',
            '.KCiicCCKKKK',
            'KmCcCcCKdmiK',
            'KdKKKKKKKKK.',
            '.KK.........',
        ],
        'SE': [
            '..KKK.....',
            '.KCicK....',
            'KCicCCK...',
            'KmCcCCKK..',
            '.KKCCKdKK.',
            '..KKKKmiK.',
            '.....KKiK.',
            '......KK..',
        ],
    },
    'charge-cannon': {
        'base': 'pump-shotgun', 'push': 3,
        'E': [
            '..KKKKKK.....',
            '.KoywyoKKKKKK',
            'KdRyoyrKmpmpK',
            'KddRrrRKdmdmK',
            '.KKKKKKKKKKK.',
        ],
        'SE': [
            '..KKK......',
            '.KoyoK.....',
            'KoywyRK....',
            'KdyorRKK...',
            '.KdRRKmKK..',
            '..KKKKdmKK.',
            '.....KKpmK.',
            '......KKdK.',
            '.......KK..',
        ],
    },
    'bankshot': {
        'base': 'handgun',
        'E': [
            'KKKKKKK.',
            'KgmpoowK',
            'KdgKKKKK',
            'KKK.....',
        ],
        'SE': [
            'KKK...',
            'KgmK..',
            'KdpoK.',
            '.KKowK',
            '..KKK.',
        ],
    },
    'boomerang-disc': {
        'base': 'grenade',
        'E': [
            '.KKK.',
            'KwpyK',
            'KpKoK',
            'KyomK',
            '.KKK.',
        ],
        'SE': [
            '.KKK.',
            'KwpyK',
            'KpKoK',
            'KyomK',
            '.KKK.',
        ],
    },
    'gravity-orb': {
        'base': 'handgun',
        'E': [
            '....KKKK.',
            'KKKKvVuVK',
            'KmddvuVvK',
            'KKKKvvVvK',
            '....KKKK.',
        ],
        'SE': [
            'KK......',
            'KmK.....',
            '.KdKKK..',
            '..KvVuK.',
            '..KVuVvK',
            '..KvVvvK',
            '...KvvK.',
            '....KK..',
        ],
    },
    'shock-hammer': {
        'base': 'pump-shotgun',
        'E': [
            '........KKKK',
            '.......KpwpK',
            'KKKKKKKKmcdK',
            'KgddmdmdmiCK',
            'KKKKKKKKmcdK',
            '.......KdmdK',
            '........KKKK',
        ],
        'SE': [
            'KK.......',
            'KgK......',
            '.KdK.KK..',
            '..KdKpwK.',
            '...KmcpwK',
            '..KpciCmK',
            '..KwpCdK.',
            '...KwdK..',
            '....KK...',
        ],
    },
}


def turn(pixels):
    """Rotate 90 degrees counter-clockwise on screen: east -> north."""
    return {(y, -x): c for (x, y), c in pixels.items()}


def mirror_x(pixels):
    return {(-x, y): c for (x, y), c in pixels.items()}


def mirror_y(pixels):
    return {(x, -y): c for (x, y), c in pixels.items()}


def held_directions(spec):
    east, southeast = grid(spec['E']), grid(spec['SE'])
    north = turn(east)
    northeast = mirror_y(southeast)
    return {
        'E': east, 'W': mirror_x(east),
        'N': north, 'S': mirror_y(north),
        'SE': southeast, 'SW': mirror_x(southeast),
        'NE': northeast, 'NW': mirror_x(northeast),
    }


def colored(pixels):
    return [p for p, c in pixels.items() if c != OUTLINE]


def tip_anchor(points, direction):
    """Furthest point along the facing direction, centred across it."""
    dx, dy = VEC[direction]
    along = [x * dx + y * dy for x, y in points]
    far = max(along)
    near_tip = [p for p, a in zip(points, along) if a >= far - 1]
    nx, ny = -dy, dx
    across = sum(x * nx + y * ny for x, y in near_tip) / len(near_tip)
    return far, across


def place(points_from, direction, target_far, target_across):
    """Offset that moves points_from's tip onto the target tip."""
    dx, dy = VEC[direction]
    nx, ny = -dy, dx
    far, across = tip_anchor(points_from, direction)
    norm = dx * dx + dy * dy
    da, dc = target_far - far, target_across - across
    # Solve offset (ox, oy): ox*dx+oy*dy = da, ox*nx+oy*ny = dc
    ox = (da * dx + dc * nx) / norm
    oy = (da * dy + dc * ny) / norm
    return round(ox), round(oy)


def split_base(cell):
    """Separate a base cell into the hero body and the held-weapon mask."""
    px = cell.load()
    weapon, body = set(), {}
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = px[x, y]
            if not a:
                continue
            if (r, g, b) in HERO_COLORS:
                body[x, y] = (r, g, b)
            else:
                weapon.add((x, y))
    # Drop outline pixels that only belonged to the weapon.
    for _ in range(2):
        drop = []
        for (x, y), c in body.items():
            if c != OUTLINE:
                continue
            near = [(x + i, y + j) for i in (-1, 0, 1) for j in (-1, 0, 1) if i or j]
            touches_body = any(q in body and body[q] != OUTLINE for q in near)
            touches_weapon = any(q in weapon for q in near)
            if touches_weapon and not touches_body:
                drop.append((x, y))
        for q in drop:
            del body[q]
            weapon.add(q)
    return body, weapon


def compose(cell, direction, held, push=0):
    body, weapon = split_base(cell)
    base_colored = [p for p in weapon if cell.getpixel(p)[:3] != OUTLINE]
    out = Image.new('RGBA', (CELL, CELL))
    for p, c in body.items():
        out.putpixel(p, (*c, 255))
    if not base_colored:
        return out
    far, across = tip_anchor(base_colored, direction)
    ox, oy = place(colored(held), direction, far + push, across)
    behind = direction in ('N', 'NE', 'NW')
    for (x, y), c in held.items():
        q = (x + ox, y + oy)
        if not (0 <= q[0] < CELL and 0 <= q[1] < CELL):
            continue
        existing = body.get(q)
        if behind and existing is not None and existing != OUTLINE:
            continue  # the body hides the weapon when walking away from camera
        if existing is not None and existing != OUTLINE and c == OUTLINE:
            continue  # never outline over the body itself
        out.putpixel(q, (*c, 255))
    return out


def hero_sheets():
    layout = json.loads((HERO / 'walk-layout.json').read_text())
    idle = Image.open(HERO / layout['idleSheet']['image']).convert('RGBA')
    idle_cols = list(layout['idleSheet']['columnsLeftToRight'])
    original_cols = idle_cols[:8]
    idle = idle.crop((0, 0, CELL * len(original_cols), CELL * 8))
    new_idle_cols = []
    for name, spec in HELD.items():
        base = Image.open(HERO / f'walk-{spec["base"]}.png').convert('RGBA')
        held = held_directions(spec)
        sheet = Image.new('RGBA', base.size)
        for row, direction in enumerate(DIRS):
            for col in range(8):
                box = (col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL)
                sheet.paste(compose(base.crop(box), direction, held[direction], spec.get('push', 0)), box[:2])
        sheet.save(HERO / f'walk-{name}.png')
        layout['sheets'][name] = f'walk-{name}.png'
        new_idle_cols.append((name, spec['base']))
    wide = Image.new('RGBA', (CELL * (len(original_cols) + len(new_idle_cols)), CELL * 8))
    wide.paste(idle, (0, 0))
    for i, (name, base_name) in enumerate(new_idle_cols):
        col = original_cols.index(base_name)
        held = held_directions(HELD[name])
        for row, direction in enumerate(DIRS):
            box = (col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL)
            pose = compose(idle.crop(box), direction, held[direction], HELD[name].get('push', 0))
            wide.paste(pose, ((len(original_cols) + i) * CELL, row * CELL))
    wide.save(HERO / layout['idleSheet']['image'])
    layout['idleSheet']['columnsLeftToRight'] = original_cols + [n for n, _ in new_idle_cols]
    (HERO / 'walk-layout.json').write_text(json.dumps(layout, indent=2) + '\n')


def previews(rendered, out_dir):
    """Upscaled contact sheets per weapon on the range ground colour."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ground = (163, 147, 119, 255)
    by_weapon = {}
    for name, (entry, rows) in rendered.items():
        by_weapon.setdefault(entry['weapon'], []).append((name, entry, rows))
    for weapon, items in by_weapon.items():
        blocks = []
        for name, entry, rows in items:
            show = rows if not entry['directional'] else [rows[2], rows[3]]
            w, h = entry['frameWidth'], entry['frameHeight']
            cols = max(len(r) for r in show)
            block = Image.new('RGBA', (cols * (w + 2), len(show) * (h + 2)), ground)
            for y, row in enumerate(show):
                for x, im in enumerate(row):
                    block.alpha_composite(im, (x * (w + 2), y * (h + 2)))
            blocks.append(block)
        width = max(b.width for b in blocks)
        height = sum(b.height + 4 for b in blocks)
        sheet = Image.new('RGBA', (width, height), (120, 108, 88, 255))
        y = 0
        for b in blocks:
            sheet.alpha_composite(b, (0, y))
            y += b.height + 4
        sheet.resize((sheet.width * 5, sheet.height * 5), Image.NEAREST).save(out_dir / f'{weapon}.png')


if __name__ == '__main__':
    from draw_new_weapon_effects import effect_sheets
    hero_sheets()
    rendered = effect_sheets()
    if '--preview' in sys.argv:
        previews(rendered, sys.argv[sys.argv.index('--preview') + 1])
