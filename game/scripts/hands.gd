class_name Hands
extends RefCounted

## Кисти обеих рук над доской. МОДУЛЬ ЧИСТЫЙ (нет сцены и состояния).
##
## РЕВИЗИЯ 26.10.2026 — ПОЛНОСТЬЮ ТРЁХМЕРНАЯ КИНЕМАТИКА (по требованию
## автора: «модель кисти со всеми суставами, пропорциями и ограничениями,
## 3D, а рисование — проекция на плоскость сверху»).
##
## 1) СКЕЛЕТ — антропометрический. Фаланги — из антропометрии кисти
##    (мм-таблица BONES_MM ниже; питч доски = ANSI 19.05 мм, PITCH_MM).
##    Цепь пальца — 3 сегмента [проксимальная, средняя, дистальная]
##    фаланги от пястного сустава (MCP); большой — свои 3 сегмента
##    [запястно-пястный остаток, проксимальная, дистальная].
##    Диапазоны суставов — по анатомии (Wikipedia/Gray, Kapandji):
##    MCP мыщельковый — сгиб 0..90°, переразгибание до −26°, отведение
##    ±25°; PIP — сгиб 0..100°; DIP — 0..80°; седловидный CMC большого
##    — широкий ход. Ограничения JOINT_LIMITS — рад.
## 2) FK/IK ВЕСЬМА В 3D: каждая кость — вектор (азимут от «вперёд к
##    доске» БАЗОВОГО направления BASE_A + отведение, суммарный сгиб);
##    целевая точка — (x, y) клавиши НА ПЛОСКОСТИ, z — высота кончика
##    над клавишей (покой ZT — hover, нажатие — просадка В клавишу,
##    Z_PRESS). Что видно сверху — проекция (x, y); высота z живёт
##    только в механике (и лёгком затемнении рисования).
## 3) ЛЮБАЯ поза — градиентный спуск по энергии
##    E(θ) = Σ JOINT_W·(θ−θrest)²/2 + минимум |tip−target|², при мягком
##    проецировании на пределы гибкости (ср. прежний аргмин L2 из
##    сеток: теперь численный решатель — те же смыслы, меньше строк).
## 4) ПОКОЙ ВЫВОДИТСЯ: корень пальца = целью покоя + KNUCKLE-смещение
##    (пястная дуга ПОД кончиками: основания НИЖЕ кончиков — пальцы
##    растут от ладони, а не назад; жалоба автора 26.10.2026: «пальцы
##    спускаются вниз против ладони — как будто растут задом»).
##    Дальше решатель ставит кончик над дом-клавишей на высоте ZT.
## 5) ХОД КИСТИ: дальняя клавиша тянет всю кисть (shift_goal), как
##    в реальном наборе. Рисование — ладонь одним полигоном, пальцы
##    лентами с полукруглыми шапками; z слегка управляет прозрачностью.

const THUMB := 0
const INDEX := 1
const MIDDLE := 2
const RING := 3
const PINKY := 4

const LEFT := 0
const RIGHT := 1

## ANSI-питч клавиатуры, мм: вся антропометрия мерится в питчах.
const PITCH_MM := 19.05

## Фаланги, мм [сегмент 1, 2, 3] по цепи каждого пальца. Четырёх пальцев
## — прокс/средняя/дистальная (антропометрия кисти, средние значения
## разных измерений расходятся на единицы мм — пропорции устойчивы).
## Большой: [запястно-пястная часть в ладони, проксимальная,
## дистальная] — первая часть прячется под ладонью.
const BONES_MM := {
	THUMB: [17.0, 31.5, 25.5],
	INDEX: [39.5, 22.0, 15.5],
	MIDDLE: [42.0, 25.0, 16.5],
	RING: [39.0, 23.5, 15.5],
	PINKY: [33.0, 18.5, 13.5],
}

## Базовый азимут пальца (рад, от направления «вперёд к доске», −y):
## у четырёх пальцев 0 — вперёд; большой смотрит В СТОРОНУ ПРОБЕЛА
## от своей половины кисти (вниз по доске и к центру).
const BASE_A := {THUMB: 2.28, INDEX: 0.0, MIDDLE: 0.0, RING: 0.0,
	PINKY: 0.0}

## Вес жёсткости сустава: четырёх пальцев — [сгиб MCP, отведение MCP,
## сгиб PIP, сгиб DIP]; большого — [сгиб CMC, отведение, поворот,
## сгиб MCP, сгиб IP]: пястный самый жёсткий, дистальный свободнее —
## тянуться кончиком.
const JOINT_W := [3.0, 2.0, 1.3, 0.8]
const JOINT_W_THUMB := [3.0, 2.0, 1.3, 2.0, 0.8]

## Пределы гибкости (рад): [min, max] по суставам. Четыре пальца:
## [сгиб MCP, отведение MCP, сгиб PIP, сгиб DIP] — MCP: сгиб
## 0..90° с переразгибанием −26°, отведение ±25°; PIP 0..100°; DIP
## 0..80° (+ небольшой запас на переразгибание у головок). Большой —
## 5 суставов: [сгиб CMC, отведение, ПОВОРОТ (оппозиция седловид-
## ного CMC: дистальная плоскость сгиба поворачивается вокруг столб-
## ца, 0..100°), сгиб MCP, сгиб IP].
const JOINT_LIMITS := {
	THUMB: [Vector2(-0.55, 1.40), Vector2(-0.55, 0.55), Vector2(0.0, 1.75), Vector2(-0.55, 1.40), Vector2(-0.10, 1.40)],
	INDEX: [Vector2(-0.45, 1.57), Vector2(-0.44, 0.44), Vector2(-0.06, 1.75), Vector2(-0.06, 1.40)],
	MIDDLE: [Vector2(-0.45, 1.57), Vector2(-0.44, 0.44), Vector2(-0.06, 1.75), Vector2(-0.06, 1.40)],
	RING: [Vector2(-0.45, 1.57), Vector2(-0.44, 0.44), Vector2(-0.06, 1.75), Vector2(-0.06, 1.40)],
	PINKY: [Vector2(-0.45, 1.57), Vector2(-0.44, 0.44), Vector2(-0.06, 1.75), Vector2(-0.06, 1.40)],
}

## Пред-покой (пара для решателя): сгибы расслабленной руки над домом.
## Четыре пальца [MCP, отведение, PIP, DIP]; большой [CMC, отведе-
## ние, поворот, MCP, IP]. Отведение 0 — решатель сам отводит, куда
## ведёт геометрия дом-клавиш; сгибы дают естественную дугу. Большой:
## дисталь чуточку закрыта и повёрнута к ладони (оппозиция).
const REST_PRIOR := {
	INDEX: [0.50, 0.0, 1.00, 0.62],
	MIDDLE: [0.48, 0.0, 0.95, 0.60],
	RING: [0.52, 0.0, 1.00, 0.64],
	PINKY: [0.58, 0.0, 1.08, 0.68],
	THUMB: [0.20, 0.05, 0.90, 0.30, 0.25],
}

