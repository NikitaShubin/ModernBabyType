class_name Hands
extends RefCounted
## Схематичный скелет обеих кистей НАД доской (автор 19.10.2026):
## ребёнок и взрослый видят, каким пальцем на какую клавишу нажимать.
## Кисти символны (кости — линии, суставы — точки), но движения плавные
## и анатомически честные: каждый палец — цепь костей фиксированной
## длины из НЕПОДВИЖНОГО корня (сустава пясти); позиция кончика
## решается инверсной кинематикой — FABRIK (Aristidou, Lasenby,
## «FABRIK: A fast, iterative solver for the Inverse Kinematics
## problem», Computer Graphics Forum 2011). FABRIK сохраняет длины
## сегментов по построению — кости никогда не растягиваются.
##
## Модуль ЧИСТЫЙ: никакой сцены и никакого состояния. Вызыватель
## (песочница, позже клавиатура игры) передаёт список клавиш
## Kbd.buttons() и рисует готовые цепи своими draw-средствами.
##
## Все длины — в ПИТЧАХ доски (ширина обычной буквенной клавиши).

## Пальцы: индексы костных таблиц и карт.
const THUMB := 0
const INDEX := 1
const MIDDLE := 2
const RING := 3
const PINKY := 4

## Руки: 0 левая, 1 правая.
const LEFT := 0
const RIGHT := 1

## Кости пальцев, [основная, средняя, ногтевая]; у большого — три
## коротких. Пропорции — от реальной кисти (дистальная фаланга
## ~половина проксимальной), палец суммарно ~3 питча: соседние
## клавиши-колонки отстоят на один питч, и согнутая цепь честно
## достаёт до свей колонки, не вытягиваясь поперёк ряда.
const BONES := {
	THUMB: [0.85, 0.62, 0.5],
	INDEX: [1.42, 1.0, 0.74],
	MIDDLE: [1.55, 1.06, 0.78],
	RING: [1.44, 1.0, 0.74],
	PINKY: [1.05, 0.82, 0.66],
}

## Висит кончик в покое НАД клавишей (в питчах над её верхним краем).
const HOVER := 0.3

## Сжатие пясти: настоящие пястные суставы зажаты (сеxtense...), а
## пальцы растопырены к своим колонкам — потому и выглядит рукой.
const KNUCKLE_SQUEEZE := 0.55

## Дом-клавиша пальца (покой — кончик над ней). Указательные закрывают
## по две колонки: покой у ПЕРВОЙ (а/о), вторая достаётся сдвигом
## цели при нажатии.
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
## правой (по другую сторону пробела от системных). Ctrl/Win/Alt —
## мизинцы (в наборе не участвуют, но руке ведь тоже надо откуда-то
## стартовать). Формат: [рука, палец]. Пробел — динамический: большой
## свободной руки, см. thumb_side.
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
}


## Рука клавиши — ССЫЛКА на общую таблицу Kbd: одна и та же нарисованная
## доска и одна и та же школа слепой печати (см. Kbd.hand_of).
static func hand_of(s: String) -> int:
	return LEFT if Kbd.hand_of(s) == "Л" else RIGHT


## Палец клавиши из FINGER_MAP. Пробел — большим свободной руки
## (правило противоположной руки — то же, что у шифта, см.
## Kbd.hand_of/«пробел:Л»/«пробел:П» в подсказке доски). Неизвестное —
## [-1, -1]: клавиша вне карты не нажимается ни одним пальцем.
static func finger_of(s: String) -> Array:
	if s == "пробел":
		return [RIGHT, THUMB]
	var m: Array = FINGER_MAP.get(s, [-1, -1])
	return m


## Кованое правило противоположной руки в терминах кисти: букве левой
## руки отвечает правый мизинец (шифт) и правый большой (пробел):
## обе пары рядом стоят на «другой половине доски».
## Тест кладёт обе крайности (буква левой, буква правой).

