"""ModernBabyType — игра для обучения слепой печати."""  # noqa: INP001

from __future__ import annotations

import json
import random
from pathlib import Path
from typing import ClassVar, NamedTuple

import pygame  # type: ignore[import-not-found]

# ==================== ТИПЫ ====================

RGBColor = tuple[int, int, int]
Position = tuple[int, int]


class LayoutParams(NamedTuple):
    """Параметры layout'а для упрощения передачи."""

    max_chars: int
    margin: int
    letter_width: int
    max_lines: int


# ==================== КОНСТАНТЫ ====================

BASE_WIDTH: int = 1100
BASE_HEIGHT: int = 650
MIN_FONT_SIZE: int = 20

COLOR_BG: RGBColor = (252, 252, 250)
COLOR_TEXT_ACTIVE_TODO: RGBColor = (20, 20, 20)
COLOR_TEXT_INACTIVE_TODO: RGBColor = (160, 160, 160)
COLOR_TEXT_PASSED: RGBColor = (220, 220, 220)
COLOR_ERROR: RGBColor = (220, 40, 40)
COLOR_HIGHLIGHT: RGBColor = (255, 255, 180)
COLOR_HERO: RGBColor = (50, 100, 220)
COLOR_ENEMY: RGBColor = (200, 50, 50)
COLOR_UI: RGBColor = (80, 80, 80)
COLOR_BUTTON: RGBColor = (240, 240, 240)
COLOR_BUTTON_HOVER: RGBColor = (220, 220, 220)

KEY_PROGRESSION: str = " аовлыдфжпреимтнгрушщзхъёйчясмитьбю,.!?-:;\"'()1234567890"
INITIAL_ACTIVE_COUNT: int = 3
WINS_TO_LEVEL_UP: int = 3
BASE_ENEMY_SPEED: float = 40.0

MAX_USERNAME_LENGTH: int = 15
TEXT_CHUNK_LINES: int = 3


pygame.init()


# ==================== МЕНЕДЖЕР ПОЛЬЗОВАТЕЛЕЙ ====================


class UserManager:
    """Управление сохранением и загрузкой данных пользователей."""

    PROGRESS_FILE: ClassVar[str] = "progress.json"
    MAX_USERNAME_LENGTH: ClassVar[int] = 15

    def __init__(self) -> None:
        """Инициализирует менеджер и загружает данные."""
        self._last_user: str | None = None
        self._users: dict[str, dict[str, int]] = {}
        self.load()

    def load(self) -> None:
        """Загружает данные из JSON файла."""
        progress_path = Path(self.PROGRESS_FILE)
        if progress_path.exists():
            try:
                data = json.loads(
                    progress_path.read_text(encoding="utf-8"),
                )
                self._last_user = data.get("last_user") if isinstance(
                    data.get("last_user"), str,
                ) or data.get("last_user") is None else None
                users_data = data.get("users", {})
                if isinstance(users_data, dict):
                    self._users = users_data
                else:
                    self._users = {}
            except (json.JSONDecodeError, KeyError, TypeError, OSError):
                self._last_user = None
                self._users = {}

    def save(self) -> None:
        """Сохраняет данные в JSON файл."""
        progress_path = Path(self.PROGRESS_FILE)
        data = {
            "last_user": self._last_user,
            "users": self._users,
        }
        progress_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def get_last_user(self) -> str | None:
        """Возвращает имя последнего пользователя."""
        return self._last_user

    def get_users_list(self) -> list[str]:
        """Возвращает список имен пользователей."""
        return list(self._users.keys())

    def user_exists(self, username: str) -> bool:
        """Проверяет существование пользователя."""
        return username in self._users

    def create_user(self, username: str) -> bool:
        """Создает нового пользователя."""
        if not username or username.strip() == "":
            return False
        clean_name = username.strip()
        if len(clean_name) > self.MAX_USERNAME_LENGTH:
            clean_name = clean_name[: self.MAX_USERNAME_LENGTH]
        if clean_name not in self._users:
            self._users[clean_name] = {
                "difficulty_level": 0,
                "wins_in_a_row": 0,
                "total_games": 0,
                "total_wins": 0,
            }
            self._last_user = clean_name
            self.save()
            return True
        return False

    def delete_user(self, username: str) -> bool:
        """Удаляет пользователя."""
        if username in self._users:
            del self._users[username]
            if self._last_user == username:
                self._last_user = None
            self.save()
            return True
        return False

    def set_last_user(self, username: str | None) -> None:
        """Устанавливает последнего пользователя."""
        if username is None or username in self._users:
            self._last_user = username
            self.save()

    def get_progress(self, username: str) -> dict[str, int] | None:
        """Возвращает прогресс пользователя."""
        if username and username in self._users:
            return self._users[username].copy()
        return None

    def save_progress(
        self,
        username: str,
        difficulty: int,
        wins_in_row: int,
    ) -> None:
        """Сохраняет прогресс пользователя."""
        if username and username in self._users:
            user_data = self._users[username]
            user_data["difficulty_level"] = difficulty
            user_data["wins_in_a_row"] = wins_in_row
            self.save()

    def has_valid_last_user(self) -> bool:
        """Проверяет, есть ли валидный последний пользователь."""
        last = self._last_user
        return last is not None and last in self._users


