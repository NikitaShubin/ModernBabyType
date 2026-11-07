#!/usr/bin/env python3
"""Склейка шардов bake_outline.gd в game/scripts/hands_shape.gd.

Шарды пишут строки "side<TAB>label<TAB>r,r,r,..." в /tmp/opencode/shape-part-<i>.txt.
Скрипт проверяет, что все позы на месте и у всех ровно N радиусов, и пишет
готовый GDScript. Запуск: .venv/bin/python tools/hand3d/merge_shape.py
"""
import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PARTS = "/tmp/opencode/shape-part-*.txt"
OUT = os.path.join(ROOT, "game", "scripts", "hands_shape.gd")
POSES = os.path.join(ROOT, "game", "scripts", "hands_poses.gd")

N = 256
CENTER = (0.0, 22.0)


def unesc(s):
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            i += 1
            out.append({"t": "\t", "n": "\n"}.get(s[i], s[i]))
        else:
            out.append(s[i])
        i += 1
    return "".join(out)


def esc(s):
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")


def read_parts():
    got = {}
    files = sorted(glob.glob(PARTS))
    if not files:
        sys.exit("merge_shape: нет ни одного %s" % PARTS)
    for path in files:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line:
                    continue
                side, label, body = line.split("\t", 2)
                vals = [float(x) for x in body.split(",")]
                if len(vals) != N:
                    sys.exit("merge_shape: %s %r — %d радиусов, ждём %d"
                             % (side, label, len(vals), N))
                key = (side, "" if label == " " else unesc(label))
                if key in got:
                    sys.exit("merge_shape: дубль %s %r" % key)
                got[key] = vals
    return got


def expected():
    """Позы из hands_poses.gd: (side, label)."""
    import re
    txt = open(POSES, encoding="utf-8").read()
    out = set()
    for m in re.finditer(r'^\t"([LR])": \{\s*$', txt, re.M):
        out.add((m.group(1), ""))
    side = None
    press = False
    for line in txt.split("\n"):
        if line.startswith("const PRESS"):
            press = True
            continue
        if not press:
            continue
        m = re.match(r'^\t"([LR])": \{$', line)
        if m:
            side = m.group(1)
            continue
        m = re.match(r'^\t\t"((?:[^"\\]|\\.)*)": \[', line)
        if m and side:
            out.add((side, unesc(m.group(1))))
    return out


def main():
    got = read_parts()
    want = expected()
    missing = sorted(want - set(got))
    extra = sorted(set(got) - want)
    if missing and os.environ.get("MBT_PARTIAL") != "1":
        sys.exit("merge_shape: не хватает %d поз: %s" % (len(missing), missing[:8]))
    if missing:
        print("merge_shape: ЧАСТИЧНО, нет %d поз" % len(missing))
    if extra:
        sys.exit("merge_shape: лишние позы: %s" % extra[:8])
    lines = [
        "# СГЕНЕРИРОВАНО tools/hand3d/bake_outline.gd — не править руками.",
        "#",
        "# Контур кисти (с предплечьем) — радиусы от центра полярной меры",
        "# в системе кисти, N лучей по кругу. Снят с ПОЛЯ hand_model.field_palm()",
        "# (ладонь без пальцев и большого) вдоль ЛОКАЛЬНОЙ z кисти: объединение",
        "# проекций примитивов теряет smin-скругление и даёт ступеньки",
        "# (автор 05.11.2026: «шишах»). Пальцы игра строит лентами из своей FK.",
        "# Перезапекание — см. шапку bake_outline.gd.",
        "class_name HandsShape",
        "extends RefCounted",
        "",
        "const N := %d" % N,
        "const CENTER := Vector2(%.3f, %.3f)" % CENTER,
        "",
        "const RADII := {",
    ]
    for side in ("L", "R"):
        lines.append('\t"%s": {' % side)
        keys = sorted(k[1] for k in got if k[0] == side)
        keys.sort(key=lambda s: (s != "", s))
        for k in keys:
            body = ", ".join("%.2f" % v for v in got[(side, k)])
            lines.append('\t\t"%s": [%s],' % (esc(k), body))
        lines.append("\t},")
    lines.append("}")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("merge_shape: %d поз → %s" % (len(got), OUT))


if __name__ == "__main__":
    main()
