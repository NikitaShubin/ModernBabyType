import pygame
import os
import random


pygame.init()


# ==================== КОНСТАНТЫ ====================


BASE_WIDTH = 1100
BASE_HEIGHT = 650
MIN_FONT_SIZE = 20

COLOR_BG = (252, 252, 250)
COLOR_TEXT_ACTIVE_TODO = (20, 20, 20)
COLOR_TEXT_INACTIVE_TODO = (160, 160, 160)
COLOR_TEXT_PASSED = (220, 220, 220)
COLOR_ERROR = (220, 40, 40)
COLOR_HIGHLIGHT = (255, 255, 180)
COLOR_HERO = (50, 100, 220)
COLOR_ENEMY = (200, 50, 50)
COLOR_UI = (80, 80, 80)

KEY_PROGRESSION = " аовлыдфжпреимтнгрушщзхъёйчясмитьбю,.!?-:;\"'()1234567890"
INITIAL_ACTIVE_COUNT = 3
WINS_TO_LEVEL_UP = 3
BASE_ENEMY_SPEED = 40


# ==================== КЛАССЫ ====================


class Enemy:
    def __init__(self, start_x, line_height):
        self.line = 0
        self.x = start_x
        self.line_height = line_height
        self.current_speed = BASE_ENEMY_SPEED

    def reset_for_new_level(self):
        self.current_speed = BASE_ENEMY_SPEED * 0.8

    def update(self, dt, level):
        self.x += self.current_speed * dt

    def adapt(self, won):
        if won:
            self.current_speed *= 1.1
        else:
            self.current_speed *= 0.75
        self.current_speed = max(
            BASE_ENEMY_SPEED * 0.3, min(self.current_speed, BASE_ENEMY_SPEED * 5)
        )


