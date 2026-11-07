# Does ANY pose of the thumb's four joints put the pad on the home target with
# the IP joint OUTBOARD of the pad? The family walk says the branch the solver
# sits on is walled in by the CMC's extension stop (-10 deg): along the whole
# curve the IP joint's x moves by 0.7 mm. That is one branch. This probe scans
# the entire joint box instead of one curve.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_grid_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const TOL := 1.0


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _scan(side: String) -> void:
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var xf := ArmModel.hand_transform(home["arm"])
	var tgt: Vector3 = HomePose.target(side, "I", root_x)
	var f_rom: Array = HandModel.THUMB_ROM["cmc_flex"]
	var a_rom: Array = HandModel.THUMB_ROM["cmc_abd"]
	var m_rom: Array = HandModel.THUMB_ROM["mcp"]
	var i_rom: Array = HandModel.THUMB_ROM["ip"]
	var found := 0
	var best := 1e9
	var best_pose := {}
	var out_ip := -1e9
	var out_pose := {}
	var out_pad := 0.0
	var ip_lo := 1e9
	var ip_hi := -1e9
	var total := 0
	var f := float(f_rom[0])
	while f <= float(f_rom[1]) + 0.001:
		var a := float(a_rom[0])
		while a <= float(a_rom[1]) + 0.001:
			var m := float(m_rom[0])
			while m <= float(m_rom[1]) + 0.001:
				var i := float(i_rom[0])
				while i <= float(i_rom[1]) + 0.001:
					total += 1
					var t := {"cmc_flex": f, "cmc_abd": a, "mcp": m, "ip": i}
					var fk: Dictionary = HandModel.thumb_fk(t)
					var pad: Vector3 = xf * HandModel.thumb_pad(fk)
					var d := pad.distance_to(tgt)
					if d < best:
						best = d
						best_pose = t
					if d <= TOL:
						found += 1
						var ip: Vector3 = _world(side, xf
							* (fk["pts"] as PackedVector3Array)[2])
						ip_lo = minf(ip_lo, ip.x)
						ip_hi = maxf(ip_hi, ip.x)
						var outward := ip.x if side == "R" else -ip.x
						var out_cur := out_ip if side == "R" else -out_ip
						if out_pose.is_empty() or outward > out_cur:
							out_ip = ip.x
							out_pose = t
							out_pad = d
					i += 4.0
				m += 3.2
			a += 2.75
		f += 2.5
	print("=== %s grid %d poses, within %.1f mm: %d" % [side, total, TOL, found])
	print("    best distance %6.3f  %s" % [best, str(best_pose)])
	if found > 0:
		print("    IP x range %7.2f .. %7.2f" % [ip_lo, ip_hi])
		print("    most outward IP x %7.2f (pad err %.2f)  %s"
			% [out_ip, out_pad, str(out_pose)])


func _init() -> void:
	_scan("L")
	_scan("R")
	quit(0)
