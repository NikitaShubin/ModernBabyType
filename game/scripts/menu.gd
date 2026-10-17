extends Node2D
## Меню игроков: список профилей, поле ввода имени, гостевой режим.
##
## Управление:
##   ↑ / ↓      прокрутка списка, с перехватом через конец
##   Enter      в поле ввода — создать профиль (или войти, если имя есть),
##              без поля — войти выбранным
##   Tab        показать / спрятать поле ввода
##   A          все клавиши у выбранного профиля (взрослый режим:
##              активны все знаки сразу). Работает только при неактивном
##              поле ввода, поэтому не мешает набору имени
##   Delete     удалить выбранный профиль
##   Backspace  стереть символ в поле ввода
##   Esc        гость — играть без профиля, прогресс не сохраняется
##   Системная клавиатура Android шлёт события без keycode: Enter ловим
##   ещё и по unicode 10/13, Backspace — по unicode 8 (игру см. в main.gd).
##
## Сигналы: chosen(name) — пустое имя означает гостя.

const S := preload("res://scripts/save.gd")

signal chosen(user_name: String)

const BASE_W := 1100.0
const BASE_H := 650.0
const ROW_H := 62.0
const FONT_TITLE := 40
const FONT_ROW := 30
const FONT_SMALL := 20
## Кегли портретной карточки: имя во всю ширину, статистика строкой
## ниже, кнопки — третьим рядом во всю ширину. Крупнее табличных:
## карточка и так выше строки, место есть (было 30/20 — мелко).
const FONT_CARD_NAME := 34
const FONT_CARD_STATS := 22
## Установленная версия — подпись кнопки обновлений (автор 15.10.2026:
## вместо слова «Обновления» показываем версию).
static func _app_version() -> String:
	return "v" + String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Дневные значения ролей — из общего словаря (см. ui.gd: все цвета
## интерфейса живут там, здесь только сокращения). Ночные ставятся в
## _apply_night, и именно поэтому новый цвет не нужно искать в двух
## файлах сразу.
const PAPER := Ui.PAPER_DAY
const INK := Ui.INK_DAY
const UI_TEXT := Ui.UI_TEXT_DAY
const DIM := Ui.DIM_DAY
const HERO_TEX: Texture2D = preload("res://assets/hero.png")

var users: Array[String] = []
var sel := 0
## Кэш колонок таблицы на кадр данных (см. _table_cols). Пустой массив —
## «посчитать заново».
var _cols_cache: Array[float] = []
## Ключ кэша колонок: вид, масштаб, число игроков (см. _table_cols).
var _cw := -1.0
var _ck := -1.0
var _cn := -1
## Кэш окна списка: сами значения и ключ, по которому они верны
## (вид, масштаб, число игроков, правка, пилюля подсказки — см. _list_rect).
var _lr_ok := false
var _lr_val := Rect2()
var _lr_w := -1.0
var _lr_h := -1.0
var _lr_k := -1.0
var _lr_n := -1
var _lr_ed := -2
var _lr_hint := ""
var _lr_safe := -1.0
var _lr_act := false
## Строчное редактирование (автор 15.10.2026): номер строки (N = строка
## ввода имени, видна только пока идёт создание), editing_new отличает
## создание от переименования — у них разные Enter/Esc. Ввод идёт в
## input_text, input_active означает «редактируем».
var editing := -1
var editing_new := false
## Долгое нажатие на СТРОКЕ списка: палец стоит дольше порога —
## переименование. Это не «долгое нажатие для набора» (его нет и
## быть не должно: у «ё» и «ъ» свои клавиши, build-game.sh сторожит),
## поэтому константа названа ROW_*, а не LONG_PRESS_*.
var _press_down := false
var _press_t := 0.0
var _press_fired := false
const ROW_PRESS_T := 0.6
# Прокрутка списка игроков (портрет): карточки не влезают все — список
# листается, а не ужимается до нечитаемого (жалоба автора 10.2026:
# «в портрете всё мелкое»). В альбомной таблица по-прежнему вся.
var _scroll := 0.0
## Цель прокрутки: колесо и флинг задают её, а _scroll догоняет плавно
## (автор 16.10.2026: «прокрутка жестами и колёсиком делается не плавно»).
## Палец в drag ведёт оба сразу — резинки под пальцем нет.
var _scroll_target := 0.0
## Скорость догона цели (1/с, экспонента с добегом): та же, что у текста
## в игре (18/с), — герои и список едут в одном темпе.
const MENU_SCROLL_CHASE := 18.0
## Добег: ближе — встаём ровно, иначе вечное микродрожание. Держим доли
## логического пикселя: при 0.5 край строки вставал под маску видимой
## полоской на плотных экранах.
const MENU_SCROLL_SNAP := 0.05
## Скорость пальца на отпускании (для флинга) — по последним движениям.
var _fling_v := 0.0
var _fling_last_y := 0.0
var _fling_last_t := 0
## Зайчик живёт в своей полосе слева от списка и прыгает на строку
## выделения (автор 15.10.2026: «не уменьшать кролика, отвести под него
## столбик и пусть прыгает от строки к строке»). Прежде он стоял у
## заголовка и наезжал на имя первого игрока.
var _bunny_from := 0.0
var _bunny_t := 1.0
## Длительность прыжка: быстро, за удар по стрелке (автор 15.10.2026:
## «в два раза медленнее, чем надо» — было 0.26 с).
const BUNNY_HOP_T := 0.13
## Сколько прошло с приземления: отпружинивание дотягивает форму
## (см. _bunny_sy). 99 — давно стоим, форма спокойная.
var _bunny_land := 99.0
const BUNNY_LAND_T := 0.16
var _drag_from := Vector2.ZERO
var _drag_scroll0 := 0.0
var _dragged := false
## Тап по листаемому списку ждёт отпускания (см. _input): иначе
## простой палец выбрал бы игрока, а жест — ещё и соседнего.
var _press_deferred := false
var _press_pos := Vector2.ZERO
## Сколько finger должен пройти, чтобы жест стал прокруткой, а не тапом.
const DRAG_MIN := 10.0
var input_active := false
var input_text := ""
## Флаг «все клавиши» для имени, которое прямо сейчас вводится (списка
## ещё нет — применять не к кому). При создании профиля переносится
## в него, затем сбрасывается.
var input_all_keys := false
## Esc запросил выход (тесты читают флаг: настоящий quit убил бы процесс).
var quit_requested := false
## Разрешить настоящий выход (тесты гасят, чтобы жить дальше).
var quit_enabled := true
## То же для строгой ё (колонка «Ё»): ждёт создания профиля.
var input_yo_strict := true
## Самообновление с GitHub: только по кнопке (никакой фоновой магии).
## Состояния: "" покой, "checking" проверка, "latest" всё свежее,
## "error" ошибка с текстом, "downloading" качаем. Модалка «Вышла X?»
## — флагом _upd_open (только Да/Нет, как подтверждение удаления).
var _upd: Updater = null
var _upd_state := ""
var _upd_msg := ""
## Прогресс закачки: процент (-1 — размер неизвестен) и сколько байт.
var _upd_pct := -1
var _upd_done := 0
var _upd_total := 0
var _upd_poll := 0.0
const UPD_POLL := 0.2
var _upd_tag := ""
var _upd_url := ""
var _upd_notes: Array[String] = []
var _upd_open := false
## Выбранная колонка флагов: 0 — «Про», 1 — «Ё». Стрелки ←/→ двигают,
## пробел переключает. Видна подсветкой заголовка.
var sel_col := 0
## Подсказка по заголовку колонки («pro»/«yo»): тап по заголовку
## объясняет, что за галка. Пусто — молчим.
var hint_header := ""
## Игрок, ради которого меню открыли: F2 возвращает в игру с ним.
var resume_user := ""
## Удаление на подтверждении: имя профиля, ждущего «Да». Пусто — модалки
## нет, меню живёт как обычно. Пока висит — весь остальной ввод глушим.
var confirm_name := ""
## Фокус кнопок модалки (0 — «Да», 1 — «Нет»): стрелки/Tab водят, Enter
## жмёт сфокусированную. По умолчанию «Да» — Enter удаляет, как раньше
## (жалоба автора 16.10.2026: было вообще не видно, где выделение).
var confirm_sel := 0
## Ховер-подсказки заголовков таблицы (автор 16.10.2026): стандартный
## тултип у курсора после короткой задержки. Тап-подсказка внизу при этом
## остаётся — на сенсоре ховера нет.
var _hover_pos := Vector2.ZERO
var _hover_t := 0.0
var _hover_scroll := 0.0
const HOVER_TIP_T := 0.5
var view_w := BASE_W
var view_h := BASE_H
var k := 1.0
## Своя клавиатура (модуль Kbd): видна, когда вводится имя, на сенсорных
## устройствах. Высоту считаем сами от view_h — игра свою высоту больше
## не ставит (у неё своя политика показа). Язык ввода держит kb_lang:
## ряды при этом не меняются (доска одна), меняется подсветка и ввод.
## Отступ от верха под вырез камеры (как в игре, см. Ui.top_inset).
var top_safe := 0.0
var kb_lang := "ru"
## Перелёт подписей при смене языка ввода (как в игре): старая буква
## уходит в угол, новая выходит в центр.
var kb_morph := 1.0
var kb_morph_from := ""
const KB_MORPH_T := 0.22
## Состояние шифта, из которого шёл перелёт.
var kb_morph_shift := false
## Клавиша под пальцем и сколько она ещё горит: человек должен видеть,
## что нажал ту самую клавишу (или промахнулся мимо всех).
var kb_press := ""
var kb_press_t := 0.0
## Вердикт вспышки: имя набирается верно → зелёный.
var kb_press_ok := true
## Клавиша, которую ДЕРЖАТ пальцем: шифт работает, пока его держат
## (автор 10.2026: «нажимаю — загорается, отпускаю — гаснет»).
var kb_held := ""
const KB_PRESS_T := 0.55
var kb_shift := false
var kb_key_sb: StyleBoxFlat
## Заливка нажатой клавиши (та же краска ночью).
var kb_press_sb: StyleBoxFlat
var kb_press_ok_sb: StyleBoxFlat
var kb_press_err_sb: StyleBoxFlat
## Ручной режим ночи из настроек: 0 день, 1 ночь, -1 авто (система).
## Кнопка крутит по кругу день → ночь → авто.
var nmode := -1
var mono: Font
## Оформление (только картинка): скруглённые чипсы под строками,
## рамка поля ввода и пилюля подсказки. Строки и тексты не меняются —
## их проверяют тесты, поэтому здесь лишь рамки вокруг тех же слов.
var row_sb: StyleBoxFlat
var row_idle_sb: StyleBoxFlat
var box_sb: StyleBoxFlat
## Своя клавиатура (модуль Kbd): клавиши прямо дают символы в поле
## ввода, без IME.
func _draw_own_kb() -> void:
	if not _own_shown():
		return
	Kbd.draw(
		self, _own_rect(), kb_lang, kb_shift, true, mono,
		int(30.0 * k), kb_key_sb, selbox_sb, _uitext(), [], null, _dim(),
		kb_morph, kb_morph_from, kb_morph_shift, _press_sb(), kb_press
	)


## Вспышка нажатой клавиши: человек должен видеть, что попал именно в неё
## (а если промахнулся — что не попал ни в одну). Гасится сама.
## Заливка вспышки с плавным затуханием: alpha падает вместе с таймером,
## последние кадры почти прозрачны, а в ноль подсветка гаснет совсем
## (автор 10.2026: «затухание не мгновенным»).
## Панели ДВА и создаются раз за жизнь: раньше здесь каждый кадр
## рождался новый StyleBoxFlat (ревизия 16.10.2026) — мусор в куче и
## лишняя работа на каждый кадр с видимой доской.
var _press_sb_fade_ok: StyleBoxFlat
var _press_sb_fade_err: StyleBoxFlat


func _press_sb() -> StyleBox:
	if _press_sb_fade_ok == null:
		_press_sb_fade_ok = Ui.panel_sb(Color(1, 1, 1, 0), 10.0, Ui.LINE_DAY, 2.5, false)
		_press_sb_fade_err = Ui.panel_sb(Color(1, 1, 1, 0), 10.0, Ui.LINE_DAY, 2.5, false)
	var src: StyleBoxFlat = kb_press_ok_sb if kb_press_ok else kb_press_err_sb
	var dst: StyleBoxFlat = _press_sb_fade_ok if kb_press_ok else _press_sb_fade_err
	var k: float = clampf(kb_press_t / KB_PRESS_T, 0.0, 1.0)
	var c := src.bg_color
	c.a *= k
	var b := src.border_color
	b.a *= k
	dst.bg_color = c
	dst.border_color = b
	return dst


func _flash(key: String, ok := true) -> void:
	kb_press = key
	kb_press_ok = ok
	kb_press_t = KB_PRESS_T
	queue_redraw()


## Отпускание удерживаемой клавиши (шифта): гасит и удержание, и вспышку.
func _release_held() -> void:
	if kb_held == "":
		return
	var was := kb_held
	kb_held = ""
	if was == "шифт":
		_set_kb_shift(false)
	if kb_press == was:
		kb_press = ""
		kb_press_t = 0.0
	queue_redraw()


func _own_press(pos: Vector2) -> bool:
	if not _own_shown() or not input_active:
		return false
	var act := Kbd.hit(_own_rect(), kb_shift, true, pos)
	if act == "":
		return false
	_flash(act)
	if act == "шифт":
		# Шифт держится пальцем, а не защёлкивается: второй палец в это
		# время жмёт букву (автор 10.2026: «нажимаю — загорается,
		# отпускаю — гаснет»). Kbd.hit отдаёт «шифт», не подпись.
		kb_held = "шифт"
		_set_kb_shift(true)
	if act == "стереть":
		input_text = input_text.left(maxi(0, input_text.length() - 1))
	elif act == "язык":
		# Глобус реально меняет язык ввода (см. игру): та же клавиша
		# даёт другую букву, подсветка перетекает.
		_set_kb_lang("en" if kb_lang == "ru" else "ru")
	elif act == "шифт":
		_set_kb_shift(true)
	elif act == "ввод":
		if editing >= 0:
			_commit_edit()
		else:
			_enter()
	elif act == "пробел":
		pass  # в имени пробелов не бывает
	else:
		# Шифт + клавиша — знак или заглавная, буква идёт на языке
		# ввода (та же клавиша в английском даёт латиницу).
		var ch := Kbd.press_out(act, kb_lang, kb_shift)
		# Через штатное выключение: знаки улетают обратно перелётом.
		_set_kb_shift(false)
		# Имя набирается верно — вспышка зелёная (автор 10.2026).
		_flash(act, true)
		if input_text.length() < S.MAX_NAME_LENGTH:
			input_text += ch if ch != "" else act
	queue_redraw()
	get_viewport().set_input_as_handled()
	return true


## Бокс выбранной стрелками галки: залит цветом вместо рамки.
var selbox_sb: StyleBoxFlat
var hint_sb: StyleBoxFlat
var list_frame_sb: StyleBoxFlat
## Панели чипов-флагов в карточке: своя заливка «включено» и ободок
## выделения (см. _ready и _card_chip).
var chip_on_sb: StyleBoxFlat
var chip_focus_sb: StyleBoxFlat
## Ночь (S.resolve_night: ручной выбор или система). Краски берутся
## из хелперов _ink/_uitext/_dim, панели мутируют в _apply_night.
var night := false
var _meadow: Meadow = null


func _ready() -> void:
	mono = load("res://fonts/DejaVuSansMono.ttf")
	if mono == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["monospace"])
		mono = fallback
	row_sb = Ui.panel_sb(Ui.SELECT_DAY, 12.0)
	row_idle_sb = Ui.panel_sb(Ui.ROW_IDLE_DAY, 12.0)
	box_sb = Ui.panel_sb(Ui.SURFACE_ALT_DAY, 10.0, Ui.LINE_DAY, 2.0, false)
	kb_key_sb = Ui.panel_sb(Ui.SURFACE_ALT_DAY, 10.0, Ui.LINE_DAY, 2.0, false)
	# Нажатая клавиша — заметная заливка: попал или промахнулся.
	kb_press_sb = Ui.panel_sb(Ui.PRESS_DAY, 10.0, Ui.LINE_DAY, 2.5, false)
	kb_press_ok_sb = Ui.panel_sb(Ui.OK_DAY, 10.0, Ui.OK_EDGE_DAY, 2.5, false)
	kb_press_err_sb = Ui.panel_sb(Ui.DANGER_DAY, 10.0, Ui.DANGER_EDGE_DAY, 2.5, false)
	selbox_sb = Ui.panel_sb(Ui.ACCENT_DAY, 10.0, Ui.ACCENT_EDGE_DAY, 2.0, false)
	hint_sb = Ui.panel_sb(Ui.PILL_DAY, 14.0, Ui.LINE_SOFT_DAY, 1.5, false)
	# Чип флага «включено»: своя зелёная заливка. Раньше включённый флаг
	# красился жёлтым row_sb — тем же, что фон выделенной строки, и на
	# выбранной карточке он тонул в выделении («выделение внутри
	# выделения», жалоба автора 16.10.2026), а ночью этот жёлтый стоял
	# пятном на тёмном фоне. Зелёный не совпадает ни с жёлтым
	# выделением, ни с пустой рамкой выключенного флага.
	chip_on_sb = Ui.panel_sb(Ui.ACCENT_DAY, 10.0, Ui.ACCENT_EDGE_DAY, 2.0, false)
	# Выделение колонки с клавиатуры — только ободок, заливку не трогает:
	# иначе фокус снова прятал состояние флага.
	chip_focus_sb = Ui.panel_sb(Color(0, 0, 0, 0), 10.0, Ui.FOCUS_DARK, 3.0, false)
	# Рамка списка — та же тихая обводка, что у пилюли-подсказки
	# (автор 16.10.2026: рамка должна быть скруглённой и неконтрастной,
	# в стиле остального интерфейса). Заливки нет, только контур.
	list_frame_sb = Ui.panel_sb(Color(0, 0, 0, 0), 12.0, Ui.LINE_SOFT_DAY, 1.5, false)
	_meadow = Meadow.new()
	add_child(_meadow)
	nmode = S.get_night_mode()
	_apply_night()
	get_tree().root.size_changed.connect(_relayout)
	_relayout()
	_reload()


