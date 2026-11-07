# Every key of the project's board, pressed by the hand and finger the map
# gives it, from the typing home pose, with the whole arm free — the same
# solver and the same options the board viewer's click uses. A key is
# "reachable" when the pad lands on the press point within REACH_TOL.
#
# The author (31.10.2026): "далеко не до всех клавиш пальцы реально
# дотягиваются. Тебе надо добавить эту проверку в тестах." This is that
# check: it prints every miss with its residual, and fails the run when the
# list is not empty.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://reach_test.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -122.51, "R": 93.94}
const REACH_TOL := 0.5          # mm; the solver's own tolerance is 0.01
# How far above the key face the solver's clearance plane sits. The idle pads
# REST on the face (home_pose.TOUCH = 0.3 mm), so a plane 3 mm above it demands
# that every idle finger be lifted off the board by the tuck — and the tuck
# then folds the fingers by unequal amounts. Measured: with +3 the far keys
# lost up to 2.1 mm of reach; the resting pads are the physical truth.
const CLEAR_LIFT := 0.0
const CLEAR_Z := Kbd3D.FACE_Z + CLEAR_LIFT


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


# The point on the key face a press aims at: the key's centre for a 1u key;
# for a wide key, the centre of the hand's own half (the game's rule for the
# space bar, and the only fair point for a shared key).
func _press_xy(side: String, k: Dictionary) -> Vector2:
	var r: Rect2 = k["r"]
	if r.size.x <= Kbd3D.KEY_W * 1.05 + 0.01:
		return r.get_center()
	var half := r.size.x * 0.5
	return Vector2(r.get_center().x + (-0.5 if side == "L" else 0.5) * half,
		r.get_center().y)


func _init() -> void:
	var ks := Kbd3D.keys()
	var homes := {}
	for side in ["L", "R"]:
		homes[side] = HomePose.build(side, ROOTS[side])
	var misses := []
	var cases := 0
	var worst := 0.0
	var worst_at := ""
	for k in ks:
		var s := String(k["s"])
		var r: Rect2 = k["r"]
		for side in ["L", "R"]:
			var xy := _press_xy(side, k)
			var hf := Kbd3D.hand_finger(s, xy.x)
			if int(hf[0]) != (0 if side == "L" else 1):
				continue
			var ray := String(hf[1])
			if ray == "":
				continue
			cases += 1
			var deep := _local(side, ROOTS[side],
				Vector3(xy.x, xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL))
			var res: Dictionary = IK.solve_chain(ray, deep, homes[side],
				{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
				"clear_w": 100.0, "dir_w": 30.0})
			var err := float(res["error"])
			if err > worst:
				worst = err
				worst_at = "%s %s %s" % [side, s, ray]
			if err > REACH_TOL:
				misses.append("%s %-7s %-3s err %6.2f" % [side, s, ray, err])
	print("reach: %d cases, %d misses (tol %.1f mm), worst %.2f at %s"
		% [cases, misses.size(), REACH_TOL, worst, worst_at])
	for m in misses:
		print("  MISS ", m)
	quit(0 if misses.is_empty() else 1)