class LevelState:
    def __init__(
        self, difficulty_level, text_lines, max_chars, margin, letter_width, max_lines
    ):
        self.difficulty = difficulty_level
        count = INITIAL_ACTIVE_COUNT + difficulty_level
        self.active_chars = set(KEY_PROGRESSION[:count])
        self.active_chars.add(" ")

        self.layout_max_chars = max_chars
        self.layout_margin = margin
        self.layout_letter_width = letter_width
        self.max_lines = max_lines

        # Переносим строки и ограничиваем видимым количеством
        self.display_lines = []
        for line in text_lines:
            wrapped = self._wrap_line(line, self.layout_max_chars)
            for segment in wrapped:
                if len(self.display_lines) < self.max_lines:
                    self.display_lines.append(list(segment))

        # Если строк меньше чем max_lines, дублируем последнюю
        while len(self.display_lines) < self.max_lines and self.display_lines:
            self.display_lines.append(self.display_lines[-1])

        self.error_overlays = {}
        self.passed_positions = set()

        self.cursor_line = 0
        self.cursor_pos = 0
        self.is_finished = False
        self.is_lost = False
        self.chars_typed_correctly = 0
        self.error_count = 0
        self.wait_for_manual_input = False

    def update_layout_params(self, max_chars, margin, letter_width, max_lines):
        """Обновляет параметры при изменении размера окна"""
        self.max_lines = max_lines

        if max_chars != self.layout_max_chars:
            original_text = []
            current = ""
            for line_list in self.display_lines:
                line_str = "".join(line_list)
                if len(line_str) < self.layout_max_chars - 2:
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
            for line in original_text[:3]:
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

        self.layout_max_chars = max_chars
        self.layout_margin = margin
        self.layout_letter_width = letter_width

    def _wrap_line(self, text, max_width):
        """Разбивает строку с учетом слов"""
        if len(text) <= max_width:
            return [text] if text else [" "]

        words = text.split()
        lines = []
        current = ""

        for word in words:
            while len(word) > max_width:
                if current:
                    lines.append(current)
                    current = ""
                lines.append(word[:max_width])
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

    def is_char_active(self, char):
        return char.lower() in self.active_chars or char == " "

    def get_char_at(self, line, pos):
        if 0 <= line < len(self.display_lines):
            if 0 <= pos < len(self.display_lines[line]):
                return self.display_lines[line][pos]
        return None

    def handle_wrong_key(self, wrong_char):
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

    def handle_backspace(self):
        self.wait_for_manual_input = True

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

        if (self.cursor_line, self.cursor_pos) in self.error_overlays:
            del self.error_overlays[(self.cursor_line, self.cursor_pos)]
            current = self.get_char_at(self.cursor_line, self.cursor_pos)
            if current and not self.is_char_active(current):
                self.wait_for_manual_input = False
            return True

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

    def handle_correct_key(self, char):
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

    def auto_advance(self, dt):
        if self.is_finished or self.is_lost or self.wait_for_manual_input:
            return

        speed = 12
        self._timer = getattr(self, "_timer", 0) + dt
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
    def __init__(self):
        self.screen = pygame.display.set_mode(
            (BASE_WIDTH, BASE_HEIGHT), pygame.RESIZABLE
        )
        pygame.display.set_caption("BabyType: Адаптивный размер (F11 - полный экран)")
        self.clock = pygame.time.Clock()

        self.current_width = BASE_WIDTH
        self.current_height = BASE_HEIGHT
        self.is_fullscreen = False

        self.font = None
        self.small_font = None
        self.recalculate_layout()

        os.makedirs("texts", exist_ok=True)
        self.text_files = [f for f in os.listdir("texts") if f.endswith(".txt")]
        if not self.text_files:
            with open("texts/demo.txt", "w", encoding="utf-8") as f:
                f.write(
                    "мама мыла раму довольно долго и тщательно всё утро\nпапа читал газету у окна в кресле и попивал чай\nсолнце светило ярко и пригревало через стекло"
                )
            self.text_files = ["demo.txt"]

        self.difficulty_level = 0
        self.wins_in_a_row = 0
        self.level = None
        self.enemy = None
        self.game_state = "playing"

        self.start_new_level(reset=True)

    def recalculate_layout(self):
        """Пересчитывает все размеры при изменении окна"""
        w, h = self.current_width, self.current_height
        scale_factor = min(w / BASE_WIDTH, h / BASE_HEIGHT)

        self.margin = max(20, int(w * 0.05))
        font_size = max(MIN_FONT_SIZE, int(40 * scale_factor))
        small_font_size = max(12, int(20 * scale_factor))
        self.font = pygame.font.SysFont("dejavusans", font_size)
        self.small_font = pygame.font.SysFont("dejavusans", small_font_size)

        self.letter_width = max(20, int(w / 32))
        self.line_height = max(30, int(h / 11))
        self.font_size = font_size

        usable_width = w - (self.margin * 2)
        self.max_chars_per_line = usable_width // self.letter_width

        # Увеличенный запас (300px) для панели задач и UI
        usable_height = h - 300
        self.max_display_lines = usable_height // self.line_height

        # Строго ограничиваем 3-5 строками, чтобы гарантированно влезло
        self.max_display_lines = max(3, min(self.max_display_lines, 5))

        if hasattr(self, "level") and self.level:
            self.level.update_layout_params(
                self.max_chars_per_line,
                self.margin,
                self.letter_width,
                self.max_display_lines,
            )

    def toggle_fullscreen(self):
        """Переключение полноэкранного режима"""
        self.is_fullscreen = not self.is_fullscreen
        if self.is_fullscreen:
            self.screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        else:
            self.screen = pygame.display.set_mode(
                (BASE_WIDTH, BASE_HEIGHT), pygame.RESIZABLE
            )

        info = pygame.display.Info()
        if self.is_fullscreen:
            self.current_width = info.current_w
            self.current_height = info.current_h
        else:
            self.current_width = BASE_WIDTH
            self.current_height = BASE_HEIGHT

        self.recalculate_layout()

    def load_random_text(self):
        """Загружает случайный фрагмент из файла"""
        filename = random.choice(self.text_files)
        filepath = os.path.join("texts", filename)

        with open(filepath, "r", encoding="utf-8") as f:
            all_lines = [line.rstrip() for line in f.readlines() if line.strip() != ""]

        if len(all_lines) == 0:
            return ["а о а о", "о а о", "а о"]

        if len(all_lines) <= 3:
            return all_lines

        max_start = len(all_lines) - 3
        start_idx = random.randint(0, max_start)
        return all_lines[start_idx : start_idx + 3]

    def start_new_level(self, reset=False):
        if reset:
            self.difficulty_level = 0
            self.wins_in_a_row = 0

        text_lines = self.load_random_text()
        self.level = LevelState(
            self.difficulty_level,
            text_lines,
            self.max_chars_per_line,
            self.margin,
            self.letter_width,
            self.max_display_lines,
        )
        self.enemy = Enemy(self.margin - 80, self.line_height)
        self.game_state = "playing"

        if not reset and self.wins_in_a_row == 0:
            self.enemy.reset_for_new_level()

    def check_collision(self):
        if self.level.is_finished:
            return False
        if self.enemy.line == self.level.cursor_line:
            cursor_x = (
                self.level.layout_margin
                + self.level.cursor_pos * self.level.layout_letter_width
            )
            if self.enemy.x >= cursor_x - 25:
                return True
        return False

    def update(self, dt):
        if self.game_state != "playing":
            return

        self.level.auto_advance(dt)
        self.enemy.update(dt, self.level)

        if self.enemy.line < len(self.level.display_lines):
            line_len = len(self.level.display_lines[self.enemy.line])
            line_end = (
                self.level.layout_margin
                + line_len * self.level.layout_letter_width
                + 40
            )
            if self.enemy.x > line_end:
                self.enemy.line += 1
                self.enemy.x = self.level.layout_margin - 80

        if self.check_collision():
            self.game_state = "lost"
            self.level.is_lost = True
            self.wins_in_a_row = 0
            self.enemy.adapt(False)
        elif self.level.is_finished:
            self.game_state = "won"
            self.wins_in_a_row += 1
            self.enemy.adapt(True)
            if self.wins_in_a_row >= WINS_TO_LEVEL_UP:
                self.difficulty_level += 1
                self.wins_in_a_row = 0

    def draw(self):
        self.screen.fill(COLOR_BG)

        # ИСПРАВЛЕНИЕ: используем фактическую высоту поверхности, а не сохраненное значение
        actual_width = self.screen.get_width()
        actual_height = self.screen.get_height()

        start_x = self.level.layout_margin
        start_y = self.line_height

        # Проверяем, сколько строк реально влезет сейчас
        available_height_for_text = (
            actual_height - 120
        )  # 120px сверху для UI и отступов
        max_lines_that_fit = available_height_for_text // self.line_height
        visible_lines = min(
            len(self.level.display_lines), max_lines_that_fit, self.max_display_lines
        )

        # Рисуем только то, что влезает
        for line_idx in range(visible_lines):
            line_chars = self.level.display_lines[line_idx]
            y = start_y + line_idx * self.line_height

            for char_idx, char in enumerate(line_chars):
                x = start_x + char_idx * self.level.layout_letter_width
                pos = (line_idx, char_idx)

                is_error = pos in self.level.error_overlays
                is_passed = pos in self.level.passed_positions
                is_cursor = (
                    line_idx == self.level.cursor_line
                    and char_idx == self.level.cursor_pos
                )
                is_active = self.level.is_char_active(char)

                if is_cursor:
                    pygame.draw.rect(
                        self.screen,
                        COLOR_HIGHLIGHT,
                        (
                            x - 2,
                            y - 4,
                            self.level.layout_letter_width,
                            self.font_size + 8,
                        ),
                    )

                if is_error:
                    base_color = COLOR_ERROR
                elif is_passed:
                    base_color = COLOR_TEXT_PASSED
                elif is_active:
                    base_color = COLOR_TEXT_ACTIVE_TODO
                else:
                    base_color = COLOR_TEXT_INACTIVE_TODO

                surf = self.font.render(char, True, base_color)
                self.screen.blit(surf, (x, y))

                if is_error:
                    err_char = self.level.error_overlays[pos]
                    err_surf = self.font.render(err_char, True, COLOR_ERROR)
                    self.screen.blit(err_surf, (x - 2, y - 4))

        # Герой (только если видим)
        if not self.level.is_finished and self.level.cursor_line < visible_lines:
            cx = start_x + self.level.cursor_pos * self.level.layout_letter_width
            cy = (
                start_y
                + self.level.cursor_line * self.line_height
                + self.line_height
                - 20
            )
            hero_size = max(15, int(self.line_height * 0.4))
            pygame.draw.rect(self.screen, COLOR_HERO, (cx, cy, hero_size, hero_size))

        # Враг (только если видим)
        if self.enemy.line < visible_lines:
            enemy_y = (
                start_y + self.enemy.line * self.line_height + self.line_height // 2
            )
            pygame.draw.circle(
                self.screen,
                COLOR_ENEMY,
                (int(self.enemy.x), enemy_y),
                max(10, int(self.line_height * 0.35)),
            )

        # UI - позиционируем относительно НИЖНЕЙ границы окна с фиксированным отступом
        # Используем actual_height вместо self.current_height
        bottom_margin = 10
        ui_line3 = actual_height - bottom_margin - 20
        ui_line2 = actual_height - bottom_margin - 45
        ui_line1 = actual_height - bottom_margin - 70

        active_list = sorted([c for c in self.level.active_chars if c != " "])
        active_str = "".join(active_list)
        error_count = len(self.level.error_overlays)

        lines_info = f"Строк: {visible_lines}/{self.max_display_lines}"
        self.screen.blit(
            self.small_font.render(
                f"Буквы: [{active_str}] | {lines_info} | Ошибок: {error_count} | Побед: {self.wins_in_a_row}/{WINS_TO_LEVEL_UP}",
                True,
                COLOR_UI,
            ),
            (self.margin, ui_line1),
        )

        self.screen.blit(
            self.small_font.render(
                f"Уровень: {self.difficulty_level} | Скорость: {self.enemy.current_speed / BASE_ENEMY_SPEED:.1f}x | "
                f"Размер: {actual_width}x{actual_height} (F11 - полный экран)",
                True,
                COLOR_UI,
            ),
            (self.margin, ui_line2),
        )

        if error_count > 0:
            hint = "Backspace удаляет красную букву справа"
        else:
            hint = "Размер окна адаптируется автоматически"
        self.screen.blit(
            self.small_font.render(hint, True, COLOR_UI), (self.margin, ui_line3)
        )

        # Экраны победы/поражения с использованием actual_width/actual_height
        if self.game_state == "won":
            overlay = pygame.Surface((actual_width, actual_height))
            overlay.set_alpha(180)
            overlay.fill((200, 255, 200))
            self.screen.blit(overlay, (0, 0))

            center_x = actual_width // 2
            center_y = actual_height // 2

            if self.difficulty_level > 0 and self.wins_in_a_row == 0:
                new_char_idx = INITIAL_ACTIVE_COUNT + self.difficulty_level - 1
                if new_char_idx < len(KEY_PROGRESSION):
                    new_letter = KEY_PROGRESSION[new_char_idx]
                    msg = f"Новая буква открыта: '{new_letter}'!"
                    sub_msg = f"Теперь активно {len(self.level.active_chars)} символов"
                else:
                    msg = "Все буквы открыты!"
                    sub_msg = "Вы молодец!"
            else:
                msg = "Уровень пройден!"
                current_idx = INITIAL_ACTIVE_COUNT + self.difficulty_level
                total = len(KEY_PROGRESSION)
                sub_msg = f"Прогресс: {current_idx}/{total} символов"

            msg_surf = self.font.render(msg, True, (0, 100, 0))
            sub_surf = self.small_font.render(sub_msg, True, (0, 100, 0))
            enter_surf = self.small_font.render("Нажмите Enter", True, (0, 100, 0))

            self.screen.blit(
                msg_surf, (center_x - msg_surf.get_width() // 2, center_y - 60)
            )
            self.screen.blit(
                sub_surf, (center_x - sub_surf.get_width() // 2, center_y + 20)
            )
            self.screen.blit(
                enter_surf, (center_x - enter_surf.get_width() // 2, center_y + 60)
            )

        elif self.game_state == "lost":
            overlay = pygame.Surface((actual_width, actual_height))
            overlay.set_alpha(180)
            overlay.fill((255, 200, 200))
            self.screen.blit(overlay, (0, 0))

            center_x = actual_width // 2
            center_y = actual_height // 2

            lost_surf = self.font.render("Враг догнал!", True, (150, 0, 0))
            retry_surf = self.small_font.render("Enter - повторить", True, (150, 0, 0))

            self.screen.blit(
                lost_surf, (center_x - lost_surf.get_width() // 2, center_y - 50)
            )
            self.screen.blit(
                retry_surf, (center_x - retry_surf.get_width() // 2, center_y + 20)
            )

        pygame.display.flip()

    def run(self):
        running = True
        while running:
            dt = self.clock.tick(60) / 1000.0

            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False

                elif event.type == pygame.VIDEORESIZE:
                    if not self.is_fullscreen:
                        self.current_width = event.w
                        self.current_height = event.h
                        self.screen = pygame.display.set_mode(
                            (event.w, event.h), pygame.RESIZABLE
                        )
                        self.recalculate_layout()
                        if self.level:
                            self.level.update_layout_params(
                                self.max_chars_per_line,
                                self.margin,
                                self.letter_width,
                                self.max_display_lines,
                            )

                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        if self.is_fullscreen:
                            self.toggle_fullscreen()
                        else:
                            running = False
                    elif event.key == pygame.K_F11:
                        self.toggle_fullscreen()
                    elif event.key == pygame.K_RETURN:
                        if self.game_state == "won":
                            self.start_new_level(reset=False)
                        elif self.game_state == "lost":
                            self.start_new_level(reset=False)
                    else:
                        if self.game_state == "playing":
                            if event.key == pygame.K_BACKSPACE:
                                self.level.handle_backspace()
                            elif event.unicode:
                                expected = self.level.get_char_at(
                                    self.level.cursor_line, self.level.cursor_pos
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

            self.update(dt)
            self.draw()

        pygame.quit()


if __name__ == "__main__":
    Game().run()
