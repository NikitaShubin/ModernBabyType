#!/usr/bin/env python3
"""Хелпер для визуального стенда на :99 (см. AGENTS.md, раздел 4).

Живёт в репозитории, а не в /tmp: /tmp у автора — tmpfs в RAM и
обнуляется при перезагрузке, а без этого хелпера нельзя ни снять
кадр, ни подать клавишу в окно игры.

Запуск (нужен DISPLAY=:99 и запущенная игра):

    .venv/bin/python tools/x11test.py geom          # геометрия окон
    .venv/bin/python tools/x11test.py focus         # фокус окну игры
    .venv/bin/python tools/x11test.py shot имя      # снимок в /tmp/opencode/имя.png
    .venv/bin/python tools/x11test.py type "текст"  # ввод текста
    .venv/bin/python tools/x11test.py key 0x6c1     # ввод по keysym
    .venv/bin/python tools/x11test.py kc 69         # ввод по сырому keycode X11

Дисплей берётся из переменной DISPLAY, если она есть, иначе :99.
Требуется python-xlib из requirements-dev.txt и xdotool/import из
системы (в .venv их нет, и ставить туда ничего не нужно).

Про keycode: key <keysym> вводит через физический keycode текущей
раскладки, поэтому для русской раскладки key 0x6c1 даёт «а». Для
функциональных клавиш используй kc с сырым кодом (F3 = 69).
"""

import os
import subprocess
import sys

D = os.environ.get("DISPLAY", ":99")
OUT_DIR = "/tmp/opencode"


def win():
    """Окно игры: первое непромежуточное достаточно большое."""
    from Xlib import display

    d = display.Display(D)
    for w in d.screen().root.query_tree().children:
        try:
            g = w.get_geometry()
        except Exception:
            continue
        if g.width > 400 and g.height > 300:
            return d, w
    return d, d.screen().root


def cmd(*args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.stdout.strip():
        print(r.stdout.strip())
    if r.stderr.strip():
        print(r.stderr.strip(), file=sys.stderr)
    return r.returncode


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    what = sys.argv[1]
    if what == "geom":
        d, w = win()
        g = w.get_geometry()
        print(w.id, g.x, g.y, g.width, g.height)
    elif what == "focus":
        d, w = win()
        w.set_input_focus(1, 0, 0)
        print("focused", w.id)
    elif what == "shot":
        name = sys.argv[2] if len(sys.argv) > 2 else "shot"
        os.makedirs(OUT_DIR, exist_ok=True)
        path = os.path.join(OUT_DIR, name + ".png")
        if cmd("import", "-display", D, "-window", "root", path) == 0:
            print(path)
    elif what == "type":
        cmd("xdotool", "type", "--clearmodifiers", "--delay", "120", sys.argv[2])
    elif what == "key":
        cmd("xdotool", "key", "--clearmodifiers", sys.argv[2])
    elif what == "kc":
        cmd("xdotool", "keydown", sys.argv[2], "sleep", "0.05", "keyup", sys.argv[2])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())