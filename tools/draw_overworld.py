"""Draw Dustpaw's original overworld terrain and landmarks, then pack them for the badge."""

from random import Random

from PIL import Image, ImageDraw

from build_assets import OUT, pack


WATER = "#284951"
INK = "#252931"
BANK = "#aa8052"
CLIFF = "#775343"
GRASS = "#7d8b54"
PINE = "#536852"
MOSS = "#677d54"
GOLD = "#a89958"
ASH = "#a16e51"
STONE = "#8c8580"
FROST = "#7d9690"

SOUTH = [(-3, 49), (8, 44), (22, 42), (35, 44), (48, 49), (63, 48),
         (73, 44), (88, 46), (100, 50), (118, 52), (129, 45), (144, 43),
         (153, 49), (161, 46), (161, 67), (148, 70), (141, 73), (123, 73),
         (114, 76), (92, 75), (82, 77), (66, 75), (53, 77), (41, 74),
         (24, 73), (17, 75), (4, 71), (-3, 72)]
NORTH = [(-2, 6), (10, 5), (19, 8), (32, 7), (45, 3), (59, 5), (70, 0),
         (92, 0), (105, 4), (116, 2), (130, 7), (143, 6), (162, 11),
         (162, 29), (147, 31), (139, 36), (125, 38), (117, 44), (101, 43),
         (91, 41), (79, 45), (67, 41), (54, 44), (42, 37), (32, 33),
         (17, 36), (7, 32), (-2, 36)]


def terrain(extension=False):
    rng = Random(77 if extension else 24)
    image = Image.new("RGBA", (160, 78), WATER)
    d = ImageDraw.Draw(image)
    rgb = lambda color: tuple(bytes.fromhex(color[1:])) + (255,)

    def island(points, color):
        d.polygon([(x, y + 3) for x, y in points], INK)
        d.polygon([(x, y + 2) for x, y in points], CLIFF)
        d.polygon(points, BANK)
        # A ridge of beach separates the land from the dark cliff face.
        d.polygon([(80 + int((x - 80) * .97), y - 1) for x, y in points], color)

    for _ in range(260):
        x, y = rng.randrange(158), rng.randrange(78)
        d.line((x, y, x + rng.randrange(1, 4), y), rng.choice(("#315b5e", "#35696b", "#3e7170")))
    island(SOUTH, GRASS)
    island(NORTH, MOSS)

    def biome(points, color, ground):
        stencil = Image.new("1", image.size)
        ImageDraw.Draw(stencil).polygon(points, 1)
        for y in range(image.height):
            for x in range(image.width):
                if stencil.getpixel((x, y)) and image.getpixel((x, y)) == rgb(ground):
                    image.putpixel((x, y), rgb(color))

    biome([(2, 51), (30, 45), (56, 51), (88, 47), (96, 58), (79, 74), (19, 75), (3, 67)],
          GOLD if not extension else MOSS, GRASS)
    biome([(96, 55), (116, 50), (143, 44), (158, 52), (158, 67), (131, 73), (104, 75)],
          "#9c8157" if not extension else GOLD, GRASS)
    biome([(26, 4), (56, 1), (84, 0), (106, 5), (97, 14), (78, 23), (52, 24), (35, 19)],
          STONE, MOSS)
    biome([(41, 20), (62, 21), (69, 28), (64, 40), (54, 43), (38, 35), (35, 25)],
          FROST if not extension else STONE, MOSS)
    biome([(73, 25), (89, 20), (105, 29), (99, 38), (80, 43), (65, 39)],
          ASH if not extension else GOLD, MOSS)
    biome([(110, 2), (147, 6), (159, 12), (159, 28), (143, 34), (125, 36), (115, 26), (107, 15)],
          PINE, MOSS)

    highlights = {
        GRASS: ("#6c794b", "#909a61"), PINE: ("#435744", "#677c58"),
        MOSS: ("#576f4c", "#82915c"), GOLD: ("#948447", "#b6a45f"),
        ASH: ("#8d5d49", "#b37f59"), STONE: ("#766e6b", "#a29a89"),
        FROST: ("#687f79", "#a1ad97"), "#9c8157": ("#8a6d4a", "#b19863"),
    }
    highlights = {rgb(color): shades for color, shades in highlights.items()}
    for _ in range(760):
        x, y = rng.randrange(158), rng.randrange(78)
        shades = highlights.get(image.getpixel((x, y)))
        if shades:
            d.point((x, y), rng.choice(shades))
            if rng.randrange(3) == 0 and image.getpixel((x + 1, y)) in highlights:
                d.point((x + 1, y), shades[1])

    def tree(x, y, bright=False):
        d.line((x - 1, y + 1, x + 3, y + 1), "#526145")
        d.rectangle((x, y - 1, x, y + 1), "#514335")
        d.polygon([(x, y - 5), (x - 2, y - 3), (x - 3, y), (x + 2, y), (x + 2, y - 3)], "#344d3f")
        d.line((x, y - 4, x - 2, y - 1), "#849953" if bright else "#667f50")
        d.point((x, y - 2), "#a1aa62" if bright else "#7b8e55")

    woods = [(4, 25), (11, 31), (16, 32), (8, 17), (13, 14), (21, 19), (15, 23),
             (5, 60), (10, 54), (32, 54), (30, 68), (55, 71), (91, 70), (101, 70),
             (119, 70), (130, 68), (146, 65), (153, 62), (151, 56), (155, 52),
             (103, 18), (109, 15), (114, 19), (129, 28), (136, 31), (144, 25),
             (149, 29), (155, 25), (118, 11), (123, 16), (128, 12), (133, 19), (141, 16)]
    for i, (x, y) in enumerate(sorted(woods, key=lambda point: point[1])):
        tree(x, y, i % 3 == 0)

    for x, y, h in [(44, 13, 7), (51, 13, 5), (80, 14, 9), (86, 14, 6),
                    (93, 17, 8), (98, 18, 5), (94, 73, 4), (148, 69, 4)]:
        d.polygon([(x - h, y), (x - 1, y - h), (x + 2, y - h + 1), (x + h, y)], "#625d5c")
        d.polygon([(x - h + 1, y - 1), (x - 1, y - h + 1), (x + 1, y - h + 2), (x, y - 2)], "#a99d89")
        if h > 5:
            d.line((x - 2, y - h + 2, x + 1, y - h + 2), "#d0c3a5")

    for x in range(61, 89, 4):
        d.line((x, 50, x + 2, 54), "#897647")
        d.line((x + 1, 50, x + 3, 53), "#c4ab65")
    for x in range(72, 96, 5):
        d.point((x, 43 - x % 3), "#cca26a")
    for x, y in [(3, 2), (11, 40), (29, 39), (62, 46), (100, 47), (145, 39), (152, 75)]:
        d.line((x, y, x + 3, y), "#4b817c")
        d.point((x + 1, y - 1), "#609189")
    return image


