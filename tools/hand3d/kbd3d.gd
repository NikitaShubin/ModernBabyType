# The project's keyboard as a real 3D board, in millimetres.
#
# The layout is NOT invented here: it is the same five-row board the game draws
# (game/scripts/kbd.gd): the digits row with its own "ё" and the two punctuation
# keys, Tab + 12 letters + backslash, Caps + 11 letters + Enter, Shift + 10
# letters + right Shift, and the bottom row Ctrl Win Alt Space Alt Globe Ctrl.
# The widths are the project's ANSI adaptation in units of the letter pitch:
# Tab 1.5, Caps 1.75, left Shift 2.25, Backspace 2, Enter 2.25, right Shift
# 2.75, and the bottom row shares its width between nine units (the space is
# three of them, exactly as in the game).
#
# The board is a pure data module: it returns rectangles and assignments, and
# the viewer builds the meshes. Coordinates are millimetres in the viewer's
# world frame: x runs left to right, y away from the typist, z up. The face of
# every key lies on z = FACE_Z; a keycap is THICK millimetres thick and sinks
# TRAVEL millimetres when pressed.
#
# The hand/finger table is a copy of game/scripts/hands.gd's FINGER_MAP (the
# study project cannot load files outside its res:// root). The copy is kept
# deliberately mechanical: one entry per physical key, no behaviour. Two rules
# are added ON TOP of the map, both about the KEYBOARD, not about a finger:
#   * a duplicate service key (the bottom row has two Ctrl, two Alt, two Win)
#     belongs to the hand on its own side — the map's single "Ctrl" cannot say
#     which of the two physical keys it means;
#   * the space bar belongs to the thumb of the hand on the clicked half, the
#     same "free hand" rule the game uses for "пробел:Л" / "пробел:П".
extends RefCounted

const PITCH := 19.05          # ANSI centre-to-centre step, mm (0.75 in)
const GAP := 1.0              # the game's gap between keycaps, mm
const KEY_W := PITCH - GAP    # a 1u keycap is 18.05 mm wide
const ROW_H := KEY_W * 1.15   # the game's keycaps are 1.15x taller than wide
const ROW_STEP := ROW_H + GAP
const THICK := 2.0            # keycap thickness, mm
const TRAVEL := 2.6           # how far a pressed key sinks, mm
const FACE_Z := -69.0         # top face of an unpressed key
const HOME_Y := 152.0         # the A row's centre line, mm

const LEFT := 0
const RIGHT := 1

const ROW_DIGITS: Array = ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"0", "-", "=", "←"]
const ROW_Q: Array = ["Tab", "й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з",
	"х", "ъ", "\\"]
const ROW_A: Array = ["Caps", "ф", "ы", "в", "а", "п", "р", "о", "л", "д",
	"ж", "э", "↵"]
const ROW_Z: Array = ["Shift", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю",
	".", "ShiftR"]
const ROW_BOTTOM: Array = ["Ctrl", "Win", "Alt", "пробел", "Alt", "глобус",
	"Ctrl"]

const ROWS: Array = [ROW_DIGITS, ROW_Q, ROW_A, ROW_Z, ROW_BOTTOM]
const HOME_ROW := 2

# Latin legend of the same physical key (Kbd.RU_EN): shown small in the corner.
const RU_EN := {
	"й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y",
	"г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
	"ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h",
	"о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
	"я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n",
	"ь": "m", "б": ",", "ю": ".", "ё": "`",
}

# game/scripts/hands.gd FINGER_MAP, one line per physical key.
const FINGER_MAP := {
	"ё": [LEFT, "V"], "1": [LEFT, "V"], "й": [LEFT, "V"],
	"ф": [LEFT, "V"], "я": [LEFT, "V"],
	"Tab": [LEFT, "V"], "Caps": [LEFT, "V"], "Shift": [LEFT, "V"],
	"2": [LEFT, "IV"], "ц": [LEFT, "IV"], "ы": [LEFT, "IV"],
	"ч": [LEFT, "IV"],
	"3": [LEFT, "III"], "у": [LEFT, "III"], "в": [LEFT, "III"],
	"с": [LEFT, "III"],
	"4": [LEFT, "II"], "5": [LEFT, "II"], "к": [LEFT, "II"],
	"е": [LEFT, "II"], "а": [LEFT, "II"], "п": [LEFT, "II"],
	"м": [LEFT, "II"], "и": [LEFT, "II"],
	"6": [RIGHT, "II"], "7": [RIGHT, "II"], "н": [RIGHT, "II"],
	"г": [RIGHT, "II"], "р": [RIGHT, "II"], "о": [RIGHT, "II"],
	"т": [RIGHT, "II"], "ь": [RIGHT, "II"],
	"8": [RIGHT, "III"], "ш": [RIGHT, "III"], "л": [RIGHT, "III"],
	"б": [RIGHT, "III"],
	"9": [RIGHT, "IV"], "щ": [RIGHT, "IV"], "д": [RIGHT, "IV"],
	"ю": [RIGHT, "IV"],
	"0": [RIGHT, "V"], "-": [RIGHT, "V"], "=": [RIGHT, "V"],
	"з": [RIGHT, "V"], "х": [RIGHT, "V"], "ъ": [RIGHT, "V"],
	"\\": [RIGHT, "V"], "ж": [RIGHT, "V"], "э": [RIGHT, "V"],
	".": [RIGHT, "V"], "ShiftR": [RIGHT, "V"], "←": [RIGHT, "V"],
	"↵": [RIGHT, "V"],
	"глобус": [RIGHT, "I"],
}


## The board's full width: fifteen letter pitches and fourteen gaps, the digits
## row's natural width (13 singles + a 2u Backspace). Every other row fills it.
static func board_w() -> float:
	return 15.0 * KEY_W + 14.0 * GAP