func _relayout() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	view_w = s.x
	view_h = s.y
	_cols_cache = []  # вид изменился — колонки прежние (см. _table_cols)
	top_safe = Ui.top_inset(view_h)
	# Масштаб — от эффективной высоты (минус клавиатура), как в игре:
	# иначе в альбомной с клавиатурой блок меню не влезает над ней.
	# Пол на телефоне выше (0.7 против 0.5): пальцем по мелкому не попасть,
	# а читаться должно без лупы (жалоба автора 10.2026). Влезаемость
	# блока при поднятом поле проверяет profiles_test.
	# На сенсорных умножаем на плотность экрана: меню считает в физических
	# пикселях, а на телефоне они в 2–3 раза мельче — иначе весь интерфейс
	# в портрете мелкий (жалоба автора 10.2026). Десктоп не меняется.
	var kmin := 0.5 if Ui.is_desktop() else 0.7
	var want := minf(view_w / BASE_W, _menu_eff_h() / BASE_H) * Ui.dpr()
	# Пока правится имя, масштаб заморожен: выезжающая клавиатура иначе
	# ужимала бы ВЕСЬ список (автор 16.10.2026). Строка ввода подтягивается
	# в видимую часть, остальное — того же размера, низ уходит под маску.
	if editing < 0:
		k = _fit_k(clampf(want, kmin, 2.5), kmin)
	# Поворот экрана меняет окно списка — прокрутка поджимается под него.
	_scroll = _scroll_clamp(_scroll)
	_scroll_target = _scroll_clamp(_scroll_target)
	# Окно ужалось (поворот, клавиатура) — выбранное могло уйти из вида:
	# вернуть целиком в окно (автор 16.10.2026). Цель правит _start_edit
	# следом, если правится имя (там важнее строка ввода, а не sel).
	if not users.is_empty() and editing < 0:
		_scroll_to_sel()
	queue_redraw()


## Ужать k, чтобы влезли ШАПКА, пара карточек и низ (поле + кнопки):
## с поднятой плотностью контент растёт, а экран — нет. Число игроков
## на k больше не влияет: список листается (см. _list_max_scroll), раньше
## двенадцать карточек ужимали весь интерфейс до нечитаемого. Меряем теми
## же формулами, что и на экране: шапка + натуральная карточка + низ.
## Итераций четыре — низ зависит от k нелинейно (полы 64px), пары шагов
## может не хватить, а лишние стоят почти ноль. Ниже kmin не уходим.
func _fit_k(k0: float, kmin: float) -> float:
	var kk := k0
	for _i in 4:
		var need := top_safe + _bar_h_at(kk) + _list_need_at(kk) + _check_block_at(kk)
		if need <= _menu_eff_h() or kk <= kmin:
			break
		kk = maxf(kmin, kk * _menu_eff_h() / need)
	return kk


## Высота списка игроков при масштабе kk: в карточках — одна натуральная
## (дальше листятся, см. _list_max_scroll), в таблице — все строки, они
## не листятся и обязаны влезть.
func _list_need_at(kk: float) -> float:
	# Окно списка фиксировано: одна карточка / одна строка. Лишние игроки
	# уходят в прокрутку, а не ужимают шрифты и строки (автор 15.10.2026).
	if _cards():
		return _card_nat_at(kk)
	return _table_step_at(kk)


## Высота верхней панели при масштабе kk — тот же запас, что и на экране.
func _bar_h_at(kk: float) -> float:
	var gh: float = float(_font_h(40 if _cards() else FONT_TITLE))
	var h: float = maxf(_tap_h_at(44.0 * kk), gh * kk)
	return h + maxf(9.0 * kk, 6.0) * 2.0


## Высота низа меню (зазор + кнопки + отступ) при масштабе kk —
## _at-вариант, чтобы _fit_k ничего не выставлял в поля.
func _check_block_at(kk: float) -> float:
	return 20.0 * kk + _btn_h_at(kk) + _pad_at(14.0 * kk)


## Открыть меню поверх игры. Видимость и процесс — только здесь:
## скрытое меню глухо и слепо архитектурно (process выключен),
## а не только проверками visible.
func open(resume: String) -> void:
	resume_user = resume
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_apply_night()
	_reload()
	# Выделение — на игроке, под которым только что была игра (автор
	# 16.10.2026): за партию порядок «недавних» мог его сдвинуть, а sel
	# остался на старом месте. Нет в списке (гость) — стоим где стояли.
	var at := users.find(resume_user)
	if at >= 0:
		var was_target := _bunny_target_y()
		sel = at
		_scroll_to_sel()
		_bunny_jump(was_target)
	queue_redraw()


## Закрыть меню: скрыть и заглушить процесс до следующего open().
func close() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	queue_redraw()


## Перечитать список с диска и встать на разумную позицию.
func _reload() -> void:
	users = S.user_list()
	_cols_cache = []  # список пересобран — колонки прежние
	if sel >= users.size():
		sel = maxi(0, users.size() - 1)
	# Режим ночи — из настроек (кнопка могла его сменить, файл — тоже).
	nmode = S.get_night_mode()
	# Модалка список не переживает: ушли из меню через F2 посреди
	# подтверждения — при следующем открытии чистый список, а не
	# вчерашний вопрос. Так же и пояснение галки: это свойство того
	# экрана, на котором его показали.
	confirm_name = ""
	hint_header = ""
	# Пустой список — это первый запуск: сразу открыта строка создания
	# с полем. Иначе буквы уходят в никуда, и кажется, что игра не
	# реагирует. Именно СТРОКА (как и остальное создание), а не голое
	# input_active: поле рисуется в строке, и без строки набираемое имя
	# было не видно вообще (ловил 16.10.2026 на первом запуске).
	if users.is_empty():
		# Пустой список: единственная строка — создание. Если правилась
		# не она (список только что опустел), открываем её заново.
		if editing < 0 or not editing_new:
			_start_edit(0)
	elif editing >= 0:
		# Правка держится ровно на своей строке: создание — это строка с
		# номером users.size(), переименование — существующая. Всё прочее
		# (список пересобрали не из той строки, кто-то создал игрока в
		# обход меню) — висячая правка, её закрываем.
		var row_ok := editing < users.size()
		if editing_new:
			row_ok = editing == users.size()
		if not row_ok:
			_drop_edit()
	_scroll = _scroll_clamp(_scroll)
	_scroll_target = _scroll_clamp(_scroll_target)
	# Список пересобран — ховер под новым содержимым гасим.
	_hover_t = 0.0
	# Выбранная строка обязана быть целиком в окне (автор 16.10.2026):
	# содержимое сдвинулось, а она — нет.
	if not users.is_empty():
		_scroll_to_sel()
	# Список пересобран — зайчик встаёт на строку выделения без прыжка
	# и без отпружинивания.
	_bunny_t = 1.0
	_bunny_land = 99.0
	queue_redraw()



## Доска следует за раскладкой физической клавиатуры (см. игру).
func _follow_keyboard_lang(ch: String) -> void:
	if ch.length() != 1:
		return
	var lo := ch.to_lower()
	if lo == "ё" or (lo >= "а" and lo <= "я"):
		_set_kb_lang("ru")
	elif lo >= "a" and lo <= "z":
		_set_kb_lang("en")


## Смена языка ввода с перелётом подписей: старая центральная буква
## уходит в свой угол, нужная выходит из другого угла в центр.
## Щипок шифта: у знаков — перелёт, у букв перелёта нет (автор
## 10.2026: между большой и малой нет мягкого перехода). Проверка на
## букве живёт в Kbd.draw.
func _set_kb_shift(v: bool) -> void:
	if v == kb_shift:
		return
	kb_morph_from = kb_lang
	kb_morph_shift = kb_shift
	kb_morph = 0.0
	kb_shift = v
	queue_redraw()


func _set_kb_lang(lang: String) -> void:
	if lang == kb_lang:
		return
	kb_morph_from = kb_lang
	kb_morph_shift = kb_shift
	kb_morph = 0.0
	kb_lang = lang
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null:
		return
	if ke.keycode == KEY_SHIFT and not ke.pressed:
		_set_kb_shift(false)
		return
	# Удержание стрелок листает список (автор 16.10.2026): автоповтор (echo)
	# пропускаем только для навигации. Буквы, пробел и Enter по эху не
	# повторяем — иначе удержание печатало бы пачками и дёргало флаги.
	var nav_key := ke.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
		KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]
	if not ke.pressed or (ke.echo and not nav_key):
		return
	# Скрытое меню клавиш не видит: иначе оно перехватывает ввод раньше
	# игры (оно добавлено позже и получает _unhandled_key_input первым).
	# Без этого F2 во время игры не открывал меню, а молча перезапускал
	# гостя, буква Ф на русской раскладке (тот же keycode, что и A)
	# переключала «все клавиши», а Tab уводил буквы в невидимое поле.
	if not visible:
		return
	# Модалка подтверждения — только свои клавиши, остальное мимо:
	# стрелки/Tab водят фокус (видно заливкой), Enter жмёт сфокусированную,
	# Д — сразу «Да», Esc/N — «Нет». Д — та же физическая клавиша, что L
	# (раскладка не важна, смотрим keycode), N — KEY_N.
	if confirm_name != "":
		# В модалке повторов нет: зажатая стрелка не должна мельтешить
		# фокусом туда-сюда.
		if ke.echo:
			_eaten()
			return
		if (
			ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER
			or ke.unicode == 10 or ke.unicode == 13
		):
			# Enter — по фокусу, а не всегда «Да».
			if confirm_sel == 0:
				_confirm_delete()
			else:
				_cancel_confirm()
		elif ke.keycode == KEY_L:
			_confirm_delete()
		elif ke.keycode == KEY_ESCAPE or ke.keycode == KEY_N:
			_cancel_confirm()
		elif ke.keycode in [KEY_LEFT, KEY_RIGHT, KEY_TAB]:
			confirm_sel = 1 - confirm_sel
			queue_redraw()
		_eaten()
		return
	# Модалка обновления: Enter — «Скачать», Esc или N — «Не сейчас».
	# Раньше с клавиатуры был только Enter, а всё остальное съедалось:
	# на экране кнопка «Не сейчас» есть, с клавиш до неё не дойти, и
	# Esc уходил из ИГРЫ (жалоба автора: на десктопе и на эмуляторе с
	# внешней клавиатурой отказ от обновления был недостижим).
	if _upd_open:
		if ke.echo:
			_eaten()
			return
		if (
			ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER
			or ke.unicode == 10 or ke.unicode == 13
		):
			_upd_yes()
		elif ke.keycode == KEY_ESCAPE or ke.keycode == KEY_N:
			_upd_no()
		_eaten()
		return
	# Раскладку физической клавиатуры мы не угадываем по сочетанию:
	# переключатель у человека какой угодно. Следим за СОСТОЯНИЕМ —
	# пришла буква, значит система отдаёт этот алфавит (требование
	# автора 10.2026). Стоит раньше редактирования: язык доски должен
	# следовать и за буквами, набранными в поле имени.
	if ke.unicode > 0:
		_follow_keyboard_lang(String.chr(ke.unicode))
	# Строчное редактирование: Enter фиксирует, Esc отменяет. Навигацию
	# (стрелки, пробел, Tab, Delete, Insert, F2) глотаем, чтобы посреди
	# ввода не прыгали выделение и флаги. А буквы, цифры и Backspace
	# идут штатным путём ниже (input_active поднят): раньше ветка глотала
	# вообще всё, и с реальной клавиатуры в поле ничего не печаталось —
	# только с виртуальной (жалоба автора 16.10.2026).
	if editing >= 0:
		if (
			ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER
			or ke.unicode == 10 or ke.unicode == 13
		):
			_commit_edit()
			_eaten()
			return
		if ke.keycode == KEY_ESCAPE:
			_cancel_edit()
			_eaten()
			return
		if ke.keycode == KEY_F2:
			# Выход из ЛЮБОГО состояния (правило chaos-теста): правка
			# имени — не тупик, F2 отменяет её и возвращает в игру.
			_cancel_edit()
			chosen.emit(resume_user)
			_eaten()
			return
		if ke.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE,
				KEY_TAB, KEY_DELETE, KEY_INSERT]:
			_eaten()
			return
	# F2 — вернуться в игру тем же игроком, кого открыли меню.
	# Физический шифт — тоже шифт доски: состояние клавиш должно меняться
	# сразу, как его меняет щипок на самой доске (автор 10.2026: «нажатие
	# шифта должно сразу менять состояние клавиш»). Отпускание приходит
	# отдельным событием с pressed = false — его мы уже отсеяли выше.
	if ke.keycode == KEY_SHIFT:
		_set_kb_shift(ke.pressed)
		if not ke.pressed:
			kb_press = ""
			kb_press_t = 0.0
		return
	if ke.keycode == KEY_F2:
		chosen.emit(resume_user)
		_eaten()
		return
	if ke.keycode == KEY_UP:
		_nav(-1)
		_eaten()
		return
	if ke.keycode == KEY_DOWN:
		_nav(1)
		_eaten()
		return
	# Постранично и в края (автор 16.10.2026): страница — высота окна,
	# минимум строка; края без зацикливания, в отличие от стрелок.
	if ke.keycode == KEY_PAGEUP:
		_nav_page(-1)
		_eaten()
		return
	if ke.keycode == KEY_PAGEDOWN:
		_nav_page(1)
		_eaten()
		return
	if ke.keycode == KEY_HOME:
		_nav_to(0)
		_eaten()
		return
	if ke.keycode == KEY_END:
		_nav_to(users.size() - 1)
		_eaten()
		return
	# Стрелки ←/→ — выбор колонки флагов (Про/Ё), пробел — переключить
	# флаг у выбранной строки. В поле ввода пробел молчит (имени
	# с пробелами не бывает), модалку стрелки не трогают (она выше).
	if ke.keycode == KEY_LEFT:
		sel_col = (sel_col + 1) % 2
		queue_redraw()
		_eaten()
		return
	if ke.keycode == KEY_RIGHT:
		sel_col = (sel_col + 1) % 2
		queue_redraw()
		_eaten()
		return
	if ke.keycode == KEY_SPACE:
		_toggle_flag()
		_eaten()
		return
	if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER or ke.unicode == 10 or ke.unicode == 13:
		_enter()
		_eaten()
		return
	if ke.keycode == KEY_TAB:
		if users.is_empty():
			_start_edit(0)
		else:
			_start_edit(sel)
		_eaten()
		return
	# Insert — создать нового (клавиатурный путь к строке создания).
	if ke.keycode == KEY_INSERT:
		_start_edit(users.size())
		_eaten()
		return
	if ke.keycode == KEY_DELETE:
		_delete()
		_eaten()
		return
	if ke.keycode == KEY_ESCAPE:
		# Esc в меню — полный выход из игры (автор 10.2026: первое нажатие
		# уводит из кона в меню, повторное в меню — гасит игру).
		# Гость — только кнопкой «Без профиля».
		quit_requested = true
		if quit_enabled:
			get_tree().quit()
		_eaten()
		return
	# Стирание — одно простое: урезать имя на символ. Серий IME
	# (DEL + перепись региона) больше нет: ввод — только своей
	# клавиатурой (решение 10.2026).
	if ke.keycode == KEY_BACKSPACE or ke.unicode == 8:
		if not input_active:
			return
		input_text = input_text.left(maxi(0, input_text.length() - 1))
		queue_redraw()
		_eaten()
		return
	# Взрослый режим — только когда поле ввода неактивно, иначе это буква.
	if not input_active and _letter(ke) == "a":
		_toggle_all_keys()
		_eaten()
		return
	if not input_active or ke.unicode == 0:
		return
	var ch := String.chr(ke.unicode)
	# Пропускаем управляющие символы (меньше пробела) и пробелы: в имени
	# их быть не должно, а имя всё равно обрежется по краям.
	if ke.unicode < 32 or ch == " " or input_text.length() >= S.MAX_NAME_LENGTH:
		return
	input_text += ch

	queue_redraw()
	_eaten()
func _process(dt: float) -> void:
	if kb_morph < 1.0:
		kb_morph = minf(1.0, kb_morph + dt / KB_MORPH_T)
		queue_redraw()
	_bunny_advance(dt)
	# Заяц двигается каждый кадр полёта — рисуем кадр, иначе спрайт
	# замирает на первой позе прыжка до его окончания (баг ниской
	# частоты обновления спрайта, автор 16.10.2026).
	if _bunny_t < 1.0 or _bunny_land < BUNNY_LAND_T:
		queue_redraw()
	# Ховер-таймер: тикает, пока курсор стоит на месте. Прокрутка под
	# стоящим курсором — тоже движение: таймер сбрасываем, иначе пузырь
	# всплывёт над чужим заголовком.
	if _scroll != _hover_scroll:
		_hover_scroll = _scroll
		_hover_t = 0.0
	else:
		_hover_t = minf(_hover_t + dt, 10.0)
	# Плавная прокрутка: список догоняет цель (колесо, флинг, стрелки).
	# Экспонента с добегом — как скролл текста в игре.
	if _scroll != _scroll_target:
		var d := _scroll_target - _scroll
		var step := d * minf(1.0, MENU_SCROLL_CHASE * dt)
		if absf(d) <= MENU_SCROLL_SNAP:
			_scroll = _scroll_target
		else:
			_scroll += step
			if signf(step) != signf(_scroll_target - _scroll):
				_scroll = _scroll_target
		queue_redraw()
	# Долгое нажатие пальцем: стоит на строке дольше порога и не едет —
	# переименовываем (та же единая функция, что у ПКМ).
	if _press_down and not _dragged and not _press_fired:
		_press_t += dt
		if _press_t >= ROW_PRESS_T:
			_press_fired = true
			var ri := _row_at(_drag_from)
			if editing < 0 and ri >= 0 and ri < users.size() and _row_shown(ri):
				_start_edit(ri)
				get_viewport().set_input_as_handled()
	if kb_press_t > 0.0:
		kb_press_t = maxf(0.0, kb_press_t - dt)
		queue_redraw()
	elif kb_press != "":
		# Иначе заливка залипает нарисованной: последний кадр с таймером
		# уже отрисован, а следующего перерисовывания не будет (жалоба
		# автора 10.2026: «выделение остаётся даже после отпускания»).
		kb_press = ""
		kb_press_t = 0.0
		queue_redraw()
		queue_redraw()
	_poll_update()


