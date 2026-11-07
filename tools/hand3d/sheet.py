#!/usr/bin/env python3
"""Лист пропорций для модели кисти из tools/hand3d.

Читает числа прямо из hand_model.gd (единственный источник правды), рисует
таблицу длин, полосовую схему фаланг и проверку правила «проксимальная =
средняя + дистальная», затем склеивает с кадрами рендера.

    python3 tools/hand3d/sheet.py
"""
import json
import os
import re

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools", "hand3d", "hand_model.gd")
OUT = os.environ.get("HAND3D_OUT", "/tmp/opencode/hand3d")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

RAYS = ["I", "II", "III", "IV", "V"]
INK = (18, 18, 20)
SOFT = (95, 95, 100)
RULE = (170, 172, 176)


def numbers():
    text = open(SRC, encoding="utf-8").read()
    mc_block = text.split("const MC_LEN := {")[1].split("}")[0]
    ph_block = text.split("const PH_LEN := {")[1].split("}\n")[0]
    mc = {k: float(v) for k, v in re.findall(r'"(\w+)":\s*([\d.]+)', mc_block)}
    ph = {}
    for key, body in re.findall(r'"(\w+)":\s*\[([^\]]+)\]', ph_block):
        ph[key] = [float(x) for x in body.split(",")]
    return mc, ph


def rows_of(mc, ph):
    rows = []
    for ray in RAYS:
        lens = ph[ray]
        mid = lens[1] if len(lens) == 3 else None
        dist = lens[2] if len(lens) == 3 else lens[1]
        diff = lens[0] - (mid + dist) if mid is not None else None
        rows.append({
            "ray": ray, "mc": mc[ray], "p": lens[0], "m": mid, "d": dist,
            "diff": diff, "total": mc[ray] + sum(lens),
        })
    return rows


def draw_table(img, x, y, width, rows):
    d = ImageDraw.Draw(img)
    f_head = ImageFont.truetype(FONT, 22)
    f_cell = ImageFont.truetype(FONT, 24)
    f_title = ImageFont.truetype(FONT_B, 28)
    f_note = ImageFont.truetype(FONT, 19)

    d.text((x, y), "Длины костей, мм · кисть 189 мм, взрослая мужская",
           font=f_title, fill=INK)
    y += 46

    head = ["луч", "пястная", "проксимальная", "средняя", "дистальная",
            "P − (M+D)", "палец целиком"]
    cells = []
    for r in rows:
        cells.append([
            r["ray"], f'{r["mc"]:.0f}', f'{r["p"]:.0f}',
            "—" if r["m"] is None else f'{r["m"]:.0f}', f'{r["d"]:.0f}',
            "—" if r["diff"] is None else f'{r["diff"]:+.0f}', f'{r["total"]:.0f}',
        ])
    # Width of a column: the widest of its head and its cells, plus padding.
    colw = []
    for i in range(len(head)):
        w = max(d.textlength(head[i], font=f_head),
                *(d.textlength(c[i], font=f_cell) for c in cells))
        colw.append(int(w) + 34)
    total = sum(colw)
    if total > width:
        k = width / total
        colw = [int(w * k) for w in colw]
    cx = [x]
    for w in colw:
        cx.append(cx[-1] + w)

    for i, name in enumerate(head):
        d.text((cx[i], y), name, font=f_head, fill=SOFT)
    y += 32
    d.line([(cx[0], y), (cx[-1], y)], fill=RULE, width=2)
    y += 12
    for c in cells:
        for i, v in enumerate(c):
            d.text((cx[i], y), v, font=f_cell, fill=INK)
        y += 36
    d.line([(cx[0], y), (cx[-1], y)], fill=RULE, width=2)
    y += 16

    notes = [
        "Правило листа-образца: проксимальная фаланга = средняя + дистальная.",
        "Разбиение — от измеренных сумм, отношение M : D = 4 : 3 сохранено.",
        "Пястные: II > III > IV > V. Палец целиком: III > IV > II > V.",
        "Кадры костей и «кожа, тыл» — разогнутая кисть, чтобы длины читались;",
        "«три четверти» — та же кисть в покое (сгиб пальцев 20/34/14°).",
    ]
    for n in notes:
        d.text((x, y), n, font=f_note, fill=SOFT)
        y += 28
    return y


