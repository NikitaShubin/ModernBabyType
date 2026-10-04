# AGENTS.md

Правила работы в этом репозитории. Обязательны для всех агентов и контрибьюторов.

## 1. Зависимости — только изолированно, никогда в систему

- Запрещено устанавливать что-либо в системный Python или ОС:
  `pip install --break-system-packages`, `sudo pip install`, `apt install python3-*` — нельзя.
- Python-утилиты (gdtoolkit, линтеры) — только в `.venv` внутри репозитория:
  `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements-dev.txt`
- **Всё запускается в контейнере.** Единственное исключение — запуск собранного
  бинарника игры, чтобы автор мог погонять. Ни сборка, ни тесты на хосте
  не запускаются.
- **Экран автора (`:0`) — только для игры и только по его просьбе.** Никаких
  тестовых окон, терминалов и пробников там не открывать: автор их закрывает
  как мусор. Всё тестовое — на виртуальном `:99`.
  - Сборка и экспорт игры: `tools/docker/build-game.sh`, образ
    `mbt-godot` собирается из `tools/docker/Dockerfile` (поверх
    `barichello/godot-ci:4.3`). Тот же Dockerfile и тот же скрипт
    использует CI, правила сборки не должны расходиться.
  - Настроек Android (JDK, SDK, ключ подписи) в системе нет: их
    подставляет `tools/docker/mbt-godot-env.sh` на старте контейнера.
- В систему (`/usr`, `apt`) — ничего.
- Временные файлы — в `/tmp/opencode/`, не в общие системные пути.
  Учти: `/tmp` у автора — tmpfs в RAM, он **обнуляется при перезагрузке**.
  Всё, что должно пережить перезагрузку, держим в `tools/`: там лежат
  export templates (1.7 ГБ), бинарь движка и хелперы визуального стенда.
  Правило «важное не в `/tmp`» сейчас особенно строгое: там жил и был
  потерян ключ pollinations и 8 кадров AnimateDiff.
- `.venv/`, `game/dist/`, `game/.godot/` — в `.gitignore`, в коммиты не идут.
  `tools/` в `.gitignore` целиком, кроме `tools/docker/`, `tools/icons/`
  и `tools/x11test.py`: эти три в репозитории, остальное пересоздаётся.
- История: в начале сессии `gdtoolkit` был однократно поставлен мимо `.venv`
  (в user-site), затем полностью откачен (`pip uninstall`, проверено).
  Дальше — только `.venv`.

## 2. Структура

- `main.py` — удалён, pygame-прототип больше не нужен.
- `game/` — игра целиком: Godot 4.3, десктоп Windows/Linux/macOS и Android.
  - `game/scenes/main.tscn` + `game/scripts/main.gd` — игровой экран.
  - `game/scenes/menu.tscn` + `game/scripts/menu.gd` — меню игроков.
    Скрытое меню клавиш не видит, иначе перехватывает ввод раньше игры.
  - `game/scripts/meadow.gd` — общий фон (небо, солнце, облака, холмы).
  - `game/scripts/balance.gd` — чистая логика сложности (без узлов сцены).
  - `game/scripts/save.gd` — профили в `user://modern_baby_type.cfg`.
  - `game/texts/*.txt` — тексты уровней (пять файлов, все со знаками).
  - `game/tests/logic_test.gd` — регресс-тесты механики (детерминированные,
    кадр за кадром). `game/tests/profiles_test.gd` — меню игроков: создание,
    вход, удаление, переключатель «все клавиши», утечка игровых клавиш.
    `game/tests/chase_test.gd` — инвариантный тест погони:
    гоняет живой цикл с рандомным вводом и на каждом кадре проверяет, что
    укол не случился, когда ёж и заяц на разных строках и ёж не перешёл.
    `game/tests/shot_driver.gd` — съёмка кадров анимации.
    Во всех тестах перед `add_child` ставятся `skip_menu = true` и
    `all_keys_override = 1`, иначе тест упрётся в меню.
  - `game/assets/` — спрайты (`hero.png` заяц, `hedge.png` ёж) и `CREDITS.md`
    с их происхождением. Это **окончательные** файлы, игра использует
    именно их; промпты, сиды и скрипт обработки лежат текстом в
    `CREDITS.md`, исходных JPEG в репозитории нет. Инфраструктуры
    генерации картинок в проекте нет и не будет.
  - `game/icon.png`, `icon.ico`, `icon.icns`, `game/android/icon_*.png` —
    иконка (зайчик), генерируется `tools/icons/make_icons.py`.
  - `game/export_presets.cfg` — пресеты Windows/Linux/macOS/Android.
    Файл в репозитории — источник правды для CI; пути к подписывающим
    утилитам в нём не зашиты, их подставляет контейнер.
