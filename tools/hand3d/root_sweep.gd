# The whole-arm shift the author asked for (02.11.2026): keep the straight
# hands (P0 angles), move each arm as a whole, so that the four fingers touch
# only their own home columns and the curl energy is minimal. The sweep moves
# both roots outward by delta and reports, per step:
#   · the summed shares^2 of the four fingers (the "curl energy");
#   · the pad-vs-column residuals (a finger that cannot reach flags !!);
#   · the inward-most pad of each hand (do the finger groups cross?);
#   · both thumb pads and the pair's gap (crossing check).
# The thumb targets stay where the P0 candidate has them during the sweep:
# the fingers are the objective here; the thumbs are pinned to the space-bar
# edges after the delta is chosen.
extends SceneTree

const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")
const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT0 := {"L": -72.51, "R": 43.94}
const HOME := {
	"L": {"II": "а", "III": "в", "IV": "ы", "V": "ф"},
	"R": {"II": "о", "III": "л", "IV": "д", "V": "ж"},
}
const RAYS := ["II", "III", "IV", "V"]


func _world(side: String, root: float, p: Dictionary,
		local: Vector3) -> Vector3:
	# The pad is measured in the hand's own frame; the arm's transform puts it
	# into the shared millimetres the board lives in (the jury's own path).
	var q := ArmModel.hand_transform(p.get("arm", {})) * local
	if side == "R":
		return Vector3(root - q.x, q.y, q.z)
	return Vector3(root + q.x, q.y, q.z)


func _key_x(side: String, label: String) -> float:
	var ks := Kbd3D.keys()
	return Kbd3D.centre(ks[Kbd3D.index_of(ks, label)]).x


func _init() -> void:
	print("delta  sumE   pad residuals dx (|.|>2 flagged X)  |  "
		+ "Lthumb Rthumb  gaptop(pin) | Lmax  Rmin  fingers")
	var best := {"d": -1.0, "e": 0.0}
	for i in range(0, 71, 2):
		var d := float(i)
		var roots := {"L": float(ROOT0["L"]) - d, "R": float(ROOT0["R"]) + d}
		var sumE := 0.0
		var flags := ""
		var thumb := {}
		var inward := {}
		for side in ["L", "R"]:
			var root := float(roots[side])
			var p := HomePose.build(side, root)
			var hard := 1e9 if side == "L" else -1e9
			for ray in RAYS:
				var sh: Array = IK.shares_of(ray, p["fingers"][ray])
				for s in sh:
					sumE += float(s) * float(s)
				var local := HandModel.finger_pad(ray,
					HandModel.finger_fk(ray, p["fingers"][ray]))
				var wp := _world(side, root, p, local)
				var dx := wp.x - _key_x(side, HOME[side][ray])
				if absf(dx) > 2.0:
					flags += " %s%s%.1f" % [side, ray, dx]
				if side == "L" and wp.x > hard:
					hard = wp.x
				if side == "R" and wp.x < hard:
					hard = wp.x
			inward[side] = hard
			var th := HandModel.thumb_of_pose(p)
			var twp := _world(side, root, p,
				HandModel.thumb_pad(HandModel.thumb_fk(th)))
			thumb[side] = twp.x
		var gap := float(thumb["R"]) - float(thumb["L"])
		var cross := "  CROSS" \
			if float(inward["L"]) >= float(inward["R"]) else ""
		var row := "d %4.1f  E %8.1f |%s| Lth %6.1f Rth %6.1f gap %6.1f" \
			+ " | Lmax %6.1f Rmin %6.1f%s"
		print(row % [d, sumE, flags, float(thumb["L"]), float(thumb["R"]),
			gap, float(inward["L"]), float(inward["R"]), cross])
		if flags == "" and (best["d"] < 0.0 or sumE < float(best["e"])):
			best = {"d": d, "e": sumE}
	if best["d"] < 0.0:
		print("no delta without pad misses")
	else:
		print("min finger energy among clean rows: delta %.0f (E %.2f)"
			% [float(best["d"]), float(best["e"])])
	quit(0)