def landmark(kind):
    image = Image.new("RGBA", (26, 17))
    d = ImageDraw.Draw(image)

    def box(x, y, w, h, color):
        d.rectangle((x, y, x + w - 1, y + h - 1), color)

    def house(x, eave, w, wall, roof):
        box(x - 1, eave, w + 3, 7, INK)
        box(x, eave + 1, w + 1, 5, wall)
        d.polygon([(x - 2, eave), (x + w // 2, eave - 6),
                   (x + w + 2, eave), (x + w + 2, eave + 1), (x - 2, eave + 1)], INK)
        d.polygon([(x, eave), (x + w // 2, eave - 5), (x + w, eave)], roof)
        d.line((x + 1, eave, x + w // 2, eave - 4), "#e4b383")
        box(x + w // 2 - 1, eave + 3, 3, 4, "#594138")

    if kind == "backyard":
        house(3, 7, 9, "#ceab78", "#a95b44")
        box(12, 10, 10, 4, "#705142")
        box(13, 10, 8, 2, "#d0b080")
        for x in (13, 17, 21):
            box(x, 9, 1, 5, "#eed39f")
    elif kind == "orchard":
        for x, y in [(7, 3), (15, 3), (11, 8), (19, 8)]:
            box(x, y + 4, 1, 4, "#513f30")
            box(x - 3, y + 1, 7, 4, "#3c5740")
            box(x - 2, y, 5, 4, "#72984e")
            box(x + 1, y + 1, 1, 1, "#e6a268")
            box(x - 2, y + 3, 1, 1, "#d89359")
    elif kind == "farmhouse":
        house(4, 7, 16, "#dfbd85", "#b3694d")
        box(16, 2, 3, 4, "#62524c")
        box(16, 2, 2, 1, "#aa8a71")
        box(6, 10, 3, 2, "#657c76")
        box(16, 10, 3, 2, "#657c76")
    elif kind == "crate-yard":
        for x, y, w in [(5, 7, 7), (15, 4, 7), (12, 9, 7), (18, 10, 6)]:
            box(x, y, w, 6, INK)
            box(x + 1, y + 1, w - 2, 4, "#a77b47")
            box(x + 1, y + 1, w - 2, 1, "#e6b971")
            d.line((x + 1, y + 4, x + w - 2, y + 1), "#d7a563")
    elif kind == "riverside":
        box(3, 10, 20, 5, "#375f62")
        box(5, 11, 15, 2, "#75a39a")
        house(8, 6, 9, "#c2a778", "#77938b")
        for x in (7, 18):
            box(x, 11, 2, 4, "#6c5041")
    elif kind == "hedge-maze":
        for color, width, shift in [("#374e3c", 4, 0), ("#809d51", 2, -1)]:
            d.line([(x, y + shift) for x, y in [(4, 12), (4, 4), (22, 4), (22, 12), (12, 12),
                                                (12, 8), (17, 8)]], color, width)
        box(7, 8, 2, 5, "#638246")
    elif kind == "burning-barn":
        house(5, 8, 15, "#a86c4e", "#a4483d")
        for x, y in [(6, 5), (17, 4), (20, 8)]:
            d.polygon([(x - 2, y + 2), (x - 1, y - 2), (x, y), (x + 2, y - 3),
                       (x + 3, y + 2)], "#e56d43")
            box(x, y + 1, 2, 2, "#f5cc70")
        box(15, 0, 3, 1, "#776b69")
    elif kind == "cold-storage":
        box(3, 3, 21, 12, INK)
        box(4, 4, 19, 10, "#729291")
        box(4, 4, 19, 3, "#bad1c7")
        box(6, 5, 14, 1, "#e2dfc0")
        box(9, 9, 9, 5, "#485d65")
        for x in (10, 13, 16):
            box(x, 10, 1, 4, "#8da7a3")
    elif kind in ("outpost", "fortress"):
        fortress = kind == "fortress"
        box(2, 6, 23, 9, INK)
        box(3, 7, 21, 7, "#a79786" if fortress else "#7f8f81")
        box(5, 8, 17, 2, "#c2b5a1" if fortress else "#a4ae8a")
        for x in (4, 11, 19):
            box(x, 3 if fortress else 5, 4, 4, INK)
            box(x + 1, 4 if fortress else 6, 2, 3, "#c4b29b" if fortress else "#9dab8f")
        box(11, 11, 5, 4, "#4c4140")
        box(13, 0, 1, 5, INK)
        box(14, 0, 5, 2, "#cf6648" if fortress else "#e1b56a")
    else:
        house(7, 7, 12, "#bda477", "#718279")
    return image


def main():
    terrain_lines = []
    for name, extension in [("main", False), ("frontier", True)]:
        image = terrain(extension)
        palette = {}
        # Each half has fewer than 92 native pixels per axis for the packed format.
        left = pack(image.crop((0, 0, 80, 78)), palette, skip=image.getpixel((0, 77)))
        right = pack(image.crop((80, 0, 160, 78)), palette, skip=image.getpixel((0, 77)))
        colors = ",".join("0x%02x%02x%02x" % color for color in palette)
        terrain_lines += [f"  {name}={{left={left},", f"    right={right},", f"    colors={{{colors}}}}},"]

    palette = {}
    kinds = ["backyard", "orchard", "farmhouse", "crate-yard", "riverside", "hedge-maze",
             "burning-barn", "cold-storage", "outpost", "fortress", "camp"]
    landmarks = [f'    ["{kind}"]={pack(landmark(kind), palette)},' for kind in kinds]
    colors = ",".join("0x%02x%02x%02x" % color for color in palette)
    lines = ["-- Generated by tools/draw_overworld.py.", "return {", *terrain_lines,
             "  landmarks={", f"    colors={{{colors}}},", *landmarks, "  },", "}"]
    (OUT / "overworld.lua").write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
