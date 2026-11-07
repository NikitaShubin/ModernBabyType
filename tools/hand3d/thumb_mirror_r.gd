# SS50f probe: the right thumb's pose as an EXACT COPY of the left's solved
# pose (the author's call of 02.11.2026: "в расслабленном состоянии правая
# рука должна полностью повторять позу левой"; "не обязана прижиматься к краю
# пробела — главное на какой-то части пробела и не пересекаться с большим
# пальцем другой руки"). The angles are LOCAL, and the right's world map is
# mirror-consistent: its x enters reversed (world = root_R - q.x), so the
# copied posture must land the right pad exactly at the roots' asymmetry
# minus the left's pad: 93.94 - (padL + 122.51) = -28.57 - (-31) = +2.43,
# over the bar's middle, y 112, hover 2 mm. The pure rests already sit in
# pairwise (L -13.13 / R -15.44 with the same 5.37 mm hover), which proves
# the map; this probe prints the solved pair, the gap, the II-head metrics
# in s5check's format and the mirrored rests for the record.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const HomePose := preload("res://home_pose.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT0 := {"L": -122.51, "R": 93.94}
const PAD_R := 9.6
const BAR_HALF := 46.46


static func base_for(side: String, root_x: float) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	p["thumb_hold"] = {"twist": float(HomePose.THUMB_TWIST[side])}
	for ray in ["II", "III", "IV", "V"]:
		var t: Vector3 = HomePose.target(side, ray, root_x)
		var r: Dictionary = IK.solve_chain(ray, t, p, HomePose._opts(ray))
		p = r["pose"]
	return p


static func world(side: String, p: Dictionary, local: Vector3) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var q := xf * local
	var rx := float(ROOT0[side])
	if side == "R":
		return Vector3(rx - q.x, q.y, q.z)
	return Vector3(rx + q.x, q.y, q.z)


static func rest_pad(side: String, base: Dictionary, twist: float) -> Vector3:
	var th: Dictionary = HandModel.THUMB_REST.duplicate(true)
	th["twist"] = twist
	var fk := HandModel.thumb_fk(th)
	return world(side, base, HandModel.thumb_pad(fk))


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var baseL := base_for("L", float(ROOT0["L"]))
	var baseR := base_for("R", float(ROOT0["R"]))
	var restL := rest_pad("L", baseL, float(HomePose.THUMB_TWIST["L"]))
	var restR := rest_pad("R", baseR, float(HomePose.THUMB_TWIST["R"]))
	print("pure rests: L (%7.2f, %7.2f, %7.2f)  R (%7.2f, %7.2f, %7.2f)" % [
		restL.x, restL.y, restL.z, restR.x, restR.y, restR.z])
	print("roots' asymmetry |L| - R = %.2f mm; mirror map rest_R = -28.57 - rest_L" % [
		absf(float(ROOT0["L"])) - float(ROOT0["R"])])

	# the left thumb solves to its own target as shipped
	var rL := IK.solve_chain("I", HomePose.target("L", "I", float(ROOT0["L"])),
		baseL, HomePose._opts("I"))
	var poseL: Dictionary = rL["pose"]
	var thL: Dictionary = HandModel.thumb_of_pose(poseL)
	var fkL := HandModel.thumb_fk(thL)
	var padL: Vector3 = world("L", poseL, HandModel.thumb_pad(fkL))

	# the pose twin: copy the dict verbatim, no IK on the right
	var thR: Dictionary = thL.duplicate(true)
	var poseR: Dictionary = baseR.duplicate(true)
	poseR["thumb"] = thR
	poseR["thumb_hold"] = {"twist": float(thR["twist"])}
	var fkR := HandModel.thumb_fk(thR)
	var padR: Vector3 = world("R", poseR, HandModel.thumb_pad(fkR))
	var gap := padL.distance_to(padR)
	var heads := {
		"L": world("L", poseL, HandModel.metacarpal_head("II")),
		"R": world("R", poseR, HandModel.metacarpal_head("II")),
	}
	var pastL := -1.0 * (padL.x - (heads["L"] as Vector3).x)
	var pastR := 1.0 * (padR.x - (heads["R"] as Vector3).x)
	print("L pad (%7.2f, %7.2f, %7.2f) II head (%6.2f, %6.2f) past %.2f" % [
		padL.x, padL.y, padL.z, (heads["L"] as Vector3).x,
		(heads["L"] as Vector3).y, pastL])
	print("R twin pad (%7.2f, %7.2f, %7.2f) II head (%6.2f, %6.2f) past %.2f" % [
		padR.x, padR.y, padR.z, (heads["R"] as Vector3).x,
		(heads["R"] as Vector3).y, pastR])
	var same := thL.duplicate(true)
	print("angle dicts identical: %s" % str(thR == thL))
	print("pad gap %.2f mm (flesh %.2f) | crossing: %s" % [gap, gap - 2.0 * PAD_R, "no" if gap > 0.0 else "YES"])
	print("margins inside bar edge: L %.2f  R %.2f mm" % [
		BAR_HALF - (absf(padL.x) + PAD_R), BAR_HALF - (absf(padR.x) + PAD_R)])
	print("predicted R twin x = %.2f" % (-28.57 - padL.x))

	# does the PLAIN per-side build() with the mirrored constants reproduce
	# the twin on its own (identical local inputs -> identical solve)?
	var plainR: Dictionary = HomePose.build("R", float(ROOT0["R"]))
	var thSR: Dictionary = HandModel.thumb_of_pose(plainR)
	var padSR: Vector3 = world("R", plainR,
		HandModel.thumb_pad(HandModel.thumb_fk(thSR)))
	print("plain build('R') pad (%7.2f, %7.2f, %7.2f) angles == twin: %s" % [
		padSR.x, padSR.y, padSR.z, str(thSR == thL)])
	var plainL: Dictionary = HomePose.build("L", float(ROOT0["L"]))
	var thSL: Dictionary = HandModel.thumb_of_pose(plainL)
	print("plain build('L') angles == twin: %s" % str(thSL == thL))
	print("mirror probe done in %.2f s" % ((Time.get_ticks_msec() - t0) * 1e-3))
	quit(0)
