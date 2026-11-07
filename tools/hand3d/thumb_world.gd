# Where the thumb's pad can go with the hand held exactly at the hover pose of
# a key: the world path of the pad as f runs, the hand's own axes, and how far
# the key face is. This says whether a frozen-arm press has any travel at all
# in the key's normal.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_world.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0

const KEYS := [["top-left", 0, 4], ["middle", 5, 2], ["top-right", 9, 4],
	["bottom-left", 0, 0], ["bottom-right", 9, 0]]


func _init() -> void:
	for k in KEYS:
		var name: String = k[0]
		var c := Vector3(KEY_X0 + float(k[1]) * KEY_PITCH,
			KEY_Y0 + float(k[2]) * KEY_PITCH, KEY_Z)
		var hover := Vector3(c.x, c.y, KEY_FACE + KEY_HOVER)
		var h: Dictionary = IK.solve_chain("I", hover, HandModel.rest_pose(),
			{"arm": true})
		var arm: Dictionary = h["pose"]["arm"]
		var xf := ArmModel.hand_transform(arm)
		print("=== %s key (%.0f, %.0f)  hover f %.3f  wrist %s" % [name, c.x, c.y,
			float(h["pose"]["thumb_f"]), str(xf.origin)])
		print("    hand x %s" % str(xf.basis.x))
		print("    hand y %s" % str(xf.basis.y))
		print("    hand z %s" % str(xf.basis.z))
		var prev := Vector3.ZERO
		for f in [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]:
			var p: Vector3 = xf * HandModel.thumb_pad(HandModel.thumb_fk(float(f)))
			var step := "" if f <= -1.0 else "  step %s" % str(p - prev)
			print("    f %5.2f  pad (%7.2f, %7.2f, %7.2f)  to key %6.2f%s" % [
				float(f), p.x, p.y, p.z, p.distance_to(c), step])
			prev = p
	quit(0)