## Клавиша обслужена меню: игре её не отдавать, иначе Backspace
## в поле имени заодно откатывал бы зайца, а A-переключатель —
## печатался. Остальное (F3, F11) меню не трогает — их разбирает игра.
func _eaten() -> void:
	get_viewport().set_input_as_handled()


## Тач и мышь: строки, поле, кнопки. Скрытое меню тычков не видит —
## тот же урок, что с клавишами.
## Пальцы на доске меню (правка имени). Тот же случай, что в игре:
## касание превращается в мышь только для первого пальца, поэтому
## «зажать шифт, нажать букву» не работало (см. _is_touch_echo).
var _touch_keys: Dictionary = {}
var _touch_pos := Vector2.ZERO
var _echo_pending := 0

const _TOUCH_ECHO_PX := 32.0


## Мышиное событие, порождённое касанием, приходит следом, в ту же
## точку. Одно касание даёт максимум одно такое эхо — считаем их
## парами, а НЕ по часам (см. одноимённое в игре).
func _touch_down_at(pos: Vector2, _finger: int) -> void:
	_touch_pos = pos
	_echo_pending += 1


func _is_touch_echo(pos: Vector2) -> bool:
	if _echo_pending <= 0 or pos.distance_to(_touch_pos) > _TOUCH_ECHO_PX:
		return false
	_echo_pending -= 1
	return true


## Отпускание указателя: и мыши, и пальца. finger — индекс пальца или
## -1 для мыши. Правила одни (см. старую ветку отпускания мыши): снять
## удержание, доиграть отложенный тап или бросок.
func _pointer_up(finger: int) -> void:
	if finger >= 0:
		_touch_up(finger)
	else:
		# Удерживаемый шифт гаснет (как на настоящей клавиатуре,
		# автор 10.2026).
		_release_held()
	var deferred := _press_deferred
	var was_drag := _dragged
	var was_long := _press_fired
	_press_deferred = false
	_dragged = false
	_press_down = false
	_press_fired = false
	if deferred and not was_drag and not was_long:
		_tap(_press_pos)
	elif was_drag and absf(_fling_v) > 240.0:
		# Бросок: список катится по инерции и плавно встаёт.
		# Палец вверх (v<0) — едем вниз по списку.
		_scroll_target = _scroll_clamp(_scroll - _fling_v * 0.12)
	_fling_v = 0.0
	if deferred or was_drag or was_long:
		get_viewport().set_input_as_handled()