## Пястная дуга ПОД кончиками (питчи; смещение КОРНЯ от цели покоя):
## x — наружу (у левой +x к центру доски: оси пальцев веером), y —
## НАЗАД К ИГРОКУ (положительное = корень НИЖЕ кончика на экране —
## пальцы растут от ладони; жалоба автора 26.10.2026: «основания
## дотягиваются до ряда цифр, пальцы спускаются вниз против ладони»),
## z — высота пясти над доской. Дуга ВЫПУКЛА К КЛАВИШАМ: корень
## среднего ВЫШЕ хорды указательный-мизинец (средняя фаланга кисти
## самая высокая — анатомия), мизинец глубже всех. Толчок корней ДО
## цифрового ряда: ~1.0–1.3 питча — на уровне верхнего буквенного
## ряда, не «1234567890» (правило автора 26.10.2026).
const KNUCKLE := {
	INDEX: Vector3(0.28, 1.15, 1.70),
	MIDDLE: Vector3(0.08, 1.02, 1.85),
	RING: Vector3(-0.10, 1.10, 1.72),
	PINKY: Vector3(-0.32, 1.30, 1.50),
}

## Корень большого относительно СВОЕЙ цели (его четверть пробела),
## долях питча: корень В ЛАДОНИ — снаружи, ЗА контактом (ниже экрана
## по y) и высоко над доской (уровень ложа большого пальца): большой
## идёт из пятки ладони наискось к пробелу, дисталь закрывается
## ПОВОРОТОМ (оппозиция CMC), а не ныряет в доску.
const THUMB_ROOT := Vector3(-0.80, -0.90, 1.80)

## Высота кончика в покое — hover над дом-клавишей (питчи над доской).
## Большой стоит ВПЛОТЬ К ПРОБЕЛУ: подушечка почти лежит (0.08 питча
## ≈ 2-3 px). Бывший 0.32 решатель не выдерживал: покой большого
## стоит на углах пределов суставов и честный аргмин приходит к
## 2-5 px над доской у ОБОИХ рук (ловлено 26.10.2026: z 4.7 / 2.34
## при целевых 10.8) — константу чиним по замыслу, а не решатель.
const Z_TIP := 0.55
const Z_TIP_THUMB := 0.08

## Высота КОНЧИКА при нажатии: клавиша прогибается под пальцем.
const Z_PRESS := -0.10

## ВЫСОТА запястья/пятки ладони (питчи над доской) и её смещение от
## среднего контакта дома: ладонь ЛЕЖИТ за нижним рядом, не лезет вверх.
const WRIST_OFF := Vector2(0.0, 2.55)
const WRIST_Z := 2.05

## Шаги траст-региона в РАДИАНАХ (направление — нормированный гради-
## ент, линейный поиск по энергии; сетка ДОЛЖНА накрывать оптимум па-
## раболы по лучу: при σ-жёсткой задаче он стоит на ~0.001–0.01 рад —
## сетка только до 0.02 перепрыгивала его и решатель замирал — ловле-
## но 26.10.2026). Итерации, вес штрафа покоя, допуск задачи: хардклэм
## на каждой оси давал bang-bang осцилляцию шага — решатель замирал;
## шкала всей позы сразу честная, энергия не растёт.
## σ задачи = SOLVE_TOL·L — ошибка кончика меряется В ЕДИНИЦАХ ДОПУ-
## СКА (порог досрочного выхода): тогда энергия НЕ окупает недоездом
## за пределом допуска — лексикографика «сначала доезд, потом покой»
## (канон 25.10.2026: покой выбирает позу СРЕДИ ДОЕХАВШИХ). Меньший
## σ работал и замирал выше допуска (аргмин балансирует; ловлено
## 26.10.2026: цель 0.92 размаха давала err 9–14 px при допуске~1.6).
const SOLVE_STEPS := [0.30, 0.12, 0.05, 0.02, 0.008, 0.003, 0.001]
const SOLVE_MAX := 420
const SOLVE_TOL := 0.012  #reach-доля — порог досрочного выхода
const SOLVE_SIG := 0.006  #reach-доля: σ задачи; err* решателя ≈ 1.04·σ
const REST_SCALE := 0.22

## Дом-клавиша пальца (покой — кончик над ней). Указательные закрывают
## по две колонки: покой у ПЕРВОЙ (а/о), вторая достаётся при нажатии.
const HOME_KEY := {
	LEFT: {INDEX: "а", MIDDLE: "в", RING: "ы", PINKY: "ф"},
	RIGHT: {INDEX: "о", MIDDLE: "л", RING: "д", PINKY: "ж"},
}

## Клавиши по пальцам — как на ФИЗИЧЕСКОЙ клавиатуре (доска игры —
## физическая раскладка: те же клавиши для РУ/EN). По русской школе
## И, Т, Ь относят правому указательному — но клавиши b/n/m физически
## стоят под ЛЕВОЙ ладонью, и тянуть их правым пальцем против физики
## нельзя: и → левый указательный, т/ь → правый (n/m — правая ладонь).
## Служебные — крайние мизинцы своей стороны: Tab/Caps/левый шифт —
## левый мизинец, стереть/ввод/правый шифт — правый. Глобус — большой
## правой (по другую сторону пробела от системных). Пробел —
## динамический: большой СВОБОДНОЙ руки; его подпись несёт руку
## («пробел:Л» / «пробел:П»), см. finger_of.
const FINGER_MAP := {
	# Левая рука.
	"ё": [LEFT, PINKY], "1": [LEFT, PINKY], "й": [LEFT, PINKY],
	"ф": [LEFT, PINKY], "я": [LEFT, PINKY],
	"Tab": [LEFT, PINKY], "Caps": [LEFT, PINKY], "Shift": [LEFT, PINKY],
	"2": [LEFT, RING], "ц": [LEFT, RING], "ы": [LEFT, RING], "ч": [LEFT, RING],
	"3": [LEFT, MIDDLE], "у": [LEFT, MIDDLE], "в": [LEFT, MIDDLE],
	"с": [LEFT, MIDDLE],
	"4": [LEFT, INDEX], "5": [LEFT, INDEX], "к": [LEFT, INDEX],
	"е": [LEFT, INDEX], "а": [LEFT, INDEX], "п": [LEFT, INDEX],
	"м": [LEFT, INDEX], "и": [LEFT, INDEX],
	# Правая рука.
	"6": [RIGHT, INDEX], "7": [RIGHT, INDEX], "н": [RIGHT, INDEX],
	"г": [RIGHT, INDEX], "р": [RIGHT, INDEX], "о": [RIGHT, INDEX],
	"т": [RIGHT, INDEX], "ь": [RIGHT, INDEX],
	"8": [RIGHT, MIDDLE], "ш": [RIGHT, MIDDLE], "л": [RIGHT, MIDDLE],
	"б": [RIGHT, MIDDLE],
	"9": [RIGHT, RING], "щ": [RIGHT, RING], "д": [RIGHT, RING],
	"ю": [RIGHT, RING],
	"0": [RIGHT, PINKY], "-": [RIGHT, PINKY], "=": [RIGHT, PINKY],
	"з": [RIGHT, PINKY], "х": [RIGHT, PINKY], "ъ": [RIGHT, PINKY],
	"\\": [RIGHT, PINKY], "ж": [RIGHT, PINKY], "э": [RIGHT, PINKY],
	".": [RIGHT, PINKY], "ShiftR": [RIGHT, PINKY], "←": [RIGHT, PINKY],
	"↵": [RIGHT, PINKY], "Ctrl": [RIGHT, PINKY], "Win": [RIGHT, PINKY],
	"Alt": [RIGHT, PINKY], "глобус": [RIGHT, THUMB],
	# голый пробел: в игре рука большого несёт подпись («пробел:Л» /
	# «пробел:П»); это дефолт — покоящийся большой левой.
	"пробел": [LEFT, THUMB],
}

