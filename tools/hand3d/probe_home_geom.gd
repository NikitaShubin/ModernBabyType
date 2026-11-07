# Where the home pose actually puts the knuckles, the pads and the fans, and
# how far the neighbouring fingers' bones are from each other. The question:
# is the index fanned inboard by the placement (knuckle outboard of its key),
# and does that convergence survive when the middle finger extends?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}


func _init() -> void:
	for side in ["L"]:
		var root_x: float = ROOTS[side]
		var home: Dictionary = HomePose.build(side, root_x)
		var xf := ArmModel.hand_transform(home["arm"])
		print("=== %s home root %.2f" % [side, root_x])
		for ray in ["II", "III", "IV", "V"]:
			var a: Dictionary = home["fingers"][ray]
			var fk: Dictionary = HandModel.finger_fk(ray, a)
			var pts: PackedVector3Array = fk["pts"]
			var head: Vector3 = xf * HandModel.metacarpal_head(ray)
			var pad: Vector3 = xf * HandModel.finger_pad(ray, fk)
			var tgt: Vector3 = HomePose.target(side, ray, root_x)
			print("  %s fan %6.2f mcp %6.2f pip %6.2f dip %6.2f" % [ray,
				float(a["fan"]), float(a["mcp"]), float(a["pip"]),
				float(a["dip"])])
			print("     knuckle %s pad %s target %s" % [
				str(_w(head, root_x)), str(_w(pad, root_x)),
				str(_w(tgt, root_x))])
		var fk2: Dictionary = HandModel.finger_fk("II", home["fingers"]["II"])
		var fk3: Dictionary = HandModel.finger_fk("III", home["fingers"]["III"])
		var p2: PackedVector3Array = fk2["pts"]
		var p3: PackedVector3Array = fk3["pts"]
		for i in 4:
			for j in 4:
				if i < 1 or j < 1:
					continue
				var d := (xf * p2[i]).distance_to(xf * p3[j])
				var rr: Array = HandModel.SKIN_R["II"]
				var r3: Array = HandModel.SKIN_R["III"]
				var pen := float(rr[i]) + float(r3[j]) - d
				if pen > 0.1:
					print("  home II_%d/III_%d d %.2f pen %.2f" % [i, j, d, pen])
	quit(0)


func _w(v: Vector3, root_x: float) -> Vector3:
	return Vector3(snappedf(v.x + root_x, 0.01), snappedf(v.y, 0.01),
		snappedf(v.z, 0.01))