## Палец отпущен — гасим ровно то, что держал этот палец.
func _touch_up(finger: int) -> void:
	_echo_pending = 0
	var act := String(_touch_keys.get(finger, ""))
	_touch_keys.erase(finger)
	if act == "" or kb_held != act:
		return
	kb_held = ""
	if act == "шифт":
		_set_kb_shift(false)
	if kb_press == act:
		kb_press = ""
		kb_press_t = 0.0
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Координаты тычка могут быть и отрицательными (узкое окно, край
	# экрана), поэтому признак «тычка не было» — отдельный флаг,
	# а не сентинел в координатах.
	# Касания слушаем САМИ, а не только мышь: Godot превращает в мышь
	# лишь первый палец, и «зажать шифт, нажать букву» вторым пальцем
	# не приходил вовсе (жалоба автора 17.10.2026). Мышиное эхо того
	# же касания отсекается (_is_touch_echo), поэтому двойного ввода
	# нет; на десктопе касаний не бывает вовсе.
	if event is InputEventScreenTouch:
		var tb := event as InputEventScreenTouch
		_touch_down_at(tb.position, tb.index)
		if tb.pressed:
			# Тот же путь, что у клика: палец один — работает и он.
			_hover_t = 0.0
			_scroll_target = _scroll
			if input_active:
				var tkey := Kbd.hit(_own_rect(), kb_shift, true, tb.position)
				if _own_press(tb.position):
					if tkey != "":
						_touch_keys[tb.index] = tkey
					return
			_press_deferred = _list_rect().has_point(tb.position)
			_press_down = _press_deferred
			_press_t = 0.0
			_press_fired = false
			_press_pos = tb.position
			_drag_from = tb.position
			_drag_scroll0 = _scroll
			_dragged = false
			_fling_v = 0.0
			if not _press_deferred:
				_tap(tb.position)
			return
		_pointer_up(tb.index)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _is_touch_echo(mb.position):
			return
		# Правая кнопка — переименовать строку под курсором (автор
		# 15.10.2026; долгое удержание пальцем — то же самое, см. _process).
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var ri := _row_at(mb.position)
			if editing < 0 and ri >= 0 and ri < users.size() and _row_shown(ri):
				_start_edit(ri)
				get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Клик — не ховер: пузырь подсказки прячем (таймер с нуля).
			_hover_t = 0.0
			# Дабл-клик по строке — играть (автор 16.10.2026): одинарный
			# только выделяет (см. _tap). Долгое удержание и drag при этом
			# не взводим — жест уже классифицирован.
			# Взялись за список — недолёт останавливаем: дальше ведёт
			# палец, а не инерция.
			_scroll_target = _scroll
			if mb.double_click:
				_press_deferred = false
				_press_down = false
				_drag_from = mb.position
				_drag_scroll0 = _scroll
				_dragged = false
				_tap_play(mb.position)
				return
			_drag_from = mb.position
			_drag_scroll0 = _scroll
			_dragged = false
			_fling_v = 0.0
			_fling_last_y = mb.position.y
			_fling_last_t = Time.get_ticks_msec()
			# Тап по СПИСКУ откладываем до отпускания — всегда, даже когда
			# список не листовится: иначе долгое удержание (переименование,
			# автор 15.10.2026) успело бы ещё и игру запустить, потому что
			# тап срабатывает по нажатию. По кнопкам и полю — сразу, там
			# долгое нажатие ничего не значит.
			_press_deferred = _list_rect().has_point(mb.position)
			_press_down = _press_deferred
			_press_t = 0.0
			_press_fired = false
			_press_pos = mb.position
			if not _press_deferred:
				_tap(mb.position)
			return
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_pointer_up(-1)
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Колесо задаёт ЦЕЛЬ, список догоняет плавно в _process.
			_hover_t = 0.0
			_scroll_target = _scroll_clamp(_scroll_target - 90.0 * k)
			queue_redraw()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_hover_t = 0.0
			_scroll_target = _scroll_clamp(_scroll_target + 90.0 * k)
			queue_redraw()
			return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			# Просто ведём мышью — ховер для тултипов заголовков.
			# С нажатой кнопкой это drag: таймер сбрасываем, иначе пузырь
			# всплывёт посреди жеста.
			_hover_pos = mm.position
			_hover_t = 0.0
			return
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var dy := mm.position.y - _drag_from.y
			if not _dragged and absf(dy) < DRAG_MIN:
				return
			_dragged = true
			# Список едет за пальцем 1:1, без отставания: цель и факт —
			# одно и то же. Скорость запоминаем для флинга на отпускании.
			_scroll = _scroll_clamp(_drag_scroll0 - dy)
			_scroll_target = _scroll
			var now := Time.get_ticks_msec()
			var dt := float(maxi(1, now - _fling_last_t)) / 1000.0
			_fling_v = (mm.position.y - _fling_last_y) / dt
			_fling_last_y = mm.position.y
			_fling_last_t = now
			queue_redraw()
			return


## Лисaется ли список сейчас: нужно для колеса мыши и для проверок
## (тесты меряют, что окно фиксировано, а лишнее ушло в прокрутку).
func _list_scrollable() -> bool:
	return _list_max_scroll() > 0.0


## Тап: прямоугольники — из тех же хелперов, что рисует _draw: единый
## источник геометрии, работает и без отрисовки (тесты headless).
func _tap(pos: Vector2) -> void:
	# Модалка — только свои две кнопки, остальное мимо.
	if confirm_name != "":
		if _confirm_yes_rect().has_point(pos):
			_confirm_delete()
			get_viewport().set_input_as_handled()
		elif _confirm_no_rect().has_point(pos):
			_cancel_confirm()
			get_viewport().set_input_as_handled()
		return
	# Модалка обновления — только свои две кнопки (удаление первее).
	if _upd_open:
		if _upd_yes_rect().has_point(pos):
			_upd_yes()
			get_viewport().set_input_as_handled()
		elif _upd_no_rect().has_point(pos):
			_upd_no()
			get_viewport().set_input_as_handled()
		return
	# Редактирование: сначала клавиатура, потом крестик отмены на своей
	# строке, потом — зафиксировать и проглотить (тап вне строки тоже
	# фиксирует:Esc есть только на железе).
	if editing >= 0:
		if _own_press(pos):
			return
		# Галки строки правки — свои: на них нарисован текущий флаг,
		# значит и переключаются они (иначе чипы декоративные: у
		# создаваемого профиля статистики нет, всё остальное в строке
		# занято полем ввода).
		if _pro_tap_rect(editing).has_point(pos):
			_toggle_pro(editing)
			get_viewport().set_input_as_handled()
			return
		if _yo_tap_rect(editing).has_point(pos):
			_toggle_yo(editing)
			get_viewport().set_input_as_handled()
			return
		if _del_tap_rect(editing).has_point(pos):
			_cancel_edit()
			get_viewport().set_input_as_handled()
			return
		_commit_edit()
		get_viewport().set_input_as_handled()
		return
	# Внутри строки сначала точечные цели (галочка, крестик), потом
	# сама строка: иначе тап по галке выделял бы этого игрока.
	# Строки за окном списка тапов не видят (как и глазом: их режет
	# маска): иначе высокие строки на тесном экране перехватывали бы
	# кнопки под списком (ловил тест: тап по «Без профиля» играл Петей).
	for i in _row_count():
		if not _row_shown(i):
			continue
		if _pro_tap_rect(i).has_point(pos):
			_toggle_pro(i)
			get_viewport().set_input_as_handled()
			return
		if _yo_tap_rect(i).has_point(pos):
			_toggle_yo(i)
			get_viewport().set_input_as_handled()
			return
		if _del_tap_rect(i).has_point(pos):
			confirm_name = users[i]
			confirm_sel = 0
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
	for i in _row_count():
		if not _row_shown(i):
			continue
		if _row_tap_rect(i).has_point(pos):
			# Одинарный тап — только выделить, и строку создания тоже
			# (автор 16.10.2026). Редактирует дабл-клик (см. _tap_play)
			# или Enter, играет — дабл-клик или Enter по игроку. Зайчик —
			# как при стрелках: прыжок от прежней цели (_nav).
			var was_target := _bunny_target_y()
			sel = i
			_scroll_to_sel()
			_bunny_jump(was_target)
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
	# Заголовки «Про»/«Ё» — подсказка, что за галка. Повторный тап гасит.
	if not users.is_empty() and _pro_head_rect().has_point(pos):
		hint_header = "" if hint_header == "pro" else "pro"
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if not users.is_empty() and _yo_head_rect().has_point(pos):
		hint_header = "" if hint_header == "yo" else "yo"
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	# Кнопка обновлений: проверить релизы на GitHub.
	if _upd_button_rect().has_point(pos):
		_upd_check()
		get_viewport().set_input_as_handled()
		return
	# Своя клавиатура: клавиши раньше остального (тап по клавише — ввод).
	if _own_press(pos):
		return
	# Нижняя левая кнопка — создать нового пользователя (автор 16.10.2026:
	# «Играть» убрана, запуск — дабл-клик или Enter по строке).
	if _new_tap_rect().has_point(pos):
		_start_edit(users.size())
		get_viewport().set_input_as_handled()
		return
	if _guest_tap_rect().has_point(pos):
		_guest()
		get_viewport().set_input_as_handled()
		return
	if _night_tap_rect().has_point(pos):
		_toggle_night()
		get_viewport().set_input_as_handled()
		return


func _letter(ke: InputEventKey) -> String:
	if ke.keycode == KEY_A:
		return "a"
	return ""


## Стрелки по списку игроков: выбранный обязан остаться в окне —
## иначе на длинном портретном списке он уезжает за край и стрелки
## перестают его показывать.
func _nav(direction: int) -> void:
	if users.is_empty():
		return
	# Создание — кнопкой «+ Новый игрок» / Insert: в обходе стрелками его
	# нет (постоянного пункта в списке нет, автор 16.10.2026).
	var was_target := _bunny_target_y()
	sel = (sel + direction + users.size()) % users.size()
	_scroll_to_sel()
	_bunny_jump(was_target)
	queue_redraw()



## Прыжок выделения на строку без зацикливания (PageUp/PageDown/Home/End):
## края держат, в отличие от круговых стрелок (см. _nav).
func _nav_to(i: int) -> void:
	if users.is_empty():
		return
	var was_target := _bunny_target_y()
	sel = clampi(i, 0, users.size() - 1)
	_scroll_to_sel()
	_bunny_jump(was_target)
	queue_redraw()


## Листание на страницу вверх/вниз: высота окна, минимум одна строка.
func _nav_page(dir: int) -> void:
	if users.is_empty():
		return
	var page := maxi(1, int(_list_rect().size.y / maxf(1.0, _row_step())))
	_nav_to(sel + dir * page)


## Дабл-клик по строке — играть этим пользователем (автор 16.10.2026:
## одинарный тап только выделяет). Создание — кнопкой «+ Новый игрок»
## внизу, дабл сюда не ведёт. Мимо строк и по скрытым (за маской) — ничего.
func _tap_play(pos: Vector2) -> void:
	if editing >= 0 or confirm_name != "" or _upd_open:
		return
	for i in users.size():
		if not _row_shown(i):
			continue
		if _row_tap_rect(i).has_point(pos):
			sel = i
			chosen.emit(users[i])
			get_viewport().set_input_as_handled()
			return


## Переключателя ввода больше нет (Tab правит выбранного, см. выше).


func _enter() -> void:
	# Enter в редактировании фиксирует строкой (см. разбор клавиш выше),
	# сюда доходит только игра выбранным. Создание — кнопкой «+ Новый
	# игрок» / Insert, Enter всегда играет.
	if not users.is_empty():
		chosen.emit(users[sel])
		return
	# Список пуст — единственный выход, гость.
	_guest()


func _delete() -> void:
	if editing >= 0 or input_active or users.is_empty():
		return
	# Удаление непоправимо — только через подтверждение.
	confirm_name = users[sel]
	confirm_sel = 0
	queue_redraw()


## Подтверждено: снести и вернуться в список.
func _confirm_delete() -> void:
	if confirm_name != "":
		S.delete_user(confirm_name)
	confirm_name = ""
	_reload()


## Отмена: профиль цел, модалка гаснет.
func _cancel_confirm() -> void:
	confirm_name = ""
	queue_redraw()


## Ленивый узел проверки обновлений + сигналы в состояние меню.
func _upd_ensure() -> void:
	if _upd != null:
		return
	_upd = Updater.new()
	add_child(_upd)
	_upd.checked.connect(_on_upd_checked)
	_upd.failed.connect(_on_upd_failed)
	_upd.downloaded.connect(_on_upd_downloaded)
	_upd.progress.connect(_on_upd_progress)


## Кнопка «Обновления»: спросить GitHub.
func _upd_check() -> void:
	_upd_ensure()
	_upd_state = "checking"
	_upd_msg = ""
	_upd_open = false
	queue_redraw()
	_upd.check()


func _on_upd_checked(has: bool, tag: String, notes: String, _url: String) -> void:
	if has:
		_upd_tag = tag
		_upd_notes.clear()
		for ln in notes.split("\n"):
			_upd_notes.append(ln)
		_upd_state = ""
		_upd_msg = ""
		_upd_open = true
	else:
		_upd_state = "latest"
		_upd_msg = ""
		_upd_open = false
	queue_redraw()


func _on_upd_failed(what: String) -> void:
	_upd_state = "error"
	_upd_msg = what
	_upd_open = false
	queue_redraw()


## «Скачать»: качаем, дальше — дело платформы (см. update.gd).
func _upd_yes() -> void:
	# Повторное нажатие во время закачки: второй запрос сбивал первый
	# (жалоба автора 10.2026 — «сбоит, если нажать в процессе закачки»).
	# Пока качаем — просто не начинаем заново.
	if _upd.downloading():
		_upd_open = false
		_upd_state = "downloading"
		queue_redraw()
		return
	_upd_open = false
	_upd_state = "downloading"
	_upd_pct = -1
	_upd_done = 0
	_upd_total = 0
	_upd_msg = ""
	queue_redraw()
	_upd.download()


## «Позже»: модалка гаснет, проверка сброшена. Если закачка УЖЕ идёт —
## её отменяем: иначе файл докачается, и через полминуты системный
## установщик вылезет поверх игры, хотя человек от обновления отказался
## (проба 10.2026).
func _upd_no() -> void:
	_upd.cancel()
	_upd_open = false
	_upd_state = ""
	_upd_msg = ""
	queue_redraw()


## Прогресс закачки: процент и «скачано из». Видно, что дело идёт
## (жалоба автора 10.2026: «было бы здорово видеть прогресс»).
func _on_upd_progress(done: int, total: int, percent: int) -> void:
	_upd_done = done
	_upd_total = total
	_upd_pct = percent
	queue_redraw()


## Опрос прогресса, пока идёт закачка: HTTPRequest сам событий
## прогресса не шлёт.
func _poll_update() -> void:
	# Пока проверка или закачка идут — кадр живёт (волна/заливка в самой
	# кнопке, см. _draw_upd_button).
	if _upd_state == "checking" or (_upd_state == "downloading" and _upd != null and _upd.downloading()):
		queue_redraw()
	if _upd_state != "downloading" or not _upd.downloading():
		return
	_upd_poll += get_process_delta_time()
	if _upd_poll < UPD_POLL:
		return
	_upd_poll = 0.0
	var total := _upd.total_bytes()
	var done := _upd.done_bytes()
	var pct := -1
	if total > 0:
		pct = clampi(int(float(done) * 100.0 / float(total)), 0, 100)
	_on_upd_progress(done, total, pct)


func _on_upd_downloaded(path: String) -> void:
	if path == "":
		# Android: файл качает браузер в Загрузки — сам он не установится
		# (системе запрещено ставить APK молча). Говорим, что делать:
		# иначе игрок ждёт, а установка «не запускается» (жалоба 10.2026).
		_upd_state = ""
		_upd_msg = "Файл в Загрузках: откройте его и нажмите «Установить»"
		_upd_open = false
		queue_redraw()
		return
	# Платформа забрала файл (установщик / перезапуск): меню молчит.
	_upd_state = ""
	_upd_msg = ""
	_upd_open = false
	queue_redraw()


## Переключить клавиатуру: системная вместо своей (и назад).
## Своя высота пересчитается релэутом (клавиатура показалась/скрылась).
func _toggle_all_keys() -> void:
	if users.is_empty():
		# Пустой список (первый запуск): переключаем флаг для вводимого
		# имени — при создании он переедет в профиль (см. _enter).
		input_all_keys = not input_all_keys
		queue_redraw()
		return
	var name := users[sel]
	S.set_all_keys(name, not S.get_all_keys(name))
	_reload()


## Про-режим строке: все клавиши сразу именно этому игроку.
func _toggle_pro(i: int) -> void:
	if i == users.size() and editing_new:
		input_all_keys = not input_all_keys
		hint_header = "pro" if _cards() else hint_header
		queue_redraw()
		return
	if i < 0 or i >= users.size():
		return
	var name := users[i]
	S.set_all_keys(name, not S.get_all_keys(name))
	_reload()
	# Пояснение — ПОСЛЕ перезагрузки: та чистит подсказку (свойство
	# прошлого экрана), а в карточках её больше негде взять.
	if _cards():
		hint_header = "pro"
	# Пилюля ужала окно — выбранное могло уйти под маску: вернуть в вид.
	_scroll_to_sel()


## Строгая ё строке: различать ё и е именно этому игроку.
func _toggle_yo(i: int) -> void:
	if i == users.size() and editing_new:
		input_yo_strict = not input_yo_strict
		hint_header = "yo" if _cards() else hint_header
		queue_redraw()
		return
	if i < 0 or i >= users.size():
		return
	var name := users[i]
	S.set_yo_strict(name, not S.get_yo_strict(name))
	_reload()
	# Пояснение — ПОСЛЕ перезагрузки: та чистит подсказку (свойство
	# прошлого экрана), а в карточках её больше негде взять.
	if _cards():
		hint_header = "yo"
	# Пилюля ужала окно — выбранное могло уйти под маску: вернуть в вид.
	_scroll_to_sel()


## Пробел по флагам: выбранная стрелками колонка (sel_col) у выбранной
## строки — или у вводимого имени, если список пуст.
func _toggle_flag() -> void:
	if input_active or confirm_name != "":
		return
	if users.is_empty():
		if sel_col == 0:
			input_all_keys = not input_all_keys
		else:
			input_yo_strict = not input_yo_strict
		queue_redraw()
		return
	if sel_col == 0:
		_toggle_pro(sel)
	else:
		_toggle_yo(sel)


func _guest() -> void:
	S.set_last_user(S.GUEST)
	chosen.emit(S.GUEST)


## Ячейки строки таблицы: уровень и счёт «побед из игр». Шапка
## объясняет колонки, поэтому в ячейках только цифры.
func _cell_texts(name: String) -> Array[String]:
	var p := S.load_profile(name)
	var res: Array[String] = [
		"ур.%d" % int(p.get("difficulty", 0)),
		"%d/%d" % [int(p.get("total_wins", 0)), int(p.get("total_games", 0))],
	]
	return res


## Колонки таблицы [имя, уровень, счёт, Про, Ё, ✕]: левые края
## и правый край. Имя занимает остаток (длинные режем с многоточием),
## остальные — по самой широкой ячейке. Та же геометрия у отрисовки,
## хит-теста и тестов: мимо не бьёт.
##
## Результат КЭШИРУЕТСЯ на кадр данных (сброс — _reload/_relayout/
## _apply_night). Считать его — обойти всех игроков с load_profile и
## замерами текста, а зовут его сотни раз за кадр: из каждой строки,
## каждой галки, каждого замера имени (автор 16.10.2026, ревизия
## производительности). Один пересчёт на кадр вместо сотен.
func _table_cols() -> Array[float]:
	# Ключ (вид/масштаб/состав) — плюс явный сброс в _reload на новые
	# тексты ячеек: статистика игрока меняется при игре, а размер
	# списка может остаться прежним.
	if (
		not _cols_cache.is_empty()
		and _cw == view_w and _ck == k and _cn == users.size()
	):
		return _cols_cache
	_cols_cache = _table_cols_now()
	_cw = view_w
	_ck = k
	_cn = users.size()
	return _cols_cache


func _table_cols_now() -> Array[float]:
	var left := 48.0 * k
	# Полоса зайчика — и в таблице: он прыгает по строкам в обеих
	# раскладках списка. Её вычитаем ИЗ ДОСТУПНОЙ ШИРИНЫ, а не сдвигаем
	# левый край: на узком окне (тест жмёт view_w до 64) сдвиг уводил
	# колонки за экран и ширину крестика делал отрицательной.
	var strip := _bunny_strip()
	var right := view_w - 48.0 * k
	# Зазор между колонками: имя важнее воздуха, но и слипаться тексту
	# нельзя (ловил кадр таблицы: «Маруся ур.00/0» — зазор 7k впритык).
	var gap := maxf(14.0 * k, 10.0)
	# Колонки-галочки: не уже пальцевых 64, иначе их не нажать,
	# и визуально галочка сливается с заголовком.
	var col_min := 44.0 * k if Ui.is_desktop() else 64.0
	var del_w := maxf(36.0 * k, col_min)
	var pro_w := maxf(_text_size("Про", FONT_SMALL).x + 28.0 * k, col_min)
	var yo_w := maxf(_text_size("Ё", FONT_SMALL).x + 28.0 * k, col_min)
	var lvl_w := _text_size("Ур", FONT_SMALL).x + 10.0 * k
	var rec_w := _text_size("Победы", FONT_SMALL).x + 10.0 * k
	for u in users:
		var cells := _cell_texts(u)
		lvl_w = maxf(lvl_w, _text_size(cells[0], FONT_ROW).x + 16.0 * k)
		rec_w = maxf(rec_w, _text_size(cells[1], FONT_ROW).x + 16.0 * k)
	# Ширина имени: всё лишнее забирает себе (имя главное в таблице).
	# Если при полных колонках-галочках места не хватает (узкий экран,
	# мелкий k) — сжимаем их, но имя ниже минимума не отдаём: иначе
	# таблица разъезжается, крестик уезжает за край, а любое имя
	# режется в многоточие (проверено тестами на k=0.5 и 412px).
	var avail := maxf(0.0, right - left - strip)
	# Имя получает не только минимум, но и столько, сколько нужно самому
	# длинному имени + воздух с обеих сторон: иначе на широком окне (где
	# масштаб растёт от высоты) колонки сжимаются и текст слипается.
	var min_name := maxf(80.0 * k, _table_name_need() + gap)
	var flag_want := lvl_w + rec_w + pro_w + yo_w + del_w + gap * 5.0
	var name_w := maxf(min_name, avail - flag_want)
	if name_w + flag_want > avail:
		# Совсем тесно (тест жмёт view_w до 64): резервируем имени часть
		# ширины и жмём остальное, иначе колонки уезжают за правый край
		# и их ширина становится отрицательной.
		var name_reserve := minf(min_name, avail * 0.4)
		var squeeze := clampf((avail - name_reserve) / flag_want, 0.0, 1.0)
		pro_w *= squeeze
		yo_w *= squeeze
		del_w *= squeeze
		lvl_w *= squeeze
		rec_w *= squeeze
		gap *= squeeze
		name_w = maxf(0.0, avail - (lvl_w + rec_w + pro_w + yo_w + del_w + gap * 5.0))
	var name_x := left + strip
	var lvl_x := name_x + name_w + gap
	var rec_x := lvl_x + lvl_w + gap
	var pro_x := rec_x + rec_w + gap
	var yo_x := pro_x + pro_w + gap
	var del_x := yo_x + yo_w + gap
	var cols: Array[float] = [name_x, lvl_x, rec_x, pro_x, yo_x, del_x, right]
	return cols


## Ширина самого длинного имени при полном кегле + отступ от края
## бокса. Имя — приоритет №1 в таблице (автор 15.10.2026), ему эта
## ширина достаётся первой, остальные колонки ужимаются (см. _table_cols).
func _table_name_need() -> float:
	var need := 0.0
	for u in users:
		need = maxf(need, _text_size_fs(u, int(FONT_ROW * k)).x)
	return need + 8.0 * k


## Кегль ячеек «Ур» и «счёт»: ужимается под СВОЮ полосу, а не только
## колонки. Колонки при нехватке места сжимаются (см. _table_cols), а
## текст остаёк полного кегля — и наезжал на соседний столбец (кадр
## таблицы 1000x700: кегль 54 в полосе 130, «ур.0 0/0» слипалось).
## Пол 60% — ниже ячейка уже не читается.
func _table_cell_fs() -> int:
	var cols := _table_cols()
	var bands := [
		cols[2] - cols[1] - 14.0 * k, cols[3] - cols[2] - 14.0 * k
	]
	var fs := int(FONT_ROW * k)
	var low := maxi(10, int(float(fs) * 0.6))
	for u in users:
		var cells := _cell_texts(u)
		while fs > low and (
			_text_size_fs(cells[0], fs).x > bands[0]
			or _text_size_fs(cells[1], fs).x > bands[1]
		):
			fs -= 2
	return fs


## Кегль шапки таблицы: тот же смысл, что у ячеек — подписи столбцов не
## должны наезжать на следующий заголовок, а колонки на узком экране
## сжаты (см. _table_cols).
func _table_head_fs() -> int:
	var cols := _table_cols()
	var bands := [
		cols[1] - cols[0] - 14.0 * k, cols[2] - cols[1] - 14.0 * k,
		cols[3] - cols[2] - 14.0 * k,
	]
	var fs := int(FONT_SMALL * k)
	var low := maxi(9, int(float(fs) * 0.7))
	for i in 3:
		while fs > low and _text_size_fs(_head_label(i), fs).x > bands[i]:
			fs -= 1
	return fs


## Подпись столбца шапки по индексу: 0 имя, 1 уровень, 2 победы.
func _head_label(i: int) -> String:
	if i == 0:
		return "Имя"
	if i == 1:
		return "Ур"
	return "Победы"


## Все имена влезают целиком (без многоточия) — для ужатия масштаба
## под таблицу (см. _relayout).
func _names_fit() -> bool:
	for u in users:
		if _short_name(u) != u:
			return false
	return true


## Имя игрока для показа: в карточках — во всю ширину карточки (кнопки
## лежат на своём ряду ниже, подрезать имя не о чем), в таблице — по
## ширине своей колонки. Обрезка многоточием: чужая длинная строка из
## changelog иначе вылезает за карточку.
func _short_name(name: String) -> String:
	if _cards():
		return _clip_fs(name, _card_name_fs(name), _card_name_cap())
	var cols := _table_cols()
	return _clip_fs(name, _table_name_fs(name), cols[1] - cols[0] - 14.0 * k)


## Кегль имени в таблице: как в карточке — ужимается под ширину колонки,
## а не режется (пол 60%). Многоточие — только если не влезло и так.
func _table_name_fs(name: String) -> int:
	var cols := _table_cols()
	var cap := cols[1] - cols[0] - 14.0 * k
	var full := int(FONT_ROW * k)
	var fs := full
	while fs > int(float(full) * 0.6) and _text_size_fs(name, fs).x > cap:
		fs -= 2
	return fs



## Ширина под имя в карточке: карточка минус поля.
func _card_name_cap() -> float:
	return _card_rect(0).size.x - _CARD_IN * k * 2.0


## Кегль имени в карточке: ужимается под ширину, чтобы длинное имя
## осталось ЦЕЛЫМ. Имя игрока — главное в карточке, обрезать его многоточием
## нельзя (жалоба автора 10.2026: в портрете имя уходило в многоточие из
## двух букв). Потолок ужимания — 60% от карточного кегля.
func _card_name_fs(name: String) -> int:
	var full := _card_fs(FONT_CARD_NAME)
	var cap := _card_name_cap()
	var fs := full
	while fs > int(float(full) * 0.6) and _text_size_fs(name, fs).x > cap:
		fs -= 2
	return fs


## Обрезать строку по ширине, с многоточием. Нужна для чужих строк
## (длинная ссылка из changelog иначе вылезает за карточку) и для
## имени профиля. fs-вариант — когда кегль уже посчитан (карточка).
func _clip(txt: String, size_px: int, cap: float) -> String:
	return _clip_fs(txt, int(float(size_px) * k), cap)


func _clip_fs(txt: String, fs: int, cap: float) -> String:
	if _text_size_fs(txt, fs).x <= cap:
		return txt
	var out := txt
	while out.length() > 1 and _text_size_fs(out + "…", fs).x > cap:
		out = out.left(out.length() - 1)
	return out + "…"



func _text_size(txt: String, size_px: int) -> Vector2:
	# Тот же кегль, что в _text: иначе рамки вокруг строк (чипсы,
	# пилюля подсказки) меряются в одном масштабе, а рисуются в другом.
	return _text_size_fs(txt, int(float(size_px) * k))


## Высота строки кеглем fs. До _ready шрифта нет (см. _text_size_fs) —
## отдаём сам кегль: для зажимов и панели хватает, после _ready всё
## пересчитывается по-настоящему.
func _font_h(fs: int) -> int:
	if mono == null:
		return maxi(fs, 1)
	return mono.get_height(fs)


func _text_size_fs(txt: String, fs: int) -> Vector2:
	# До _ready шрифта нет (open зовут и до входа в дерево — там прямой
	# add_child невозможен, см. _open_menu): отдаём грубую оценку, её
	# хватает для зажимов прокрутки, а после _ready всё пересчитывается.
	if mono == null:
		return Vector2(float(txt.length()) * float(fs) * 0.6, float(fs))
	return Ui.text_size(mono, txt, fs)


func _text(txt: String, pos: Vector2, size_px: int, col: Color) -> void:
	_text_fs(txt, pos, int(float(size_px) * k), col)


## Тот же _text, но кегль уже посчитан (в карточках он множится ещё и на
## рост карточки — см. _card_fs). Замер обязан брать тот же кегль, иначе
## рамки чипов и подписи разъезжаются.
func _text_fs(txt: String, pos: Vector2, fs: int, col: Color) -> void:
	draw_string(
		mono, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col
	)


## Текст строчного редактора: имя плюс курсор.


## Базовая строка меню: заголовок + строки. Дальше всё считается от неё.
## В портрете блок опускаем, чтобы не кучковался сверху (низ пустой);
## альбом не трогаем. Тапы идут через те же хелперы — мимо не бьют.
## Центрирование — от эффективной высоты (минус клавиатура): иначе
## на телефоне с выездом клавиатуры блок остаётся под ней.
func _menu_eff_h() -> float:
	return Ui.eff_h(view_h, _own_h())


## Своя клавиатура в меню: видна, когда вводится имя. Высоту для
## раскладки считаем от неё же.
func _own_shown() -> bool:
	if not visible:
		return false
	if not input_active:
		return false
	return true


## Область своей клавиатуры: низ экрана.
func _own_rect() -> Rect2:
	# Как в игре: доска занимает не больше 46% высоты, иначе на низком
	# экране она накрывает кнопки (регрессия 10.2026: доска стала выше —
	# единиц в самом широком ряду стало 15 вместо 16 — и накрыла кнопку
	# «Играть», тап уходил в клавишу).
	var m := 16.0 + Ui.bottom_inset(view_h)
	var max_h: float = maxf(160.0, (view_h - m) * 0.46)
	var w := view_w - 32.0
	var h := Kbd.height_for(w)
	if h > max_h:
		w = clampf(Kbd.width_for(max_h), 240.0, view_w - 32.0)
		h = minf(Kbd.height_for(w), max_h)
	# Низ экрана со скруглениями и жестом: клавиатуру поднимаем на
	# безопасный отступ, иначе угловые клавиши обрезаны (жалоба 10.2026).
	return Rect2((view_w - w) * 0.5, view_h - h - m, w, h)


func _own_h() -> float:
	if not _own_shown():
		return 0.0
	return _own_rect().size.y


func _rows_top() -> float:
	# Весь блок едет вниз под вырез камеры (top_safe): строки, поле
	# и кнопки — вместе, иначе шапка уедет, а поле останется под камерой.
	# Портрет: список начинается сразу под заголовком и тянется до поля
	# ввода — пустоты снизу больше нет (раньше блок «центрировался» и при
	# двух игроках висел сверху, кадр «01-cards» визуального прогона).
	# Под верхней панелью; в таблице ещё и шапки колонок (они рисуются
	# на 44k выше первой строки).
	# Портрет: под панелью сразу список (+14k воздуха до первой карточки).
	# Таблица: сначала шапка колонок — ей нужно место и под заголовком,
	# и над строками (тесноту ловил аудит 15.10.2026: заголовок на шапке,
	# шапка на строках).
	if _cards():
		return top_safe + _bar_h() + 14.0 * k
	return top_safe + _bar_h() + 90.0 * k


## Окно списка игроков: между шапкой и полем ввода. Здесь карточки
## растут на всю высоту, а когда не влезают — список листается.
## Полная высота содержимого списка: строки плюс строка создания.
## Отдельная функция, а не n × шаг: цепочка окно↔кнопки обязана идти в
## одну сторону, иначе бесконечная рекурсия (ловил сторож:
## «Stack overflow … _pad»).
## Сколько строк в списке: игроки плюс строка ввода имени, но только пока
## идёт создание (постоянного пункта «создать» в списке нет, автор
## 16.10.2026: создание — кнопкой «+ Новый игрок» внизу). Строка ввода
## листается вместе со всеми.
func _row_count() -> int:
	return users.size() + (1 if editing_new else 0)


func _list_all_h() -> float:
	# Высота — НАСТОЯЩАЯ: n карточек и n−1 зазоров (зазор после последней
	# карточки не занимает экран; раньше считался — список «не влезал»
	# на ровно один зазор и лишний раз уезжал вниз).
	var n := maxi(_row_count(), 1)
	if _cards():
		return float(n) * _card_nat() + float(n - 1) * _CARD_GAP * _card_k() + _list_end_pad()
	return float(n) * _table_step_at(k) + _list_end_pad()


## Воздух под последним пунктом внутри окна: низ списка не стоит ровно
## на краю окна — иначе край карточки упирается в границу маски и
## визуально режется (автор 16.10.2026). Едет вместе со всем содержимым
## (см. _list_max_scroll), на центровку короткого списка не влияет
## заметно (половина запаса сверху).
func _list_end_pad() -> float:
	return maxf(6.0, 8.0 * k)





## Окно списка — и в карточках, и в таблице: от шапки колонок (или от
## верхней панели) до поля ввода. Что не влезло — листятся; низ экрана
## при этом на месте (см. _buttons_y).
func _list_rect() -> Rect2:
	# Кэш по входным данным. Считать окно дорого: внутри — замер текста
	# пилюли, а сама функция зовётся десятки раз за кадр (из каждой
	# строки, каждой кнопки, каждого хит-теста) — ревизия 16.10.2026.
	# Ключ, а не флаг: тесты и поворот экрана пишут view_w/view_h/k
	# напрямую, и такой кэш не может отдать чужую геометрию.
	if (
		_lr_ok and _lr_w == view_w and _lr_h == view_h and _lr_k == k
		and _lr_n == users.size() and _lr_ed == editing
		and _lr_hint == hint_header and _lr_safe == top_safe
		and _lr_act == input_active
	):
		return _lr_val
	_lr_val = _list_rect_now()
	_lr_w = view_w
	_lr_h = view_h
	_lr_k = k
	_lr_n = users.size()
	_lr_ed = editing
	_lr_hint = hint_header
	_lr_safe = top_safe
	_lr_act = input_active
	_lr_ok = true
	return _lr_val


func _list_rect_now() -> Rect2:
	# Верх окна — реальный верх первой строки. В таблице строка
	# центрируется на _rows_top, а её бокс начинается на 38k выше
	# (_row_tap_rect), и без этого запаса первая строка уезжала под
	# шапку колонок, а её галка ложилась прямо на «Про» (экран автора
	# 3120x2080). В карточках бокс начинается ровно на _rows_top.
	var top := _rows_top() - _row_box_lead()
	# До кнопок — с запасом: отдельного поля ввода внизу больше нет, имя
	# правится прямо в строке (автор 15.10.2026). Под пилюлю с пояснением
	# галки места резервируем: иначе она ложилась на строку снизу.
	var bottom := _buttons_y() - 20.0 * k - _hint_reserve_h()
	var one: float = _card_nat() if _cards() else _table_step_at(k)
	return Rect2(
		_list_left(), top,
		view_w - _list_left() - _edge(),
		maxf(one, bottom - top)
	)


## Насколько бокс строки заходит выше _rows_top: в таблице строка
## центрируется на нём (см. _row_tap_rect), в карточке — начинается там.
func _row_box_lead() -> float:
	if _cards():
		return 0.0
	return 38.0 * k


## Верх списка с поправкой на пустоту: когда все карточки влезли, они
## стоят по центру окна (списком сверху с дырой снизу выглядит
## недоделанно), а при прокрутке — от самого верха окна.
func _list_top() -> float:
	var free := _list_rect().size.y - _list_all_h()
	return _rows_top() + maxf(0.0, free * 0.5)


## Насколько список длиннее окна: столько можно пролистать. Считаем по
## настоящей высоте содержимого (_list_all_h — со строкой создания),
## иначе строка «Создать нового пользователя» не листовилась вовсе.
func _list_max_scroll() -> float:
	return maxf(0.0, _list_all_h() - _list_rect().size.y)


## Границы прокрутки, держащие строку фокуса целиком в окне (автор
## 16.10.2026: выбранное всегда полностью видимо). Фокус — строка ввода,
## пока правится имя, иначе выбранная. Обычные [0, max] плюс требование
## «строка в окне» — пересечение. Колесо, drag и флинг дальше не уходят:
## список стоит, а не отпускает выбранное за край.
func _focus_scroll_bounds() -> Vector2:
	var max_sc := _list_max_scroll()
	if users.is_empty():
		return Vector2(0.0, max_sc)
	var focus := editing if editing >= 0 else sel
	focus = clampi(focus, 0, _row_count() - 1)
	var view := _list_rect()
	# Бокс при нулевой прокрутке: видимость — это сдвиг sc, при котором
	# бокс целиком внутри окна. Меряем бокс, а не линию (см. _row_box_at):
	# иначе якорь разрешал прятать верх бокса под маской.
	var b0 := _row_box_at(focus, 0.0)
	var lo := maxf(0.0, b0.position.y + b0.size.y - view.end.y)
	var hi := minf(max_sc, b0.position.y - view.position.y)
	if lo > hi:
		# Строка выше окна целиком (карточка с клавиатурой): держим её
		# верх, как _scroll_to_idx.
		lo = clampf(b0.position.y - view.position.y, 0.0, max_sc)
		hi = lo
	return Vector2(lo, hi)


func _scroll_clamp(v: float) -> float:
	var b := _focus_scroll_bounds()
	return clampf(v, b.x, b.y)


## Держать выбранного игрока в окне (стрелки на клавиатуре, Enter).
func _scroll_to_sel() -> void:
	_scroll_to_idx(sel)


## Строка с индексом в окно (включая строку ввода при создании):
## редактирование начинается с видимой строки, иначе поле под маской.
## Бокс строки i при прокрутке sc: та же геометрия, что тапается
## (_row_tap_rect), но при заданной прокрутке, а не текущей. Нужен для
## расчёта цели ДО того, как список доехал: целясь линией строки, обёртка
## через край (и возврат после создания) прятала верхнюю строку таблицы
## под маску — её бокс начинается на 38k выше линии (автор 16.10.2026).
func _row_box_at(i: int, sc: float) -> Rect2:
	if _cards():
		var view := _list_rect()
		return Rect2(
			view.position.x, _list_top() + float(i) * _row_step() - sc,
			view.size.x, _card_h()
		)
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step() - sc
	# Левый край — за полосой зайчика с воздухом, а не на ней (ловил
	# аудит 15.10.2026: бокс на 4px заходил под спрайт).
	var x0 := _list_left() + 4.0 * k
	return Rect2(
		x0, row_y - 38.0 * k,
		cols[6] + 16.0 * k - x0, _row_step() - 6.0 * k
	)


func _scroll_to_idx(idx: int) -> void:
	# И таблица тоже: она листается наравне с карточками.
	if idx < 0 or idx > users.size():
		return
	# Двигаем ЦЕЛЬ — список догонит плавно в _process. Считаем от цели же,
	# а не от недолетевшего факта: иначе серия стрелок копила бы ошибку.
	# Меряем БОКС (_row_box_at), а не линию: иначе верхняя строка таблицы
	# вставала боксом под маску (см. выше).
	var view := _list_rect()
	var b := _row_box_at(idx, _scroll_target)
	if b.position.y < view.position.y or (b.size.y >= view.size.y and b.end.y > view.end.y):
		# Выше окна — или выше окна целиком (карточка с клавиатурой:
		# показываем верх, там поле ввода, а не низ).
		_scroll_target = _scroll_clamp(_scroll_target - (view.position.y - b.position.y))
	elif b.end.y > view.end.y:
		_scroll_target = _scroll_clamp(_scroll_target + (b.end.y - view.end.y))
	queue_redraw()


## Нижнего поля ввода и галок для него больше нет: имя правится прямо
## в строке списка (автор 15.10.2026).


## Строка кнопок действий. В карточках — прижата к низу экрана: «Играть»
## всегда под пальцем и не ездит вниз-вверх вместе с числом игроков. На
## пустом списке — под галочкой «Про» для вводимого имени.
func _buttons_y() -> float:
	# Низ экрана: «Играть» всегда под большим пальцем. Но когда список
	# короткий, кнопки встают сразу под ним — иначе на высоком окне под
	# ними дыра (жалоба автора 10.2026 про пустоту).
	var after: float = _rows_top() + _list_all_h() + 20.0 * k
	return minf(
		_menu_eff_h() - _btn_h() - _edge(),
		maxf(after, _rows_top() + _bar_h())
	)



## Шаг блока игроков: карточка в портрете, строка таблицы в альбоме.
## У карточки шаг = высота + зазор (карточки идут с зазором _CARD_GAP).
## На телефоне строка не ниже пальца, иначе тап по строке (игра этим
## игроком) мажет мимо.
## Шаг строки таблицы при масштабе kk — _at-вариант для _fit_k.
func _table_step_at(kk: float) -> float:
	var step := ROW_H * kk
	if not Ui.is_desktop():
		step = maxf(step, 64.0)
	return step


func _row_step() -> float:
	if _cards():
		return _card_h() + _CARD_GAP * _card_k()
	return _table_step_at(k)



## Карточки или таблица: в портрете (view_h > view_w) таблица нечитаема —
## колонки тонкие, имена режутся до многоточия из двух букв, а пальцу в
## них не попасть. Там карточка во всю ширину: имя крупно, статистика
## мелкой строкой, крупные кнопки-чипы справа. На широком экране
## (и на десктопе) — привычная таблица.
func _cards() -> bool:
	return view_h > view_w


## Сторона крупной кнопки в карточке (Про, Ё, ✕). На телефоне — под
## палец, но не выше 132px: при k≈2.5 (телефон с плотностью экрана)
## кнопка, посчитанная от k, съела бы пол-карточки и место для имени.
func _card_btn_at(kk: float) -> float:
	if _finger():
		return clampf(72.0 * kk, _TAP_MIN, 132.0)
	return 56.0 * kk


## Сторона кнопки в карточке (Про, Ё, ✕). На телефоне — под палец: пол
## 64px и потолок 150px (на телефоне с плотностью экрана кнопка из k
## съела бы пол-карточки). В карточке, растянутой на окно, кнопка тоже
## растёт — но в тех же пределах.
func _card_btn() -> float:
	return _card_btn_at(_card_k())



## Высота зайчика: прежняя (спрайт 76k), автор просил его не уменьшать.
func _bunny_size() -> float:
	return 76.0 * k


func _bunny_w() -> float:
	return _bunny_size() * float(HERO_TEX.get_width()) / float(HERO_TEX.get_height())


## Ширина полосы под зайчика: сам спрайт плюс зазор до текста. Списка
## нет — полосы нет: тогда зайчик остаётся у заголовка (см. _bunny_x).
func _bunny_strip() -> float:
	if users.is_empty():
		return 0.0
	# Полоса не съедает окно: на очень узком экране её доля падает.
	# В карточках зазор шире (там зайчик рядом с крупным именем), в
	# таблице колонкам тесно — там уже.
	var gap := 24.0 * k if _cards() else 12.0 * k
	return minf(_bunny_w() + gap, view_w * 0.22)


## Левый край списка без полосы: с неё полоса и начинается.
func _list_left0() -> float:
	if _cards():
		return _edge()
	return 48.0 * k


func _list_left() -> float:
	return _list_left0() + _bunny_strip()


func _bunny_x() -> float:
	if _bunny_strip() > 0.0:
		return _list_left0() + _bunny_strip() * 0.5
	# Пустой список: слева от заголовка. Не влез между кнопкой обновлений
	# и текстом — см. _bunny_visible (тогда не рисуем вовсе).
	var tw := _text_size(TITLE_TEXT, _title_fs()).x
	return _title_x() - tw * 0.5 - 12.0 * k - _bunny_w() * 0.5


## Виден ли зайчик: в своей полосе — всегда, у заголовка пустого списка —
## только если не наезжает на кнопку обновлений (ловил аудит 15.10.2026).
func _bunny_visible() -> bool:
	if _bunny_strip() > 0.0:
		return true
	if _title_fs() <= 0:
		return false
	return _bunny_x() - _bunny_w() * 0.5 >= _upd_button_rect().end.x + 8.0 * k


## Высота, на которой зайчик должен стоять: середина строки выделения.
## На пустом списке — у заголовка.
func _bunny_target_y() -> float:
	if users.is_empty():
		return top_safe + _bar_h() * 0.5
	# Цель — центр рисуемого бокса (тот же хелпер, что у отрисовки):
	# раньше центр считался отдельной формулой без прокрутки и с другим
	# отступом — на длинном пролистанном списке заяц вставал ниже своей
	# строки (автор 16.10.2026: «сдвинут на 1 пункт вниз»).
	var chip := _row_draw_rect(clampi(sel, 0, maxi(0, users.size() - 1)))
	return chip.get_center().y


func _bunny_pos() -> Vector2:
	return Vector2(_bunny_x(), _bunny_y())


## Прыжок по-настоящему: положение — ПАРАБОЛА с ускорением вниз,
## без сдвига по абсциссе (автор 15.10.2026: «заяц плавно сдвигается, а
## я хотел анимацию прыжка — подпрыгивал и по законам физики с ускорением
## вниз по параболе приземлялся на другую строку»). На краях t=0 и t=1
## ровно строки, в середине — высота h; чем дальше строки, тем выше
## прыжок. Сглаживание тут было бы враньём: ease тянет начало, и прыжок
## выглядит сдвигом с горкой.
func _bunny_y() -> float:
	var to := _bunny_target_y()
	if _bunny_t >= 1.0:
		return to
	var t := clampf(_bunny_t, 0.0, 1.0)
	# Высота скромная: достаёт, но не до соседней строки (автор 15.10.2026:
	# «подпрыгивает аж до следующей строчки» — было ×1.15 + 26k).
	var h: float = minf(absf(to - _bunny_from) * 0.5, 80.0 * k) + 14.0 * k
	return lerpf(_bunny_from, to, t) - 4.0 * h * t * (1.0 - t)


## Перенести зайчика на текущую строку выделения. from_y — строка, С
## которой прыгаем: это ПРЕДЫДУЩАЯ ЦЕЛЬ, а не середина полёта. Иначе
## серия быстрых стрелок складывает прыжки друг на друга и заяц улетает
## вверх (автор 15.10.2026). Звать со старой целью ДО смены выделения:
## после смены _bunny_y() уже отдаёт новую цель (ловил profiles_test).
func _bunny_jump(from_y: float) -> void:
	_bunny_from = from_y
	_bunny_t = 0.0


func _bunny_advance(dt: float) -> void:
	_bunny_land = minf(99.0, _bunny_land + dt)
	if _bunny_t >= 1.0:
		if _bunny_land < BUNNY_LAND_T:
			queue_redraw()
		return
	_bunny_t = minf(1.0, _bunny_t + dt / BUNNY_HOP_T)
	if _bunny_t >= 1.0:
		_bunny_land = 0.0
	queue_redraw()


## Вертикальный масштаб зайчика в прыжке — прыгучий мячик (автор
## 15.10.2026): присед перед толчком, вытягивание в полёте, присед на
## приземлении и пружинное дотягивание после. По горизонтали — обратно
## (объём сохраняется, с гиперболой, как просили).
func _bunny_sy(t: float) -> float:
	if t >= 1.0:
		var r := clampf(_bunny_land / BUNNY_LAND_T, 0.0, 1.0)
		# Начинается ровно с посадочных 0.86 (конец ключей), без щелчка.
		return 1.0 - 0.14 * cos(r * PI * 2.0) * exp(-4.0 * r)
	var keys := [
		[0.0, 1.0], [0.15, 0.82], [0.45, 1.18], [0.80, 1.15], [1.0, 0.86],
	]
	for i in range(keys.size() - 1):
		var t0: float = keys[i][0]
		var t1: float = keys[i + 1][0]
		if t >= t0 and t <= t1:
			var u := (t - t0) / maxf(0.001, t1 - t0)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(keys[i][1]), float(keys[i + 1][1]), u)
	return 0.86