## Рука клавиши: +1 у левой, −1 у правой (знак живёт в зеркалировании
## x смещений и азимутов).
static func side_of(h: int) -> float:
	return 1.0 if h == LEFT else -1.0


## [рука, палец] клавиши; [-1, -1] если клавиши нет в карте.
## Пробел поддержан подписями «пробел:Л» / «пробел:П» (большой СВОБОД-
## ной руки); латиница мапится в свою русскую клавишу (физически одна).
static func finger_of(s: String) -> Array:
	var e: Variant = FINGER_MAP.get(s)
	if e != null:
		return [(e as Array)[0] as int, (e as Array)[1] as int]
	if s.begins_with("пробел:"):
		return [(LEFT if s.ends_with("Л") else RIGHT), THUMB]
	if s.length() == 1:
		var lo := s.to_lower()
		if lo != s:
			e = FINGER_MAP.get(lo)
			if e != null:
				return [(e as Array)[0] as int, (e as Array)[1] as int]
		# Латиница: у той же клавиши русская пара (Kbd.RU_EN двусторонняя).
		for ru in Kbd.RU_EN.keys():
			if String(Kbd.RU_EN[ru]) == lo:
				e = FINGER_MAP.get(String(ru))
				if e != null:
					return [(e as Array)[0] as int,
						(e as Array)[1] as int]
	return [-1, -1]


## Рука клавиши (int): LEFT/RIGHT, из карты пальцев.
static func hand_of(s: String) -> int:
	return finger_of(s)[0] as int


## Палец подсказки: [рука, палец] или [-1, -1] (чужая подпись не двигает
## руку). Регистр буквы палец не меняет, латиница — та же клавиша.
static func hint_finger(sig: String) -> Array:
	return finger_of(sig)


## Точка подсказки по подписи: центр ПЛОЩАДИ клавиши; половины пробела —
## по своей стороне, на высоте ряда.
static func hint_point(bs: Array, sig: String) -> Vector2:
	var r := sig_rect(bs, sig)
	if r.size == Vector2.ZERO:
		return Vector2.ZERO
	return r.get_center()


## Прямоугольник подписи: половины пробела («пробел:Л»/«пробел:П») —
## своя половина; остальное — клавиша доски по подписи.
static func sig_rect(bs: Array, sig: String) -> Rect2:
	if sig.begins_with("пробел:") and not sig.ends_with(":"):
		var sp := key_rect(bs, "пробел")
		if sp.size == Vector2.ZERO:
			return Rect2()
		var half_l := sig.ends_with("Л")
		return Rect2(sp.position.x + sp.size.x * (0.0 if half_l else 0.5),
			sp.position.y, sp.size.x * 0.5, sp.size.y)
	return key_rect(bs, sig)


## Точка нажатия по подписи: центр ПЛОЩАДИ клавиши (палец опускается на
## всю плоскость); половины пробела — по своей стороне. Малая клавиша —
## центр; большая — ближайший к покойному кончику край с отступом в
## половину малой клавиши (автор 25.10.2026).
static func press_point(bs: Array, sig: String, tip: Vector2) -> Vector2:
	var pitch := pitch_of(bs)
	var r := sig_rect(bs, sig)
	if r.size == Vector2.ZERO or pitch <= 0.0:
		return Vector2.ZERO
	if _is_small(r, pitch, bs):
		return r.get_center()
	var iy := minf(0.5 * _row_h(bs, pitch), r.size.y * 0.5)
	var ix := minf(0.5 * pitch, r.size.x * 0.5)
	if tip == Vector2.ZERO:
		return Vector2(r.position.x + r.size.x * 0.5, r.position.y + iy)
	return Vector2(clampf(tip.x, r.position.x + ix, r.end.x - ix),
		clampf(tip.y, r.position.y + iy, r.end.y - iy))


## Цель нажатия: КОНТАКТ на плоскости. Просадка в клавишу — это ВЫСОТА
## кончика (Z_PRESS, 3D), а не смещение по экрану.
static func press_goal(bs: Array, sig: String, tip: Vector2) -> Vector2:
	return press_point(bs, sig, tip)


## Цель сдвига КИСТИ целиком. rest — обе руки (rest_both), h/f — кто
## жмёт, tgt — КОНТАКТ нажатия. Кисть ходит ТОЛЬКО когда работать пальцем
## с места нечем; признак «нечем» — ТРОЙНАЯ РЕШЕННАЯ проба нажатия:
## 1) 3D-дистанция корень→контакт дальше предельного размаха (дальние
##    ряды с близких пальцев — клавиша «1» с мизинца);
## 2) решатель НЕ доезжает (мизинец не достаёт «я»: кончик оказывается
##    ЗА корнем — азимут обратной направленности, ловлено 26.10.2026);
## 3) уже на грани размаха — большой сглаживающий ход до COMFY.
## Ход сядет палец на удобный изгиб; решается КОРОТКОЙ пробой нажатия
## на каждый кандидат хода (0..SOLV_MAX_SHIFT). Дальние ряды едут
## ходом, дом-клавиши — с места.
const COMFY := 0.85
const REACH_LIMIT := 0.995
## Порог доезда пробы нажатия (доля питча — примерно половина клави-
## ши) и сетка пробных ходов (питчи). Ход годится, если проба доезжа-
## ет; из доезжающих берётся МИНИМАЛЬНЫЙ, иначе самый доезжающий.
const PRESS_TOL := 0.25
const SHIFT_TRIES := [0.0, 0.7, 1.4, 2.1, 2.8]