# ==================== КЛАССЫ ИГРЫ ====================


class Enemy:
    """Враг (красный круг), догоняющий игрока."""

    def __init__(self, start_x: int, line_height: int) -> None:
        """Инициализирует врага."""
        self.line: int = 0
        self.x: float = float(start_x)
        self.line_height: int = line_height
        self.current_speed: float = BASE_ENEMY_SPEED

    def reset_for_new_level(self) -> None:
        """Сбрасывает скорость для нового уровня."""
        self.current_speed = BASE_ENEMY_SPEED * 0.8

    def update(self, dt: float, level: LevelState) -> None:  # noqa: ARG002
        """Обновляет позицию врага."""
        self.x += self.current_speed * dt

    def adapt(self, *, won: bool) -> None:
        """Адаптирует скорость в зависимости от результата."""
        if won:
            self.current_speed *= 1.1
        else:
            self.current_speed *= 0.75
        self.current_speed = max(
            BASE_ENEMY_SPEED * 0.3,
            min(self.current_speed, BASE_ENEMY_SPEED * 5),
        )


class LevelState:
    """Состояние текущего уровня."""

    def __init__(
        self,
        difficulty_level: int,
        text_lines: list[str],
        layout: LayoutParams,
    ) -> None:
        """Инициализирует состояние уровня."""
        self.difficulty: int = difficulty_level
        count = INITIAL_ACTIVE_COUNT + difficulty_level
        self.active_chars: set[str] = set(KEY_PROGRESSION[:count])
        self.active_chars.add(" ")

        self.layout = layout
        self.max_lines = layout.max_lines

        self.display_lines: list[list[str]] = []
        for line in text_lines:
            wrapped = self._wrap_line(line, self.layout.max_chars)
            for segment in wrapped:
                if len(self.display_lines) < self.max_lines:
                    self.display_lines.append(list(segment))

        while len(self.display_lines) < self.max_lines and self.display_lines:
            self.display_lines.append(self.display_lines[-1])

        self.error_overlays: dict[Position, str] = {}
        self.passed_positions: set[Position] = set()

        self.cursor_line: int = 0
        self.cursor_pos: int = 0
        self.is_finished: bool = False
        self.is_lost: bool = False
        self.chars_typed_correctly: int = 0
        self.error_count: int = 0
        self.wait_for_manual_input: bool = False
        self._timer: float = 0.0

    def update_layout_params(self, layout: LayoutParams) -> None:
        """Обновляет параметры при изменении окна."""
        self.max_lines = layout.max_lines

        if layout.max_chars != self.layout.max_chars:
            self._rebuild_lines(layout.max_chars)

        self.layout = layout

    def _rebuild_lines(self, max_chars: int) -> None:
        """Перестраивает строки при изменении ширины."""
        original_text: list[str] = []
        current = ""
        for line_list in self.display_lines:
            line_str = "".join(line_list)
            if len(line_str) < self.layout.max_chars - 2:
                if current:
                    current += " " + line_str
                else:
                    current = line_str
                original_text.append(current)
                current = ""
            else:
                current += line_str

        if current:
            original_text.append(current)

        self.display_lines = []
        for line in original_text[:TEXT_CHUNK_LINES]:
            if len(self.display_lines) >= self.max_lines:
                break
            wrapped = self._wrap_line(line, max_chars)
            for segment in wrapped:
                if len(self.display_lines) < self.max_lines:
                    self.display_lines.append(list(segment))

        if self.cursor_line >= len(self.display_lines):
            self.cursor_line = len(self.display_lines) - 1
            self.cursor_pos = (
                len(self.display_lines[-1]) - 1 if self.display_lines else 0
            )

    def _wrap_line(self, text: str, max_width: int) -> list[str]:
        """Разбивает строку с учетом слов."""
        if len(text) <= max_width:
            return [text] if text else [" "]

        words = text.split()
        lines: list[str] = []
        current = ""

        for raw_word in words:
            word = raw_word
            if len(word) > max_width:
                if current:
                    lines.append(current)
                    current = ""
                lines.append(word[:max_width])
                while len(word[max_width:]) > max_width:
                    remaining = word[max_width:]
                    lines.append(remaining[:max_width])
                    word = remaining
                word = word[max_width:]

            if len(current) + len(word) + (1 if current else 0) <= max_width:
                current += (" " if current else "") + word
            else:
                if current:
                    lines.append(current)
                current = word

        if current:
            lines.append(current)

        return lines if lines else [" "]

    def is_char_active(self, char: str) -> bool:
        """Проверяет, является ли символ активным."""
        return char.lower() in self.active_chars or char == " "

    def get_char_at(self, line: int, pos: int) -> str | None:
        """Возвращает символ по координатам."""
        if (
            0 <= line < len(self.display_lines)
            and 0 <= pos < len(self.display_lines[line])
        ):
            return self.display_lines[line][pos]
        return None

    def handle_wrong_key(self, wrong_char: str) -> None:
        """Обрабатывает нажатие неправильной клавиши."""
        if self.is_finished or self.is_lost:
            return

        pos_key = (self.cursor_line, self.cursor_pos)
        self.error_overlays[pos_key] = wrong_char
        self.error_count += 1

        if self.cursor_pos > 0:
            self.cursor_pos -= 1
        elif self.cursor_line > 0:
            self.cursor_line -= 1
            self.cursor_pos = len(self.display_lines[self.cursor_line]) - 1

        self.wait_for_manual_input = True

    def _delete_forward_error(self) -> bool:
        """Удаляет ошибку впереди курсора."""
        forward_line, forward_pos = self.cursor_line, self.cursor_pos + 1
        if forward_line < len(self.display_lines):
            if forward_pos >= len(self.display_lines[forward_line]):
                forward_line += 1
                forward_pos = 0

            if (
                forward_line < len(self.display_lines)
                and (forward_line, forward_pos) in self.error_overlays
            ):
                del self.error_overlays[(forward_line, forward_pos)]
                self.cursor_line = forward_line
                self.cursor_pos = forward_pos
                current = self.get_char_at(self.cursor_line, self.cursor_pos)
                if current and not self.is_char_active(current):
                    self.wait_for_manual_input = False
                return True
        return False

    def _delete_current_error(self) -> bool:
        """Удаляет ошибку в текущей позиции."""
        current_pos = (self.cursor_line, self.cursor_pos)
        if current_pos in self.error_overlays:
            del self.error_overlays[current_pos]
            current = self.get_char_at(self.cursor_line, self.cursor_pos)
            if current and not self.is_char_active(current):
                self.wait_for_manual_input = False
            return True
        return False

    def _backtrack_to_previous(self) -> bool:
        """Возвращает курсор к предыдущему активному символу."""
        line, pos = self.cursor_line, self.cursor_pos - 1
        if pos < 0:
            line -= 1
            if line < 0:
                self.passed_positions.discard((0, 0))
                return True
            pos = len(self.display_lines[line]) - 1

        while line >= 0:
            char = self.get_char_at(line, pos)
            self.passed_positions.discard((line, pos))
            if char and self.is_char_active(char):
                self.cursor_line = line
                self.cursor_pos = pos
                return True

            if pos > 0:
                pos -= 1
            else:
                line -= 1
                if line < 0:
                    break
                pos = len(self.display_lines[line]) - 1 if line >= 0 else 0

        self.cursor_line = 0
        self.cursor_pos = 0
        self.passed_positions.discard((0, 0))
        return True

    def handle_backspace(self) -> bool:
        """Обрабатывает нажатие Backspace."""
        self.wait_for_manual_input = True

        if self._delete_forward_error():
            return True
        return self._delete_current_error() or self._backtrack_to_previous()

    def handle_correct_key(self, char: str) -> None:
        """Обрабатывает правильное нажатие."""
        if self.is_finished or self.is_lost:
            return

        expected = self.get_char_at(self.cursor_line, self.cursor_pos)
        if not expected or expected.lower() != char.lower():
            return

        self.wait_for_manual_input = False
        self.passed_positions.add((self.cursor_line, self.cursor_pos))
        self.chars_typed_correctly += 1

        self.cursor_pos += 1
        if self.cursor_pos >= len(self.display_lines[self.cursor_line]):
            self.cursor_line += 1
            self.cursor_pos = 0
            if self.cursor_line >= len(self.display_lines):
                self.is_finished = True

    def auto_advance(self, dt: float) -> None:
        """Автоматически продвигает курсор."""
        if self.is_finished or self.is_lost or self.wait_for_manual_input:
            return

        speed = 12
        self._timer += dt
        interval = 1.0 / speed

        while self._timer >= interval:
            self._timer -= interval
            if self.is_finished:
                return

            if (self.cursor_line, self.cursor_pos) in self.error_overlays:
                return

            current = self.get_char_at(self.cursor_line, self.cursor_pos)
            if current is None:
                self.is_finished = True
                return

            if self.is_char_active(current):
                return

            self.passed_positions.add((self.cursor_line, self.cursor_pos))
            self.cursor_pos += 1
            if self.cursor_pos >= len(self.display_lines[self.cursor_line]):
                self.cursor_line += 1
                self.cursor_pos = 0
                if self.cursor_line >= len(self.display_lines):
                    self.is_finished = True


