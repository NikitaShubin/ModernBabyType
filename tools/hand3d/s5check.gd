# The jury of the enshrined home pose (the numbers the author asked for).
# It measures the pose AS SHIPPED — via HomePose.build — so the probe and the
# shipped file can never disagree:
#   · the hand's axis tilt per hand (deg, outward positive) and the palm's
#     tilt towards the centre (deg, positive = the "holding a ball" look);
#   · each pad's world position against its key (the residual must be ~0);
#   · the elbow gap and the thumbs' tapered flesh gap (mm);
#   · the thumb's top-view margin past the II knuckle head ("not under the
#     palm": the pad should sit beyond the palm's inboard edge, in FRONT of
#     the metacarpal rim) for both hands;
#   · the thumb's chain points in world space, for the top-view eyeball.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

# The thumb's capsule radii, joint by joint (the same table the viewer hands
# the solver's foreign obstacle).
const THUMB_R := [11.8, 10.8, 9.6, 6.6]

# The roots come from the environment (MBT_ROOT_L / MBT_ROOT_R) so the jury can
# ride a whole-arm-shifted candidate without touching this file. Without the
# env, the enshrined roots are used.
const ROOT0 := {"L": -122.51, "R": 93.94}


func _root(side: String) -> float:
	var e := OS.get_environment("MBT_ROOT_" + side)
	if e != "":
		return float(e)
	return float(ROOT0[side])
const HOME_LABELS := {
	"L": {"II": "а", "III": "в", "IV": "ы", "V": "ф"},
	"R": {"II": "о", "III": "л", "IV": "д", "V": "ж"},
}


func _world(side: String, p: Dictionary, local: Vector3) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var q := xf * local
	var rx := _root(side)
	if side == "R":
		return Vector3(rx - q.x, q.y, q.z)
	return Vector3(rx + q.x, q.y, q.z)


func _key_cx(side: String, label: String) -> float:
	var ks := Kbd3D.keys()
	return Kbd3D.centre(ks[Kbd3D.index_of(ks, label)]).x


func _init() -> void:
	print("ARM ", str(HomePose.ARM))
	for side in ["L", "R"]:
		var p := HomePose.build(side, _root(side))
		var arm: Dictionary = p["arm"]
		# Directions must go through the BASIS: the transform's origin is
		# the wrist position, and it swamps the axis (the lesson of stage
		# one — D read -0.1 deg through the transform, -2.0 through basis).
		var hb: Basis = ArmModel.hand_transform(arm).basis
		var d := hb * Vector3(0, 1, 0)
		var n := hb * Vector3(0, 0, -1)
		var splay := rad_to_deg(atan2(-d.x, d.y))
		var tilt := rad_to_deg(atan2(n.x, -n.z))
		# the forearm's own axis tilt, for the report
		var fa := ArmModel.frames(arm)
		var w: Vector3 = fa["wrist"]
		var fdir := Vector3(w - fa["elbow"])
		var fabd := rad_to_deg(atan2(fdir.x, fdir.y))
		print("%s splay %.1f  palm_tilt %.1f  forearm_tilt %.1f"
			% [side, splay, tilt, fabd])
		for ray in ["II", "III", "IV", "V"]:
			var local := HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, p["fingers"][ray]))
			var pad := _world(side, p, local)
			var cx := _key_cx(side, HOME_LABELS[side][ray])
			var dy := pad.y - Kbd3D.row_y(2)
			print("  %s %s pad world x %.2f y %.2f z %.2f | key x %.2f dy %.2f dz %.3f"
				% [side, ray, pad.x, pad.y, pad.z, cx, dy,
				pad.z - (Kbd3D.FACE_Z + HomePose.TOUCH)])
		# the thumb: pad and chain in world space
		var th := HandModel.thumb_of_pose(p)
		var fk := HandModel.thumb_fk(th)
		var pts: Array = []
		for i in 4:
			pts.append(_world(side, p, fk["pts"][i]))
		var pad_i := _world(side, p, HandModel.thumb_pad(fk))
		var head_ii := _world(side, p, HandModel.metacarpal_head("II"))
		var head_iii := _world(side, p, HandModel.metacarpal_head("III"))
		var inboard := 1.0 if side == "R" else -1.0
		var margin_i := inboard * (pad_i.x - head_ii.x)
		var margin_fwd := pad_i.y - head_ii.y
		print("  %s thumb pad x %.2f y %.2f z %.2f | II head x %.2f y %.2f | pad past II head %.2f mm, forward %.2f mm | chain %s"
			% [side, pad_i.x, pad_i.y, pad_i.z, head_ii.x, head_ii.y,
			margin_i, margin_fwd, str(pts)])
		print("  %s thumb angles %s | III head x %.2f y %.2f"
			% [side, str(th), head_iii.x, head_iii.y])
	# gaps
	var pl := HomePose.build("L", _root("L"))
	var pr := HomePose.build("R", _root("R"))
	var thl := HandModel.thumb_fk(HandModel.thumb_of_pose(pl))
	var thr := HandModel.thumb_fk(HandModel.thumb_of_pose(pr))
	var padl := _world("L", pl, HandModel.thumb_pad(thl))
	var padr := _world("R", pr, HandModel.thumb_pad(thr))
	# The two thumbs as TAPERED capsules — the same measure the solver's
	# foreign obstacle uses (ik.gd `_seg_pts` + the per-joint radii). The pad
	# centres are only half the story: the flesh gap is
	# dist - r_a(s) - r_b(t), minimised over the 3x3 segment pairs.
	var cl := []
	var cr := []
	for i in 4:
		cl.append(_world("L", pl, thl["pts"][i]))
		cr.append(_world("R", pr, thr["pts"][i]))
	var flesh := INF
	for i in 3:
		for j in 3:
			var sg: Array = IK._seg_pts(cl[i], cl[i + 1], cr[j], cr[j + 1])
			var ra: float = lerpf(float(THUMB_R[i]), float(THUMB_R[i + 1]),
				float(sg[1]))
			var rb: float = lerpf(float(THUMB_R[j]), float(THUMB_R[j + 1]),
				float(sg[2]))
			flesh = minf(flesh, float(sg[0]) - ra - rb)
	print("thumbs: pads %.2f mm apart (centres), tapered flesh gap %.2f mm"
		% [padl.distance_to(padr), flesh])
	var fl := ArmModel.frames(pl["arm"])
	var fr := ArmModel.frames(pr["arm"])
	var el: Vector3 = fl["elbow"]
	var er: Vector3 = fr["elbow"]
	var wlv: Vector3 = fl["wrist"]
	var wrv: Vector3 = fr["wrist"]
	var wl := Vector3(_root("L") + wlv.x, wlv.y, wlv.z)
	var wr := Vector3(_root("R") - wrv.x, wrv.y, wrv.z)
	print("elbows world x %.1f / %.1f -> gap %.1f mm; wrists %s / %s"
		% [_root("L") + el.x, _root("R") - er.x,
		(_root("R") - er.x) - (_root("L") + el.x), str(wl),
		str(wr)])
	quit(0)