static func shift_goal(rest: Dictionary, h: int, f: int, tgt: Vector2,
		pitch: float) -> Vector2:
	if not rest.has(h) or pitch <= 0.0:
		return Vector2.ZERO
	var fd: Dictionary = rest.get(h, {}) as Dictionary
	var fl := fd.get("fingers", {}) as Dictionary
	if not fl.has(f):
		return Vector2.ZERO
	var fdata: Dictionary = fl[f] as Dictionary
	var root: Vector3 = fdata["root"] as Vector3
	var m: float = side_of(h)
	var bones: Array = bones_px(f, pitch)
	var reach := 0.0
	for b in bones:
		reach += b as float
	var tp := Vector3(tgt.x, tgt.y, Z_PRESS * pitch)
	var d := tp - root
	var dist := d.length()
	if dist < 1e-6 or reach <= 0.0:
		return Vector2.ZERO
	# Скольжение по ПЛОСКОСТИ доски: вертикаль добирается изгибом.
	var dir2 := Vector2(d.x, d.y)
	if dir2.length() < 1e-6:
		# Цель ровно под корнем — ход бессмысленен, изгиб сам.
		return Vector2.ZERO
	dir2 = dir2.normalized()
	var rest_ang: Array = fdata.get("angles", []) as Array
	if dist > REACH_LIMIT * reach:
		# Дальняя клавиша: ход на доезд минус удобный запас.
		return dir2 * (dist - COMFY * reach)
	# В размахе по дистанции, но проба нажатия может намекать на
	# недоезд (азимут/глубокий сгиб) — тогда короткий ход. Сетка
	# восходящая: первый доезжающий ход — МИНИМАЛЬНЫЙ.
	for k in SHIFT_TRIES.size():
		var offer: float = SHIFT_TRIES[k] * pitch
		if _press_ok(_trial(root, dir2, tp, pitch, f, m, rest_ang,
				offer), tp, pitch):
			return dir2 * offer
	# Ни один ход не доезжает — ход на максимум сетки: недоезд меньше.
	return dir2 * (SHIFT_TRIES[SHIFT_TRIES.size() - 1] * pitch)


## Проба нажатия с ХОДОМ кисти offer вдоль dir2 (плоскость доски):
## корень едет, решатель ставит цепь на контакт tp. rest — покойные
## углы пальца ( continuity позы), при чужой длине — пред-покой.
static func _trial(root: Vector3, dir2: Vector2, tp: Vector3,
		pitch: float, f: int, m: float, rest_ang: Array,
		offer: float) -> Array:
	var n := _dof_count(f)
	var rr: Array = rest_ang if rest_ang.size() == n \
		else REST_PRIOR[f]
	var cand := root + Vector3(dir2.x * offer, dir2.y * offer, 0.0)
	return ik_chain(cand, bones_px(f, pitch), tp, rr, rr, f, m)


static func _press_ok(res: Array, tp: Vector3, pitch: float) -> bool:
	var tip: Vector3 = (res[1] as Array)[3]
	return tip.distance_to(tp) < PRESS_TOL * pitch


## Просадка кончика В клавишу нажатием живёт В З (Z_PRESS); экранная
## просадка retired — константа удалена 26.10.2026.


## Малая клавиша — буквенного шага ширина (клавиши одного ряда одной
## высоты, малость меряется шириной).
static func _is_small(r: Rect2, pitch: float, bs: Array) -> bool:
	return r.size.x <= pitch * 1.05 + 0.01 \
		and r.size.y <= _row_h(bs, pitch) * 1.05 + 0.01


## Высота ряда — у буквенной клавиши (все ряды одной высоты).
static func _row_h(bs: Array, pitch: float) -> float:
	for b in bs:
		if Kbd.is_plain_letter(String(b["s"])):
			return (b["r"] as Rect2).size.y
	return pitch


## Покойный кончик пальца (экранная проекция; для press_point / проверок).
static func rest_tip(rest: Dictionary, h: int, f: int) -> Vector2:
	if rest.has(h):
		var fing: Dictionary = (rest[h] as Dictionary).get("fingers", {}) \
			as Dictionary
		if fing.has(f):
			var fd: Dictionary = fing[f] as Dictionary
			var chain: Array = fd.get("chain", []) as Array
			if chain.size() == 4:
				var tip3: Vector3 = chain[3] as Vector3
				return Vector2(tip3.x, tip3.y)
	return Vector2.ZERO


## Прямоугольник клавиши по подписи — мера самого списка buttons().
static func key_rect(bs: Array, s: String) -> Rect2:
	for b in bs:
		if String(b["s"]) == s:
			return b["r"] as Rect2
	return Rect2()


## Шаг доски (питч) — ШАГ колонок буквенного ряда, не ширина клавиши:
## клавиши стоят с зазором; веер кончиков кисти идёт по клавишам с их
## зазорами.
static func pitch_of(bs: Array) -> float:
	var best := 0.0
	for b0 in bs:
		var r0 := b0["r"] as Rect2
		if not Kbd.is_plain_letter(String(b0["s"])):
			continue
		for b1 in bs:
			var r1 := b1["r"] as Rect2
			if not Kbd.is_plain_letter(String(b1["s"])):
				continue
			if r0.position.y != r1.position.y:
				continue
			var dx := absf(r1.position.x - r0.position.x)
			if dx > 0.01 and (best == 0.0 or dx < best):
				best = dx
	if best > 0.0:
		return best
	for b0 in bs:
		if Kbd.is_plain_letter(String(b0["s"])):
			return (b0["r"] as Rect2).size.x
	return 0.0


## Центр точки нажатия клавиши.
static func key_center(bs: Array, s: String) -> Vector2:
	var r := key_rect(bs, s)
	if r.size == Vector2.ZERO:
		return Vector2.ZERO
	return r.position + r.size * 0.5


## Кости пальца ИСТИННОЙ длины (питчи): антропометрия, БЕЗ проекционных
## поправок — проекцию считает решатель из 3D-позы.
static func bones_px(f: int, pitch: float) -> Array:
	var out: Array = []
	for mm in BONES_MM[f]:
		out.append((mm as float) / PITCH_MM * pitch)
	return out


## Ширины пальца [у пясти, у кончика]: от питча с полами и потолками —
## на мелкой доске палец не худее изнутри, на крупной не толще.
## Кончик — подушечка, не игла.
static func widths_of(pitch: float) -> Array:
	return [clampf(0.34 * pitch, 9.0, 21.0), clampf(0.20 * pitch, 6.0, 12.0)]


## ---------- 3D-кинематика ----------