def draw_bars(img, x, y, ph, scale=4.2):
    """Фаланги в масштабе: видно, что P закрывает M и D."""
    d = ImageDraw.Draw(img)
    f_row = ImageFont.truetype(FONT, 22)
    f_num = ImageFont.truetype(FONT, 16)
    f_title = ImageFont.truetype(FONT_B, 22)
    f_note = ImageFont.truetype(FONT, 19)
    colours = [(206, 138, 104), (228, 188, 132), (186, 166, 206)]

    d.text((x, y), "Фаланги в масштабе", font=f_title, fill=INK)
    y += 40
    for ray in RAYS:
        lens = ph[ray]
        d.text((x, y + 4), ray, font=f_row, fill=INK)
        bx = x + 46
        tops = []
        for i, ln in enumerate(lens):
            w = int(ln * scale)
            d.rectangle([bx, y, bx + w - 2, y + 28], fill=colours[min(i, 2)])
            d.text((bx + 5, y + 5), f"{ln:.0f}", font=f_num, fill=(40, 32, 30))
            tops.append((bx, bx + w - 2))
            bx += w
        # Скобки под рядом: проксимальная и (средняя + дистальная) равны.
        by = y + 31
        d.line([(tops[0][0], by), (tops[0][1], by)], fill=INK, width=2)
        if len(tops) == 3:
            d.line([(tops[1][0], by), (tops[2][1], by)], fill=INK, width=2)
        y += 42
    d.text((x, y), "скобки равной длины: проксимальная | средняя + дистальная "
           "(у большого пальца средней нет)", font=f_note, fill=SOFT)
    return y + 32


BG = (217, 221, 224)


def frame(name, box):
    """Crop to the hand before scaling: a fixed 1000x1300 frame leaves a
    narrow profile view as a stamp in the corner of its cell."""
    path = os.path.join(OUT, name + ".png")
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGB")
    px = im.load()
    x0, y0, x1, y1 = im.width, im.height, 0, 0
    for y in range(0, im.height, 2):
        for x in range(0, im.width, 2):
            r, g, b = px[x, y]
            if abs(r - BG[0]) + abs(g - BG[1]) + abs(b - BG[2]) > 18:
                x0 = min(x0, x)
                x1 = max(x1, x)
                y0 = min(y0, y)
                y1 = max(y1, y)
    if x1 <= x0 or y1 <= y0:
        return None
    pad = 14
    im = im.crop((max(0, x0 - pad), max(0, y0 - pad),
                  min(im.width, x1 + pad), min(im.height, y1 + pad)))
    k = min(box[0] / im.width, box[1] / im.height)
    return im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)


