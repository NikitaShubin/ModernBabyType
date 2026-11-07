# Which vertices project onto the two stray pixels of close-palm-f70-hand?
# Rebuilds the exact camera of wrist_close.gd and unprojects every deformed
# hand vertex. Prints the closest vertices, their neighbours and their
# triangles, so a sliver can be named. Headless.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const Viewer := preload("res://viewer.gd")
const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const DOTS := [[564, 332], [585, 314]]


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var rig := SkinRig.build(rest, opened, REST_MESH, Viewer.WRIST_FLAT_H)
	var pose: Dictionary = HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = 70.0
	var model := HandModel.new(1.0, 0.0, pose)
	var p: PackedVector3Array = SkinRig.cpu_positions(rig, model)
	var a: Array = opened.surface_get_arrays(0)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]

	# The camera, exactly as wrist_close.gd sets it up, projected by hand:
	# Godot's look_at puts -Z on the target, UP is the up hint.
	var yaw := -1.30
	var pitch := 0.10
	var dist := 0.16
	var center := Vector3(0.0, -0.005, -0.01)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var cam_pos := center + dir * dist
	var back := (cam_pos - center).normalized()
	var right := Vector3.UP.cross(back).normalized()
	var up := back.cross(right).normalized()
	var focal := 400.0 / tan(deg_to_rad(15.0))

	# The rig root spins with the yaw; the mesh sits under it with SCALE.
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * Viewer.SCALE)
	for d in DOTS:
		var want := Vector2(float(d[0]), float(d[1]))
		var best := []
		for i in p.size():
			var q := basis * p[i] - cam_pos
			var depth := -q.dot(back)
			if depth <= 0.0:
				continue
			var s := Vector2(400.0 + q.dot(right) / depth * focal,
				400.0 - q.dot(up) / depth * focal)
			best.append([s.distance_to(want), i, s])
		best.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		print("dot %s" % str(want))
		for k in 6:
			var i: int = best[k][1]
			print("   %.2f px  v%d  at %s  dy %.2f" % [float(best[k][0]), i,
				str(p[i]), p[i].y - ArmView.CUT_Y])
		var near: int = best[0][1]
		var tris := []
		for t in range(0, idx.size(), 3):
			if idx[t] == near or idx[t + 1] == near or idx[t + 2] == near:
				var q0 := p[idx[t]]
				var q1 := p[idx[t + 1]]
				var q2 := p[idx[t + 2]]
				var area := (q1 - q0).cross(q2 - q0).length() * 0.5
				tris.append([area, idx[t], idx[t + 1], idx[t + 2]])
		tris.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		print("   triangles at v%d: %d, smallest:" % [near, tris.size()])
		for k in mini(tris.size(), 5):
			print("     area %.6f mm2  %d %d %d  dys %.2f %.2f %.2f" % [
				float(tris[k][0]), int(tris[k][1]), int(tris[k][2]), int(tris[k][3]),
				p[int(tris[k][1])].y - ArmView.CUT_Y,
				p[int(tris[k][2])].y - ArmView.CUT_Y,
				p[int(tris[k][3])].y - ArmView.CUT_Y])
	quit()