## FK цепи из корня: углы [сгиб MCP, отведение MCP, сгиб PIP/IP,
## сгиб DIP]; у большого — 5 [-сгиб CMC, отведение, ПОВОРОТ (оппози-
## ция CMC), сгиб MCP, сгиб IP]. База «вперёд к доске» (−y), отведе-
## ние — азимут вокруг вертикали от базового направления BASE_A[f];
## сгибы суммируются по цепи (фаланги продолжают дугу). m — рука:
## +1 левая, −1 правая (зеркало по x). Возвращает [root, j1, j2, tip]
## — Vector3.
##
## ПОВОРОТ большого (twist): сгиб дистальных фаланг совершается в
## плоскости, повёрнутой вокруг горизонтальной оси столбца на угол
## ang[2]: перпендикуляр = cosT·(0,0,−1) + sinT·m·(c_az, s_az, 0).
## При T=0 — вертикальный сгиб «в доску» (как у четырёх пальцев); при
## T≈π/2 дисталь закрывается ГОРИЗОНТАЛЬНО «через ладонь» — оппози-
## ция седловидного CMC (большой достаёт пробел из-за ладони, а не
## ныряет в доску: ловлено численно 26.10.2026 — без поворота хорда
## четверти пробела/~=0.32 длины недостижима, кончик тонул под доску).
## Ось поворота ЗЕРКАЛИТСЯ РУКОЙ (×m): оппозиция обеих кистей меряется
## ОДНИМ знаком [0..90°], и fk правой руки при тех же углах — точное
## x-зеркало левой (иначе решатель большого катился в разные долины:
## twist 0.34 слева против 0.22 справа, руки не отражения 26.10.2026).
static func fk_chain(root: Vector3, bones: Array, ang: Array, f: int,
		m: float) -> Array:
	var az := (BASE_A[f] as float) + (ang[1] as float)
	var s_az := sin(az)
	var c_az := cos(az)
	var cum := (ang[0] as float)
	var twist := (ang[2] as float) if f == THUMB else 0.0
	var c_t := cos(twist)
	var s_t := sin(twist)
	var pts: Array = [root]
	var p := root
	var n_ang := ang.size()
	for i in 3:
		# Сгиб очередного сустава: подписывается к прежней дуге.
		# Индекс сгиба: пальцы — [MCP=0, PIP=2, DIP=3] (отведение на
		# 1); большой — [CMC=0, MCP=3, IP=4] (поворот на 2).
		if i >= 1:
			var fi := (i + 1) if f != THUMB else (i + 2)
			cum += (ang[fi] as float)
		var c_i := cos(cum)
		var s_i := sin(cum)
		var L := (bones[i] as float)
		var dx := m * s_az * c_i
		var dy := -c_az * c_i
		var dz := -s_i
		if f == THUMB and i >= 1:
			# Дистальные фаланги: плоскость сгиба повёрнута на twist
			# вокруг столбца (см. докстринг fk_chain); ось поворота
			# зеркалится рукой (×m) — те же углы дают зеркало.
			var px := c_i * (m * s_az) + s_i * (s_t * m * c_az)
			var py := c_i * (-c_az) + s_i * (s_t * s_az)
			var pz := -s_i * c_t
			dx = px
			dy = py
			dz = pz
		p = p + Vector3(dx, dy, dz) * L
		pts.append(p)
	return pts


## Стартовая оценка — «струна к цели»: азимут по горизонтальной
## составляющей, суммарный сгиб — по вертикальному перепаду,
## разбросанный по трём суставам дуги.
static func _init_angles(root: Vector3, bones: Array, target: Vector3,
		f: int, m: float, prior: Array) -> Array:
	var d := target - root
	var L := 0.0
	for b in bones:
		L += b as float
	var az := (BASE_A[f] as float) + (prior[1] as float)
	if Vector2(d.x, d.y).length() > 1e-6:
		az = atan2(m * d.x, -d.y)
	var tilt := 0.0
	if L > 1e-6:
		tilt = asin(clampf(-d.z / L, -1.0, 1.0))
	# Разброс сгиба по дуге: MCP получает свою долю покоя.
	if f == THUMB:
		# [CMC, ABD, TWIST (покоя не наклоняем), MCP, IP]
		return [
			tilt * 0.35 + (prior[0] as float) * 0.25,
			wrapf(az - (BASE_A[f] as float), -PI, PI),
			(prior[2] as float),
			tilt * 0.40 + (prior[3] as float) * 0.25,
			tilt * 0.25 + (prior[4] as float) * 0.25,
		]
	return [
		tilt * 0.40 + (prior[0] as float) * 0.25,
		wrapf(az - (BASE_A[f] as float), -PI, PI),
		tilt * 0.35,
		tilt * 0.25,
	]