## Деформация целиком: вертикаль из _bunny_sy, горизонталь — обратно.
func _bunny_sq() -> Vector2:
	var sy := _bunny_sy(clampf(_bunny_t, 0.0, 1.0))
	return Vector2(1.0 - (sy - 1.0) * 0.75, sy)


## Высота прыжка для тестов: та же формула, что в _bunny_y.
func _bunny_h(dist: float) -> float:
	return minf(dist * 0.5, 80.0 * k) + 14.0 * k


## Натуральная высота содержимого карточки при масштабе kk: отступ,
## имя, статистика, ряд кнопок под палец, отступ. _at-вариант чистый:
## и мера заполнения, и подбор k считают по нему, ничего не выставляя.
func _card_nat() -> float:
	return _card_nat_at(_card_k())


## То же при произвольном масштабе карточек — для подбора k (см. _fit_k):
## без _at-варианта парсер проскакивал мимо (был runtime Parse Error на
## перезагрузке скрипта, который gdparse не видит).
func _card_nat_at(ck: float) -> float:
	return _CARD_PAD * ck + FONT_CARD_NAME * 1.3 * ck + 8.0 * ck \
		+ FONT_CARD_STATS * 1.35 * ck + 8.0 * ck + _card_btn_at(ck) + _CARD_PAD * ck


## Масштаб карточек — от ШИРИНЫ экрана, а не от общего k. На телефоне
## размер интерфейса держит доля экрана, а не масштаб меню: k растёт от
## плотности и на 1080×2400 доходит до 2.5, и карточка в 440px — это
## два с половиной экрана текста (жалоба автора 10.2026: в портрете
## всё мелкое, а места много). Опорная ширина 600: на ней карточка —
## около 300px, кнопка под палец, имя читается.
func _card_k() -> float:
	return clampf(view_w / 600.0, 0.8, 2.4)


## Кегль внутри карточки: базовый × масштаб экрана. Один множитель на
## имя, статистику и подписи кнопок — иначе карточка разъезжается сама
## с собой, а замер берёт другой кегль (см. _clip).
func _card_fs(base_px: int) -> int:
	return maxi(10, int(round(float(base_px) * _card_k())))


## Высота карточки на экране: всегда натуральная. Размер строк НЕ зависит
## от их числа (автор 15.10.2026): мало игроков — карточки по центру окна,
## много — лишнее уходит в прокрутку.
func _card_h() -> float:
	return _card_nat()



