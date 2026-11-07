extends SceneTree
const Kbd3D := preload("res://kbd3d.gd")
func _init() -> void:
	print("board w ", Kbd3D.board_w(), " home_y ", Kbd3D.HOME_Y, " row_step ", Kbd3D.ROW_STEP)
	for k in Kbd3D.keys():
		if String(k["s"]) == "пробел" or String(k["s"]) == "←" or String(k["s"]) == "ж":
			print(k["s"], " ", k["r"], " hand ", k["hand"], " finger ", k["finger"])
	quit()