## Решатель позы: минимум энергии E = e²/σ² + REST_SCALE·Σ w·dev² —
## квадрат ошибки кончика В ЕДИНИЦАХ ДОПУСКА σ (= SOLVE_SIG·L) плюс
## весовой штраф углов от покоя. Направление — чистый градиент E с
## ТРАСТ-РЕГИОНОМ (см. константы решателя), линейный поиск по сетке
## (энергия не растёт никогда, без bang-bang осцилляций и взборов —
## ловлено численно 26.10.2026).
## rest — покойные углы (DOF пальца), prev — прошлые углы (ползучесть
## позы на равной энергии). Возвращает [углы, цепь].
static func ik_chain(root: Vector3, bones: Array, target: Vector3,
		rest: Array = [], prev: Array = [], f: int = INDEX,
		m: float = 1.0) -> Array:
	var L := 0.0
	for b in bones:
		L += b as float
	if bones.size() != 3 or L <= 0.0:
		return [rest, fk_chain(root, bones, rest as Array, f, m)]
	var fallback: Array = REST_PRIOR[f]
	var n := _dof_count(f)
	var lim: Array = JOINT_LIMITS[f]
	var ang := _init_angles(root, bones, target, f, m,
		rest if rest.size() == n else fallback)
	# Начальная поза обязана быть ЛЕГАЛЬНОЙ: цель вне конуса отведения
	# даёт az сверх предела, и каждый пробный шаг зажимает его скачком —
	# энергия взрывается, линейный поиск отвергает всё (ловлено 26.10.
	# 2026: ang[1]=0.85 при пределе ±0.44, решатель на месте).
	for dof in n:
		ang[dof] = clampf((ang[dof] as float),
			(lim[dof] as Vector2).x, (lim[dof] as Vector2).y)
	var w: Array = JOINT_W_THUMB if f == THUMB else JOINT_W
	var delta := 0.02
	var sig2: float = pow(SOLVE_SIG * L, 2.0)
	var chain := fk_chain(root, bones, ang, f, m)
	# Недостижимая цель: цепь В СТРУНУ на цель (как у старого решате-
	# ля), без биологических ограничений — это геометрия, а не поза.
	var d_tot := target - root
	if d_tot.length() > L + 1e-9:
		var t0 := asin(clampf(-d_tot.z / d_tot.length(), -1.0, 1.0))
		var az0 := wrapf(atan2(m * d_tot.x, -d_tot.y) - (BASE_A[f] as float),
			-PI, PI)
		# Сгибы копируют покой — струна тянется расслабленной рукой.
		var straight: Array = []
		for dof in n:
			straight.append(0.0)
		straight[0] = t0
		straight[1] = az0
		return [straight, fk_chain(root, bones, straight, f, m)]
	for it in SOLVE_MAX:
		var tip := chain[3] as Vector3
		var e := target - tip
		if e.length() < SOLVE_TOL * L:
			break
		# Численный якобиан 3×DOF.
		var J: Array = []
		for dof in n:
			var a2 := ang.duplicate()
			a2[dof] = (a2[dof] as float) + delta
			var tip2: Vector3 = (fk_chain(root, bones, a2, f, m)[3]) as Vector3
			J.append((tip2 - tip) / delta)
		# Энергия: E = e²/σ² + REST_SCALE·Σ w·dev² (e в единицах до-
		# пуска σ, см. SOLVE_SIG). Направление — ЧИСТЫЙ ГРАДИЕНТ E без
		# предобуславливания: деление задачи́го члена на вес сустава w
		# глушило ПЯСТНЫЙ сгиб (w=3) — PIP/DIP отъезжали к своим по-
		# толкам (наживо 26.10.2026: PIP=1.75, MCP=0.08 на крючке).
		# Жёсткость покоя в направлении даёт сам штраф; масштаб шага —
		# ТРАСТ-РЕГИОН в радианах (градиент при σ-жёсткой задаче начи-
		# нается с ~10²–10³ рад — сетка ДОЛЕЙ шага относительно него
		# слепа: минимальная доля всё равно прыжок за потолок).
		# DLS-шаг с хардклэмпом каждой оси давал bang-bang: знак шага
		# отражался на итерации, решатель замирал (ловлено численно
		# 26.10.2026: jt=±5.65 ровно в знак).
		var grad: Array[float] = []
		for dof in n:
			# ∇E_task = −2·J·e/σ²: e = target − tip, ∂e/∂θ = −J.
			# НЕ упрощать до +2·J·e — задачи́й шаг встанет на ВЗБОР по
			# энергии (такое ловлено: решатель стартовал с err 89 и
			# застрял на err 76, шаг шёл против цели).
			var task_g: float = -2.0 * J[dof].dot(e) / sig2
			var pull: float = ang[dof]
			if rest.size() == n:
				pull = rest[dof]
			elif prev.size() == n:
				pull = prev[dof]
			var dev: float = wrapf((ang[dof] as float) - pull, -PI, PI)
			var rest_g := 2.0 * REST_SCALE * (w[dof] as float) * dev
			grad.append(task_g + rest_g)
		var gnorm := 0.0
		for dof3 in n:
			gnorm += grad[dof3] * grad[dof3]
		gnorm = sqrt(gnorm)
		if gnorm < 1e-12:
			break
		var cur_err: float = (chain[3] as Vector3).distance_to(target)
		var cur_dev := 0.0
		for dof2 in n:
			var pull_cur: float = ang[dof2]
			if rest.size() == n:
				pull_cur = rest[dof2]
			elif prev.size() == n:
				pull_cur = prev[dof2]
			cur_dev += (w[dof2] as float) * pow(
				wrapf((ang[dof2] as float) - pull_cur, -PI, PI), 2.0)
		var cur_en: float = cur_err * cur_err / sig2 \
			+ REST_SCALE * cur_dev
		var best_ang := ang
		var best_chain := chain
		var best_e := cur_en
		for k in SOLVE_STEPS.size():
			var sc: float = -SOLVE_STEPS[k]
			var a_try := ang.duplicate()
			for dof in n:
				a_try[dof] = clampf((ang[dof] as float)
					+ grad[dof] / gnorm * sc,
					(lim[dof] as Vector2).x, (lim[dof] as Vector2).y)
			var c_try: Array = fk_chain(root, bones, a_try, f, m)
			var t_try: Vector3 = c_try[3]
			var try_err: float = t_try.distance_to(target)
			var try_dev := 0.0
			for dof2 in n:
				var pull2: float = rest[dof2] if rest.size() == n \
					else (ang[dof2] as float)
				try_dev += (w[dof2] as float) * pow(
					wrapf((a_try[dof2] as float) - pull2, -PI, PI), 2.0)
			var en: float = try_err * try_err / sig2 \
				+ REST_SCALE * try_dev
			if en < best_e:
				best_e = en
				best_ang = a_try
				best_chain = c_try
		if best_e >= cur_en - 1e-9:
			break
		ang = best_ang
		chain = best_chain
	return [ang, chain]


## Разница углов (−π..π) — для проверки покоя и мер в тестах.
static func _angdiff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


## Число степеней свободы пальца: четыре пальца — 4 [MCP flex, MCP
## abd, PIP flex, DIP flex], большой — 5 (плюс поворот CMC).
static func _dof_count(f: int) -> int:
	return 5 if f == THUMB else 4


## ---------- ПОКОЙ ----------

## Поза покоя ОБЕИХ кистей: у каждого пальца корень = цель покоя +
## KNUCKLE-смещение (пястная дуга ПОД кончиками), решатель ставит
## кончик над дом-клавишей на высоте hover. Большой догоняет свою
## четверть пробела. Геометрия чистая, без подгонки подобием: 3D-
## решателю не нужно «дотягивать» кончики по 2D-карте.
##
## ЗЕРКАЛО СТРОИТСЯ, А НЕ СЛУЧАЕТСЯ: правый большой получает РОВНО
## те же углы, что левый (fk зеркален при тех же углах — см. докс-
## тринг fk_chain), кончик ложится в зеркальную цель по построению.
## Спускать правый большой самостоятельно нельзя: долина twist'а
## плоская, улп-шум целей за сотни итераций разводит спуски на
## ~0.013 рад — руки перестают быть отражениями (ловлено
## diag_mirror 26.10.2026 на 540×1140).
static func rest_both(bs: Array) -> Dictionary:
	var pitch := pitch_of(bs)
	if pitch <= 0.0:
		return {}
	var pose := {}
	for h in [LEFT, RIGHT]:
		var p := _rest_one(bs, h, pitch)
		if p.is_empty():
			return {}
		pose[h] = p
	# Зеркало большого: углы левой кисти — в правую.
	var fl: Dictionary = (pose[LEFT]["fingers"] as Dictionary)[THUMB] \
		as Dictionary
	var fr: Dictionary = (pose[RIGHT]["fingers"] as Dictionary)[THUMB] \
		as Dictionary
	var ang: Array = fl["angles"] as Array
	fr["angles"] = ang
	var chain := fk_chain(fr["root"] as Vector3, bones_px(THUMB, pitch),
		ang, THUMB, side_of(RIGHT))
	fr["chain"] = chain
	return pose


