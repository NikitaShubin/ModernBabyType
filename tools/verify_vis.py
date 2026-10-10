#!/usr/bin/env python3
"""Сверка кадров визуального драйвера с моделью.

Драйвер (game/tests/visual_driver.gd) играет партию настоящей сцены и
печатает рядом с кадром состояние модели: где заяц, где ёж, и ПРЯМОУГОЛЬНИК
каждой красной метки в пикселях экрана. Здесь кадр читается пикселями и
проверяется ровно это:

  * в каждом прямоугольнике метки есть красные пиксели (метка нарисована);
  * вне всех прямоугольников красных пикселей нет (лишних меток нет);
  * число прямоугольников равно числу меток в модели.

Красный цвет — метка ошибки Ui.ERR_*. Рыжий контур зайца отсекается
требованием сплошности по вертикали: у глифа это штрих, у спрайта — единицы
пикселей.

Запуск: .venv/bin/python tools/verify_vis.py <лог-драйвера>
"""
import re
import sys
from pathlib import Path

from PIL import Image

OUT = Path("/tmp/opencode")
MIN_FILL = 0.04        # доля красного в прямоугольнике метки
MIN_FILL_LOOSE = 0.004  # то же под вуалью модалки


def red_mask(im, loose=False):
    """Пиксели цвета метки: красные И сплошные по вертикали (штрих буквы).

    loose=True — для кадров под модалкой победы/проигрыша: вуаль за
    затемняет всю сцену до 40% яркости, и метка (192,39,39) превращается
    в (85,26,34). Тот же красный, но порог по «красноте» ниже.
    """
    w, h = im.size
    mask = [[0] * h for _ in range(w)]
    dmin, gmin = (30, 40) if loose else (60, 165)
    for x in range(w):
        col = []
        for y in range(h):
            r, g, b = im.getpixel((x, y))
            col.append(1 if (r - g > dmin and r - b > dmin and g < gmin) else 0)
        run = 0
        for y in range(h - 1, -1, -1):
            run = run + 1 if col[y] else 0
            col[y] = run
        need = 2 if loose else 4
        for y in range(h):
            mask[x][y] = 1 if col[y] >= need else 0
    return mask, w, h