- `tools/docker/` — образ и скрипты сборки (в репозитории).
- `tools/icons/` — генератор иконок (в репозитории).
- `tools/x11test.py` — хелпер визуального стенда (в репозитории, потому что
  `/tmp` обнуляется при перезагрузке).
- `.github/workflows/release.yml` — релиз по тегу `v*`: тот же образ, что и
  локально, `build-game.sh --all`, четыре артефакта.

## 3. Команды

```bash
source .venv/bin/activate
.venv/bin/gdparse game/scripts/balance.gd game/scripts/save.gd game/scripts/main.gd \
  game/scripts/menu.gd game/tests/logic_test.gd game/tests/profiles_test.gd \
  game/tests/chase_test.gd game/tests/shot_driver.gd
tools/docker/build-game.sh --test-only          # три теста
tools/docker/build-game.sh --all                # тесты + 4 платформы
tools/docker/build-game.sh --preset Android     # одна платформа
tools/docker/build-game.sh --shot               # кадры анимации
```

Тесты: `LOGIC_TEST` (логика ввода), `PROFILES_TEST` (меню игроков),
`CHASE_TEST` (инвариант погони). Все три обязательны к запуску. Тест, который
ни разу не падает на сломанном коде, бесполезен: правя геометрию погони,
сначала ломаю правило руками, убеждаюсь, что `CHASE_TEST` это ловит, и только
потом ставлю исправленное.

`gdparse` из requirements-dev новее движка и НЕ ловит несоответствия API:
`KEY_GO_BACK` и `virtual_keyboard_show()` без аргументов он проглотил,
а Godot 4.3 на них упал с Parse Error. Новые вызовы DisplayServer и ключи
`KEY_*` сверять с 4.3 (grep по бинарю в образе), а не с gdparse.

Открыть `game/` в Godot 4.3+, запуск — F5. Релизы: `git tag v0.0.3 && git push --tags`
(тег обязан совпадать с `config/version` в `game/project.godot`, CI это
проверяет).

## 4. Визуальный тест-цикл (виртуальный экран :99, :0 не трогаем!)

```bash
Xvfb :99 -screen 0 1280x800x24 &   # один раз; живёт сам по себе
setxkbmap -display :99 -model pc105 -layout ru  # ввод кириллицы (потом вернуть us)
DISPLAY=:99 ./game/dist/ModernBabyType.x86_64 &
DISPLAY=:99 .venv/bin/python tools/x11test.py shot <имя>  # скрин в /tmp/opencode/<имя>.png
DISPLAY=:99 .venv/bin/python tools/x11test.py geom   # размер окна
DISPLAY=:99 .venv/bin/python tools/x11test.py focus  # фокус окну игры
DISPLAY=:99 .venv/bin/python tools/x11test.py kc 69  # F3: debug-HUD
setxkbmap -display :99 us  # вернуть раскладку после тестов
```
Пример ввода буквы: `x11test.py key 0x6c1` (через keysym→keycode текущей
раскладки; при `ru` в трее keycode 41 даёт «а» и работает как ввод).

Внимание: `key <keysym>` вводит через физический keycode раскладки (трей `ru`),
для функциональных клавиш использовать `kc <сырой keycode X11>` (F3=69).
Процесс игры гасить только так (голый `pkill -f` убивает собственный шелл):
`PID=$(ps -eo pid,args | grep "[M]odernBabyType.x86_64" | awk '{print $1}'); [ -n "$PID" ] && kill "$PID"`.
Стоячее правило: после каждого изменения — пересобрать, быстро проверить
и оставить игру ЗАПУЩЕННОЙ окном, чтобы автор мог погонять.