static func _rest_one(bs: Array, h: int, pitch: float) -> Dictionary:
	var space := key_rect(bs, "пробел")
	if space.size == Vector2.ZERO:
		return {}
	var m := side_of(h)
	var fingers := {}
	var rests := {}
	var sum_y := 0.0
	var n := 0
	for f in [INDEX, MIDDLE, RING, PINKY]:
		var home_map: Dictionary = HOME_KEY[h] as Dictionary
		var home := key_rect(bs, String(home_map[f]))
		if home.size == Vector2.ZERO:
			return {}
		var txy := press_point(bs, String(home_map[f]), Vector2.ZERO)
		if txy == Vector2.ZERO:
			return {}
		rests[f] = _solve_rest(bs, f, h, pitch, txy)
		var fd: Dictionary = rests[f]
		var chain: Array = fd["chain"] as Array
		sum_y += (chain[3] as Vector3).y
		n += 1
		fingers[f] = fd
	# Цель большого — четверть пробела СВОЕЙ стороны, СИММЕТРИЧНАЯ
	# ЦЕЛИКОМ ОТНОСИТЕЛЬНО ОСИ РУКИ (ось «ф»↔«ж» — крайних дом-клавиш),
	# а не центра доски: доска асимметрична по служебным (слева Tab/
	# Caps/Shift = 5.5 питча, справа стереть/ввод/шифт иной ширины),
	# и центр доски ≠ центр буквенных рядов. Два разных центра (доска
	# для большого, дом-группа для пальцев) разводили кисти: левый
	# большой поджимался к указательному (мелкая V-выемка), правый
	# уходил вправо от руки (глубокая) — кисти не были отражениями
	# ГЛАЗАМИ, хотя числа попарно зеркальны (ловлено кадром
	# hands-mirror-02-rest-zoom 26.10.2026). Ось меряется крайними
	# домами, а не половинами пробела — на нечётной пиксельной ширине
	# те ложились на полпикселя несимметрично. Кламп к пробелу: при
	# широкой доске цель не уходит за край клавиши.
	var axis := 0.5 * (key_rect(bs, "ф").get_center().x
		+ key_rect(bs, "ж").get_center().x)
	var tx := axis - m * space.size.x * 0.25
	var pad := 0.15 * pitch
	tx = clampf(tx, space.position.x + pad,
		space.position.x + space.size.x - pad)
	var tyx := Vector2(tx,
		space.position.y
		+ minf(0.5 * _row_h(bs, pitch), space.size.y * 0.5))
	rests[THUMB] = _solve_rest(bs, THUMB, h, pitch, tyx)
	sum_y += ((rests[THUMB]["chain"] as Array)[3] as Vector3).y
	n += 1
	for f in rests.keys():
		fingers[f] = rests[f]
	# Запястье — за нижним рядом, к центру кисти.
	var wrist := Vector2(tyx.x + m * WRIST_OFF.x * pitch,
		(tyx.y) + WRIST_OFF.y * pitch)
	return {"fingers": fingers, "rest_ang": rests, "hand": h,
		"knuckle_y": sum_y / n, "wrist": wrist}


## Покой ОДНОГО пальца: корень = цель покоя + KNUCKLE (зеркалом по
## руке), z — из таблицы; решатель ставит кончик снова над целью на
## высоте hover. Возвращает [углы, цепь].
static func _solve_rest(bs: Array, f: int, h: int, pitch: float,
		txy: Vector2) -> Dictionary:
	var m := side_of(h)
	var bones := bones_px(f, pitch)
	var tip_z := (Z_TIP_THUMB if f == THUMB else Z_TIP) * pitch
	if f == THUMB:
		var k := THUMB_ROOT
		var root := Vector3(txy.x + m * k.x * pitch, txy.y + k.y * pitch,
			k.z * pitch)
		var res := ik_chain(root, bones, Vector3(txy.x, txy.y, tip_z),
			REST_PRIOR[f], REST_PRIOR[f], f, m)
		return {"root": root, "angles": res[0] as Array,
			"chain": res[1] as Array}
	var k: Vector3 = KNUCKLE[f]
	var root := Vector3(txy.x + m * k.x * pitch, txy.y + k.y * pitch,
		k.z * pitch)
	var res := ik_chain(root, bones, Vector3(txy.x, txy.y, tip_z),
		REST_PRIOR[f], REST_PRIOR[f], f, m)
	return {"root": root, "angles": res[0] as Array, "chain": res[1] as Array}


## ---------- РИСОВАНИЕ ----------

## Обе кисти на доске. presses = {рука: {палец: [цель, ход 0..1]}}:
## палец решается из покоя к цели (кончик — НА ПЛОСКОСТИ клавиши,
## просадка в клавишу — по z), ход лерпит 3D-цепь от покоя к нажатию.
## shifts = {рука: Vector2} — кисть ЦЕЛИКОМ съезжает по плоскости.
static func draw_both(ci: CanvasItem, rest: Dictionary,
		presses: Dictionary, pitch: float, ink: Color,
		shifts: Dictionary = {}) -> void:
	if rest.is_empty() or pitch <= 0.0:
		return
	var w := widths_of(pitch)
	var w0 := w[0] as float
	var w1 := w[1] as float
	var palm_col := ink
	palm_col.a = 0.32
	for h in [LEFT, RIGHT]:
		if not rest.has(h):
			continue
		var pose: Dictionary = rest[h]
		var fingers: Dictionary = pose["fingers"] as Dictionary
		var off: Vector2 = shifts.get(h, Vector2.ZERO)
		var press_f: Dictionary = {}
		if presses.has(h) and (presses[h] is Dictionary):
			press_f = presses[h] as Dictionary
		var solved := {}
		for f in fingers.keys():
			var fd: Dictionary = fingers[f] as Dictionary
			var chain0: Array = fd["chain"] as Array
			var rest_ang: Array = fd.get("angles", []) as Array
			var cpt: Array = []
			var phase := 0.0
			if press_f.has(f):
				var info: Array = press_f[f] as Array
				phase = clampf(info[1] as float, 0.0, 1.0)
				# Цель — в МИРОВЫХ координатах; решаем из несдвинутого
				# корня к цели СНИМКА сдвига (off после решения садит
				# цепь в сдвинутую кисть, кончик — на мировой клавише).
				var tgt := Vector3((info[0] as Vector2).x,
					(info[0] as Vector2).y, Z_PRESS * pitch) \
					- Vector3(off.x, off.y, 0.0)
				var res := ik_chain(fd["root"] as Vector3,
					bones_px(f, pitch), tgt, rest_ang, rest_ang,
					f, side_of(h))
				cpt = res[1] as Array
			var pts: Array = []
			var zi := 0.0
			for i in chain0.size():
				var a := chain0[i] as Vector3
				var p := a
				if phase > 0.0 and cpt.size() == chain0.size():
					var b := cpt[i] as Vector3
					p = a.lerp(b, phase)
				p = Vector3(p.x + off.x, p.y + off.y, p.z)
				pts.append(Vector2(p.x, p.y))
				zi += p.z
			var col := ink
			# Нажатый палец плотнее (лежит на клавише), покой — небо
			# сквозь него: давление читается и сверху.
			var zf := zi / chain0.size()
			col.a = clampf(0.66 - 0.09 * zf / pitch + 0.20 * phase,
				0.30, 0.85)
			solved[f] = [pts, col]
		_draw_palm(ci, pose, palm_col, pitch, off, solved)
		# Пальцы от мизинца к большому: большой рисуется последним.
		for f in [PINKY, RING, MIDDLE, INDEX, THUMB]:
			if solved.has(f):
				var sd: Array = solved[f] as Array
				_draw_finger(ci, sd[0] as Array, w0, w1, sd[1] as Color)


