# The thumb pad may sit anywhere on the space bar's 20.76 mm depth. Does the
# choice of depth (and of x within the author's 20-23 mm) change where the IP
# joint lands? The home pose's thumbs currently hook inward (IP x -5.0 and
# +9.0, a 17.4 mm gap between two ~21 mm thick joints), and the pad's depth is
# the one coordinate the brief leaves free.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_depth_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const LIFT := 2.0
const XS := [20.5, 23.0]
const YS := [98.5, 101.0, 104.0, 106.5, 108.5, 110.5, 113.0, 116.0, 118.5]


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _energy(t: Dictionary) -> float:
	var e := 0.0
	for j in HandModel.THUMB_JOINTS:
		var d := float(t[j]) - float(HandModel.THUMB_REST[j])
		e += d * d
	return e


func _scan(side: String) -> void:
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var xf := ArmModel.hand_transform(home["arm"])
	print("=== %s home thumb %s" % [side, str(HandModel.thumb_of_pose(home))])
	for x in XS:
		for y in YS:
			var wx := -float(x) if side == "L" else float(x)
			var t := Vector3((wx - root_x) * (1.0 if side == "L" else -1.0),
				float(y), Kbd3D.FACE_Z + LIFT)
			var r: Dictionary = IK.solve_chain("I", t, home,
				{"arm": false, "thumb_dof": 4})
			var p: Dictionary = r["pose"]
			var th: Dictionary = HandModel.thumb_of_pose(p)
			var fk: Dictionary = HandModel.thumb_fk(th)
			var ip: Vector3 = _world(side, xf * (fk["pts"] as PackedVector3Array)[2])
			var pad: Vector3 = _world(side, xf * HandModel.thumb_pad(fk))
			print("  x %5.1f y %6.1f  err %5.2f  IP x %7.2f  pad %s  E %7.1f  %s"
				% [wx, y, float(r["error"]), ip.x, str(pad), _energy(th),
				str(th)])


func _init() -> void:
	_scan("L")
	_scan("R")
	quit(0)