class Game:
    """Основной класс игры."""

    def __init__(self) -> None:
        """Инициализирует игру."""
        self.screen = pygame.display.set_mode(
            (BASE_WIDTH, BASE_HEIGHT),
            pygame.RESIZABLE,
        )
        pygame.display.set_caption(
            "ModernBabyType: Адаптивный размер (F11 - полный экран)",
        )
        self.clock = pygame.time.Clock()

        self.current_width: int = BASE_WIDTH
        self.current_height: int = BASE_HEIGHT
        self.is_fullscreen: bool = False

        self.font: pygame.font.Font | None = None
        self.small_font: pygame.font.Font | None = None

        # Initialize level and enemy before recalculate_layout
        self.level: LevelState | None = None
        self.enemy: Enemy | None = None

        self.recalculate_layout()

        self.user_manager = UserManager()
        self.current_user: str | None = None
        self.input_text: str = ""
        self.input_active: bool = False
        self.selected_user_idx: int = 0
        self.user_list: list[str] = []

        texts_dir = Path("texts")
        texts_dir.mkdir(parents=True, exist_ok=True)
        self.text_files: list[Path] = [
            f for f in texts_dir.iterdir() if f.suffix == ".txt"
        ]
        if not self.text_files:
            demo_file = texts_dir / "demo.txt"
            demo_file.write_text(
                "мама мыла раму довольно долго\n"
                "папа читал газету у окна\n"
                "солнце светило ярко и светило",
                encoding="utf-8",
            )
            self.text_files = [demo_file]

        self.difficulty_level: int = 0
        self.wins_in_a_row: int = 0

        if self.user_manager.has_valid_last_user():
            self.current_user = self.user_manager.get_last_user()
            self.load_user_progress()
            self.game_state: str = "playing"
            self.start_new_level(reset=False)
        else:
            self.game_state = "user_select"
            self.update_user_list()

    def update_user_list(self) -> None:
        """Обновляет список пользователей."""
        self.user_list = self.user_manager.get_users_list()
        if self.selected_user_idx >= len(self.user_list):
            self.selected_user_idx = max(0, len(self.user_list) - 1)

    def load_user_progress(self) -> None:
        """Загружает прогресс текущего пользователя."""
        if self.current_user:
            progress = self.user_manager.get_progress(self.current_user)
            if progress:
                self.difficulty_level = progress["difficulty_level"]
                self.wins_in_a_row = progress["wins_in_a_row"]
            else:
                self.difficulty_level = 0
                self.wins_in_a_row = 0

    def save_current_progress(self) -> None:
        """Сохраняет прогресс текущего пользователя."""
        if self.current_user:
            self.user_manager.save_progress(
                self.current_user,
                self.difficulty_level,
                self.wins_in_a_row,
            )

    def _get_layout_params(self) -> LayoutParams:
        """Возвращает текущие параметры layout'а."""
        return LayoutParams(
            max_chars=self.max_chars_per_line,
            margin=self.margin,
            letter_width=self.letter_width,
            max_lines=self.max_display_lines,
        )

    def recalculate_layout(self) -> None:
        """Пересчитывает размеры при изменении окна."""
        w, h = self.current_width, self.current_height
        scale_factor = min(w / BASE_WIDTH, h / BASE_HEIGHT)

        self.margin: int = max(20, int(w * 0.05))
        font_size = max(MIN_FONT_SIZE, int(40 * scale_factor))
        small_font_size = max(12, int(20 * scale_factor))
        self.font = pygame.font.SysFont("dejavusans", font_size)
        self.small_font = pygame.font.SysFont("dejavusans", small_font_size)

        self.letter_width: int = max(20, int(w / 32))
        self.line_height: int = max(30, int(h / 11))
        self.font_size: int = font_size

        usable_width = w - (self.margin * 2)
        self.max_chars_per_line: int = usable_width // self.letter_width

        usable_height = h - 300
        self.max_display_lines: int = usable_height // self.line_height
        self.max_display_lines = max(3, min(self.max_display_lines, 5))

        if self.level:
            self.level.update_layout_params(self._get_layout_params())

    def toggle_fullscreen(self) -> None:
        """Переключает полноэкранный режим."""
        self.is_fullscreen = not self.is_fullscreen
        if self.is_fullscreen:
            self.screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        else:
            self.screen = pygame.display.set_mode(
                (BASE_WIDTH, BASE_HEIGHT),
                pygame.RESIZABLE,
            )

        info = pygame.display.Info()
        if self.is_fullscreen:
            self.current_width = info.current_w
            self.current_height = info.current_h
        else:
            self.current_width = BASE_WIDTH
            self.current_height = BASE_HEIGHT

        self.recalculate_layout()

    def load_random_text(self) -> list[str]:
        """Загружает случайный фрагмент текста."""
        filename = random.choice(self.text_files)  # noqa: S311
        with filename.open(encoding="utf-8") as f:
            all_lines = [line.rstrip() for line in f if line.strip() != ""]

        if len(all_lines) == 0:
            return ["а о а о", "о а о", "а о"]

        if len(all_lines) <= TEXT_CHUNK_LINES:
            return all_lines

        max_start = len(all_lines) - TEXT_CHUNK_LINES
        start_idx = random.randint(0, max_start)  # noqa: S311
        return all_lines[start_idx : start_idx + TEXT_CHUNK_LINES]

    def start_new_level(self, *, reset: bool = False) -> None:
        """Начинает новый уровень."""
        if reset:
            self.difficulty_level = 0
            self.wins_in_a_row = 0

        text_lines = self.load_random_text()
        self.level = LevelState(
            self.difficulty_level,
            text_lines,
            self._get_layout_params(),
        )
        self.enemy = Enemy(self.margin - 80, self.line_height)
        self.game_state = "playing"

        if not reset and self.wins_in_a_row == 0:
            self.enemy.reset_for_new_level()

    def check_collision(self) -> bool:
        """Проверяет столкновение с врагом."""
        if not self.level or self.level.is_finished or not self.enemy:
            return False
        if self.enemy.line == self.level.cursor_line:
            cursor_x = (
                self.level.layout.margin
                + self.level.cursor_pos * self.level.layout.letter_width
            )
            if self.enemy.x >= cursor_x - 25:
                return True
        return False

    def update(self, dt: float) -> None:
        """Обновляет состояние игры."""
        if self.game_state != "playing" or not self.level or not self.enemy:
            return

        self.level.auto_advance(dt)
        self.enemy.update(dt, self.level)

        if self.enemy.line < len(self.level.display_lines):
            line_len = len(self.level.display_lines[self.enemy.line])
            line_end = (
                self.level.layout.margin
                + line_len * self.level.layout.letter_width
                + 40
            )
            if self.enemy.x > line_end:
                self.enemy.line += 1
                self.enemy.x = self.level.layout.margin - 80

        if self.check_collision():
            self.game_state = "lost"
            self.level.is_lost = True
            self.wins_in_a_row = 0
            self.enemy.adapt(won=False)
            self.save_current_progress()
        elif self.level.is_finished:
            self.game_state = "won"
            self.wins_in_a_row += 1
            self.enemy.adapt(won=True)
            if self.wins_in_a_row >= WINS_TO_LEVEL_UP:
                self.difficulty_level += 1
                self.wins_in_a_row = 0
            self.save_current_progress()

    def _draw_user_button(
        self,
        i: int,
        user: str,
        w: int,
        start_y: int,
        line_height: int,
    ) -> None:
        """Отрисовывает кнопку пользователя."""
        y = start_y + i * line_height

        if i == self.selected_user_idx:
            bg_color = COLOR_HIGHLIGHT
            border_color = COLOR_HERO
            text_color = COLOR_TEXT_ACTIVE_TODO
        else:
            bg_color = COLOR_BUTTON
            border_color = COLOR_UI
            text_color = COLOR_TEXT_ACTIVE_TODO

        rect = pygame.Rect(w // 2 - 140, y, 280, 45)
        pygame.draw.rect(self.screen, bg_color, rect)
        pygame.draw.rect(self.screen, border_color, rect, 2)

        if self.font is not None:
            name_surf = self.font.render(user, True, text_color)  # noqa: FBT003
            self.screen.blit(
                name_surf,
                (
                    w // 2 - name_surf.get_width() // 2,
                    y + (45 - name_surf.get_height()) // 2,
                ),
            )

    def draw_user_select(self) -> None:  # noqa: PLR0915
        """Отрисовывает меню выбора пользователя."""
        if self.font is None or self.small_font is None:
            return

        self.screen.fill(COLOR_BG)
        w, h = self.screen.get_width(), self.screen.get_height()

        title = self.font.render("Кто играет?", True, COLOR_TEXT_ACTIVE_TODO)  # noqa: FBT003
        self.screen.blit(title, (w // 2 - title.get_width() // 2, 80))

        start_y = 160
        line_height = 55

        for i, user in enumerate(self.user_list):
            self._draw_user_button(i, user, w, start_y, line_height)

        if not self.user_list:
            empty_text = self.small_font.render(
                "Пока нет сохраненных игроков",
                True,  # noqa: FBT003
                COLOR_TEXT_INACTIVE_TODO,
            )
            self.screen.blit(
                empty_text,
                (w // 2 - empty_text.get_width() // 2, start_y),
            )

        input_y = h - 200
        input_rect = pygame.Rect(w // 2 - 140, input_y, 280, 45)

        if self.input_active:
            bg_color = COLOR_HIGHLIGHT
            border_color = COLOR_HERO
        else:
            bg_color = (255, 255, 255)
            border_color = COLOR_UI

        pygame.draw.rect(self.screen, bg_color, input_rect)
        pygame.draw.rect(self.screen, border_color, input_rect, 2)

        display_text = self.input_text + ("|" if self.input_active else "")
        input_text_surf = self.font.render(display_text, True, COLOR_TEXT_ACTIVE_TODO)  # noqa: FBT003
        text_y = input_rect.centery - input_text_surf.get_height() // 2
        self.screen.blit(input_text_surf, (input_rect.x + 15, text_y))

        if self.input_active or self.input_text:
            prompt_text = "Новый игрок:"
        else:
            prompt_text = "Нажмите Tab для ввода имени"
        prompt = self.small_font.render(prompt_text, True, COLOR_UI)  # noqa: FBT003
        self.screen.blit(prompt, (w // 2 - prompt.get_width() // 2, input_y - 25))

        if self.user_list and self.small_font is not None:
            del_rect = pygame.Rect(
                w // 2 + 150,
                start_y + self.selected_user_idx * line_height + 10,
                25,
                25,
            )
            del_color = (
                (255, 200, 200)
                if del_rect.collidepoint(pygame.mouse.get_pos())
                else (255, 150, 150)
            )
            pygame.draw.rect(self.screen, del_color, del_rect)
            pygame.draw.rect(self.screen, COLOR_ERROR, del_rect, 1)
            del_text = self.small_font.render("×", True, (255, 255, 255))  # noqa: FBT003
            self.screen.blit(
                del_text,
                (
                    del_rect.centerx - del_text.get_width() // 2,
                    del_rect.centery - del_text.get_height() // 2,
                ),
            )

        hint = self.small_font.render(
            "↑↓ выбор  •  Enter вход  •  Tab ввод  •  "
            "Del удалить  •  Esc без сохранения",
            True,  # noqa: FBT003
            COLOR_TEXT_INACTIVE_TODO,
        )
        self.screen.blit(hint, (w // 2 - hint.get_width() // 2, h - 50))

    def handle_user_select_input(self, event: pygame.event.Event) -> bool:
        """Обрабатывает ввод в меню выбора."""
        if event.type == pygame.KEYDOWN:
            return self._handle_user_select_keydown(event)
        if event.type == pygame.MOUSEBUTTONDOWN:
            return self._handle_user_select_mouse(event)
        return True

    def _navigate_user_list(self, direction: int) -> None:
        """Навигирует по списку пользователей."""
        if self.user_list and not self.input_active:
            self.selected_user_idx = (self.selected_user_idx + direction) % len(
                self.user_list,
            )

    def _handle_text_input(self, event: pygame.event.Event) -> None:
        """Обрабатывает ввод текста."""
        if event.key == pygame.K_BACKSPACE:
            self.input_text = self.input_text[:-1]
        elif len(self.input_text) < MAX_USERNAME_LENGTH and event.unicode.isprintable():
            self.input_text += event.unicode

    def _handle_user_select_keydown(self, event: pygame.event.Event) -> bool:
        """Обрабатывает клавиши в меню выбора."""
        key = event.key

        if key == pygame.K_ESCAPE:
            self._start_guest_mode()
        elif key == pygame.K_UP:
            self._navigate_user_list(-1)
        elif key == pygame.K_DOWN:
            self._navigate_user_list(1)
        elif key == pygame.K_RETURN:
            self._handle_enter_in_menu()
        elif key == pygame.K_DELETE:
            self._handle_delete_in_menu()
        elif key == pygame.K_TAB:
            self.input_active = not self.input_active
        elif self.input_active:
            self._handle_text_input(event)

        return True

    def _start_guest_mode(self) -> None:
        """Запускает гостевой режим."""
        self.current_user = None
        self.user_manager.set_last_user(None)
        self.difficulty_level = 0
        self.wins_in_a_row = 0
        self.game_state = "playing"
        self.start_new_level(reset=True)

    def _handle_enter_in_menu(self) -> None:
        """Обрабатывает Enter в меню."""
        if self.input_active and self.input_text.strip():
            username = self.input_text.strip()
            if self.user_manager.create_user(username):
                self.current_user = username
                self.difficulty_level = 0
                self.wins_in_a_row = 0
            else:
                self.current_user = username
                self.user_manager.set_last_user(username)
                self.load_user_progress()
            self.input_text = ""
            self.game_state = "playing"
            self.start_new_level(reset=False)
        elif self.user_list and not self.input_active:
            self.current_user = self.user_list[self.selected_user_idx]
            self.user_manager.set_last_user(self.current_user)
            self.load_user_progress()
            self.game_state = "playing"
            self.start_new_level(reset=False)

    def _handle_delete_in_menu(self) -> None:
        """Обрабатывает Delete в меню."""
        if not self.input_active and self.user_list:
            user_to_del = self.user_list[self.selected_user_idx]
            self.user_manager.delete_user(user_to_del)
            self.update_user_list()
            if self.current_user == user_to_del:
                self.current_user = None

    def _handle_user_select_mouse(self, event: pygame.event.Event) -> bool:
        """Обрабатывает мышь в меню выбора."""
        if event.button != 1:
            return True

        w, h = self.screen.get_width(), self.screen.get_height()
        start_y = 160
        line_height = 55

        for i in range(len(self.user_list)):
            rect = pygame.Rect(w // 2 - 140, start_y + i * line_height, 280, 45)
            if rect.collidepoint(event.pos):
                self._select_user_by_index(i)
                return True

        if self.user_list:
            del_rect = pygame.Rect(
                w // 2 + 150,
                start_y + self.selected_user_idx * line_height + 10,
                25,
                25,
            )
            if del_rect.collidepoint(event.pos):
                user_to_del = self.user_list[self.selected_user_idx]
                self.user_manager.delete_user(user_to_del)
                self.update_user_list()
                if self.current_user == user_to_del:
                    self.current_user = None
                return True

        input_rect = pygame.Rect(w // 2 - 140, h - 200, 280, 45)
        self.input_active = input_rect.collidepoint(event.pos)
        return True

    def _select_user_by_index(self, index: int) -> None:
        """Выбирает пользователя по индексу."""
        self.selected_user_idx = index
        self.current_user = self.user_list[index]
        self.user_manager.set_last_user(self.current_user)
        self.load_user_progress()
        self.game_state = "playing"
        self.start_new_level(reset=False)

    def _draw_text_grid(
        self,
        visible_lines: int,
        start_x: int,
        start_y: int,
    ) -> None:
        """Отрисовывает сетку текста."""
        if not self.level or not self.font:
            return

        for line_idx in range(visible_lines):
            line_chars = self.level.display_lines[line_idx]
            y = start_y + line_idx * self.line_height

            for char_idx, char in enumerate(line_chars):
                x = start_x + char_idx * self.level.layout.letter_width
                pos = (line_idx, char_idx)

                is_error = pos in self.level.error_overlays
                is_passed = pos in self.level.passed_positions
                is_cursor = (
                    line_idx == self.level.cursor_line
                    and char_idx == self.level.cursor_pos
                )

                if is_cursor:
                    pygame.draw.rect(
                        self.screen,
                        COLOR_HIGHLIGHT,
                        (
                            x - 2,
                            y - 4,
                            self.level.layout.letter_width,
                            self.font_size + 8,
                        ),
                    )

                if is_error:
                    base_color = COLOR_ERROR
                elif is_passed:
                    base_color = COLOR_TEXT_PASSED
                elif self.level.is_char_active(char):
                    base_color = COLOR_TEXT_ACTIVE_TODO
                else:
                    base_color = COLOR_TEXT_INACTIVE_TODO

                surf = self.font.render(char, True, base_color)  # noqa: FBT003
                self.screen.blit(surf, (x, y))

                if is_error:
                    err_char = self.level.error_overlays[pos]
                    err_surf = self.font.render(err_char, True, COLOR_ERROR)  # noqa: FBT003
                    self.screen.blit(err_surf, (x - 2, y - 4))

    def _draw_hero(self, start_x: int, start_y: int) -> None:
        """Отрисовывает героя."""
        if not self.level:
            return

        cx = start_x + self.level.cursor_pos * self.level.layout.letter_width
        cy = (
            start_y
            + self.level.cursor_line * self.line_height
            + self.line_height
            - 20
        )
        hero_size = max(15, int(self.line_height * 0.4))
        pygame.draw.rect(self.screen, COLOR_HERO, (cx, cy, hero_size, hero_size))

    def _draw_enemy(self, start_y: int) -> None:
        """Отрисовывает врага."""
        if not self.enemy:
            return

        enemy_y = (
            start_y + self.enemy.line * self.line_height + self.line_height // 2
        )
        pygame.draw.circle(
            self.screen,
            COLOR_ENEMY,
            (int(self.enemy.x), enemy_y),
            max(10, int(self.line_height * 0.35)),
        )

    def _draw_ui(
        self,
        visible_lines: int,
        actual_width: int,
        actual_height: int,
    ) -> None:
        """Отрисовывает интерфейс."""
        if not self.level or not self.small_font or not self.enemy:
            return

        bottom_margin = 10
        ui_line3 = actual_height - bottom_margin - 20
        ui_line2 = actual_height - bottom_margin - 45
        ui_line1 = actual_height - bottom_margin - 70

        active_list = sorted([c for c in self.level.active_chars if c != " "])
        active_str = "".join(active_list)
        error_count = len(self.level.error_overlays)

        lines_info = f"Строк: {visible_lines}/{self.max_display_lines}"
        user_info = f" | {self.current_user}" if self.current_user else " | гость"

        line1_text = (
            f"Буквы: [{active_str}] | {lines_info} | "
            f"Ошибок: {error_count} | "
            f"Побед: {self.wins_in_a_row}/{WINS_TO_LEVEL_UP}{user_info}"
        )
        self.screen.blit(
            self.small_font.render(line1_text, True, COLOR_UI),  # noqa: FBT003
            (self.margin, ui_line1),
        )

        speed_val = self.enemy.current_speed / BASE_ENEMY_SPEED
        speed_text = f"{speed_val:.1f}x" if self.enemy else "-"
        line2_text = (
            f"Уровень: {self.difficulty_level} | "
            f"Скорость: {speed_text} | "
            f"Размер: {actual_width}x{actual_height} (F11 - полный экран)"
        )
        self.screen.blit(
            self.small_font.render(line2_text, True, COLOR_UI),  # noqa: FBT003
            (self.margin, ui_line2),
        )

        hint = (
            "Backspace удаляет красную букву справа"
            if error_count > 0
            else "Размер окна адаптируется автоматически"
        )
        self.screen.blit(
            self.small_font.render(hint, True, COLOR_UI),  # noqa: FBT003
            (self.margin, ui_line3),
        )

    def draw(self) -> None:
        """Отрисовывает игровое поле."""
        if self.game_state == "user_select":
            self.draw_user_select()
            pygame.display.flip()
            return

        self.screen.fill(COLOR_BG)

        if not self.level or not self.font or not self.small_font:
            pygame.display.flip()
            return

        actual_width = self.screen.get_width()
        actual_height = self.screen.get_height()

        start_x = self.level.layout.margin
        start_y = self.line_height

        available_height = actual_height - 120
        max_lines_fit = available_height // self.line_height
        visible_lines = min(
            len(self.level.display_lines),
            max_lines_fit,
            self.max_display_lines,
        )

        self._draw_text_grid(visible_lines, start_x, start_y)

        if not self.level.is_finished and self.level.cursor_line < visible_lines:
            self._draw_hero(start_x, start_y)

        if self.enemy and self.enemy.line < visible_lines:
            self._draw_enemy(start_y)

        self._draw_ui(visible_lines, actual_width, actual_height)

        if self.game_state == "won":
            self._draw_won_screen(actual_width, actual_height)
        elif self.game_state == "lost":
            self._draw_lost_screen(actual_width, actual_height)

        pygame.display.flip()

    def _draw_won_screen(self, width: int, height: int) -> None:
        """Отрисовывает экран победы."""
        if not self.font or not self.small_font or not self.level:
            return

        overlay = pygame.Surface((width, height))
        overlay.set_alpha(180)
        overlay.fill((200, 255, 200))
        self.screen.blit(overlay, (0, 0))

        center_x = width // 2
        center_y = height // 2

        if self.difficulty_level > 0 and self.wins_in_a_row == 0:
            new_char_idx = INITIAL_ACTIVE_COUNT + self.difficulty_level - 1
            if new_char_idx < len(KEY_PROGRESSION):
                new_letter = KEY_PROGRESSION[new_char_idx]
                msg = f"Новая буква открыта: '{new_letter}'!"
                chars = len(self.level.active_chars)
                sub_msg = f"Теперь активно {chars} символов"
            else:
                msg = "Все буквы открыты!"
                sub_msg = "Вы молодец!"
        else:
            msg = "Уровень пройден!"
            current_idx = INITIAL_ACTIVE_COUNT + self.difficulty_level
            total = len(KEY_PROGRESSION)
            sub_msg = f"Прогресс: {current_idx}/{total} символов"

        msg_surf = self.font.render(msg, True, (0, 100, 0))  # noqa: FBT003
        sub_surf = self.small_font.render(sub_msg, True, (0, 100, 0))  # noqa: FBT003

        if self.current_user:
            enter_text = "Enter - продолжить | F2 - сменить игрока"
        else:
            enter_text = "Enter - продолжить | F2 - выбрать игрока"

        enter_surf = self.small_font.render(enter_text, True, (0, 100, 0))  # noqa: FBT003

        self.screen.blit(
            msg_surf,
            (center_x - msg_surf.get_width() // 2, center_y - 60),
        )
        self.screen.blit(
            sub_surf,
            (center_x - sub_surf.get_width() // 2, center_y + 20),
        )
        self.screen.blit(
            enter_surf,
            (center_x - enter_surf.get_width() // 2, center_y + 60),
        )

    def _draw_lost_screen(self, width: int, height: int) -> None:
        """Отрисовывает экран поражения."""
        if not self.font or not self.small_font:
            return

        overlay = pygame.Surface((width, height))
        overlay.set_alpha(180)
        overlay.fill((255, 200, 200))
        self.screen.blit(overlay, (0, 0))

        center_x = width // 2
        center_y = height // 2

        lost_surf = self.font.render("Враг догнал!", True, (150, 0, 0))  # noqa: FBT003

        if self.current_user:
            retry_text = "Enter - повторить | F2 - сменить игрока"
        else:
            retry_text = "Enter - повторить | F2 - выбрать игрока"

        retry_surf = self.small_font.render(retry_text, True, (150, 0, 0))  # noqa: FBT003

        self.screen.blit(
            lost_surf,
            (center_x - lost_surf.get_width() // 2, center_y - 50),
        )
        self.screen.blit(
            retry_surf,
            (center_x - retry_surf.get_width() // 2, center_y + 20),
        )

    def _process_resize(self, event: pygame.event.Event) -> None:
        """Обрабатывает изменение размера окна."""
        if not self.is_fullscreen:
            self.current_width = event.w
            self.current_height = event.h
            self.screen = pygame.display.set_mode(
                (event.w, event.h),
                pygame.RESIZABLE,
            )
            self.recalculate_layout()
            if self.level:
                self.level.update_layout_params(self._get_layout_params())

    def _process_keydown(self, event: pygame.event.Event) -> bool:
        """Обрабатывает нажатия клавиш в игре.

        Returns:
            True если нужно выйти из игры.

        """
        if event.key == pygame.K_ESCAPE:
            if self.is_fullscreen:
                self.toggle_fullscreen()
            else:
                self.save_current_progress()
                return True
        elif event.key == pygame.K_F11:
            self.toggle_fullscreen()
        elif event.key == pygame.K_F2:
            self._open_user_select()
        elif event.key == pygame.K_RETURN:
            if self.game_state in {"won", "lost"}:
                self.start_new_level(reset=False)
        elif self.game_state == "playing":
            self._process_typing(event)
        return False

    def _open_user_select(self) -> None:
        """Открывает меню выбора пользователя."""
        self.save_current_progress()
        self.user_manager.set_last_user(None)
        self.current_user = None
        self.difficulty_level = 0
        self.wins_in_a_row = 0
        self.update_user_list()
        self.input_text = ""
        self.input_active = False
        self.game_state = "user_select"

    def _process_typing(self, event: pygame.event.Event) -> None:
        """Обрабатывает ввод текста."""
        if not self.level:
            return

        if event.key == pygame.K_BACKSPACE:
            self.level.handle_backspace()
        elif event.unicode:
            expected = self.level.get_char_at(
                self.level.cursor_line,
                self.level.cursor_pos,
            )
            is_correct = (
                expected
                and self.level.is_char_active(expected)
                and event.unicode.lower() == expected.lower()
            )

            if is_correct:
                self.level.handle_correct_key(event.unicode)
            else:
                self.level.handle_wrong_key(event.unicode)

    def _process_events(self) -> bool:
        """Обрабатывает события pygame.

        Returns:
            False если нужно выйти из игры.

        """
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.save_current_progress()
                return False

            if event.type == pygame.VIDEORESIZE:
                self._process_resize(event)
                continue

            if event.type == pygame.KEYDOWN:
                if self.game_state == "user_select":
                    if not self.handle_user_select_input(event):
                        return False
                    continue

                if self._process_keydown(event):
                    return False
            elif event.type == pygame.MOUSEBUTTONDOWN:
                if self.game_state == "user_select":
                    self.handle_user_select_input(event)
        return True

    def run(self) -> None:
        """Запускает основной игровой цикл."""
        running = True
        while running:
            dt = self.clock.tick(60) / 1000.0

            running = self._process_events()

            if running:
                self.update(dt)
                self.draw()

        pygame.quit()


if __name__ == "__main__":
    Game().run()
