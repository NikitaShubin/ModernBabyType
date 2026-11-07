# TEMP probe (author, 03.11.2026): the shipped home pose after the thumb's
# contact moved out and the solver's comfort polish was switched on. Reports
# the thumb's angles and how tangential it is, every finger's pad and its
# contact with its own key, and the thumb's clearance from its own palm —
# the author's #2 (the third phalanx must not hide under the palm) still has
# to hold after the move.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const HomePose := preload("res://home_pose.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")


func _pads(side: String, p: Dictionary, root_x: float) -> void:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var sgn := -1.0 if side == "R" else 1.0
	var th := HandModel.thumb_of_pose(p)
	var tfk := HandModel.thumb_fk(th)
	var d2: Vector3 = (xf.basis * (tfk["dirs"][2] as Vector3)).normalized()
	var pad: Vector3 = xf * HandModel.thumb_pad(tfk)
	var off := rad_to_deg(asin(clampf(absf(d2.z), 0.0, 1.0)))
	print("%s thumb | cmc_flex %+5.1f abd %+5.1f twist %+5.1f mcp %+5.1f ip %+5.1f"
		% [side, float(th["cmc_flex"]), float(th["cmc_abd"]),
			float(th["twist"]), float(th["mcp"]), float(th["ip"])])
	print("        d2 (%+0.2f %+0.2f %+0.2f)  tip %4.1f deg off the face | pad world x %+6.2f y %+6.2f z %+6.2f"
		% [d2.x, d2.y, d2.z, off, pad.x * sgn + root_x, pad.y, pad.z])
	for ray in ["II", "III", "IV", "V"]:
		var fk := HandModel.finger_fk(ray, p["fingers"][ray])
		var fp: Vector3 = xf * HandModel.finger_pad(ray, fk)
		var wx := fp.x * sgn + root_x
		var tgt: Vector3 = HomePose.target(side, ray, root_x)
		var want := Kbd3D.row_y(2)
		print("        %s pad world x %+7.2f y %+7.2f z %+6.2f | own key x %+7.2f y %+6.2f | miss %5.2f"
			% [ray, wx, fp.y, fp.z, tgt.x * sgn + root_x, want,
				Vector2(fp.x - tgt.x, fp.y - tgt.y).length()])


func _build(side: String, root: float, comfort: bool) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	p["thumb_hold"] = {"twist": float(HomePose.THUMB_TWIST[side]),
		"cmc_abd": float(HomePose.THUMB_ABD[side])}
	for ray in ["II", "III", "IV", "V", "I"]:
		var o: Dictionary = HomePose._opts(ray)
		o["comfort"] = comfort
		p = IK.solve_chain(ray, HomePose.target(side, ray, root), p, o)["pose"]
	return p


func _run() -> void:
	for side in ["L", "R"]:
		var root := float(HomePose.HOME_ROOTS[side])
		print("--- %s, comfort OFF ---" % side)
		_pads(side, _build(side, root, false), root)
		print("--- %s, comfort ON (shipped) ---" % side)
		_pads(side, _build(side, root, true), root)


func _init() -> void:
	_run()
	quit()