def main():
    mc, ph = numbers()
    rows = rows_of(mc, ph)
    W = 1560

    # Draw on a tall canvas, crop to what was actually used: a fixed height
    # cut the last row off the bars.
    body = Image.new("RGB", (W, 900), (252, 251, 249))
    y = draw_table(body, 44, 34, W - 88, rows)
    y = draw_bars(body, 44, y + 26, ph)
    body = body.crop((0, 0, W, y + 24))

    labels = [("bones-dorsal", "кости, тыл"), ("bones-palmar", "кости, ладонь"),
              ("bones-side", "кости, профиль"), ("skin-straight-open-dorsal", "кожа, тыл"),
              ("skin-3q", "кожа, три четверти")]
    cw = W // len(labels)
    fh = 470
    strip = Image.new("RGB", (W, fh + 38), (255, 255, 255))
    d = ImageDraw.Draw(strip)
    f = ImageFont.truetype(FONT, 22)
    for i, (name, lab) in enumerate(labels):
        im = frame(name, (cw - 24, fh))
        if im is None:
            continue
        strip.paste(im, (i * cw + (cw - im.width) // 2, 34 + (fh - im.height) // 2))
        d.text((i * cw + 12, 6), lab, fill=INK, font=f)

    out = Image.new("RGB", (W, body.height + strip.height + 16), (255, 255, 255))
    out.paste(body, (0, 0))
    out.paste(strip, (0, body.height + 16))
    path = os.path.join(OUT, "sheet-props.png")
    out.save(path)
    print(path, out.size)


def thumb_sheet():
    """The thumb alone: its three joints along its one coordinate f.

    Two rows of the same three states — the skin and the bones, both from
    the radial side, where the palmar flexion of MCP and IP is seen in
    profile instead of being foreshortened.

    The labels come from thumb_states.json, which main.gd writes from
    HandModel.thumb_at() while baking: the sheet must not carry its own copy
    of the angle arithmetic, or the numbers drift from the mesh. The point it
    shows is the third line — the share of its own range each joint has
    spent: it is the same for CMC, MCP and IP in every state, which is what
    "the joints bend together" means in numbers.
    """
    states = ["rest", "open", "press"]
    W = 1900
    cw = W // 3
    fh = 620
    f = ImageFont.truetype(FONT, 24)
    # One camera for all six frames: the radial side, where the palmar
    # flexion of MCP and IP is seen in profile (from the dorsum a pressing
    # thumb is foreshortened into a stump, and the sheet has to show that the
    # three joints bend together).
    rows = [("thumb-skin-%s", (120, 380, 900, 1180)),
            ("thumb-bones-%s", (120, 380, 900, 1180))]
    meta = {}
    mpath = os.path.join(OUT, "thumb_states.json")
    if os.path.exists(mpath):
        meta = json.load(open(mpath, encoding="utf-8"))
    names = {"rest": "покой · минимум энергии", "open": "прямой, в плоскости",
             "press": "жмёт"}
    out = Image.new("RGB", (W, 2 * (fh + 78) + 12), (255, 255, 255))
    d = ImageDraw.Draw(out)
    for r, (pat, box) in enumerate(rows):
        y0 = r * (fh + 78)
        for i, key in enumerate(states):
            name = pat % key
            path = os.path.join(OUT, name + ".png")
            if not os.path.exists(path):
                continue
            im = Image.open(path).convert("RGB").crop(box)
            im.thumbnail((cw - 18, fh), Image.LANCZOS)
            out.paste(im, (i * cw + (cw - im.width) // 2, y0 + 78 + (fh - im.height) // 2))
            if r == 0:
                m = meta.get(key, {})
                a = m.get("angles", {})
                e = m.get("effort", {})
                d.text((i * cw + 12, y0 + 4), names.get(key, key), fill=INK, font=f)
                if a:
                    d.text((i * cw + 12, y0 + 32),
                           "f %+.2f   ·   CMC %.0f°/%.0f°   ·   MCP %.0f°   ·   IP %.0f°" % (
                               m["f"], a["cmc_flex"], a["cmc_abd"], a["mcp"], a["ip"]),
                           fill=SOFT, font=f)
                    d.text((i * cw + 12, y0 + 58),
                           "ход суставов: CMC %.0f%%   MCP %.0f%%   IP %.0f%%" % (
                               e["cmc"], e["mcp"], e["ip"]),
                           fill=(30, 90, 160), font=f)
            else:
                d.text((i * cw + 12, y0 + 8), "кости, с лучевой стороны", fill=SOFT, font=f)
    path = os.path.join(OUT, "sheet-thumb.png")
    out.save(path)
    print(path, out.size)


def skin_sheet():
    """Five views of the resting hand, one strip."""
    W = 2600
    labels = [("skin-dorsal", "тыл"), ("skin-palmar", "ладонь"),
              ("skin-radial", "с лучевой стороны"), ("skin-ulnar", "с локтевой стороны"),
              ("skin-3q", "три четверти")]
    cw = W // len(labels)
    fh = 700
    sheet = Image.new("RGB", (W, fh + 44), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(FONT, 26)
    for i, (name, lab) in enumerate(labels):
        im = frame(name, (cw - 18, fh))
        if im is None:
            continue
        sheet.paste(im, (i * cw + (cw - im.width) // 2, 44 + (fh - im.height) // 2))
        d.text((i * cw + 12, 10), lab, fill=INK, font=f)
    path = os.path.join(OUT, "sheet-skin.png")
    sheet.save(path)
    print(path, sheet.size)


if __name__ == "__main__":
    thumb_sheet()
    main()
    skin_sheet()