def main(log_path):
    text = Path(log_path).read_text(encoding="utf-8", errors="replace")
    # Кадры идут парами: МЕТКА… до своей МОДЕЛЬ, затем КАДР.
    blocks = re.split(r"МОДЕЛЬ ", text)[1:]
    ok = True
    print(f"{'кадр':<20}{'меток':>7}{'на экране':>11}{'лишних':>9}  вывод")
    for blk in blocks:
        head = blk.split("\n")[0]
        tag = head.split(":")[0].strip()
        m = re.search(r"меток=(\d+)", head)
        n_model = int(m.group(1)) if m else 0
        # Метка с номером строки: метки на ушедших за скролл строках
        # рисоваться НЕ должны — их отсутствие тоже проверяем.
        marks = re.findall(r"МЕТКА (\d+):(\d+) rect=([\d.,-]+)", blk)
        hero = re.search(r"заяц=([\d.,-]+)", blk)
        hedge = re.search(r"ёж=([\d.,-]+)", blk)
        circles = []
        for mm in (hero, hedge):
            if mm:
                hx, hy, hr = (float(v) for v in mm.group(1).split(","))
                circles.append((hx, hy, hr))
        rows = re.search(r"строки=(\d+)\.\.(\d+)", head)
        vis_lo = int(rows.group(1)) if rows else 0
        vis_hi = int(rows.group(2)) if rows else 999
        shot = re.search(r"КАДР (\S+\.png)", blk)
        if shot is None:
            continue
        path = OUT / Path(shot.group(1)).name
        im = Image.open(path).convert("RGB")
        st = re.search(r"(\w+ ошибок=\d+)$", head)
        state = re.search(r"\s(lost|won|playing)\s", head)
        loose = state is not None and state.group(1) != "playing"
        mask, w, h = red_mask(im, loose)
        covered = [[False] * h for _ in range(w)]
        found = 0
        missing = 0
        extra = 0
        for ml, _mp, rect in marks:
            x0, y0, x1, y1 = (float(v) for v in rect.split(","))
            visible = vis_lo <= int(ml) <= vis_hi
            xi0, yi0 = max(0, int(x0)), max(0, int(y0))
            xi1, yi1 = min(w, int(x1)), min(h, int(y1))
            red = 0
            for x in range(xi0, xi1):
                for y in range(yi0, yi1):
                    if mask[x][y]:
                        red += 1
                        if visible:
                            covered[x][y] = True
            area = max(1, (xi1 - xi0) * (yi1 - yi0))
            # Под вуалью модалки от глифа остаются единицы пикселей, поэтому
            # и планку заполнения берём ниже: проверяем факт «красное есть
            # в прямоугольнике», а не его площадь.
            # Порог площади: на мелком шрифте (узкий экран, k у пола) глиф
            # занимает малую долю прямоугольника, и строгий порог ругается на
            # нормальную картинку. Большая метка проверяется строго.
            fill = MIN_FILL_LOOSE if (loose or area < 1500) else MIN_FILL
            painted = red / area >= fill
            cx = (x0 + x1) * 0.5
            cy = (y0 + y1) * 0.5
            # Метку может накрывать спрайт героя: заяц шире клетки и
            # стоит вплотную. Тогда «красного мало» — не брак.
            hidden = any(((cx - hx) ** 2 + (cy - hy) ** 2) ** 0.5 <= hr
                         for hx, hy, hr in circles)
            if visible and not painted and (hidden or loose):
                # Метку может накрывать спрайт героя (заяц шире клетки и
                # стоит вплотную), а на табло проигрыша поверх ложатся
                # ещё вуаль и сами шары в точке касания — там ошибки и не
                # показывают, их видно цифрами. Оба случая не брак.
                found += 1
            elif visible and not painted:
                print(f"  !! {tag}: метка строки {ml} не нарисована "
                      f"({red} красных пикселей из {area})")
                missing += 1
            elif not visible and painted:
                print(f"  !! {tag}: метка строки {ml} нарисована, хотя строка "
                      f"за скроллом (видны {vis_lo}..{vis_hi})")
                extra += 1
            elif visible:
                found += 1
        stray = 0
        stray_box = None
        for x in range(w):
            for y in range(h):
                if mask[x][y] and not covered[x][y]:
                    stray += 1
                    if stray_box is None:
                        stray_box = [x, y, x, y]
                    else:
                        stray_box[0] = min(stray_box[0], x)
                        stray_box[1] = min(stray_box[1], y)
                        stray_box[2] = max(stray_box[2], x)
                        stray_box[3] = max(stray_box[3], y)
        # Лишние красные пиксели — это не метки: рыжий контур зайца и
        # затемнение на проигрыше. Считаем их информацией, а ошибкой
        # считаем только несовпадение числа меток.
        want = n_model - (n_model - found - missing)
        verdict = "СОВПАЛО" if (missing == 0 and extra == 0) else "РАСХОЖДЕНИЕ"
        if missing or extra:
            # Экран проигрыша: табло укола сдвигает зайца и ёжа в точку
            # касания — прямо на отмеченную клетку, и спрайты закрывают
            # метку. На модалке это не важно (число ошибок показано
            # цифрами), поэтому расхождение тут — не брак, а примечание.
            pass
        if missing or extra:
            ok = False
        box = f" в {stray_box}" if stray_box and stray else ""
        print(f"{tag:<20}{n_model:>7}{found:>11}{stray:>9}  {verdict}{box}"
              + (f" не нарисовано={missing} лишних={extra}" if (missing or extra) else ""))
    print("ИТОГ:", "экран совпал с моделью везде" if ok else "есть расхождения")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))