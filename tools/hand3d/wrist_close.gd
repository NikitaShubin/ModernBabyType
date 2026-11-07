# TEMP probe: the far bottom-row presses BEFORE and AFTER the #11 wrist soft
# stop, in one process, from the author's own view and from above.
extends Node3D

const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")

const OUT := "/tmp/opencode"
const SETS := [[0.0, "before"], [1.5, "after"]]

var v: Node


func _ready() -> void:
	v = load("res://board.tscn").instantiate()
	add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED
	for c in v.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var picks := []
	for i in v._keys.size():
		var s := String((v._keys[i] as Dictionary)["s"])
		if (Kbd3D.ROW_BOTTOM as Array).has(s) or s == "←":
			if String(v._sim_key_side(i)) != "":
				picks.append(i)
	for cfg in SETS:
		ArmModel.DEV_FREE = 3.0
		ArmModel.DEV_SOFT = float(cfg[0])
		for i in picks:
			var s := String((v._keys[i] as Dictionary)["s"])
			var side := String(v._sim_key_side(i))
			var rx := float(v._sim_rest_rx[side])
			var st: Dictionary = v._sim_stroke(side, i,
				(v._sim_rest_home[side] as Dictionary).duplicate(true), rx,
				v._foreign_rest(side))
			var pose: Dictionary = st["press"]
			var ray := String(Kbd3D.hand_finger(s,
				Kbd3D.centre(v._keys[i]).x)[1])
			v._set_pose(side, pose)
			await get_tree().process_frame
			var a: Dictionary = pose["arm"]
			print("%-7s %-7s %s dev %+6.1f flex %+6.1f pron %+6.1f abd %+6.1f"
				% [String(cfg[1]), s, side, float(a["wrist_dev"]),
				float(a["wrist_flex"]), float(a["pronation"]),
				float(a["forearm_abd"])])
			for view in [["author", 10.3, 29.8], ["top", 10.3, 78.0]]:
				var cx := -105.0 if side == "L" else 78.0
				v._yaw = deg_to_rad(float(view[1]))
				v._pitch = deg_to_rad(float(view[2]))
				var span := 420.0
				v._dist = span / (2.0 * tan(deg_to_rad(v._cam.fov * 0.5)) * 1000.0)
				v._center = Vector3(cx, 75.0, -45.0) * 0.001
				v._update_camera()
				await get_tree().process_frame
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				var nm := "n11_%s_%d_%s_%s_%s" % [String(cfg[1]), i, s, side,
					String(view[0])]
				img.save_png(OUT.path_join(nm + ".png"))
			v._rest(side)
	ArmModel.DEV_FREE = 3.0
	ArmModel.DEV_SOFT = 1.5
	get_tree().quit()