## Зазор между карточками и отступ карточки от края экрана (×k).
const _CARD_GAP := 10.0
const _CARD_PAD := 14.0
const _CARD_IN := 18.0


## Карточка игрока i: во всю ширину окна списка, с учётом прокрутки.
## Тап по ней — играть этим игроком (кнопки внутри проверяются раньше
## самой карточки).
func _card_rect(i: int) -> Rect2:
	var view := _list_rect()
	return Rect2(
		view.position.x, _list_top() + float(i) * _row_step() - _scroll,
		view.size.x, _card_h()
	)



## Верх ряда кнопок в карточке: прижат к низу, под статистикой.
func _card_btn_row(i: int) -> float:
	var c := _card_rect(i)
	return c.position.y + c.size.y - _CARD_PAD * k - _card_btn()


## Прямоугольник кнопки в карточке: which — "pro", "yo" или "del".
## Три равные кнопки во всю ширину (Про | Ё | ✕, крестик крайний справа:
## опасное действие не спутаешь). Равные доли не перекрываются ни при
## каком k — в отличие от прошлого ряда у правого края, где длинное имя
## упиралось в кнопки.
func _card_btn_rect(i: int, which: String) -> Rect2:
	var c := _card_rect(i)
	var gap := maxf(8.0 * k, 2.0)
	var inset := _CARD_IN * k
	var x0 := c.position.x + inset
	var w := (c.size.x - inset * 2.0 - gap * 2.0) / 3.0
	if _finger() and w < _TAP_MIN:
		# Три кнопки в ряд на узкой карточке были по 48px — мимо пальца.
		# Сжимаем поля и зазор ровно настолько, чтобы дойти до пола, и
		# НЕ БОЛЬШЕ: поля по краям карточки держат имя и цифры в одной
		# колонке (иначе чипы уезжают под зайчика и к самому краю).
		var edge: float = minf(_TAP_MIN, (c.size.x - 6.0 * k) / 3.0)
		var want: float = edge * 3.0 + gap * 2.0
		inset = maxf(2.0 * k, inset - (want - c.size.x) * 0.5)
		w = maxf((c.size.x - inset * 2.0 - gap * 2.0) / 3.0, edge)
		x0 = c.position.x + inset
	var y := _card_btn_row(i)
	# Слева направо: Про, Ё, ✕.
	var idx := 0
	if which == "yo":
		idx = 1
	elif which == "del":
		idx = 2
	return Rect2(x0 + float(idx) * (w + gap), y, w, _card_btn())


## Флаг профиля i включён? ("pro" — все клавиши, "yo" — строгая ё).


## Поле строчного редактора: рамка + текст + курсор. x — левый край,
## cy — центр строки, fs — кегль, cap — ширина под текст.
func _draw_edit_field(x: float, cy: float, fs: int, cap: float) -> void:
	var cur_w := _text_size_fs("|", fs).x
	var adv := _text_size_fs("н", fs).x
	var th := float(_font_h(fs))
	var box_w := minf(_text_size_fs(input_text, fs).x + cur_w + adv + 20.0 * k, cap)
	var r := Rect2(x, cy - th * 0.75, maxf(box_w, cur_w + adv + 20.0 * k), th * 1.5)
	draw_style_box(box_sb, r)
	var shown := _clip_fs(input_text, fs, maxf(r.size.x - 20.0 * k - cur_w, 4.0)) + "|"
	_text_fs(shown, Vector2(x + 8.0 * k, cy + th * 0.35), fs, _ink())


## Строка под точкой: игроки из списка, -1 мимо. Строка ввода имени
## (пока идёт создание) — тоже строка: листается вместе со всеми.
func _row_at(pos: Vector2) -> int:
	for i in _row_count():
		if _row_tap_rect(i).has_point(pos):
			return i
	return -1


## Начать строчное редактирование (автор 15.10.2026): ПКМ, долгое нажатие,
## кнопка «+ Новый игрок», Insert, Tab. editing_new отличает создание от
## переименования.
func _start_edit(i: int) -> void:
	editing = clampi(i, 0, users.size())
	editing_new = editing == users.size()
	if editing_new:
		input_text = ""
		input_all_keys = false
		input_yo_strict = true
	else:
		input_text = users[editing]
	input_active = true
	_relayout()
	_scroll_to_idx(editing)
	queue_redraw()


## Enter в редактировании: создание — новая строка вниз списка (без
## автозапуска), переименование — на месте. Пустое/занятое имя —
## остаёмся в редактировании.
func _commit_edit() -> void:
	if editing < 0:
		return
	var name := S.clean_name(input_text)
	if name.is_empty():
		# Создание без имени: человек ещё набирает — поле остаётся.
		# Переименование пустым именем — откат к прежнему виду.
		if editing_new:
			return
		_cancel_edit()
		return
	if editing_new:
		if S.user_exists(name):
			return
		S.create_user(name)
		S.set_all_keys(name, input_all_keys)
		S.set_yo_strict(name, input_yo_strict)
		_reload()
		sel = users.find(name)
		_scroll_to_sel()
		_cancel_edit()
		return
	if name == users[editing]:
		_cancel_edit()
		return
	if S.user_exists(name):
		return
	var old := users[editing]
	if S.rename_user(old, name):
		_reload()
		sel = users.find(name)
		_scroll_to_sel()
		_cancel_edit()


## Esc в редактировании: создание — строка исчезает, переименование —
## возвращается прежний вид (имя в списке не трогали, оно в input_text).
## Сброс правки БЕЗ пересборки геометрии. Из _reload звать _cancel_edit
## нельзя: тот тянет _relayout, а тот берёт размер из вьюпорта (в тестах
## он 64x64 и сбивает выставленные руками величины).
func _drop_edit() -> void:
	editing = -1
	editing_new = false
	input_text = ""
	input_active = false
	input_all_keys = false
	input_yo_strict = true


func _cancel_edit() -> void:
	editing = -1
	editing_new = false
	input_text = ""
	input_active = false
	# Ждущие флаги — тоже состояние правки: без сброса они «переживали»
	# сессию и всплывали галочками у следующего создаваемого.
	input_all_keys = false
	input_yo_strict = true
	_relayout()
	queue_redraw()


## Флаг строки для отрисовки: у создаваемой — черновики из поля ввода.
func _row_flag(i: int, which: String) -> bool:
	if i == users.size():
		if not editing_new:
			return false
		return input_all_keys if which != "yo" else input_yo_strict
	return _flag_on(i, which)


func _flag_on(i: int, which: String) -> bool:
	if i < 0 or i >= users.size():
		return false
	var p := S.load_profile(users[i])
	if which == "yo":
		return bool(p.get("yo_strict", true))
	return bool(p.get("all_keys", false))


func _row_tap_rect(i: int) -> Rect2:
	if _cards():
		return _card_rect(i)
	# Тот же бокс, что _row_box_at при текущей прокрутке: единый источник
	# геометрии (см. выше).
	return _row_box_at(i, _scroll)


## Строка видна в окне списка (для тапов): уехавшая за край — как
## срезанная маской, её не выбрать (см. выше).
func _row_shown(i: int) -> bool:
	if users.is_empty():
		return false
	return _list_rect().intersects(_row_tap_rect(i))


## Нарисованная строка таблицы: тап-зона ужата сверху и снизу, чтобы
## соседние строки не слипались (аудит 15.10.2026: 6px между боксами).
## Центр тот же — зайчик и галочки стоят как стояли.
func _row_draw_rect(i: int) -> Rect2:
	var t := _row_tap_rect(i)
	return Rect2(
		t.position + Vector2(0.0, 5.0 * k),
		t.size - Vector2(0.0, 10.0 * k)
	)


## Галочка «Про» в строке: тот же переключатель, что клавиша A,
## но пальцем/мышью. Тап по ней не играет профилем, только флагом.
## Тап-зона кнопки в строке: высотой — вся строка (по вертикали соседи
## не пересекаются: центры через _row_step), шириной — своя колонка
## (иначе перехватит тап соседа).
func _cell_rect(cx: float, row_y: float, col_w: float) -> Rect2:
	var h := _row_step()
	return Rect2(cx - col_w * 0.5, row_y - h * 0.5, col_w, h)


func _pro_tap_rect(i: int) -> Rect2:
	if _cards():
		return _card_btn_rect(i, "pro")
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step() - _scroll
	var cx := (cols[3] + cols[4]) * 0.5
	return _cell_rect(cx, row_y, cols[4] - cols[3])


## Галочка «Ё» в строке: строгая ё именно этому игроку.
## Тап не играет профилем, только флагом.
func _yo_tap_rect(i: int) -> Rect2:
	if _cards():
		return _card_btn_rect(i, "yo")
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step() - _scroll
	var cx := (cols[4] + cols[5]) * 0.5
	return _cell_rect(cx, row_y, cols[5] - cols[4])


## Крестик удаления в строке: открывает модалку подтверждения.
func _del_tap_rect(i: int) -> Rect2:
	if _cards():
		return _card_btn_rect(i, "del")
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step() - _scroll
	var cx := (cols[5] + cols[6]) * 0.5
	return _cell_rect(cx, row_y, cols[6] - cols[5])


## Заголовок меню: кегль, левая граница и базовая строка — отдельными
## функциями, чтобы проверять положение числом (profiles_test): при k от
## плотности он наезжал на кнопку обновлений, а в таблице — ещё и на
## шапки колонок.
const TITLE_TEXT := "Кто играет?"


func _title_fs() -> int:
	var tfs := 46 if _cards() else FONT_TITLE
	var room: float = _title_right() - _title_left()
	# Ужимается под место (k на телефоне доходит до 2.5), а если между
	# кнопкой обновлений и темой места нет вовсе — скрывается: пустой
	# заголовок лучше наезжающего на кнопку текста.
	while tfs > 16 and _text_size(TITLE_TEXT, tfs).x > room:
		tfs -= 2
	return tfs if _text_size(TITLE_TEXT, tfs).x <= room else 0


func _title_left() -> float:
	return _upd_button_rect().end.x + 14.0 * k


func _title_right() -> float:
	return maxf(
		_night_tap_rect().position.x - 14.0 * k,
		_upd_button_rect().end.x + 15.0 * k
	)


func _title_x() -> float:
	return _title_left() + (_title_right() - _title_left()) * 0.5


## Заголовок — по центру верхней панели, между кнопкой обновлений и
## темой; по базовой линии он стоит чуть ниже середины кнопки.
func _title_y() -> float:
	# От базовой панели (без сообщения): иначе круг _bar_h → заголовок →
	# сообщение → _bar_h (ловил сторожем: тысячи ошибок за прогон).
	var gh: float = float(_font_h(maxi(_title_fs(), 1)))
	return top_safe + (_bar_base_h() + gh) * 0.5


## Базовая строка пояснения к галочке. В карточках — над полем ввода,
## внутри окна списка: под прижатым к экрану низом места нет, там своя
## клавиатура (ловил на кадре «name-field»: текст ложился на верхний ряд
## клавиш). Отдельная функция, чтобы проверять положение числом
## (profiles_test, _part29_card_scroll).
## Верх пилюли пояснения к галочке. Пилюля плавает над низом окна списка
## (временный тост со сплошным фоном): в зазоре до поля ей тесно, а под
## кнопками она уходила бы за экран. Та же точка в обоих режимах.
func _chip_hint_y() -> float:
	# Строкой ниже рамки окна (с воздухом 6k): иначе пилюля ложилась
	# прямо на её нижний край и перекрывала его.
	return _list_rect().end.y + 6.0 * k


## Высота пилюли с пояснением (одна строка + подложка).
func _hint_pill_h() -> float:
	return _text_size("Про: все буквы сразу, важен регистр.", FONT_SMALL).y + 16.0 * k


## Сколько окно списка уступает пилюле. Пусто — когда пояснения нет
## (или идёт редактирование: пилюля ложилась на поле и чипы строки).
## Запас внутри окна, а не поверх карточек: строка, до которой пилюля
## не дотянулась, уезжает в прокрутку.
func _hint_reserve_h() -> float:
	if hint_header == "" or not _cards() or editing >= 0:
		return 0.0
	return _hint_pill_h() + 12.0 * k


## Заголовки «Про»/«Ё»: тап показывает, что за галка (hint_header).
## В карточках шапки нет (там чипы подписаны прямо на кнопках, а
## объяснение приходит из самого переключения) — отдаём пустой
## прямоугольник, чтобы тап не попал в никуда.
func _pro_head_rect() -> Rect2:
	if _cards():
		return Rect2()
	var cols := _table_cols()
	var cx := (cols[3] + cols[4]) * 0.5
	var y := _rows_top() - 56.0 * k
	return Rect2(cx - 48.0 * k, y - 28.0 * k, 96.0 * k, 40.0 * k)


func _yo_head_rect() -> Rect2:
	if _cards():
		return Rect2()
	var cols := _table_cols()
	var cx := (cols[4] + cols[5]) * 0.5
	var y := _rows_top() - 56.0 * k
	return Rect2(cx - 48.0 * k, y - 28.0 * k, 96.0 * k, 40.0 * k)


## Заголовки «Ур» и «Победы»: хит-зона в той же строке шапки. Ширина — по
## тексту с воздухом (те же 12k с каждой стороны, что у отступа имени).
func _ur_head_rect() -> Rect2:
	if _cards():
		return Rect2()
	var cols := _table_cols()
	var y := _rows_top() - 56.0 * k
	var w := _text_size_fs("Ур", _table_head_fs()).x + 24.0 * k
	return Rect2(cols[1] - 12.0 * k, y - 28.0 * k, w, 40.0 * k)


func _rec_head_rect() -> Rect2:
	if _cards():
		return Rect2()
	var cols := _table_cols()
	var y := _rows_top() - 56.0 * k
	var w := _text_size_fs("Победы", _table_head_fs()).x + 24.0 * k
	return Rect2(cols[2] - 12.0 * k, y - 28.0 * k, w, 40.0 * k)


## Текст тултипа под курсором: все заголовки таблицы, кроме очевидного
## «Имя» (автор 16.10.2026). Пусто — курсор не на заголовке или не таблица.
func _head_tip_at(pos: Vector2) -> String:
	if _cards() or users.is_empty():
		return ""
	if _ur_head_rect().has_point(pos):
		return "Уровень: растёт с победами."
	if _rec_head_rect().has_point(pos):
		return "Победы / все партии."
	if _pro_head_rect().has_point(pos):
		return "Про: все буквы сразу, важен регистр."
	if _yo_head_rect().has_point(pos):
		return "Ё: без галки е засчитывается за ё."
	return ""


## Пузырь ховер-подсказки у курсора. Та же пилюля (hint_sb) и те же отступы,
## что у нижней подсказки про чипы, — один стиль. К краю экрана пузырь
## перекидывается на другую сторону курсора, а не уезжает за него.
func _draw_hover_tip() -> void:
	if _hover_t < HOVER_TIP_T or editing >= 0 or confirm_name != "" or _upd_open:
		return
	var tip := _head_tip_at(_hover_pos)
	if tip == "":
		return
	var fs := int(FONT_SMALL * k)
	var tw := _text_size_fs(tip, fs).x
	var th := _text_size_fs(tip, fs).y
	var w := tw + 28.0 * k
	var h := th + 16.0 * k
	var p := _hover_pos + Vector2(16.0 * k, 20.0 * k)
	if p.x + w > view_w - _edge():
		p.x = _hover_pos.x - w - 8.0 * k
	if p.y + h > view_h - _edge():
		p.y = _hover_pos.y - h - 8.0 * k
	p.x = clampf(p.x, _edge(), maxf(_edge(), view_w - _edge() - w))
	p.y = clampf(p.y, _edge(), maxf(_edge(), view_h - _edge() - h))
	draw_style_box(hint_sb, Rect2(p, Vector2(w, h)))
	_text_fs(tip, Vector2(p.x + 14.0 * k, p.y + 8.0 * k + th), fs, _uitext())


## Мелочи, из-за которых кнопку не попасть пальцем, а в чехле — тем
## более (жалоба автора 10.2026 на «Лог»):
##   *_TAP — минимальная сторона кнопки: меньше 64px не для пальца;
##   *_PAD — отступ от края: в чехле край экрана закрыт рукой.
## На десктопе курсором — точность не нужна, там по к=1 всё крупное.
const _TAP_MIN := 64.0
const _PAD_MIN := 22.0


## Палец или мышь. Узкое окно — палец даже на десктопе: автор гонял
## игру в портретном окне и жаловался, что кнопки «новый игрок» и «без
## профиля» мелкие, а чипы «Про/Ё/✕» тем более (16.10.2026). Правило
## поэтому не про платформу, а про форму: портретное окно — палец.
func _finger() -> bool:
	return not Ui.is_desktop() or view_w < 700.0


## Высота зоны тапа: на телефоне меньше 64px не для пальца, на десктопе
## курсором и так попасть можно. _at-вариант — для подбора k (см. _fit_k).
func _tap_h(h: float) -> float:
	return _tap_h_at(h)


func _tap_h_at(h: float) -> float:
	return h if Ui.is_desktop() else maxf(h, _TAP_MIN)



## Отступ от края: минимум, чтобы палец не упирался в чехол.
func _pad(p: float) -> float:
	return _pad_at(p)


func _pad_at(p: float) -> float:
	return p if Ui.is_desktop() else maxf(p, _PAD_MIN)


## Внешний отступ от края окна (автор 15.10.2026: элементы липли к краям —
## на телефоне там чехол и палец мажет, да и неэстетично). Стандартно:
## 16k на десктопе, на сенсоре не меньше 28px.
const _EDGE_MIN := 36.0


func _edge() -> float:
	return maxf(24.0 * k, 24.0 if Ui.is_desktop() else _EDGE_MIN)



## Верхняя панель меню (автор 15.10.2026): слева «Обновления», по
## центру «Кто играет?», справа солнце-луна. Всё, что раньше лежало в
## шапке и в нижнем ряду, живёт здесь — и ничего не наезжает: границы
## заданы тремя функциями (_upd_button_rect, _night_tap_rect, _title_*).
func _bar_pad() -> float:
	return maxf(9.0 * k, 6.0)


func _bar_btn() -> float:
	return _tap_h(44.0 * k)


