# Does the thumb SPLAY toward its key, or does the whole hand move?
#
# The author's rule (31.10.2026): pressing a bottom-row key with the right
# thumb must splay the thumb in the direction of the press and keep the whole
# hand as still as it can. This probe measures, for each thumb key of both
# hands, how far the THUMB PAD travels versus how far the INDEX pad (the whole
# hand's marker) travels, and which joints did the work.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_splay_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const ROOTS := {"L": -72.51, "R": 43.94}
const ARM_KEYS := ["wrist_flex", "wrist_dev", "pronation", "forearm_flex",
	"forearm_abd", "elbow_x", "elbow_y", "elbow_z"]


func _pad(side: String, ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


func _init() -> void:
	var ks := Kbd3D.keys()
	var names := ["Ctrl", "Alt", "пробел", "глобус", "Win"]
	for side in ["L", "R"]:
		var root_x: float = ROOTS[side]
		var home: Dictionary = HomePose.build(side, root_x)
		var rest_thumb := _pad(side, "I", home)
		var rest_ii := _pad(side, "II", home)
		var arm0: Dictionary = home["arm"]
		print("=== %s hand (root %.2f)" % [side, root_x])
		print("  rest: thumb pad %s  index pad %s"
			% [str(rest_thumb), str(rest_ii)])
		print("  rest arm %s" % str(arm0))
		var th0: Dictionary = HandModel.thumb_of_pose(home)
		print("  rest thumb %s" % str(th0))
		for nm in names:
			var idx := -1
			var wx := 0.0
			for i in ks.size():
				var k: Dictionary = ks[i]
				if String(k["s"]) != nm:
					continue
				var r: Rect2 = k["r"]
				# The game's own rule: a wide key is pressed at the clicked
				# point, a small one at its centre.
				var hx := r.get_center().x
				if r.size.x > Kbd3D.KEY_W * 1.05:
					var ix := minf(Kbd3D.KEY_W * 0.5, r.size.x * 0.5)
					hx = clampf(r.get_center().x + (0.6 * r.size.x * 0.5
						if side == "L" else -0.6 * r.size.x * 0.5),
						r.position.x + ix, r.end.x - ix)
				var hf := Kbd3D.hand_finger(nm, hx)
				if int(hf[0]) != (0 if side == "L" else 1):
					continue
				if String(hf[1]) != "I":
					continue
				idx = i
				wx = hx
				break
			if idx < 0:
				continue
			var r2: Rect2 = ks[idx]["r"]
			var world := Vector3(wx, r2.get_center().y,
				Kbd3D.FACE_Z - Kbd3D.TRAVEL)
			var t := _local(side, root_x, world)
			var res: Dictionary = IK.solve_chain("I", t, home,
				{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
				"clear_w": 100.0, "dir_w": 30.0})
			var pose: Dictionary = res["pose"]
			var pad := _pad(side, "I", pose)
			var ii := _pad(side, "II", pose)
			var thumb_move := pad.distance_to(rest_thumb)
			var hand_move := ii.distance_to(rest_ii)
			var th: Dictionary = HandModel.thumb_of_pose(pose)
			var arm: Dictionary = pose["arm"]
			print("  %-7s world x %+7.2f  err %.3f  fit %.3f  iters %d"
				% [nm, wx, float(res["error"]), float(res["fit"]),
				int(res["iterations"])])
			print("      pad %s" % str(pad))
			print("      thumb moved %6.2f  hand moved %6.2f  ratio %5.2f"
				% [thumb_move, hand_move,
				thumb_move / maxf(hand_move, 0.001)])
			var dth := []
			for j in HandModel.THUMB_JOINTS:
				dth.append("%s %+.1f" % [j, float(th[j]) - float(th0[j])])
			var darm := []
			for j in ARM_KEYS:
				darm.append("%s %+.1f" % [j, float(arm.get(j, 0.0))
					- float(arm0.get(j, 0.0))])
			print("      thumb %s" % ", ".join(dth))
			print("      arm   %s" % ", ".join(darm))
	quit(0)
