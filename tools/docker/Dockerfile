# Образ для сборки, тестов и съёмки кадров игры.
#
# Поверх barichello/godot-ci:4.3 добавляем софтверный OpenGL (Mesa) и
# env-скрипт mbt-godot. Без Mesa Godot в контейнере не может открыть
# окно даже на Xvfb: EGL не грузится, и --headless тем не помогает — в
# нём фиктивный рендерер, из которого не взять картинку.
#
# В образе уже есть всё для экспорта на все четыре платформы:
#   * export templates 4.3 (в $HOME/.local/share/godot/export_templates),
#   * JDK 17 и Android SDK с build-tools/platform-tools/ndk (gradle-сборка
#     Android включена: обновление ставится из игры через системный
#     установщик, для него нужен нативный плагин и gradle; шаблон
#     android/build разворачивает build-game.sh из android_source.zip),
#   * /opt/rcedit.exe + wine64 — правка иконки и версии в .exe,
#   * zip/unzip — macOS-экспорт собирается в .zip.
FROM barichello/godot-ci:4.3

RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1-mesa-dri \
        libglx-mesa0 \
        libegl1 \
        libgl1 \
        libgles2 \
        zip \
        unzip \
        libxkbfile1 \
        libxcb-cursor0 \
        libx11-6 \
        libxcb1 \
        libxext6 \
        libxi6 \
        libxrender1 \
        libxtst6 \
        libsm6 \
        libice6 \
        libglib2.0-0 \
        libdbus-1-3 \
        libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*
# Рантайм Qt-xcb сверх Mesa: нужен только окну эмулятора
# (tools/emulator). Сборкам и тестам он не мешает, в CI лишний вес —
# полтора десятка мегабайт.

# llvmpipe: рендер на CPU, видеокарта в контейнере не нужна
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV GALLIUM_DRIVER=llvmpipe

# Пути к rcedit и wine. Godot берёт их из editor_settings при
# --export-release и молча оставляет .exe с иконкой движка, если не
# нашёл. Пути прописаны в настройках на старте контейнера.
ENV GODOT_RCEDIT=/opt/rcedit.exe
ENV GODOT_WINE=/usr/bin/wine64-stable

# WINEPREFIX обязан лежать во временном каталоге контейнера, а не в
# примонтированном tools/home: wine отказывается создавать префикс в
# каталоге, который ему не принадлежит, а каталоги на Windows-диске,
# примонтированные на хосте, выглядят принадлежащими root. Иначе
# экспорт Windows молча остаётся без иконки: rcedit не запустился, а
# ошибки никто не печатает.
ENV WINEPREFIX=/tmp/mbt-wine
ENV WINEDEBUG=-all

# Шаблоны экспорта из базового образа лежат под /root, а контейнер
# работает от uid автора (см. build-game.sh --user): без прав на чтение
# и проход резервная ветка ensure_templates() в mbt-godot-env.sh их не
# увидит. Копировать 1.7 ГБ в /opt ради этого расточительно — достаточно
# открыть чтение (слой весит байты, а не гигабайты).
RUN chmod a+x /root /root/.local /root/.local/share /root/.local/share/godot \
    && chmod -R a+rX /root/.local/share/godot/export_templates \
    && ls /root/.local/share/godot/export_templates/
# Android SDK — пишемый для всех: gradle-сборка идёт от uid автора
# (см. build-game.sh --user), а недостающие пакеты шаблона
# (platforms;android-34, build-tools;34.0.0) gradle доставляет сам
# через sdkmanager. В закрытый на запись /usr/lib/android-sdk он
# падает «The SDK directory is not writable» (CI 10.2026).
RUN chmod -R a+w /usr/lib/android-sdk 2>/dev/null || true
# (идемпотентно) и генерирует debug-keystore для Android, если его
# нет. И то и другое нужно любой сборке, поэтому происходит на слое
# сборки образа, а не в скриптах CI. Ключ остаётся в образе и не
# попадает ни в репозиторий, ни в артефакты релиза.
COPY mbt-godot-env.sh /usr/local/bin/mbt-godot
RUN chmod +x /usr/local/bin/mbt-godot \
    # Прогреваем настройки и keystore на слое образа: первый экспорт в
    # CI не должен тратить время на keytool, а если JDK в базовом
    # образе не окажется, падать будет здесь, а не в рабочем потоке.
    && mbt-godot --version \
    && ls -l /opt/mbt/debug.keystore

ENV GODOT_BIN=godot
ENTRYPOINT ["/usr/local/bin/mbt-godot"]
CMD ["--version"]