## Высота верхней панели: кнопка плюс поля, а с сообщением об
## обновлении — ещё строка под ним (иначе текст лёг бы на список).
## Высота панели без строки сообщения. Отдельная функция, чтобы разорвать
## круг: сообщение меряется от заголовка, а заголовок — от панели.
func _bar_base_h() -> float:
	# Панель выше любой из двух вещей: кнопки под палец и заголовка.
	var gh: float = float(_font_h(maxi(_title_fs(), 1)))
	var h: float = maxf(_bar_btn(), gh if _title_fs() > 0 else 0.0)
	return h + _bar_pad() * 2.0


func _bar_h() -> float:
	# Строки сообщения больше нет (всё в кнопке) — высота панели
	# постоянна и ни от чего не ездит (автор 15.10.2026).
	return _bar_base_h()


## Кнопка проверки обновлений — левый край верхней панели. Ширина
## ограничена тем, что справа живут заголовок и тема: на узком экране
## кнопка ужимается, а не вылезает за поле (тест жмёт view_w до 64).
## Замер — тем же кеглем, каким рисует _button (26, не FONT_SMALL).
## Подпись кнопки обновлений по состоянию. Всё — внутри кнопки:
## раскладка от текста не ездит (автор 15.10.2026).
func _upd_label() -> String:
	match _upd_state:
		"checking":
			return "Проверка…"
		"latest":
			return "Обновлений нет"
		"error":
			return _upd_msg if _upd_msg != "" else "Ошибка"
		"downloading":
			if _upd_pct >= 0:
				return "%d%%" % _upd_pct
			return "Качаю…"
		_:
			if _upd_tag != "" and not _upd_open:
				return "Установить " + _upd_tag
			return _app_version()


## Ширина кнопки — по самому длинному варианту подписи сразу, чтобы её
## не приходилось расширять (автор 15.10.2026). Ошибку в ширину не
## закладываем (текст чужой) — она ужимается клиппингом.
func _upd_button_rect() -> Rect2:
	var pad := _edge()
	var h := _bar_btn()
	var w := 0.0
	# Теги версий одной длины (v0.0.x): меряем по текущей, а не по
	# выдуманной длинной — иначе кнопка съедает полпанели.
	for cand in [_app_version(), "Проверка…", "Обновлений нет", "Установить " + _app_version(), "100%"]:
		w = maxf(w, _text_size(cand, 26).x)
	w += 36.0 * k
	var room: float = view_w - pad * 2.0 - h - 24.0 * k
	return Rect2(pad, top_safe + _bar_pad(), minf(maxf(w, h), maxf(0.0, room)), h)


## Кнопка обновлений: подпись-версия и состояния — внутри, заливка
## прогресса — тоже внутри (автор 15.10.2026: никаких подписей и полос
## снаружи, раскладка не ездит).
func _draw_upd_button() -> void:
	var ub := _upd_button_rect()
	# Заливка и волна — строго внутри кнопки: снаружи им делать нечего
	# (ловил автор 15.10.2026: волна вылезала за границы).
	var inner := Rect2(
		ub.position + Vector2(3.0 * k, 3.0 * k),
		ub.size - Vector2(6.0 * k, 6.0 * k)
	)
	if _upd_state == "downloading" and _upd_pct >= 0:
		var fill := Rect2(
			ub.position, Vector2(ub.size.x * float(_upd_pct) / 100.0, ub.size.y)
		).intersection(inner)
		if fill.size.x > 0.0:
			draw_rect(fill, Color(0.35, 0.62, 0.92, 0.45))
	elif _upd_state == "checking":
		# Процентов нет — бегущая волна: видно, что дело идёт.
		var t := fmod(Time.get_ticks_msec() / 1000.0 * 1.2, 1.0)
		var ww := ub.size.x * 0.35
		var xx := ub.position.x - ww + t * (ub.size.x + ww * 2.0)
		var wave := Rect2(xx, ub.position.y, ww, ub.size.y).intersection(inner)
		if wave.size.x > 0.0:
			draw_rect(wave, Color(0.35, 0.62, 0.92, 0.45))
	_button(ub, _clip(_upd_label(), 26, maxf(ub.size.x - 16.0 * k, 10.0)))


## Карточка «Вышла версия?»: заголовок + заметки + две кнопки.
## Ширина — по самому длинному тексту, кнопки всегда внизу.
func _upd_card_rect() -> Rect2:
	var w := _text_size("Вышла " + _upd_tag, FONT_ROW).x + 96.0 * k
	for ln in _upd_notes:
		w = maxf(w, _text_size(ln, FONT_SMALL).x + 96.0 * k)
	w = clampf(w, 420.0 * k, view_w - 64.0 * k)
	var h := 200.0 * k + 30.0 * k * float(_upd_notes.size())
	return Rect2((view_w - w) * 0.5, (view_h - h) * 0.5, w, h)


func _upd_yes_rect() -> Rect2:
	var card := _upd_card_rect()
	return Rect2(
		Vector2(card.get_center().x - 190.0 * k, card.position.y + card.size.y - 80.0 * k),
		Vector2(170.0 * k, _tap_h(56.0 * k))
	)


func _upd_no_rect() -> Rect2:
	var card := _upd_card_rect()
	return Rect2(
		Vector2(card.get_center().x + 20.0 * k, card.position.y + card.size.y - 80.0 * k),
		Vector2(170.0 * k, _tap_h(56.0 * k))
	)


## Нижнего поля ввода больше нет (см. выше).


## Краски текста под режим: днём константы, ночью светлые.
func _ink() -> Color:
	if night:
		return Ui.INK_NIGHT
	return INK


func _uitext() -> Color:
	if night:
		return Ui.INK_NIGHT.darkened(0.12)
	return UI_TEXT


func _dim() -> Color:
	if night:
		return Ui.LINE_NIGHT
	return DIM


## Спрайт ночью темнее и холоднее — см. Ui.NIGHT_TINT.
## Ночь: ручной выбор из файла важнее системы.
func _night_resolve() -> void:
	night = S.resolve_night(nmode, true, S.system_dark())


## Применить ночь: панели мутируют на месте, фон переключается.
func _apply_night() -> void:
	_night_resolve()
	_cols_cache = []  # на всякий случай: смена темы могла сдвинуть метрики
	# До _ready панелей ещё нет (open зовут и до входа в дерево): красить
	# нечего, а писать в Nil нельзя — в шаблоне это роняет игру, хотя
	# редактор прощает (ловил segfault 15.10.2026). _ready сам красит.
	if row_idle_sb == null:
		return
	# Все цвета — из словаря ролей (ui.gd). Здесь только «что за панель
	# и какая у неё роль»; значение дня/ночи знает словарь, поэтому
	# новый цвет правится в одном месте, а не в двух файлах сразу.
	if night:
		row_idle_sb.bg_color = Ui.ROW_IDLE_NIGHT
		box_sb.bg_color = Ui.SURFACE_ALT_NIGHT
		box_sb.border_color = Ui.LINE_NIGHT
		selbox_sb.bg_color = Ui.ACCENT_NIGHT
		selbox_sb.border_color = Ui.ACCENT_EDGE_NIGHT
		hint_sb.bg_color = Ui.PILL_NIGHT
		hint_sb.border_color = Ui.LINE_SOFT_NIGHT
		chip_on_sb.bg_color = Ui.ACCENT_NIGHT
		chip_on_sb.border_color = Ui.ACCENT_EDGE_NIGHT
		# Ободок фокуса — по подложке: на тёмной ночной рамке нужен
		# СВЕТЛЫЙ, на светлом чипе и жёлтой строке — тёмный (см. _card_chip).
		chip_focus_sb.border_color = Ui.FOCUS_LIGHT
		list_frame_sb.border_color = Ui.LINE_SOFT_NIGHT
		kb_key_sb.bg_color = Ui.SURFACE_ALT_NIGHT
		kb_key_sb.border_color = Ui.LINE_NIGHT
		kb_press_sb.bg_color = Ui.PRESS_NIGHT
		kb_press_sb.border_color = Ui.LINE_NIGHT
		kb_press_ok_sb.bg_color = Ui.OK_NIGHT
		kb_press_ok_sb.border_color = Ui.OK_EDGE_NIGHT
		kb_press_err_sb.bg_color = Ui.DANGER_NIGHT
		kb_press_err_sb.border_color = Ui.DANGER_EDGE_NIGHT
	else:
		row_idle_sb.bg_color = Ui.ROW_IDLE_DAY
		box_sb.bg_color = Ui.SURFACE_ALT_DAY
		box_sb.border_color = Ui.LINE_DAY
		selbox_sb.bg_color = Ui.ACCENT_DAY
		selbox_sb.border_color = Ui.ACCENT_EDGE_DAY
		hint_sb.bg_color = Ui.PILL_DAY
		hint_sb.border_color = Ui.LINE_SOFT_DAY
		chip_on_sb.bg_color = Ui.ACCENT_DAY
		chip_on_sb.border_color = Ui.ACCENT_EDGE_DAY
		chip_focus_sb.border_color = Ui.FOCUS_DARK
		list_frame_sb.border_color = Ui.LINE_SOFT_DAY
		kb_key_sb.bg_color = Ui.SURFACE_ALT_DAY
		kb_key_sb.border_color = Ui.LINE_DAY
		kb_press_sb.bg_color = Ui.PRESS_DAY
		kb_press_sb.border_color = Ui.LINE_DAY
		kb_press_ok_sb.bg_color = Ui.OK_DAY
		kb_press_ok_sb.border_color = Ui.OK_EDGE_DAY
		kb_press_err_sb.bg_color = Ui.DANGER_DAY
		kb_press_err_sb.border_color = Ui.DANGER_EDGE_DAY
	if _meadow != null:
		_meadow.night = night
		_meadow._apply_sky()
	queue_redraw()


## Переключатель ночи по кругу: день → ночь → авто → день.
## Выбор запоминается в настройках.
func _toggle_night() -> void:
	if nmode == S.NIGHT_DAY:
		nmode = S.NIGHT_ON
	elif nmode == S.NIGHT_ON:
		nmode = S.NIGHT_AUTO
	else:
		nmode = S.NIGHT_DAY
	S.set_night_mode(nmode)
	_apply_night()


## Высота кнопок действий: на телефоне не ниже пальца.
func _btn_h() -> float:
	return _btn_h_at(k)


func _btn_h_at(kk: float) -> float:
	# В ПОРТРЕТЕ ряд внизу — ровно та же высота, что у чипов «Про/Ё/✕»
	# в карточке: одна и та же величина, а не две похожие формулы.
	# Раньше ряд считалcя от k, а чипы — от ширины экрана (_card_k), и
	# на широком окне с плотностью 1 (то есть на портретном окне
	# десктопа) выходило 70px против 130 (автор 17.10.2026: «кнопки
	# новый игрок и без профиля по-прежнему маленькие, хотя я просил
	# сделать их такими же толстыми, как и Про и Ё в вертикальном режиме»).
	if _cards():
		return _card_btn_at(_card_k())
	if _finger():
		return clampf(72.0 * kk, _TAP_MIN, 132.0)
	return 52.0 * kk



## Нижняя левая кнопка: создать нового пользователя (раньше «Играть»).
func _new_tap_rect() -> Rect2:
	var r := _btn_row()
	var h := _btn_h()
	var free := _btn_free(r)
	return Rect2(r.position.x, r.position.y, maxf(free - _btn_gap() - _guest_share(free), 0.0), h)


func _guest_tap_rect() -> Rect2:
	var r := _btn_row()
	var h := _btn_h()
	var gw := _guest_share(_btn_free(r))
	return Rect2(r.end.x - gw, r.position.y, gw, h)


## Ночь — квадрат у правого края: иконка, а не надпись.
## Солнце-луна — правый край верхней панели (автор 15.10.2026).
func _night_tap_rect() -> Rect2:
	var h := _bar_btn()
	var pad := _edge()
	return Rect2(view_w - pad - h, top_safe + _bar_pad(), h, h)


## Ряд кнопок под полем: во всю ширину экрана, с полями для чехла.
## Раньше кнопки стояли на константах от центра, и в портрете ряд
## уезжал за правый край — ночная обрезалась (кадр «01-cards»
## визуального прогона 10.2026). Теперь ряд всегда в границах
## экрана, а оставшееся место делят «Играть» и «Без профиля».
func _btn_row() -> Rect2:
	var m := _edge()
	return Rect2(m, _buttons_y(), view_w - m * 2.0, _btn_h())


func _btn_gap() -> float:
	return 16.0 * k


## Свободная ширина ряда кнопок (ночная кнопка уехала наверх, 15.10.2026).
func _btn_free(r: Rect2) -> float:
	return maxf(r.size.x, 0.0)


## Доля «Без профиля» в этом месте. Только доля, без минимума: минимум
## на узком экране (тест рисует меню в 64px) наезжал на соседнюю
## кнопку. Подпись при нехватке места ужимается сама (см. _button) —
## кнопки остаются неперекрытыми при любой ширине.
func _guest_share(free: float) -> float:
	return free * 0.5


## Кнопки модалки подтверждения: «Да» и «Нет» по центру карточки.
func _confirm_yes_rect() -> Rect2:
	var c := _confirm_card_rect().get_center()
	var h := _tap_h(56.0 * k)
	return Rect2(c + Vector2(-190.0 * k, 24.0 * k), Vector2(170.0 * k, h))


func _confirm_no_rect() -> Rect2:
	var c := _confirm_card_rect().get_center()
	var h := _tap_h(56.0 * k)
	return Rect2(c + Vector2(20.0 * k, 24.0 * k), Vector2(170.0 * k, h))


## Карточка модалки: по центру экрана, по ширине текста вопроса.
func _confirm_card_rect() -> Rect2:
	var t := "Удалить «%s»?" % confirm_name
	var w := maxf(_text_size(t, FONT_ROW).x + 96.0 * k, 420.0 * k)
	var h := 210.0 * k
	return Rect2((view_w - w) * 0.5, (view_h - h) * 0.5, w, h)


## Опасное действие (крестик удаления): красный в обеих темах.
func _danger() -> Color:
	if night:
		return Ui.DANGER_TEXT_NIGHT
	return Ui.DANGER_TEXT_DAY


## Включён ли взрослый режим: у выбранного — его флаг, на пустом
## списке — флаг вводимого имени.
func _check_on() -> bool:
	if users.is_empty():
		return input_all_keys
	return bool(S.load_profile(users[sel]).get("all_keys", false))


## Кнопка-пилюля с подписью по центру. Кегль ужимается под ширину
## кнопки: на телефоне с плотностью «Без профиля» на 26k не влезала
## и подпись вылезала за край.
func _button(r: Rect2, label: String, focused := false) -> void:
	# Сфокусированная кнопка залита, как выбранная галка (selbox_sb):
	# иначе в модалке не видно, где стоит выделение.
	draw_style_box(selbox_sb if focused else hint_sb, r)
	var fs := int(26.0 * k)
	# Замер — null-безопасный: _draw исполняется, даже пока шрифта нет.
	while fs > 10 and _text_size_fs(
		label, fs
	).x > r.size.x - 16.0 * k:
		fs -= 2
	var w := _text_size_fs(label, fs).x
	var y := r.get_center().y + float(_font_h(fs)) * 0.3
	draw_string(mono, Vector2(r.get_center().x - w * 0.5, y), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ink())


## Кнопка день/ночь/авто: показывает ТЕКУЩИЙ режим. Все три значка —
## векторный композит с явными границами (строго внутри кнопки):
## солнце — диск с лучами, ночь — залитый месяц (диск + вырез),
## авто — полдиска (тёмная/светлая, как системная авто-тема).
## Шрифтовые ☀/◐ вылезали за кнопку, а эмоджи-лун в DejaVu нет
## вовсе (проверено по cmap — тофу на половине платформ).
func _draw_daynight(r: Rect2) -> void:
	draw_style_box(hint_sb, r)
	var c := r.get_center()
	var bg := hint_sb.bg_color
	if nmode == S.NIGHT_ON:
		# Залитый месяц: диск чернилами, вырез цветом кнопки со сдвигом.
		var mr := 11.0 * k
		draw_circle(c, mr, _ink())
		draw_circle(c + Vector2(mr * 0.42, -mr * 0.38), mr * 0.82, bg)
	elif nmode == S.NIGHT_AUTO:
		# Полдиска: левая чернилами, правая вырезана под кнопку.
		var ar := 11.0 * k
		draw_circle(c, ar, _ink())
		draw_rect(Rect2(c + Vector2(0.0, -ar), Vector2(ar, ar * 2.0)), bg)
	else:
		# Солнце: диск плюс 8 лучей, всё в радиусе 15k.
		var sr := 7.0 * k
		draw_circle(c, sr, _ink())
		for i in 8:
			var a := TAU * float(i) / 8.0
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * 10.5 * k, c + dir * 15.0 * k, _ink(), 2.5 * k)


