# Looks for folds near the ulnar border: a slit in a render is a place where
# the surface doubles back, and a scan can name it.
extends SceneTree

const HandModel := preload("res://hand_model.gd")


func _initialize() -> void:
	var m := HandModel.new(1.0)
	for y in [40, 46, 52, 58, 64]:
		for z in [-14, -10, -6, -2, 2, 6]:
			var line := "y=%3d z=%4d: " % [y, z]
			var prev := m.field(Vector3(-60, y, z))
			var flips := 0
			for i in 81:
				var x := -60.0 + i
				var v: float = m.field(Vector3(x, y, z))
				if (prev < 0.0) != (v < 0.0):
					flips += 1
					line += "%+.1f " % x
				prev = v
			if flips > 2:
				print(line, "  <- %.0f crossings" % flips)
	quit()
