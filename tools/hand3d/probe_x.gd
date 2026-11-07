extends SceneTree
const Kbd3D := preload("res://kbd3d.gd")
func _init() -> void:
	var ks := Kbd3D.keys()
	for s in ["ф", "ы", "в", "а", "о", "л", "д", "ж"]:
		var k: Dictionary = ks[Kbd3D.index_of(ks, s)]
		print(s, " ", Kbd3D.centre(k), " rect ", k["r"])
	quit(0)
