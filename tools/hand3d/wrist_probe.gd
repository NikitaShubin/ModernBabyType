# How far does the WHOLE HAND travel when one finger presses a key? The pad's
# move is the press itself; the wrist's move is what the eye reads as "the hand
# jumps". A thumb press near the space bar should be a thumb move, not a
# 30 mm lift of the wrist. Reports the wrist (hand origin), the arm angles and
# the pressing pad for home and for the deep press of a few keys, per hand.
# Also solves each target with the arm FROZEN: if the digit reaches alone, any
# arm move in the free solve is an energy choice, not a necessity.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const ROOTS := {"L": -72.51, "R": 43.94}
# [label, x offset from the key centre] — the space bar is split between the
# hands, so its probe point sits on the hand's own half.
const KEYS := {
	"L": [["пробел", -20.0], ["Ctrl", 0.0], ["а", 0.0], ["ф", 0.0]],
	"R": [["пробел", 20.0], ["глобус", 0.0], ["о", 0.0], ["ж", 0.0]],
}
const ARM_KEYS := ["wrist_flex", "wrist_dev", "pronation", "forearm_flex",
	"forearm_abd", "elbow_x", "elbow_y", "elbow_z"]


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _wrist(p: Dictionary) -> Vector3:
	return ArmModel.hand_transform(p.get("arm", {})).origin


func _d3(p: Dictionary) -> Vector3:
	# World direction of the thumb's distal phalanx: the dir term's measure.
	var fk := HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	return (xf.basis * (fk["dirs"][2] as Vector3)).normalized()


func _init() -> void:
	printerr("probe start")
	var ks := Kbd3D.keys()
	for side in ["L", "R"]:
		var root_x := float(ROOTS[side])
		var home: Dictionary = HomePose.build(side, root_x)
		var wh := _wrist(home)
		printerr("=== %s home wrist local %s  thumb d3 %s"
			% [side, str(wh), str(_d3(home))])
		for entry in KEYS[side]:
			var label := String(entry[0])
			var k: Dictionary = ks[Kbd3D.index_of(ks, label)]
			var c := Kbd3D.centre(k)
			var hx := c.x + float(entry[1])
			var hf := Kbd3D.hand_finger(label, hx)
			var ray := String(hf[1])
			# The mirrored right hand takes the target in its own local frame:
			# world x = root - local x, so local x = root - world x.
			var lx := (hx - root_x) if side == "L" else (root_x - hx)
			var local := Vector3(lx, c.y, c.z - Kbd3D.TRAVEL)
			var opts := {"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
				"clear_w": 100.0, "dir_w": 30.0}
			var r: Dictionary = IK.solve_chain(ray, local, home, opts)
			var p: Dictionary = r["pose"]
			var w := _wrist(p)
			var pad := _pad(ray, p)
			var arm: Dictionary = p.get("arm", {})
			var aa := []
			for j in ARM_KEYS:
				aa.append("%+.1f" % float(arm.get(j, 0.0)))
			var frozen: Dictionary = IK.solve_chain(ray, local, home,
				{"arm": false, "thumb_dof": 4, "clear_z": CLEAR_Z,
				"clear_w": 100.0, "dir_w": 30.0})
			printerr("  %-7s %s err %.2f  frozen err %.2f" % [label, ray,
				float(r["error"]), float(frozen["error"])])
			printerr("      wrist %s  d %s  |d| %.1f" % [str(w), str(w - wh),
				(w - wh).length()])
			printerr("      pad   %s  d %s  |d| %.1f  d3 %s" % [str(pad),
				str(pad - _pad(ray, home)), (pad - _pad(ray, home)).length(),
				str(_d3(p))])
			printerr("      arm   %s" % " ".join(aa))
	quit(0)
