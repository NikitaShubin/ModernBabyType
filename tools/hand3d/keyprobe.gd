extends SceneTree
func _init() -> void:
	print("LOC:", KEY_LOCATION_LEFT, " ", KEY_LOCATION_RIGHT, " ", KEY_LOCATION_UNSPECIFIED)
	var k := InputEventKey.new()
	print("location field: ", k.location)
	print("F1..F4:", KEY_F1, " ", KEY_F2, " ", KEY_F3, " ", KEY_F4)
	print("META:", KEY_META, " CTRL:", KEY_CTRL, " ALT:", KEY_ALT)
	print("TAB:", KEY_TAB, " CAPS:", KEY_CAPSLOCK, " BSP:", KEY_BACKSPACE, " ENT:", KEY_ENTER, " KPENT:", KEY_KP_ENTER)
	print("SPC:", KEY_SPACE, " GRV:", KEY_QUOTELEFT, " MINUS:", KEY_MINUS, " EQ:", KEY_EQUAL)
	print("BRK:", KEY_BRACKETLEFT, " ", KEY_BRACKETRIGHT, " BSH:", KEY_BACKSLASH)
	quit()