## Цепь костей из фиксированного корня к цели (FABRIK). Отдаёт массив
## суставов [корень, ..., кончик]; длины сегментов равны bones ТОЧНО
## (инвариант меряет тест). Недостижимо — цепь вытягивается по лучу
## корень→цель, кончик на Σbones. Итераций мало: сходимость за
## 2–3 прохода, лишние — только если цель едет кадром раньше.
static func ik_chain(root: Vector2, bones: Array, target: Vector2,
		iters := 16) -> Array:
	# Начальная поза — КОЛИНЕАРНЫЙ луч корень→цель с шагом ЗАВЕТНОЙ
	# костной длины (классическая инициализация FABRIK). Равномерный
	# шаг «порциями» из-за шумов float32 раскалывает вырожденно
	# коллинеарную цепь в предельный цикл (ловил: RING на мелкой доске,
	# err 11 при 16 итерациях); с костным шагом сходится с первого
	# прохода. Недостижимая цель — цепь растянута по лучу на Σbones.
	var dir := target - root
	var dist := dir.length()
	if dist < 0.0001:
		dir = Vector2(0, -1)
	else:
		dir = dir / dist
	var reach := 0.0
	for b in bones:
		reach += b
	# Достижимая цель: цепь уже ЛЕЖИТ концом на цели (шейка масштаба
	# dist/reach) — FABRIK сходится с первого прохода. Недостижимая:
	# растянута целиком на Σbones по лучу.
	var scale := minf(dist / maxf(reach, 0.0001), 1.0)
	var pts: Array = [root]
	var cum := 0.0
	for b in bones:
		cum += b
		pts.append(root + dir * cum * scale)
	for it in iters:
		pts[bones.size()] = target
		for i in range(bones.size() - 1, -1, -1):
			var d: Vector2 = pts[i + 1] - pts[i]
			var seg := maxf(d.length(), 0.0001)
			pts[i] = pts[i + 1] - d / seg * bones[i]
		pts[0] = root
		for i in range(1, bones.size() + 1):
			var d: Vector2 = pts[i] - pts[i - 1]
			var seg := maxf(d.length(), 0.0001)
			pts[i] = pts[i - 1] + d / seg * bones[i - 1]
		if (pts[bones.size()] - target).length() < 0.001:
			break
	return pts


## Кости пальца в пикселях доски (питч из buttons()).
static func bones_px(f: int, pitch: float) -> Array:
	var out: Array = []
	for b in BONES[f]:
		out.append(b * pitch)
	return out


## Прямоугольник клавиши по подписи — мера самого списка buttons().
static func key_rect(bs: Array, s: String) -> Rect2:
	for b in bs:
		if String(b["s"]) == s:
			return b["r"] as Rect2
	return Rect2()


## Шаг доски (питч) — ширина обычной буквенной клавиши из списка.
static func pitch_of(bs: Array) -> float:
	for b in bs:
		if Kbd.is_plain_letter(String(b["s"])):
			return (b["r"] as Rect2).size.x
	return 0.0


## Центр точки нажатия клавиши: по центру ПЛОЩАДИ клавиши — не верх
## (палец должен опуститься ВСЯ плоскость, иначе промах руки выглядит
## наложением на соседей). 
static func key_center(bs: Array, s: String) -> Vector2:
	var r := key_rect(bs, s)
	if r.size == Vector2.ZERO:
		return Vector2.ZERO
	return r.position + r.size * 0.5


