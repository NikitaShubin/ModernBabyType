# Can each finger reach each key with the ARM FROZEN at rest? That is the
# extreme of "the hand does not move forward": the wrist stays at z = 0 and
# only the finger (and its fan) work. Prints the reach error and the pad.
#   mbt-godot --headless --path /work/tools/hand3d --script res://reach_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0


func _init() -> void:
	var rest := HandModel.rest_pose()
	for ray in ["I", "II", "III", "IV", "V"]:
		var miss := []
		var worst := 0.0
		var worst_at := ""
		var total := 0.0
		for iy in 5:
			for ix in 10:
				var k := iy * 10 + ix
				var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
					KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
				var deep := Vector3(face.x, face.y, face.z - 3.6)
				var r: Dictionary = IK.solve_chain(ray, deep, rest,
					{"arm": false, "f_lo": -1.0})
				var e := float(r["error"])
				total += e
				if e > 0.5:
					miss.append("%d(%.1f)" % [k, e])
				if e > worst:
					worst = e
					worst_at = str(k)
		print("%s: frozen-arm miss %d/50 mean %.2f worst %.2f at %s %s" % [
			ray, miss.size(), total / 50.0, worst, worst_at, str(miss)])
	quit(0)
