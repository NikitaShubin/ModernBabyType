#!/usr/bin/env python3
"""Иконки платформ из зайца-героя.

Спрайт `game/assets/hero.png` — 139×160, альфа-бокс во весь кадр
(см. game/assets/CREDITS.md). Отсюда и иконки: кроп по альфе и ровно
тот же заяц, что в игре, на бумажном фоне `#f7f3e8` (он же фон
игрового экрана и меню).

Что делает скрипт:

  game/icon.png                  512×512  — config/icon, иконка в окне
  game/icon.ico                  16…256   — Windows (пресет сам зовёт rcedit)
  game/icon.icns                 16…1024  — macOS
  game/android/icon_192.png      192×192  — иконка приложения
  game/android/icon_fg_432.png   432×432  — адаптивная, передний слой
  game/android/icon_bg_432.png   432×432  — адаптивная, задний слой
  game/android/icon_mono_432.png 432×432  — силуэт для themed icons

Запуск из корня репозитория, venv с pillow:

    .venv/bin/python tools/icons/make_icons.py

Зависимость ровно одна — pillow. Скрипт детерминирован: повторный
запуск даёт байт-в-байт те же файлы, поэтому их можно коммитить.
"""

import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HERO = ROOT / "game" / "assets" / "hero.png"
GAME = ROOT / "game"
ANDROID = GAME / "android"

# Тот же PAPER, что в scripts/main.gd и scripts/menu.gd. Иконка на
# бумаге: белый квад на светлых панелях (вкладки, файловые менеджеры)
# сливается, а тёмные глаза зайца читаются на любом фоне.
PAPER = (0xF7, 0xF3, 0xE8, 0xFF)
# Заяц в иконке занимает ~78% полотна: не липнет к краю, но и не
# болтается мелким пятном. Для адаптивной иконки Android запас
# больше (16%), там по краям всё равно срезается маска.
PAD = 0.14
PAD_ADAPTIVE = 0.16

# Стандартный набор кеглей Windows. 24×24 сюда не берём: rcedit под
# wine кладёт в .exe не все переданные размеры, и если в группе иконок
# заявлен размер, а картинки нет, Проводник рисует пустое место. Проверено
# на rcedit 1.0.2: без 24×24 попадают в .exe все шесть.
ICO_MAX = 256
ICNS_SIZES = (16, 32, 64, 128, 256, 512, 1024)
# Типы блоков ICNS по spec'у Apple: OSType + размер + данные.
ICNS_TYPES = {
    16: b"icp4", 32: b"icp5", 64: b"icp6", 128: b"ic07",
    256: b"ic08", 512: b"ic09", 1024: b"ic10",
}


def load_hero() -> Image.Image:
    """Заяц без пустых полей по краям."""
    hero = Image.open(HERO).convert("RGBA")
    if hero.getchannel("A").getextrema() == (255, 255):
        raise SystemExit(
            f"{HERO}: нет альфа-канала, кроп по содержимому невозможен"
        )
    box = hero.getbbox()
    if box is None:
        raise SystemExit(f"{HERO}: спрайт пустой")
    return hero.crop(box)


def hero_scaled(size: int, pad: float) -> Image.Image:
    """Заяц, вписанный в квадрат size×size по меньшей стороне."""
    hero = load_hero()
    free = int(round(size * (1.0 - 2.0 * pad)))
    scale = min(free / hero.width, free / hero.height)
    return hero.resize(
        (max(1, round(hero.width * scale)), max(1, round(hero.height * scale))),
        Image.LANCZOS,
    )


def hero_on_paper(size: int) -> Image.Image:
    """Заяц на бумажном фоне — так иконка выглядит в списках."""
    hero = hero_scaled(size, PAD)
    canvas = Image.new("RGBA", (size, size), PAPER)
    canvas.alpha_composite(hero, ((size - hero.width) // 2, (size - hero.height) // 2))
    return canvas


def adaptive_fg(size: int) -> Image.Image:
    """Передний слой адаптивной иконки: заяц без фона.

    Android рисует маску (круг, скруглённый квад, «каплю»), поэтому
    фон здесь обязан быть прозрачным, а заяц — целиком внутри
    безопасной зоны, иначе маска отрежет уши.
    """
    hero = hero_scaled(size, PAD_ADAPTIVE)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(hero, ((size - hero.width) // 2, (size - hero.height) // 2))
    return canvas


def silhouette(size: int) -> Image.Image:
    """Силуэт для themed icons (Android 13+): сплошной цвет + альфа.

    Цвет Android тонирует сам, поэтому важна только форма. Альфа берётся
    из спрайта — сглаживание края сохраняется.
    """
    hero = hero_scaled(size, PAD_ADAPTIVE)
    alpha = Image.new("L", (size, size), 0)
    alpha.paste(hero.getchannel("A"), ((size - hero.width) // 2, (size - hero.height) // 2))
    mono = Image.new("RGBA", (size, size), (0xB0, 0x23, 0x23, 0xFF))
    mono.putalpha(alpha)
    return mono


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def write_icns(path: Path) -> None:
    """Собрать .icns руками: Pillow этот формат не пишет.

    Формат: заголовок `icns` + общая длина, затем блоки
    [OSType (4 байта)][длина блока (4 байта, big-endian)][PNG].
    """
    blocks = []
    for n in ICNS_SIZES:
        raw = png_bytes(hero_on_paper(n))
        blocks.append(ICNS_TYPES[n] + len(raw).to_bytes(4, "big") + raw)
    body = b"".join(blocks)
    path.write_bytes(b"icns" + len(body).to_bytes(4, "big") + body)


def main() -> None:
    if not HERO.is_file():
        raise SystemExit(f"нет {HERO}: иконки собираются из зайца игры")
    ANDROID.mkdir(parents=True, exist_ok=True)

    hero_on_paper(512).save(GAME / "icon.png")
    # Pillow сам собирает многослойный ICO из одного PNG нужного кегля:
    # картинки меньше ICO_MAX рисует сам, поэтому хватает базовой.
    hero_on_paper(ICO_MAX).save(GAME / "icon.ico", format="ICO", sizes=[
        (n, n) for n in (16, 32, 48, 64, 128, 256)
    ])
    write_icns(GAME / "icon.icns")
    hero_on_paper(192).save(ANDROID / "icon_192.png")
    adaptive_fg(432).save(ANDROID / "icon_fg_432.png")
    Image.new("RGBA", (432, 432), PAPER).save(ANDROID / "icon_bg_432.png")
    silhouette(432).save(ANDROID / "icon_mono_432.png")

    print("иконки готовы:")
    for p in [
        GAME / "icon.png", GAME / "icon.ico", GAME / "icon.icns",
        ANDROID / "icon_192.png", ANDROID / "icon_fg_432.png",
        ANDROID / "icon_bg_432.png", ANDROID / "icon_mono_432.png",
    ]:
        print(f"  {p.relative_to(ROOT)}  {p.stat().st_size} Б")


if __name__ == "__main__":
    sys.exit(main())