## Покой ОДНОЙ кисти над ДАНОЙ доской: bs — полный список
## Kbd.buttons() (код вызывает его на обе руки), hand — которая.
## Пальцы — свои колонки дом-ряда; кончики ВИСЯТ над клавишами на
## HOVER питча; большой у пробела своей половины.
## Возврат: {wrist, knuckle_y, fingers: {палец: [точки…]},
##           targets: {палец: цель}}. Пусто — когда доски нет.
static func rest_pose(bs: Array, h: int) -> Dictionary:
	var pitch := pitch_of(bs)
	if pitch <= 0.0:
		return {}
	var home_map: Dictionary = HOME_KEY[h]
	var space := key_rect(bs, "пробел")
	if space.size == Vector2.ZERO:
		return {}
	# Пясть тесно под ВНУТРЕННИМИ колонками: центр руки — середина
	# между дом-клавишами указательных обеих... — у каждой руки своим
	# кластером: колонки ф…а для левой, о…ж для правой. Сжатие кластера
	# (KNUCKLE_SQUEEZE) ставит корни ВНУТРИ своих колонок, а пальцы
	# растопыриваются из FABRIK — рука видна как рука.
	var xs: Array = []
	for f in [PINKY, RING, MIDDLE, INDEX]:
		var r := key_rect(bs, String(home_map[f]))
		xs.append(r.position.x + r.size.x * 0.5)
	var center := 0.0
	for x in xs:
		center += x
	center /= float(xs.size())
	# Высота пясти: ниже дом-ряда так, чтобы САМЫЙ КОРОТКИЙ палец
	# (мизинец, 2.53 питча) доставал до своей дом-клавиши с изгибом:
	# расстояние корень→цель (2.15 + HOVER по вертикали + сдвиг
	# сжатого корня по горизонтали) чуть меньше длины цепи — иначе
	# палец вытянут струной и рука выглядит сломанной.
	var home_top := (key_rect(bs, String(home_map[INDEX]))).position.y
	var knuckle_y := home_top + 2.15 * pitch
	var wrist := Vector2(center, knuckle_y + 1.15 * pitch)
	var pose: Dictionary = {
		"wrist": wrist, "knuckle_y": knuckle_y, "fingers": {}, "targets": {},
	}
	# Четыре пальца: корни — сжатый кластер по X.
	var roots: Array = []
	for x in xs:
		roots.append(center + (x - center) * KNUCKLE_SQUEEZE)
	var fi := 0
	for f in [PINKY, RING, MIDDLE, INDEX]:
		var root := Vector2(roots[fi], knuckle_y)
		# Цель: над ДОМ-клавишей пальца (не над колонкой корня).
		var r2 := key_rect(bs, String(home_map[f]))
		var target := Vector2(
			r2.position.x + r2.size.x * 0.5, r2.position.y - HOVER * pitch)
		pose.fingers[f] = ik_chain(root, bones_px(f, pitch), target)
		pose.targets[f] = target
		fi += 1
	# Большой: корень сзади пясти, цель — своя половина пробела.
	# Левый большой — справа от пясти (к центру доски), правый — слева.
	var side := 1.0 if h == LEFT else -1.0
	var thumb_root := Vector2(center + side * 2.35 * pitch, knuckle_y + 0.4 * pitch)
	var thumb_target := Vector2(
		space.position.x + space.size.x * (0.25 if h == LEFT else 0.75),
		space.position.y - HOVER * pitch * 0.5)
	pose.fingers[THUMB] = ik_chain(thumb_root, bones_px(THUMB, pitch), thumb_target)
	pose.targets[THUMB] = thumb_target
	return pose


## Покой обеих кистей сразу (вызов rest_pose на руки 0/1).
static func rest_both(bs: Array) -> Dictionary:
	if pitch_of(bs) <= 0.0:
		return {}
	return {LEFT: rest_pose(bs, LEFT), RIGHT: rest_pose(bs, RIGHT)}


## Цель нажатия клавиши s (тап или подсказка): центр клавишной
## ПЛОЩАДИ — палец опускается до поверхности, а не до верхнего ребра.
## Пусто — клавиши нет (нажатие мимо доски: рука не реагирует).
static func press_target(bs: Array, s: String) -> Vector2:
	if key_rect(bs, s).size == Vector2.ZERO:
		return Vector2.ZERO
	return key_center(bs, s)


## Рука и палец для нажимаемой клавиши: [рука, палец]; пробел — паяц
## большим свободной руки, по правилу противоположной руки. Возврат
## [-1, -1] — рука не двигается (нажатие мимо).
static func press_finger(bs: Array, s: String) -> Array:
	if s == "пробел":
		# Правило противоположной руки живёт в голове вызователя
		# (у него есть текущая буква); без контекста — правый большой.
		return [RIGHT, THUMB]
	return finger_of(s)
