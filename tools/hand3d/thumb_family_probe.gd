# Does the thumb's own 4-DOF family admit a pose that reaches the home pad
# with the IP joint FURTHER OUT? The pad target is one 3D point and the thumb
# has four joints, so the solutions form a curve; the solver picks the cheapest
# point on it, and that point hooks the IP joint inward (world x -5.0 on the
# left, +9.0 on the right: a 17.4 mm gap between two ~21 mm thick joints).
#
# This probe enumerates the family on a grid and prints the IP joint's x for
# the poses that reach the pad. If an outward pose exists, the home solve can
# be steered to it; if not, the pad itself has to move.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_family_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_REST := {"cmc_flex": 0.0, "cmc_abd": 0.0, "mcp": 16.0, "ip": 34.0}
const JOINTS := ["cmc_flex", "cmc_abd", "mcp", "ip"]
const ROM := {"cmc_flex": [-10.0, 25.0], "cmc_abd": [-25.0, 30.0],
	"mcp": [-4.0, 60.0], "ip": [-4.0, 90.0]}


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _energy(t: Dictionary) -> float:
	# The same shape as the solver's rest prior: squared deviation from the
	# rest angle, summed. Good enough to rank the family's members.
	var e := 0.0
	for j in JOINTS:
		var d := float(t[j]) - float(THUMB_REST[j])
		e += d * d
	return e


func _scan(side: String) -> void:
	var root_x: float = ROOTS[side]
	var p: Dictionary = HomePose.build(side, root_x)
	var xf := ArmModel.hand_transform(p["arm"])
	var tgt: Vector3 = HomePose.target(side, "I", root_x)
	print("=== %s target local %s" % [side, str(tgt)])
	var found := 0
	var best_e := 1e9
	var best_t := {}
	var best_ip := 0.0
	var out_t := {}
	var out_ip := 0.0
	var min_ip := 1e9
	var max_ip := -1e9
	for a in range(-10, 26, 5):
		for b in range(-25, 31, 5):
			for m in range(-4, 61, 4):
				for i in range(-4, 91, 6):
					var t := {"cmc_flex": float(a), "cmc_abd": float(b),
						"mcp": float(m), "ip": float(i)}
					var fk: Dictionary = HandModel.thumb_fk(t)
					var pad: Vector3 = xf * HandModel.thumb_pad(fk)
					if pad.distance_to(tgt) > 0.6:
						continue
					found += 1
					var ip: Vector3 = _world(side, xf * (fk["pts"] as PackedVector3Array)[2])
					var e := _energy(t)
					min_ip = minf(min_ip, ip.x)
					max_ip = maxf(max_ip, ip.x)
					if e < best_e:
						best_e = e
						best_t = t
						best_ip = ip.x
					# Outward is away from the centre line: more negative on the
					# left, more positive on the right.
					var out := ip.x if side == "R" else -ip.x
					var out_cur := out_ip if side == "R" else -out_ip
					if out_t.is_empty() or out > out_cur:
						out_t = t
						out_ip = ip.x
	print("    reaching poses %d  IP x range %7.2f .. %7.2f" % [found,
		min_ip, max_ip])
	print("    cheapest   energy %8.1f  IP x %7.2f  %s" % [best_e, best_ip,
		str(best_t)])
	print("    most outward  IP x %7.2f  %s" % [out_ip, str(out_t)])
	var cur: Dictionary = HandModel.thumb_of_pose(p)
	var cfk: Dictionary = HandModel.thumb_fk(cur)
	var cip: Vector3 = _world(side, xf * (cfk["pts"] as PackedVector3Array)[2])
	print("    solver pose   energy %8.1f  IP x %7.2f  %s" % [_energy(cur),
		cip.x, str(cur)])


func _init() -> void:
	_scan("L")
	_scan("R")
	quit(0)
