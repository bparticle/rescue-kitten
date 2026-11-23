"""Firing, travel and impact effect sheets for the starter-arsenal weapons.

Run through tools/draw_new_weapon_art.py. Every frame is drawn on the native
pixel grid with the shared colour keys from that script, so the art packs into
the same palette as the hero and terrain.
"""

import json
import math

from PIL import Image

from draw_new_weapon_art import C, DIRS, FX, VEC


class Frame:
    def __init__(self, w, h):
        self.w, self.h, self.px = w, h, {}
        self.cx, self.cy = w // 2, h // 2

    def put(self, x, y, ch, over=True):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h and (over or (x, y) not in self.px):
            self.px[x, y] = ch

    def line(self, x0, y0, x1, y1, ch, over=True):
        x0, y0, x1, y1 = (int(round(v)) for v in (x0, y0, x1, y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.put(x0, y0, ch, over)
            if x0 == x1 and y0 == y1:
                return
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ring(self, cx, cy, r, ch, gaps=0, phase=0.0, over=True):
        steps = max(8, int(r * 8))
        for i in range(steps):
            u = i / steps
            if gaps and int(u * gaps * 2) % 2:
                continue
            a = 2 * math.pi * u + phase
            self.put(cx + r * math.cos(a), cy + r * math.sin(a), ch, over)

    def disc(self, cx, cy, r, ch, over=True):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.3:
                    self.put(x, y, ch, over)

    def polar(self, r, theta, base=0.0):
        a = base + theta
        return self.cx + r * math.cos(a), self.cy + r * math.sin(a)

    def outline(self, ch='K'):
        for (x, y) in list(self.px):
            for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if q not in self.px:
                    self.put(*q, ch, over=False)

    def mirrored(self):
        g = Frame(self.w, self.h)
        for (x, y), c in self.px.items():
            g.put(self.w - 1 - x, y, c)
        return g

    def image(self):
        im = Image.new('RGBA', (self.w, self.h))
        for (x, y), ch in self.px.items():
            im.putpixel((x, y), (*C[ch], 255))
        return im


class Rand:
    def __init__(self, seed):
        self.seed = seed

    def __call__(self):
        self.seed = (self.seed * 1103515245 + 12345) & 0x7fffffff
        return self.seed / 0x7fffffff


def angle_of(direction):
    dx, dy = VEC[direction]
    return math.atan2(dy, dx)


def fwd(f, a, t, s=0.0):
    """Point t pixels ahead and s pixels to the right of facing angle a."""
    return (f.cx + t * math.cos(a) - s * math.sin(a), f.cy + t * math.sin(a) + s * math.cos(a))


def fline(f, a, t0, t1, ch, s=0.0, over=True):
    f.line(*fwd(f, a, t0, s), *fwd(f, a, t1, s), ch, over)


def star(f, x, y, r, ch, diag=None):
    for i in range(-r, r + 1):
        f.put(x + i, y, ch)
        f.put(x, y + i, ch)
    if diag:
        for i in range(1, max(2, r)):
            for sx in (-1, 1):
                for sy in (-1, 1):
                    f.put(x + sx * i, y + sy * i, diag, over=False)


def sparks(f, rnd, count, r0, r1, ch, phase=0.0, length=1):
    for i in range(count):
        a = phase + 2 * math.pi * (i + rnd() * 0.6) / count
        r = r0 + (r1 - r0) * rnd()
        x, y = f.cx + r * math.cos(a), f.cy + r * math.sin(a)
        f.put(x, y, ch)
        if length > 1:
            f.line(x, y, x - (length - 1) * math.cos(a), y - (length - 1) * math.sin(a), ch)


def jagged(f, rnd, x0, y0, x1, y1, ch, amp=2.0, steps=5, glow=None):
    """Lightning between two points with fixed ends."""
    nx, ny = -(y1 - y0), x1 - x0
    norm = math.hypot(nx, ny) or 1
    nx, ny = nx / norm, ny / norm
    pts = [(x0, y0)]
    for i in range(1, steps):
        t = i / steps
        o = (rnd() * 2 - 1) * amp
        pts.append((x0 + (x1 - x0) * t + nx * o, y0 + (y1 - y0) * t + ny * o))
    pts.append((x1, y1))
    core = Frame(f.w, f.h)
    for p, q in zip(pts, pts[1:]):
        core.line(*p, *q, ch)
    if glow:
        for (x, y) in list(core.px):
            for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if q not in core.px and rnd() < 0.55:
                    f.put(*q, glow, over=False)
    for (x, y), c in core.px.items():
        f.put(x, y, c)


def edge_cells(d, size=16):
    """Pixels of a tile-wide line that leaves the tile exactly where the next tile starts."""
    dx, dy = VEC[d]
    x0 = 0 if dx > 0 else size - 1 if dx < 0 else size // 2
    y0 = 0 if dy > 0 else size - 1 if dy < 0 else size // 2
    return [(x0 + dx * i, y0 + dy * i) for i in range(size)], (x0, y0), (x0 + dx * (size - 1), y0 + dy * (size - 1))


# ------------------------------------------------------------------ rail rifle
def rail_muzzle(d):
    a, out = angle_of(d), []
    for k in range(4):
        f = Frame(16, 16)
        if k == 0:
            fline(f, a, 0, 3, 'i')
            fline(f, a, -1, 1, 'c', 2)
            fline(f, a, -1, 1, 'c', -2)
            f.put(*fwd(f, a, 0), 'W')
        elif k == 1:
            fline(f, a, 1, 6, 'i', 1)
            fline(f, a, 1, 6, 'i', -1)
            fline(f, a, 0, 7, 'W')
            f.line(*fwd(f, a, 1, -4), *fwd(f, a, 1, 4), 'c', over=False)
            f.put(*fwd(f, a, 0), 'n')
        elif k == 2:
            fline(f, a, 3, 7, 'i')
            fline(f, a, 2, 5, 'c', 1)
            fline(f, a, 2, 5, 'c', -1)
            for s in (-4, 4):
                f.put(*fwd(f, a, 2, s), 'C')
        else:
            for t, s in ((5, 0), (7, 1), (6, -2), (2, 3), (2, -3)):
                f.put(*fwd(f, a, t, s), 'C')
        out.append(f)
    return out


def rail_beam(d):
    dx, dy = VEC[d]
    cells, _, _ = edge_cells(d)
    side = [(-dy, dx), (dy, -dx)] if not (dx and dy) else [(1, 0), (0, 1)]
    out = []
    for k in range(4):
        f = Frame(16, 16)
        for i, (x, y) in enumerate(cells):
            if k == 0:
                f.put(x, y, 'W')
                for sx, sy in side:
                    f.put(x + sx, y + sy, 'i')
            elif k == 1:
                f.put(x, y, 'n' if i % 5 else 'i')
                for j, (sx, sy) in enumerate(side):
                    if (i + 2 * j) % 3:
                        f.put(x + sx, y + sy, 'c')
            elif k == 2:
                if i % 4 != 3:
                    f.put(x, y, 'c')
                if i % 6 == 1:
                    f.put(x + side[0][0], y + side[0][1], 'C')
            elif i % 4 == 0:
                f.put(x, y, 'C')
        out.append(f)
    return out


def rail_pierce(d):
    a, out = angle_of(d), []
    rnd = Rand(11)
    for k in range(5):
        f = Frame(24, 24)
        if k == 0:
            star(f, f.cx, f.cy, 3, 'i', 'c')
            fline(f, a, 1, 6, 'W')
            f.put(f.cx, f.cy, 'W')
        elif k == 1:
            f.ring(f.cx, f.cy, 3, 'i')
            f.put(f.cx, f.cy, 'n')
            fline(f, a, 3, 10, 'n')
            fline(f, a, 4, 8, 'c', 2)
            fline(f, a, 4, 8, 'c', -2)
            fline(f, a, -3, -5, 'c')
        elif k == 2:
            f.ring(f.cx, f.cy, 5, 'c', gaps=5, phase=0.3)
            fline(f, a, 6, 11, 'c')
            fline(f, a, 7, 9, 'C', 3)
            fline(f, a, 7, 9, 'C', -3)
            sparks(f, rnd, 5, 3, 6, 'i')
        elif k == 3:
            f.ring(f.cx, f.cy, 7, 'C', gaps=6, phase=0.6)
            fline(f, a, 9, 11, 'C')
            sparks(f, rnd, 4, 5, 8, 'c')
        else:
            sparks(f, rnd, 5, 6, 10, 'C')
        out.append(f)
    return out


# -------------------------------------------------------------------- bankshot
def bank_muzzle(d):
    a, out = angle_of(d), []
    for k in range(3):
        f = Frame(12, 12)
        if k == 0:
            fline(f, a, 0, 4, 'Y')
            fline(f, a, 1, 2, 'o', 1)
            fline(f, a, 1, 2, 'o', -1)
            fline(f, a, 0, 1, 'W')
        elif k == 1:
            fline(f, a, 2, 5, 'y')
            fline(f, a, 2, 3, 'O', 1)
            fline(f, a, 2, 3, 'O', -1)
            f.put(*fwd(f, a, 2), 'Y')
        else:
            f.put(*fwd(f, a, 4), 'O')
            f.put(*fwd(f, a, 3, 2), 'R')
            f.put(*fwd(f, a, 3, -2), 'R')
        out.append(f)
    return out


def bank_round(d):
    a, out = angle_of(d), []
    for k in range(2):
        f = Frame(10, 10)
        fline(f, a, -4, -2, 'R' if k else 'O')
        fline(f, a, -2, -1, 'o')
        f.put(*fwd(f, a, -3, 1 if k else -1), 'O')
        f.put(*fwd(f, a, 0), 'W')
        f.put(*fwd(f, a, 1), 'Y')
        out.append(f)
    return out


def bank_ricochet():
    out, rnd = [], Rand(5)
    for k in range(5):
        f = Frame(16, 16)
        if k == 0:
            star(f, f.cx, f.cy, 2, 'Y', 'Y')
            f.put(f.cx, f.cy, 'W')
        elif k == 1:
            star(f, f.cx, f.cy, 4, 'y', 'Y')
            f.ring(f.cx, f.cy, 3, 'o', over=False)
            star(f, f.cx, f.cy, 1, 'W')
        elif k == 2:
            f.ring(f.cx, f.cy, 5, 'o', gaps=4, phase=0.4)
            sparks(f, rnd, 5, 3, 6, 'Y', length=2)
            f.put(f.cx, f.cy, 'y')
        elif k == 3:
            sparks(f, rnd, 5, 5, 7, 'O', length=2)
            f.ring(f.cx, f.cy, 6, 'R', gaps=5)
        else:
            sparks(f, rnd, 4, 6, 7, 'R')
        out.append(f)
    return out


def reflector():
    """Rows: '/' plate then '\\' plate. Frames: idle, struck, cooling."""
    rows = [[], []]
    for k in range(3):
        f = Frame(16, 16)
        face = [('w', 'p', 'm'), ('W', 'Y', 'y'), ('Y', 'w', 'p')][k]
        for i in range(-5, 6):
            x, y = f.cx + i, f.cy - 2 - i
            f.put(x, y - 1, face[0])
            f.put(x, y, face[1])
            f.put(x + 1, y, face[2])
        f.line(f.cx, f.cy - 1, f.cx, f.cy + 4, 'd')
        f.line(f.cx - 3, f.cy + 5, f.cx + 3, f.cy + 5, 'm')
        f.line(f.cx - 2, f.cy + 6, f.cx + 2, f.cy + 6, 'd')
        f.outline('K')
        if k == 1:
            f.put(f.cx - 6, f.cy + 1, 'Y')
            f.put(f.cx + 5, f.cy - 9 if f.cy >= 9 else 0, 'Y')
        rows[0].append(f)
        rows[1].append(f.mirrored())
    return rows


def bank_impact():
    out, rnd = [], Rand(9)
    for k in range(4):
        f = Frame(12, 12)
        if k == 0:
            star(f, f.cx, f.cy, 2, 'Y')
            f.put(f.cx, f.cy, 'W')
        elif k == 1:
            star(f, f.cx, f.cy, 1, 'W')
            sparks(f, rnd, 6, 2, 4, 'o', length=2)
            f.put(f.cx, f.cy, 'Y')
        elif k == 2:
            sparks(f, rnd, 6, 3, 5, 'O')
            f.put(f.cx, f.cy, 'o')
        else:
            sparks(f, rnd, 4, 4, 5, 'R')
        out.append(f)
    return out


# -------------------------------------------------------------- boomerang disc
def disc_spin():
    out = []
    for k in range(4):
        f = Frame(11, 11)
        f.disc(f.cx, f.cy, 3.6, 'p')
        f.ring(f.cx, f.cy, 3.4, 'o')
        a = k * math.pi / 2 + 0.6
        for r in (1.5, 2.5, 3.4):
            f.put(f.cx + r * math.cos(a), f.cy + r * math.sin(a), 'w')
        f.put(f.cx + 3.4 * math.cos(a + math.pi), f.cy + 3.4 * math.sin(a + math.pi), 'm')
        f.put(f.cx + 2.6 * math.cos(a + 2.2), f.cy + 2.6 * math.sin(a + 2.2), 'y')
        f.put(f.cx, f.cy, 'K')
        f.outline('K')
        out.append(f)
    return out


def disc_throw(d):
    a, out = angle_of(d), []
    for k in range(3):
        f = Frame(18, 18)
        t0, t1 = [(-1.3, -0.2), (-1.3, 0.9), (-0.2, 1.3)][k]
        lead, tail = [('W', 'w'), ('w', 'A'), ('A', 'a')][k]
        for i in range(24):
            th = t0 + (t1 - t0) * i / 23
            f.put(*f.polar(6, th, a), lead)
            if i % 2 == 0:
                f.put(*f.polar(7.5, th, a), tail, over=False)
        out.append(f)
    return out


def disc_hit():
    out, rnd = [], Rand(21)
    for k in range(4):
        f = Frame(16, 16)
        if k < 3:
            r, ch = [5, 6, 4][k], ['W', 'Y', 'o'][k]
            for i in range(-r, r + 1):
                if k == 2 and abs(i) < 2:
                    continue
                f.put(f.cx + i, f.cy + i, ch)
                f.put(f.cx + i, f.cy - i, ch)
        if k == 0:
            f.ring(f.cx, f.cy, 2, 'y', over=False)
            f.put(f.cx, f.cy, 'W')
        else:
            sparks(f, rnd, 5 if k < 3 else 4, 3 + k, 5 + k, ['o', 'o', 'O', 'R'][k])
        out.append(f)
    return out


def disc_catch():
    out = []
    for k in range(3):
        f = Frame(12, 12)
        if k == 0:
            f.ring(f.cx, f.cy, 3, 'y')
            f.put(f.cx, f.cy, 'W')
        elif k == 1:
            f.ring(f.cx, f.cy, 4.5, 'o', gaps=4)
        else:
            for i in range(4):
                th = i * math.pi / 2 + math.pi / 4
                f.put(*f.polar(5, th), 'o')
        out.append(f)
    return out


# --------------------------------------------------------------- arc projector
def arc_muzzle(d):
    a, out = angle_of(d), []
    for k in range(3):
        f = Frame(16, 16)
        rnd = Rand(31 + k * 7 + DIRS.index(d))
        reach = [5, 7, 6][k]
        for spread in ((-0.6, 0.0, 0.6) if k < 2 else (-0.4, 0.5)):
            jagged(f, rnd, f.cx, f.cy, *f.polar(reach, spread, a), 'i' if k < 2 else 'c',
                   amp=1.2, steps=3, glow='c' if k < 2 else None)
        f.put(f.cx, f.cy, 'n' if k < 2 else 'c')
        out.append(f)
    return out


def arc_bolt(d):
    _, start, end = edge_cells(d)
    out = []
    for k in range(3):
        f = Frame(16, 16)
        rnd = Rand(101 + k * 13 + DIRS.index(d) * 3)
        jagged(f, rnd, *start, *end, 'n', amp=2.6, steps=4, glow='c')
        if k == 2:
            for q, c in list(f.px.items()):
                f.px[q] = 'C' if c == 'c' else 'c'
        out.append(f)
    return out


def arc_zap():
    out = []
    for k in range(4):
        f = Frame(20, 20)
        rnd = Rand(77 + k)
        if k == 0:
            f.disc(f.cx, f.cy, 1.5, 'n')
            for i in range(5):
                th = i * 2 * math.pi / 5 + 0.3
                jagged(f, rnd, f.cx, f.cy, *f.polar(5, th), 'i', amp=1.0, steps=2, glow='c')
            f.put(f.cx, f.cy, 'W')
        elif k == 1:
            f.ring(f.cx, f.cy, 5, 'c', gaps=6)
            for i in range(4):
                th = i * math.pi / 2 + 0.8
                jagged(f, rnd, *f.polar(2, th), *f.polar(8, th), 'i', amp=1.5, steps=3, glow='c')
            f.put(f.cx, f.cy, 'n')
        elif k == 2:
            f.ring(f.cx, f.cy, 7, 'C', gaps=7, phase=0.4)
            sparks(f, rnd, 5, 4, 8, 'c')
        else:
            sparks(f, rnd, 4, 6, 9, 'C')
        out.append(f)
    return out


# ---------------------------------------------------------------- cryo sprayer
TONGUES = [
    ['.........', '..R..OO..', '.ROOOYYO.', 'ROYYHYYOR', '..OOYYOR.', '...RR.O..', '.........'],
    ['.........', '.RR.O....', 'ROOYYOO..', '.OYYHHYOR', '..OROYYO.', '.....ORR.', '......R..'],
    ['....R....', '...OO....', '.ROYOO.R.', 'ROYYHYOO.', '.OOYYHYYR', '..R.OOOO.', '.....R...'],
]


def cryo_puffs():
    """Rows: age (fresh, drifting, fading). Columns: flicker shape."""
    ramps = [{'R': 'F', 'O': 'f', 'Y': 'q', 'H': 'n'},
             {'R': 'e', 'O': 'F', 'Y': 'f', 'H': 'q'},
             {'R': 'e', 'O': 'e', 'Y': 'F', 'H': 'f'}]
    rows = []
    for age, ramp in enumerate(ramps):
        row = []
        for k, shape in enumerate(TONGUES):
            f = Frame(9, 7)
            for y, line in enumerate(shape):
                for x, ch in enumerate(line):
                    if ch != '.':
                        f.put(x, y, ramp[ch])
            if age == 0:
                f.put(2 + k * 2, 2 + k % 2, 'n')
            row.append(f)
        rows.append(row)
    return rows


def cryo_muzzle(d):
    a, out = angle_of(d), []
    for k in range(3):
        f = Frame(12, 12)
        if k == 0:
            fline(f, a, 0, 3, 'n')
            fline(f, a, 1, 3, 'q', 1)
            fline(f, a, 1, 3, 'q', -1)
            f.put(*fwd(f, a, 0), 'W')
        elif k == 1:
            fline(f, a, 2, 4, 'q')
            for s in (-2, 2):
                f.put(*fwd(f, a, 3, s), 'f')
            f.put(*fwd(f, a, 5, 1), 'n')
            f.put(*fwd(f, a, 1), 'f')
        else:
            f.put(*fwd(f, a, 4, -1), 'F')
            f.put(*fwd(f, a, 5, 2), 'f')
            f.put(*fwd(f, a, 3, 2), 'F')
        out.append(f)
    return out


def frost_coat():
    """Overlay for a frosted target. Frames 1-2 coat it, then 3-4 loop."""
    w, h = 22, 18
    corners = [(3, 2), (w - 4, 2), (3, h - 3), (w - 4, h - 3)]
    out = []
    for k in range(4):
        f = Frame(w, h)
        grow = min(k, 2)
        for x, y in corners:
            sx = 1 if x < w // 2 else -1
            sy = 1 if y < h // 2 else -1
            f.put(x, y, 'q')
            f.put(x + sx, y, 'f')
            f.put(x, y + sy, 'f')
            if grow:
                f.line(x + sx, y, x + sx * (2 + grow), y, 'f', over=False)
                f.line(x, y + sy, x, y + sy * (1 + grow), 'F', over=False)
                f.put(x + sx, y + sy, 'q')
        if grow:
            for x in range(6, w - 6, 2 if grow == 1 else 1):
                f.put(x, 1, 'q' if x % 3 else 'n')
                if x % 4 == 1:
                    f.put(x, 2, 'f')
                    if grow == 2:
                        f.put(x, 3, 'F')
        if grow == 2:
            for y in range(5, h - 5, 3):
                f.put(1, y, 'f')
                f.put(w - 2, y + 1, 'f')
        if k == 2:
            f.put(5, 1, 'W')
            f.put(w - 5, h - 3, 'n')
        if k == 3:
            f.put(w - 7, 1, 'W')
            f.put(4, h - 4, 'n')
        out.append(f)
    return out


def frost_shatter():
    shard_angles = [0.2, 1.1, 1.9, 2.8, 3.6, 4.5, 5.4]
    out = []
    for k in range(6):
        f = Frame(26, 26)
        rnd = Rand(200 + k)
        if k == 0:
            for th in shard_angles:
                f.line(f.cx, f.cy, *f.polar(4, th), 'n')
            f.disc(f.cx, f.cy, 1, 'W')
        else:
            r = [0, 4, 7, 9.5, 11, 12][k]
            for i, th in enumerate(shard_angles):
                x, y = f.polar(r + (i % 2), th + 0.08 * k)
                if k <= 2:
                    f.put(x, y, 'n')
                    f.put(x + 1, y, 'q')
                    f.put(x, y + 1, 'f')
                    f.put(x + 1, y + 1, 'F')
                elif k <= 4:
                    f.put(x, y, 'q' if k == 3 else 'f')
                    f.put(x + (i % 2), y + 1 - (i % 2), 'F')
                else:
                    f.put(x, y, 'F' if i % 2 else 'e')
            if k == 1:
                f.ring(f.cx, f.cy, 3, 'q', gaps=5)
                f.put(f.cx, f.cy, 'n')
            if k == 2:
                f.ring(f.cx, f.cy, 5, 'f', gaps=6, phase=0.5)
            if k in (2, 3):
                sparks(f, rnd, 4, 2, r - 1, 'n' if k == 2 else 'f')
        out.append(f)
    return out


# --------------------------------------------------------------- charge cannon
def charge_orb():
    """Muzzle glow while Select is held. Frames 1-4 build; 5-6 loop at full."""
    out = []
    for k in range(6):
        f = Frame(16, 16)
        rnd = Rand(300 + k)
        if k == 0:
            f.put(f.cx, f.cy, 'y')
            for i in range(3):
                f.put(*f.polar(5, i * 2.1 + 0.4), 'o')
        elif k == 1:
            f.disc(f.cx - 0.5, f.cy - 0.5, 1, 'y')
            for i in range(4):
                th = i * 1.57 + 0.8
                f.line(*f.polar(6, th), *f.polar(4.5, th), 'o')
        elif k == 2:
            f.disc(f.cx, f.cy, 2, 'o')
            f.disc(f.cx, f.cy, 1, 'y')
            f.put(f.cx, f.cy, 'W')
            f.ring(f.cx, f.cy, 4.5, 'O', gaps=4, phase=0.3)
        else:
            r = 3 if k in (3, 5) else 3.6
            f.disc(f.cx, f.cy, r + 0.8, 'R')
            f.disc(f.cx, f.cy, r, 'o')
            f.disc(f.cx, f.cy, r - 1.2, 'y')
            f.disc(f.cx - 0.6, f.cy - 0.6, 0.8, 'W')
            sparks(f, rnd, 4, r + 2.5, r + 3.5, 'o' if k % 2 else 'Y', phase=k)
        out.append(f)
    return out


def charge_release(d):
    a, out = angle_of(d), []
    for k in range(3):
        f = Frame(18, 18)
        if k == 0:
            f.disc(f.cx, f.cy, 2.5, 'Y')
            fline(f, a, 0, 7, 'W')
            fline(f, a, 1, 5, 'Y', 2)
            fline(f, a, 1, 5, 'Y', -2)
            f.disc(f.cx, f.cy, 1, 'W')
        elif k == 1:
            f.ring(f.cx, f.cy, 4, 'o')
            fline(f, a, 3, 8, 'y')
            fline(f, a, 2, 6, 'O', 3)
            fline(f, a, 2, 6, 'O', -3)
        else:
            f.ring(f.cx, f.cy, 6, 'R', gaps=6)
            fline(f, a, 6, 8, 'O')
        out.append(f)
    return out


def charge_bolt(d, full):
    a, out = angle_of(d), []
    size = 22 if full else 14
    r, tail = (3, 9) if full else (1.6, 5)
    for k in range(4 if full else 2):
        f = Frame(size, size)
        for t in range(1, tail + 1):
            ch = 'O' if t < tail * 0.4 else 'R'
            width = r * (1 - t / (tail + 1))
            f.put(*fwd(f, a, -t), 'o' if t < 2 else ch)
            if width >= 0.8:
                f.put(*fwd(f, a, -t, width), ch)
                f.put(*fwd(f, a, -t, -width), ch)
        if k % 2:
            f.put(*fwd(f, a, -tail - 1, 1), 'R')
        f.disc(f.cx, f.cy, r + 0.6, 'o')
        f.disc(f.cx, f.cy, r - 0.6, 'y')
        f.put(*fwd(f, a, max(0.0, r - 2)), 'W')
        if full:
            rnd = Rand(400 + k + DIRS.index(d))
            sparks(f, rnd, 3, r + 2, r + 3.5, 'Y' if k % 2 else 'o', phase=k * 0.9)
        out.append(f)
    return out


def charge_impact():
    out = []
    for k in range(6):
        f = Frame(32, 32)
        rnd = Rand(500 + k)
        if k == 0:
            f.disc(f.cx, f.cy, 4, 'Y')
            f.disc(f.cx, f.cy, 2, 'W')
            f.ring(f.cx, f.cy, 6, 'y', gaps=8)
        elif k == 1:
            f.ring(f.cx, f.cy, 8, 'o')
            f.ring(f.cx, f.cy, 7, 'y')
            f.disc(f.cx, f.cy, 3, 'Y')
            f.disc(f.cx, f.cy, 1.5, 'W')
            for i in range(8):
                th = i * math.pi / 4
                f.line(*f.polar(4, th), *f.polar(6, th), 'Y')
        elif k == 2:
            f.ring(f.cx, f.cy, 11, 'O', gaps=10, phase=0.2)
            f.ring(f.cx, f.cy, 10, 'o')
            f.disc(f.cx, f.cy, 2.5, 'o')
            f.put(f.cx, f.cy, 'y')
            sparks(f, rnd, 8, 5, 9, 'y', length=2)
        elif k == 3:
            f.ring(f.cx, f.cy, 13, 'R', gaps=9, phase=0.5)
            f.ring(f.cx, f.cy, 12, 'O', gaps=7)
            sparks(f, rnd, 8, 7, 12, 'o', length=2)
        elif k == 4:
            f.ring(f.cx, f.cy, 14, 'R', gaps=12, phase=0.1)
            sparks(f, rnd, 7, 10, 14, 'O')
        else:
            sparks(f, rnd, 6, 12, 15, 'R')
        out.append(f)
    return out


# ----------------------------------------------------------------- gravity orb
def orb_launch(d):
    a, out = angle_of(d), []
    for k in range(3):
        f = Frame(14, 14)
        x, y = fwd(f, a, 1)
        if k == 0:
            f.ring(x, y, 2, 'u')
            f.put(x, y, 'W')
        elif k == 1:
            f.ring(x, y, 3.5, 'X', gaps=4)
            fline(f, a, 2, 4, 'u')
        else:
            f.ring(x, y, 5, 'x', gaps=5, phase=0.4)
        out.append(f)
    return out


def orb_shot():
    out = []
    for k in range(4):
        f = Frame(12, 12)
        f.disc(f.cx, f.cy, 3, 'v')
        f.disc(f.cx, f.cy, 2.2, 'V')
        f.put(f.cx - 1, f.cy - 1, 'u')
        f.put(f.cx, f.cy, 'b')
        f.outline('z')
        th = k * math.pi / 2
        f.put(*f.polar(5, th), 'u')
        f.put(*f.polar(5, th + math.pi), 'X')
        out.append(f)
    return out


def gravity_well():
    """Looping vortex where the orb settles. The dotted ring marks a 17 px pull radius."""
    frames, out = 6, []
    for k in range(frames):
        f = Frame(40, 40)
        f.ring(f.cx, f.cy, 17, 'b', gaps=12, phase=k * 0.35)
        for arm in range(3):
            base = arm * 2 * math.pi / 3 + k * (2 * math.pi / 3) / frames
            for i in range(40):
                r = 15 - i * 0.3
                if r < 3.5:
                    break
                if r > 12 and i % 2:
                    continue
                ch = 'x' if r > 11 else 'X' if r > 6.5 else 'u'
                f.put(*f.polar(r, base + (15 - r) * 0.22), ch)
        f.disc(f.cx, f.cy, 3.2, 'b')
        f.disc(f.cx, f.cy, 2.2, 'z')
        f.put(f.cx + (1 if k % 2 else -1), f.cy - 1, 'V')
        out.append(f)
    return out


def well_collapse():
    out = []
    for k in range(5):
        f = Frame(32, 32)
        rnd = Rand(600 + k)
        if k == 0:
            f.disc(f.cx, f.cy, 2.5, 'X')
            f.disc(f.cx, f.cy, 1.5, 'u')
            sparks(f, rnd, 6, 5, 8, 'X', length=3)
        elif k == 1:
            f.ring(f.cx, f.cy, 4, 'u')
            f.ring(f.cx, f.cy, 5, 'X', gaps=6)
            f.disc(f.cx, f.cy, 1.2, 'W')
        elif k == 2:
            f.ring(f.cx, f.cy, 9, 'X')
            f.ring(f.cx, f.cy, 8, 'u', gaps=8)
            sparks(f, rnd, 6, 3, 7, 'u')
        elif k == 3:
            f.ring(f.cx, f.cy, 13, 'x', gaps=10, phase=0.3)
            sparks(f, rnd, 6, 9, 12, 'X')
        else:
            sparks(f, rnd, 6, 12, 15, 'b')
        out.append(f)
    return out


# ---------------------------------------------------------------- shock hammer
def hammer_swing(d):
    """Smear centred on the hero pivot. Sweeps from the facing's left to its right."""
    a, out = angle_of(d), []
    spans = [(-1.5, -0.9), (-1.5, 0.1), (-1.1, 1.2), (0.3, 1.5)]
    for k, (t0, t1) in enumerate(spans):
        f = Frame(36, 36)
        steps = 40
        for i in range(steps + 1):
            th = t0 + (t1 - t0) * i / steps
            lead = i / steps
            for r in (10, 11, 12, 13, 14):
                if (k == 3 and r in (10, 14)) or (k == 0 and r == 14):
                    continue
                if k == 3:
                    if i % 3 == 0:
                        continue
                    ch = 'C' if r == 13 else 'e'
                elif lead > 0.85:
                    ch = 'W' if r in (12, 13) else 'i'
                elif lead > 0.5:
                    ch = 'i' if r >= 12 else 'c'
                else:
                    ch = 'c' if r >= 12 else 'C'
                f.put(*f.polar(r, th, a), ch)
        if k == 2:
            for th in (t1 - 0.05, t1 + 0.12):
                f.put(*f.polar(15.5, th, a), 'i')
        out.append(f)
    return out


def hammer_shock():
    out = []
    for k in range(5):
        f = Frame(26, 26)
        rnd = Rand(700 + k)
        if k == 0:
            f.disc(f.cx, f.cy, 2.5, 'i')
            f.disc(f.cx, f.cy, 1.2, 'W')
            for i in range(4):
                th = i * math.pi / 2 + 0.4
                jagged(f, rnd, *f.polar(2, th), *f.polar(6, th), 'n', amp=1, steps=2)
        elif k == 1:
            f.ring(f.cx, f.cy, 5, 'i')
            f.ring(f.cx, f.cy, 6, 'c', gaps=8)
            for i in range(5):
                th = i * 2 * math.pi / 5 + 0.1
                jagged(f, rnd, *f.polar(6, th), *f.polar(10, th), 'i', amp=1.2, steps=2, glow='c')
            f.put(f.cx, f.cy, 'n')
        elif k == 2:
            f.ring(f.cx, f.cy, 8, 'c', gaps=6, phase=0.4)
            sparks(f, rnd, 6, 5, 10, 'i')
        elif k == 3:
            f.ring(f.cx, f.cy, 10, 'C', gaps=8, phase=0.2)
            sparks(f, rnd, 5, 8, 11, 'c')
        else:
            sparks(f, rnd, 5, 9, 12, 'C')
        out.append(f)
    return out


def knock_skid(d):
    """Dust behind a knocked-back target. Facing = knockback direction."""
    a, out = angle_of(d), []
    for k in range(3):
        f = Frame(18, 18)
        ch = ['w', 'A', 'a'][k]
        for t, s, big in ((-2, 2, 1), (-4, -2, 1), (-6, 1, 0), (-1, -3, 0)):
            x, y = fwd(f, a, t - k * 2, s)
            f.put(x, y, ch)
            if big and k < 2:
                f.put(x + 1, y, ch)
                f.put(x, y + 1, 'A' if k == 0 else 'a')
                f.put(x + 1, y + 1, 'a')
        fline(f, a, -1 - k, -5 - k * 2, 'a' if k == 0 else 's')
        out.append(f)
    return out


# (weapon, sheet name, use, draw, kind, frames per second, notes)
#   kind 'dir': one row per facing N..NW.  'one': single row.  'rows': draw returns rows.
EFFECTS = [
    ('rail-rifle', 'rail-muzzle', 'fire', rail_muzzle, 'dir', 30, 'Muzzle flare at the rail tip.'),
    ('rail-rifle', 'rail-beam', 'travel', rail_beam, 'dir', 24,
     'Tile repeated every tileStep along the beam, edge to edge. Frames fade the beam.'),
    ('rail-rifle', 'rail-pierce', 'impact', rail_pierce, 'dir', 24,
     'Play on every target the slug passes through. The exit spray follows the shot.'),
    ('bankshot', 'bank-muzzle', 'fire', bank_muzzle, 'dir', 30, 'Pistol flash.'),
    ('bankshot', 'bank-round', 'travel', bank_round, 'dir', 20,
     'Round in flight. Switch rows to the new heading after the bounce.'),
    ('bankshot', 'bank-ricochet', 'bounce', bank_ricochet, 'one', 24,
     'Spark at the bounce point on the reflector face.'),
    ('bankshot', 'reflector', 'prop', reflector, 'rows', 12,
     'Range prop. Row 1 is the "/" plate, row 2 the "\\" plate. Frame 1 idle, 2 struck, 3 cooling.'),
    ('bankshot', 'bank-impact', 'impact', bank_impact, 'one', 24, 'Hit spark on the target.'),
    ('boomerang-disc', 'disc-throw', 'fire', disc_throw, 'dir', 24, 'Throw swoosh in front of the hero.'),
    ('boomerang-disc', 'disc-spin', 'travel', disc_spin, 'one', 20, 'Disc in flight, out and back.'),
    ('boomerang-disc', 'disc-hit', 'impact', disc_hit, 'one', 24,
     'Slash spark. Plays on the outward hit and again on the return hit.'),
    ('boomerang-disc', 'disc-catch', 'return', disc_catch, 'one', 20, 'Catch glint at the hero.'),
    ('arc-projector', 'arc-muzzle', 'fire', arc_muzzle, 'dir', 30, 'Forked crackle at the emitter.'),
    ('arc-projector', 'arc-bolt', 'travel', arc_bolt, 'dir', 20,
     'Jagged tile repeated every tileStep along the bolt and each chain link. Cycle frames.'),
    ('arc-projector', 'arc-zap', 'impact', arc_zap, 'one', 24, 'Zap on the first and each chained target.'),
    ('cryo-sprayer', 'cryo-muzzle', 'fire', cryo_muzzle, 'dir', 30, 'Frost burst at the nozzle.'),
    ('cryo-sprayer', 'cryo-puff', 'travel', cryo_puffs, 'rows', 54,
     'Spray puffs, like the flame tongues. Row = age (fresh, drifting, fading), column = flicker.'),
    ('cryo-sprayer', 'frost-coat', 'status', frost_coat, 'one', 8,
     'Overlay on a frosted target. Frames 1-2 coat it, then loop frames 3-4.'),
    ('cryo-sprayer', 'frost-shatter', 'impact', frost_shatter, 'one', 24,
     'A follow-up hit on a frosted target shatters the coat.'),
    ('charge-cannon', 'charge-orb', 'charge', charge_orb, 'one', 12,
     'At the muzzle while Select is held. Frames 1-4 build, then loop frames 5-6 at full charge.'),
    ('charge-cannon', 'charge-release', 'fire', charge_release, 'dir', 30, 'Release flash.'),
    ('charge-cannon', 'charge-bolt-low', 'travel', lambda d: charge_bolt(d, False), 'dir', 20,
     'Bolt for a partial charge.'),
    ('charge-cannon', 'charge-bolt-full', 'travel', lambda d: charge_bolt(d, True), 'dir', 20,
     'Bolt for a full charge.'),
    ('charge-cannon', 'charge-impact', 'impact', charge_impact, 'one', 24, 'Shockwave on hit.'),
    ('gravity-orb', 'orb-launch', 'fire', orb_launch, 'dir', 24, 'Launch ring.'),
    ('gravity-orb', 'orb-shot', 'travel', orb_shot, 'one', 16, 'Orb in flight.'),
    ('gravity-orb', 'gravity-well', 'field', gravity_well, 'one', 12,
     'Looping vortex while the orb pulls. The dotted ring marks a 17 px pull radius.'),
    ('gravity-orb', 'well-collapse', 'impact', well_collapse, 'one', 20,
     'The well collapses and releases the clustered targets.'),
    ('shock-hammer', 'hammer-swing', 'fire', hammer_swing, 'dir', 30,
     'Sweep smear centred on the hero pivot, reaching 10-14 px.'),
    ('shock-hammer', 'hammer-shock', 'impact', hammer_shock, 'one', 24, 'Shock on each target in the arc.'),
    ('shock-hammer', 'knock-skid', 'knockback', knock_skid, 'dir', 18,
     'Dust behind a knocked-back target. Facing = knockback direction.'),
]

LOOPING = {'travel', 'field', 'status', 'charge'}
LOOP_FROM = {'charge-orb': 5, 'frost-coat': 3}
TILE_STEP = {'N': [0, -16], 'NE': [16, -16], 'E': [16, 0], 'SE': [16, 16],
             'S': [0, 16], 'SW': [-16, 16], 'W': [-16, 0], 'NW': [-16, -16]}


def effect_rows(draw, kind):
    if kind == 'dir':
        return [draw(d) for d in DIRS]
    if kind == 'one':
        return [draw()]
    return draw()


def effect_sheets():
    """Write every sheet and return {name: rows of PIL frames} for previews."""
    FX.mkdir(parents=True, exist_ok=True)
    layout = {
        'note': 'Native pixels. Pivot is the frame centre. Directional sheets have one row per '
                'facing, top to bottom: ' + ', '.join(DIRS) + '. Frames run left to right.',
        'effects': [],
    }
    rendered = {}
    for weapon, name, use, draw, kind, fps, notes in EFFECTS:
        rows = effect_rows(draw, kind)
        w, h = rows[0][0].w, rows[0][0].h
        cols = max(len(r) for r in rows)
        sheet = Image.new('RGBA', (w * cols, h * len(rows)))
        images = []
        for y, row in enumerate(rows):
            images.append([])
            for x, frame in enumerate(row):
                im = frame.image()
                images[-1].append(im)
                sheet.paste(im, (x * w, y * h))
        (FX / weapon).mkdir(exist_ok=True)
        sheet.save(FX / weapon / f'{name}.png')
        entry = {
            'weapon': weapon, 'name': name, 'use': use, 'image': f'{weapon}/{name}.png',
            'frameWidth': w, 'frameHeight': h, 'frames': cols, 'rows': len(rows),
            'framesPerSecond': fps, 'pivot': {'x': w // 2, 'y': h // 2},
            'directional': kind == 'dir', 'notes': notes,
        }
        entry['playback'] = 'loop' if use in LOOPING and name != 'rail-beam' else 'once'
        if name in LOOP_FROM:
            entry['loopFromFrame'] = LOOP_FROM[name]
        if name in ('rail-beam', 'arc-bolt'):
            entry['tileStep'] = TILE_STEP
        layout['effects'].append(entry)
        rendered[name] = (entry, images)
    (FX / 'effects-layout.json').write_text(json.dumps(layout, indent=2) + '\n')
    return rendered
