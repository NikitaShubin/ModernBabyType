# Grid search for the typing home placement of the FOUR fingers, with the arm
# frozen at each candidate. The fingers solve independently (no tuck): the arm
# is the shared placement, the fingers adapt. Prints the best candidate and the
# per-finger errors, so the home pose is measured, not guessed.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const HOVER := 12.0
const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const ROOT_X := -72.56
const RAYS := ["II", "III", "IV", "V"]


func _pad(p: Dictionary, ray: String) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _targets() -> Dictionary:
	var ks := Kbd3D.keys()
	var out := {}
	for ray in RAYS:
		var label: String = {"II": "а", "III": "в", "IV": "ы", "V": "ф"}[ray]
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, label)])
		out[ray] = Vector3(c.x - ROOT_X, c.y, Kbd3D.FACE_Z + HOVER)
	return out


func _score(targets: Dictionary, arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	for ray in RAYS:
		var r: Dictionary = IK.solve_chain(ray, targets[ray], p,
			{"arm": false, "tuck": false, "clear_z": CLEAR_Z,
			"clear_w": 100.0, "dir_w": 30.0})
		p = r["pose"]
	var worst := 0.0
	var sum := 0.0
	var errs := {}
	for ray in RAYS:
		var e := _pad(p, ray).distance_to(targets[ray])
		errs[ray] = e
		worst = maxf(worst, e)
		sum += e * e
	return {"worst": worst, "sum": sum, "errs": errs, "pose": p}


func _init() -> void:
	var targets := _targets()
	var best := {"worst": 1e9}
	var t0 := Time.get_ticks_msec()
	for iz in 9:
		var z := -40.0 + 5.0 * float(iz)
		for iy in 5:
			var y := 0.0 + 5.0 * float(iy)
			for ifx in 5:
				var fx := -20.0 + 10.0 * float(ifx)
				var arm := ArmModel.rest_arm()
				arm["elbow_y"] = y
				arm["elbow_z"] = z
				arm["wrist_flex"] = fx
				var s := _score(targets, arm)
				if float(s["worst"]) < float(best["worst"]):
					best = s
					best["arm"] = arm
					print("best worst %.2f sum %.1f  z %.0f y %.0f fx %.0f  %s"
						% [float(s["worst"]), float(s["sum"]), z, y, fx,
						str(s["errs"])])
	print("elapsed ", Time.get_ticks_msec() - t0, " ms")
	print("BEST arm ", best["arm"])
	print("  errs ", best["errs"])
	print("  pose fingers ", best["pose"]["fingers"])
	quit(0)