## A modifier's width in millimetres. Same formula as the game's `_mod_w`: a
## 1.5u key is 1.5 pitches plus 0.5 of a gap, so the letters after it start on
## a whole number of pitches.
static func mod_w(units: float) -> float:
	return units * KEY_W + (units - 1.0) * GAP


static func row_y(row: int) -> float:
	return HOME_Y + float(HOME_ROW - row) * ROW_STEP


## Every key of the board, left to right, top row first:
##   {s, r: Rect2, hand: int, finger: String, row: int}
## The rectangle is in world millimetres, y growing away from the typist.
## The bottom row is shared out by the project's own rule: nine units across
## the full width, so its keys are wider than the letter keys (the space bar is
## exactly one third of the board, as on the game's screen).
static func keys() -> Array:
	var out := []
	var w := board_w()
	var x0 := -w * 0.5
	var x1 := w * 0.5
	for ri in ROWS.size():
		var row: Array = ROWS[ri]
		var y := row_y(ri)
		var x := x0
		var n := row.size()
		if ri == 4:
			# The bottom row: proportional to its units, gaps included.
			var total := 0.0
			for label in row:
				total += _span(String(label))
			var unit := (w - GAP * float(n - 1)) / total
			for bi in n:
				var s := String(row[bi])
				var kw := unit * _span(s)
				out.append(_key(s, Rect2(x, y - ROW_H * 0.5, kw, ROW_H), ri,
					x, x + kw))
				x += kw + GAP
			continue
		if ri == 0:
			# Digits: thirteen 1u keys, Backspace takes the remainder (2u).
			for bi in n:
				var s := String(row[bi])
				if s == "←":
					continue
				out.append(_key(s, Rect2(x, y - ROW_H * 0.5, KEY_W, ROW_H),
					ri, x, x + KEY_W))
				x += KEY_W + GAP
			out.append(_key("←", Rect2(x, y - ROW_H * 0.5, x1 - x, ROW_H),
				ri, x, x1))
			continue
		# The three letter rows: a wide leading key, 1u letters, a wide trailing
		# key that takes the rest of the board (backslash, Enter, right Shift).
		for bi in n:
			var s := String(row[bi])
			var wide := bi == 0 or bi == n - 1
			if not wide:
				out.append(_key(s, Rect2(x, y - ROW_H * 0.5, KEY_W, ROW_H),
					ri, x, x + KEY_W))
				x += KEY_W + GAP
				continue
			var kw := mod_w(_span(s)) if bi == 0 else (x1 - x)
			out.append(_key(s, Rect2(x, y - ROW_H * 0.5, kw, ROW_H), ri,
				x, x + kw))
			x += kw + GAP
	return out


## The project's key widths in units of the letter pitch.
static func _span(label: String) -> float:
	if label == "пробел":
		return 3.0
	if label == "←":
		return 2.0
	if label == "Tab":
		return 1.5
	if label == "Caps":
		return 1.75
	if label == "Shift":
		return 2.25
	if label == "ShiftR":
		return 1.5
	return 1.0


static func _key(s: String, r: Rect2, row: int, xa: float, xb: float) -> Dictionary:
	var hf := hand_finger(s, (xa + xb) * 0.5)
	return {"s": s, "r": r, "row": row, "hand": int(hf[0]),
		"finger": String(hf[1]), "x0": xa, "x1": xb}


## [hand, finger] for a physical key. The map above decides it; the two
## position rules (duplicate service keys and the space bar's halves) are
## applied here because only the board knows WHICH of the two keys was hit.
static func hand_finger(s: String, x: float) -> Array:
	if s == "пробел":
		return [LEFT if x < 0.0 else RIGHT, "I"]
	if s == "Ctrl" or s == "Win" or s == "Alt":
		return [LEFT if x < 0.0 else RIGHT, "V"]
	var e: Variant = FINGER_MAP.get(s)
	if e != null:
		return [(e as Array)[0] as int, String((e as Array)[1])]
	return [-1, ""]


## The key under a point on the key face, or -1. A point in a gap is given to
## the nearest key when it is within `slop` millimetres of that key's rectangle;
## the mouse is precise, but a fingertip is not (the game's own rule).
static func key_at(ks: Array, p: Vector2, slop := 0.0) -> int:
	var best := -1
	var best_d := 1e9
	for i in ks.size():
		var r: Rect2 = ks[i]["r"]
		if r.has_point(p):
			return i
		if slop > 0.0:
			var q := Vector2(clampf(p.x, r.position.x, r.end.x),
				clampf(p.y, r.position.y, r.end.y))
			var d := q.distance_to(p)
			if d <= slop and d < best_d:
				best_d = d
				best = i
	return best


## The centre of a key in world millimetres, on the key face.
static func centre(k: Dictionary) -> Vector3:
	var r: Rect2 = k["r"]
	return Vector3(r.get_center().x, r.get_center().y, FACE_Z)


## The main legend and the small Latin pair of a key, for the 3D cap.
static func legend(s: String) -> String:
	if s == "пробел":
		return ""
	if s == "ShiftR":
		return "Shift"
	if s == "глобус":
		return "◎"
	return s


static func latin(s: String) -> String:
	return String(RU_EN.get(s, ""))


## The key with a given label, or -1. ShiftR is its own label; "Shift" is the
## left one. Used by the probes and by the viewer's keyboard shortcuts.
static func index_of(ks: Array, s: String, which := 0) -> int:
	var seen := 0
	for i in ks.size():
		if String(ks[i]["s"]) == s:
			if seen == which:
				return i
			seen += 1
	return -1
