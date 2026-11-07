# How far in front of the key the approach must stop so the thumb has room to
# press with the hand held still. At the hover point the solver happily spends
# the thumb's whole extension (f = -1), and then the press has nothing left but
# the arm — the hand sinks. This probe measures, for a few reserves, whether a
# frozen-arm press from the reserve point reaches the key face.
#   mbt-godot --headless --path /work/tools/hand3d --script res://click_reserve.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0
const KEY_TRAVEL := 2.6
const RESERVES := [0.0, 4.0, 8.0, 12.0, 16.0]

const KEYS := [["top-left", 0, 4], ["middle", 5, 2], ["top-right", 9, 4],
	["bottom-left", 0, 0]]


func _init() -> void:
	for k in KEYS:
		var name: String = k[0]
		var c := Vector3(KEY_X0 + float(k[1]) * KEY_PITCH,
			KEY_Y0 + float(k[2]) * KEY_PITCH, KEY_Z)
		var deep := Vector3(c.x, c.y, KEY_FACE - KEY_TRAVEL - 1.0)
		print("=== %s key (%.0f, %.0f)" % [name, c.x, c.y])
		for r in RESERVES:
			var hover := Vector3(c.x, c.y, KEY_FACE + KEY_HOVER + float(r))
			var h: Dictionary = IK.solve_chain("I", hover, HandModel.rest_pose(),
				{"arm": true})
			var hf: Dictionary = IK.solve_chain("I", deep, h["pose"], {"arm": false})
			var ph: Vector3 = h["pad"]
			var pf: Vector3 = hf["pad"]
			print("  reserve %4.1f: hover f %6.3f, frozen press f %6.3f, reach %6.2f, pad z %.2f -> %.2f, travel %s" % [
				float(r), float(h["pose"]["thumb_f"]),
				float(hf["pose"]["thumb_f"]), float(hf["error"]), ph.z, pf.z,
				str(pf - ph)])
	quit(0)
