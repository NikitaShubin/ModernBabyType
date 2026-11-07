# The palm's dorsal silhouette as a curve: width at each height above the cut,
# and the angle the outline makes there. A real hand widens from ~55 at the
# wrist crease to ~88 at the knuckles over ~90 mm, i.e. 10-20 degrees a side;
# a 25-30 degree stretch right above the cut is what reads as a kink.
# Headless: mbt-godot --headless --path /work/tools/hand3d --script res://wrist_prof2.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")


func _init() -> void:
	var m := HandModel.new(1.0, 0.0)
	var ys := [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0, 60.0, 80.0]
	var w := []
	var lo := []
	var hi := []
	for y in ys:
		var x0 := 1e9
		var x1 := -1e9
		var x := -70.0
		while x <= 70.0:
			var z := -45.0
			while z <= 30.0:
				if m.field(Vector3(x, y, z)) <= 0.0:
					x0 = minf(x0, x)
					x1 = maxf(x1, x)
					z += 0.5
				z += 0.5
			x += 0.25
		lo.append(x0)
		hi.append(x1)
		w.append(x1 - x0)
	var line := "y:"
	for i in ys.size():
		line += " %6.0f" % ys[i]
	print(line)
	line = "w:"
	for v in w:
		line += " %6.1f" % v
	print(line)
	line = "lo:"
	for v in lo:
		line += " %6.1f" % v
	print(line)
	line = "hi:"
	for v in hi:
		line += " %6.1f" % v
	print(line)
	# Slope of each side, in degrees from the hand's long axis.
	line = "deg:"
	for i in range(1, ys.size()):
		var dy := float(ys[i]) - float(ys[i - 1])
		var a := rad_to_deg(atan2(absf(float(lo[i]) - float(lo[i - 1])), dy))
		var b := rad_to_deg(atan2(absf(float(hi[i]) - float(hi[i - 1])), dy))
		line += " %6.1f" % maxf(a, b)
	print(line, "   (max of the two sides, between the columns above)")
	quit()