## Одна лента: вдоль хорды «корень→кончик» со СЖАТЫМИ поперечными
## смещениями из цепи. Лента по сырой цепи рвёт триангуляцию: 3D-ход
## костей спроецирован в XY как S-петля (звенья по 2 px против ширины
## 10 px), борта пересекаются, EarCut рисует клин-огрызок (ловлено
## снимком dbg-strip). Каркас — хорда, поперечные смещения точек цепи
## зажаты в ±0.35 длины: мягкая дуга остаётся, радиус всюду сильно
## больше полширины — самопересечений нет.
static func _draw_finger(ci: CanvasItem, chain: Array, w0: float,
		w1: float, col: Color) -> void:
	var n := chain.size()
	if n < 2:
		return
	var root := chain[0] as Vector2
	var tip := chain[n - 1] as Vector2
	var axis := tip - root
	var alen := axis.length()
	if alen < 1e-3:
		return
	var axis_u := axis / alen
	var perp := Vector2(-axis_u.y, axis_u.x)
	var pts: Array = []
	for i in n:
		var t: float = (i as float) / ((n - 1) as float)
		var d := ((chain[i] as Vector2) - root).dot(perp)
		d = clampf(d, -0.35 * alen, 0.35 * alen)
		pts.append(root + axis_u * (alen * t) + perp * d)
	# Борта — по перпендикуляру ХОРДЫ: разворачивающаяся развёртка на
	# крутых дугах оставляла локальные вывороты бортов (полоса в
	# щели), перпендикуляр хорды их не даёт вовсе; дуга читается
	# самими смещёнными точками каркаса.
	var nv := func(i: int) -> Vector2:
		return perp
	var out := PackedVector2Array()
	for i in n:
		var p := pts[i] as Vector2
		var fr := 1.0 - (i as float) / ((n - 1) as float)
		var wi := lerpf(w1, w0, fr)
		out.append(p - (nv.call(i) as Vector2) * (wi * 0.5))
	var tip2 := pts[n - 1] as Vector2
	var nt: Vector2 = (nv.call(n - 1) as Vector2)
	for kk in [1, 2, 3, 4]:
		var phi: float = nt.angle() + PI + PI * (kk as float) / 5.0
		out.append(tip2 + (w1 * 0.5) * Vector2(cos(phi), sin(phi)))
	for i in range(n - 1, -1, -1):
		var p2 := pts[i] as Vector2
		var fr2 := 1.0 - (i as float) / ((n - 1) as float)
		var wi2 := lerpf(w1, w0, fr2)
		out.append(p2 + (nv.call(i) as Vector2) * (wi2 * 0.5))
	var root2 := pts[0] as Vector2
	var nr0: Vector2 = (nv.call(0) as Vector2)
	for kk2 in [1, 2, 3, 4]:
		var phi0: float = nr0.angle() + PI * (kk2 as float) / 5.0
		out.append(root2 + (w0 * 0.5) * Vector2(cos(phi0), sin(phi0)))
	ci.draw_colored_polygon(out, col)


## Ладонь: полигон по корням пальцев решённой позы (+ сдвиг кисти) и
## двум углам пятки, сглаженный Catmull-Rom замкнуто. Порядок точек —
## по углу вокруг центроида: звёздчатый полигон не самопересекается.
static func _draw_palm(ci: CanvasItem, pose: Dictionary, col: Color,
		pitch: float, off: Vector2, solved: Dictionary) -> void:
	var pts := PackedVector2Array()
	for f in [PINKY, RING, MIDDLE, INDEX, THUMB]:
		if solved.has(f):
			var sd: Array = solved[f] as Array
			var ch: Array = sd[0] as Array
			if ch.is_empty():
				continue
			pts.append(ch[0] as Vector2)
	if pts.size() < 3:
		return
	var x_min := (pts[0] as Vector2).x
	var x_max := (pts[0] as Vector2).x
	for p in pts:
		x_min = minf(x_min, p.x)
		x_max = maxf(x_max, p.x)
	# Пятка — ЗА нижним рядом доски (запястье уходит за край), и СУЖЕ
	# размаха пальцев: ладонь трапецией, не каплей.
	var wrist := (pose["wrist"] as Vector2) + off
	var heel_y: float = wrist.y - 1.15 * pitch
	var heel_in := 0.55 * pitch
	pts.append(Vector2(x_max - heel_in, heel_y))
	pts.append(Vector2(x_min + heel_in, heel_y))
	var cx := 0.0
	var cy := 0.0
	for p in pts:
		cx += p.x
		cy += p.y
	cx /= pts.size()
	cy /= pts.size()
	var ordered: Array = pts.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var aa := (a - Vector2(cx, cy)).angle()
		var bb := (b - Vector2(cx, cy)).angle()
		return aa < bb)
	var arr: Array = []
	for p in ordered:
		arr.append(p)
	ci.draw_colored_polygon(PackedVector2Array(_smooth_closed(arr)), col)


## Замкнутый Catmull-Rom: 4 сэмпла на звено, кольцо замыкается.
static func _smooth_closed(pts: Array, samples: int = 4) -> Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out: Array = []
	for i in n:
		var p0: Vector2 = pts[(i - 1 + n) % n]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n]
		out.append(p1)
		for s in range(1, samples):
			var t := (s as float) / (samples as float)
			out.append(_catmull(p0, p1, p2, p3, t))
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