func _draw() -> void:
	# Без шрифта рисовать нечего (open зовут и до _ready): _draw при этом
	# всё равно исполняется, а метод на null-шрифте роняет шаблон
	# (ловил segfault 15.10.2026). После _ready придёт queue_redraw.
	if mono == null:
		return
	# Вуаль вместо глухой заливки: игра позади чуть видна, и понятно,
	# что меню — пауза, а не другой экран. Строки и тексты те же, что
	# были, вокруг них лишь карточки.
	var veil := PAPER
	if night:
		veil = Ui.PAPER_NIGHT
	veil.a = 0.94
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), veil)
	var cx := view_w * 0.5
	# Список идёт ПЕРВЫМ: он листается, и карточка, ушедшая за окно,
	# не должна лезть на заголовок или на поле ввода — её срезают маски
	# (см. _list_masks). Поэтому шапка рисуется после списка.
	if _cards():
		_draw_cards()
	else:
		_draw_table()
	var y := _rows_top()
	var tfs := _title_fs()
	if tfs > 0:
		var title_w := _text_size("Кто играет?", tfs).x
		_text(
			"Кто играет?",
			Vector2(_title_x() - title_w * 0.5, _title_y()),
			tfs,
			_ink()
		)
	# Зайчик — либо в своей полосе слева от списка (и прыгает по строкам),
	# либо у заголовка, пока список пуст (если влез, см. _bunny_visible).
	if _bunny_visible():
		_draw_bunny(_bunny_pos())
	# Нижнего поля и галок для него больше нет: всё правится в строках.
	# Кнопки действий: та же механика, что Enter и Esc, но пальцем.
	# Третья — ночь: иконка показывает, во что переключит.
	_button(_new_tap_rect(), "+ Новый игрок")
	_button(_guest_tap_rect(), "Без профиля")
	_draw_own_kb()
	# Пояснение галки по тапу на заголовок — строкой под кнопками.
	# Модалка его перекрывает (рисуется позже поверх). В редактировании
	# не показываем: пилюля ложилась прямо на поле и чипы строки.
	if hint_header != "" and confirm_name == "" and editing < 0:
		var expl: Array[String] = []
		if hint_header == "pro":
			expl = ["Про: все буквы сразу, важен регистр."]
		else:
			expl = ["Ё: без галки е засчитывается за ё."]
		# Пояснение — пилюля в своём зазоре (см. _chip_hint_y): текст без
		# подложки ложился на карточки и читался как грязь.
		var ey := _chip_hint_y()
		for li in expl.size():
			var lw := _text_size(expl[li], FONT_SMALL).x
			var base := ey + 8.0 * k + _text_size(expl[li], FONT_SMALL).y
			draw_style_box(
				box_sb,
				Rect2(
					view_w * 0.5 - lw * 0.5 - 14.0 * k, ey,
					lw + 28.0 * k, base - ey + 8.0 * k
				)
			)
			_text(
				expl[li], Vector2(view_w * 0.5 - lw * 0.5, base),
				FONT_SMALL, _uitext()
			)
	# Кнопка проверки обновлений слева вверху + строка состояния.
	# На десктопе и телефоне одинаково: проверка — обычный HTTP.
	_draw_upd_button()
	_draw_daynight(_night_tap_rect())
	# Модалка «Вышла версия?» — поверх всего, кроме удаления
	# (удаление первее: его ветка ввода раньше).
	if _upd_open:
		var dimmer := Color(0.05, 0.05, 0.08, 0.55)
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), dimmer)
		var ucard := _upd_card_rect()
		draw_style_box(box_sb, ucard)
		var ut := "Вышла %s" % _upd_tag
		var uw := _text_size(ut, FONT_ROW).x
		_text(
			ut,
			Vector2(ucard.get_center().x - uw * 0.5, ucard.position.y + 62.0 * k),
			FONT_ROW, _ink()
		)
		var notecap := ucard.size.x - 48.0 * k
		for li in _upd_notes.size():
			var ln := _clip(_upd_notes[li], FONT_SMALL, notecap)
			var lw := _text_size(ln, FONT_SMALL).x
			_text(
				ln,
				Vector2(ucard.get_center().x - lw * 0.5, ucard.position.y + 110.0 * k + 30.0 * k * float(li)),
				FONT_SMALL, _uitext()
			)
		# Кнопка: где игра ставит сама — «Скачать», где качает браузер
		# (Android) — честно «Загрузить»: дальше файл открывают руками.
		_button(_upd_yes_rect(), "Скачать" if Updater.self_installs() else "Загрузить")
		_button(_upd_no_rect(), "Позже")
	# Модалка подтверждения удаления — поверх всего.
	if confirm_name != "":
		var dimmer := Color(0.05, 0.05, 0.08, 0.55)
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), dimmer)
		var card := _confirm_card_rect()
		draw_style_box(box_sb, card)
		var qt := "Удалить «%s»?" % confirm_name
		var qw := _text_size(qt, FONT_ROW).x
		_text(
			qt,
			Vector2(card.get_center().x - qw * 0.5, card.position.y + 62.0 * k),
			FONT_ROW, _ink()
		)
		_button(_confirm_yes_rect(), "Да", confirm_sel == 0)
		_button(_confirm_no_rect(), "Нет", confirm_sel == 1)


## Таблица игроков (широкий экран, десктоп): шапка колонок + строки.
## Тап по строке только выделяет, играет дабл-клик или Enter; тап по
## галочке — только флаг, тап по крестику — удаление с подтверждением.
## Тап по заголовку «Про»/«Ё» объясняет галку. Выбранная стрелками
## колонка подсвечена в шапке (пробел переключает её флаг).
func _draw_table() -> void:
	var y := _rows_top()
	# Таблица игроков: строки во всю ширину. Тап по строке только
	# выделяет, тап по галочке — только флаг, тап по крестику —
	# удаление с подтверждением. Шапка колонок рисуется ПОСЛЕ строк и
	# своей полосой бумаги: строка таблицы центрируется на _rows_top и
	# уезжает на полстроки вверх — бокс первой строки ложился прямо на
	# подписи «Про»/«Ё» (экран автора 3120x2080).
	var view := _list_rect()
	for i in _row_count():
		var row_y := y + float(i) * _row_step() - _scroll
		if row_y > view.end.y or row_y + _row_step() < view.position.y:
			continue
		var cols := _table_cols()
		var chip := _row_draw_rect(i)
		draw_style_box(row_sb if i == sel else row_idle_sb, chip)
		# Выбранная строка всегда на жёлтом — тёмным текстом.
		var tcol := INK if i == sel else _ink()
		var cy := chip.get_center().y
		if editing == i:
			# Редактируем: поле вместо имени.
			_draw_edit_field(cols[0] + 8.0 * k, cy, int(FONT_ROW * k), cols[1] - cols[0] - 16.0 * k)
		else:
			# Имя с отступом от края бокса (автор 15.10.2026: примыкало),
			# по вертикали — в центре рисуемой строки.
			var nm := _short_name(users[i])
			var nfs := _table_name_fs(users[i])
			_text_fs(
				nm,
				Vector2(cols[0] + 8.0 * k, cy + float(_font_h(nfs)) * 0.35),
				nfs, tcol
			)
		if not (editing == i and editing_new):
			# У создаваемого профиля статистики нет — только поле и чипы.
			var cells := _cell_texts(users[i])
			var cfs := _table_cell_fs()
			_text_fs(cells[0], Vector2(cols[1], row_y), cfs, tcol)
			_text_fs(cells[1], Vector2(cols[2], row_y), cfs, tcol)
		# Галочка «Про» по центру своей колонки. Цвет — от БОКСА, а не
		# от строки: бокс белый днём и тёмный ночью, а цвет строки
		# (tcol) на выбранной строке тёмный всегда — ночью галочка
		# тонула в тёмном боксе, стоило навести выделение.
		var chk_col := Ui.INK_NIGHT if night else INK
		# Выбранная стрелками галка залита своим боксом (selbox_sb),
		# заголовок колонки подсвечен выше. Рамки было не видно
		# в длинном списке.
		var pro_box := box_sb
		var yo_box := box_sb
		if i == sel:
			if sel_col == 0:
				pro_box = selbox_sb
			else:
				yo_box = selbox_sb
		var pcx := (cols[3] + cols[4]) * 0.5
		draw_style_box(pro_box, Rect2(pcx - 16.0 * k, cy - 16.0 * k, 32.0 * k, 32.0 * k))
		# Галка на залитом боксе — тёмная всегда (заливка светлая
		# в обеих темах), на обычном — от темы.
		var pro_chk := INK if pro_box == selbox_sb else chk_col
		if _row_flag(i, "pro"):
			draw_line(
				Vector2(pcx - 10.0 * k, cy + 4.0 * k),
				Vector2(pcx, cy + 14.0 * k),
				pro_chk, 4.0 * k
			)
			draw_line(
				Vector2(pcx, cy + 14.0 * k),
				Vector2(pcx + 16.0 * k, cy - 10.0 * k),
				pro_chk, 4.0 * k
			)
		# Галочка «Ё» по центру своей колонки: тот же бокс, тот же цвет.
		var ycx := (cols[4] + cols[5]) * 0.5
		draw_style_box(yo_box, Rect2(ycx - 16.0 * k, cy - 16.0 * k, 32.0 * k, 32.0 * k))
		var yo_chk := INK if yo_box == selbox_sb else chk_col
		if _row_flag(i, "yo"):
			draw_line(
				Vector2(ycx - 10.0 * k, cy + 4.0 * k),
				Vector2(ycx, cy + 14.0 * k),
				yo_chk, 4.0 * k
			)
			draw_line(
				Vector2(ycx, cy + 14.0 * k),
				Vector2(ycx + 16.0 * k, cy - 10.0 * k),
				yo_chk, 4.0 * k
			)
		# Крестик: удаление у игроков, отмена в редактировании.
		var dcx := (cols[5] + cols[6]) * 0.5
		var dtxt := "✕"
		var dw := _text_size(dtxt, FONT_ROW)
		_text(dtxt, Vector2(dcx - dw.x * 0.5, row_y), FONT_ROW, _danger())
	_draw_top_mask(view)
	_draw_list_mask(view)
	_draw_table_head()
	_draw_scrollbar()
	_draw_list_frame(view)
	_draw_hover_tip()


## Шапка колонок: имена столбцов над строками. Рисуется после верхней
## маски (см. _draw_top_mask), поэтому её нельзя перекрыть ни строкой,
## ни её боксом.
func _draw_table_head() -> void:
	if users.is_empty():
		return
	var y := _rows_top() - 56.0 * k
	var hcols := _table_cols()
	var hfs := _table_head_fs()
	_text_fs("Имя", Vector2(hcols[0] + 8.0 * k, y), hfs, _dim())
	_text_fs("Ур", Vector2(hcols[1], y), hfs, _dim())
	_text_fs("Победы", Vector2(hcols[2], y), hfs, _dim())
	var pro_hw := _text_size_fs("Про", hfs).x
	_text_fs(
		"Про",
		Vector2((hcols[3] + hcols[4]) * 0.5 - pro_hw * 0.5, y),
		hfs, _ink() if sel_col == 0 else _dim()
	)
	var yo_hw := _text_size_fs("Ё", hfs).x
	_text_fs(
		"Ё",
		Vector2((hcols[4] + hcols[5]) * 0.5 - yo_hw * 0.5, y),
		hfs, _ink() if sel_col == 1 else _dim()
	)


## Маска над окном списка: непрозрачная полоса от верха экрана до окна.
## Строка, ушедшая вверх при прокрутке, обрезается ею, а не лезет на шапку
## колонок и выше — за рамку (автор 16.10.2026). Короткой полосы хватало,
## только пока список не листали: уехавшая далеко строка показывалась над
## ней, в зоне заголовка. Шапка колонок, зайчик и верхняя панель рисуются
## позже поверх маски, их она не трогает.
func _draw_top_mask(view: Rect2) -> void:
	if view.position.y <= 0.0:
		return
	var paper := Ui.PAPER_NIGHT if night else PAPER
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(view_w, view.position.y)),
		paper
	)


## Карточки игроков: три своих ряда (имя во всю ширину, статистика,
## три равные кнопки под палец) плюс маска снизу — список листается,
## и карточка, ушедшая за окно, не лезет на поле ввода. Тап по строке
## только выделяет (играет дабл-клик или Enter), тап по кнопке — только
## флаг, крестик удаляет.
func _draw_cards() -> void:
	var view := _list_rect()
	for i in _row_count():
		var card := _card_rect(i)
		if card.position.y > view.end.y or card.end.y < view.position.y:
			continue
		draw_style_box(row_sb if i == sel else row_idle_sb, card)
		# Выбранная карточка всегда на жёлтом — тёмным текстом.
		var tcol := INK if i == sel else _ink()
		var x := card.position.x + _CARD_IN * k
		var inner := card.size.x - _CARD_IN * k * 2.0
		if editing == i:
			# Редактируем: поле вместо имени.
			var efs := _card_fs(FONT_CARD_NAME)
			_draw_edit_field(x, card.position.y + _CARD_PAD * k + float(_font_h(efs)) * 0.65, efs, inner)
		else:
			# Ряд 1: имя во всю ширину (обрезка — в _short_name).
			var name := _short_name(users[i])
			var nfs := _card_name_fs(name)
			var nsz := _text_size_fs(name, nfs).y
			var ny := card.position.y + _CARD_PAD * k + nsz
			_text_fs(name, Vector2(x, ny), nfs, tcol)
		# Ряд 2: статистика во всю ширину, мелко и приглушённо.
		# У создаваемого профиля её нет — только поле и чипы.
		if not (editing == i and editing_new):
			var cells := _cell_texts(users[i])
			var sfs := _card_fs(FONT_CARD_STATS)
			var stat := _clip_fs("%s · %s" % [cells[0], cells[1]], sfs, inner)
			var ssz := _text_size_fs(stat, sfs).y
			var sy := card.position.y + _CARD_PAD * k + float(_font_h(_card_fs(FONT_CARD_NAME))) + 8.0 * k + ssz
			_text_fs(stat, Vector2(x, sy), sfs, _uitext() if i != sel else INK)
		_card_chip(i, "pro", "Про")
		_card_chip(i, "yo", "Ё")
		# Крестик: удаление у игроков, отмена в редактировании.
		var del := _card_btn_rect(i, "del")
		draw_style_box(box_sb, del)
		var dfs := _card_fs(FONT_ROW)
		var dtxt := "✕"
		var dw := _text_size_fs(dtxt, dfs)
		_text_fs(
			dtxt,
			Vector2(
				del.get_center().x - dw.x * 0.5,
				del.get_center().y + dw.y * 0.3
			),
			dfs, _danger()
		)
	_draw_top_mask(view)
	_draw_list_mask(view)
	_draw_scrollbar()
	_draw_list_frame(view)


## Скроллбар списка (автор 15.10.2026: когда пунктов много): тонкая
## полоса у правого края окна, бегунок — доля видимого. Рисуем поверх
## маски, чтобы был виден всегда, пока список листается.
func _draw_scrollbar() -> void:
	var max_sc := _list_max_scroll()
	if max_sc <= 0.0 or users.is_empty():
		return
	# Цвета — от темы: тёмный бегунок на тёмном фоне ночью было практически
	# не видно (автор 16.10.2026). Днём — тёмный на бумаге, ночью — светлый
	# на тёмном, той же семьи, что ночные обводки (#8b93a8).
	var view := _list_rect()
	var w := maxf(5.0 * k, 4.0)
	var x := view.end.x - w - 3.0 * k
	var track_col := Color(0.2, 0.18, 0.14, 0.18) if not night else Color(1, 1, 1, 0.10)
	var thumb_col := Color(0.2, 0.18, 0.14, 0.65) if not night else Ui.DIM_NIGHT
	draw_rect(Rect2(x, view.position.y, w, view.size.y), track_col)
	var th := maxf(24.0 * k, view.size.y * view.size.y / (view.size.y + max_sc))
	var ty := view.position.y + (view.size.y - th) * (_scroll / max_sc)
	draw_rect(Rect2(x, ty, w, th), thumb_col)


## Рамка вокруг окна списка (автор 16.10.2026: списку не хватало рамки).
## Скруглённый тихий контур в стиле пилюли-подсказки: граница области
## видна, но не выбивается. Контент из-под неё не выглядывает (низ держит
## _list_end_pad).
func _draw_list_frame(view: Rect2) -> void:
	if list_frame_sb == null:
		return
	draw_style_box(list_frame_sb, view)


## Маска под окном списка: непрозрачная полоса между окном и кнопками.
## Уехавшая вниз при прокрутке строка обрезается ею. Сверху маски не
## нужно: прокрутка ограничена так, что первая строка не поднимается
## выше окна.
func _draw_list_mask(view: Rect2) -> void:
	var paper := Ui.PAPER_NIGHT if night else PAPER
	draw_rect(
		Rect2(
			Vector2(0.0, view.end.y), Vector2(view_w, _buttons_y() - view.end.y)
		),
		paper
	)



## Подпись на кнопке карточки (Про / Ё / ✕): кегль карточки, а не
## табличный, иначе на растянутой карточке подпись тонет.
## Чип-флаг в карточке: «Про» и «Ё».
##
## Состояние — ЗНАКОМ и своей заливкой (автор 16.10.2026: «включение и
## выключение кнопки про почему-то никак не отличается», а «Ё»
## закрашивалась в цвет фона выделенной строки — выделение внутри
## выделения»):
##   включено — «✓ Про» на зелёном (chip_on_sb), тёмный текст;
##   выключено — пустая рамка box_sb, подпись приглушённая;
##   выделение колонки с клавиатуры — ТОЛЬКО ободок (chip_focus_sb),
##   иначе фокус опять спрятал бы состояние.
func _card_chip(i: int, which: String, label: String) -> void:
	var r := _card_btn_rect(i, which)
	var lit := i == sel and sel_col == (0 if which == "pro" else 1)
	var on := _row_flag(i, which)
	var txt := ("✓ " if on else "") + label
	var fs := _card_fs(FONT_ROW)
	# «✓ Про» на узкой карточке не влезает — ужимаем кегль, а не режем
	# подпись (иначе состояние снова не читается).
	var room: float = r.size.x - 12.0 * k
	while fs > 9 and _text_size_fs(txt, fs).x > room:
		fs -= 1
	var sz := _text_size_fs(txt, fs)
	draw_style_box(chip_on_sb if on else box_sb, r)
	if lit:
		# Ободок — ПО ПОДЛОЖКЕ: на тёмной ночной рамке нужен светлый,
		# на светлом чипе и жёлтой строке — тёмный. Один цвет на оба
		# случая даёт 1.1:1 (см. theme_test).
		chip_focus_sb.border_color = (
			Ui.FOCUS_LIGHT if (night and not on) else Ui.FOCUS_DARK
		)
		draw_style_box(chip_focus_sb, r)
	_text_fs(
		txt,
		Vector2(r.get_center().x - sz.x * 0.5, r.get_center().y + sz.y * 0.3),
		fs, Ui.ACCENT_INK if on else _uitext()
	)



## Зайчик рядом с заголовком: тот же спрайт, что в игре.
func _draw_bunny(c: Vector2) -> void:
	var sq := _bunny_sq()
	var s := 76.0 * k / HERO_TEX.get_height()
	# Ноги стоят: присед идёт от земли, а не из центра.
	var feet := c + Vector2(0.0, -(1.0 - sq.y) * 38.0 * k)
	draw_set_transform(feet, 0.0, Vector2(s * sq.x, s * sq.y))
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5, (Ui.NIGHT_TINT if night else Color.WHITE))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
