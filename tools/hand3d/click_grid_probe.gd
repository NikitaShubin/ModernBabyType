# Every key of the grid with every finger, through the exact click scheme of
# viewer.gd: the press is solved once with the whole arm free (the thumb capped
# at THUMB_PRESS_LO), then the hover is either the press pose with the thumb
# lifted (thumb) or solved from the press pose with the arm free (four
# fingers). Reports where the press misses, where the hover is not farther from
# the face than the press (the key would not sink), and how far the hand turns.
#   mbt-godot --headless --path /work/tools/hand3d --script res://click_grid_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0
const KEY_TRAVEL := 2.6
const THUMB_PRESS_LO := -0.35
const THUMB_HOVER_LIFT := 0.30

const NX := 10
const NY := 5


func _init() -> void:
	var rest := HandModel.rest_pose()
	for ray in ["I", "II", "III", "IV", "V"]:
		var miss := []
		var flat := []
		var worst_move := 0.0
		var worst_at := ""
		var worst_span := 1e9
		var span_at := ""
		var frozen_flat := []
		var frozen_span := 1e9
		var frozen_at := ""
		for iy in NY:
			for ix in NX:
				var k := iy * NX + ix
				var c := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
					KEY_Y0 + float(iy) * KEY_PITCH, KEY_Z)
				var face := Vector3(c.x, c.y, KEY_FACE)
				var deep := Vector3(c.x, c.y, KEY_FACE - KEY_TRAVEL - 1.0)
				var flo := THUMB_PRESS_LO if ray == "I" else -1.0
				var press: Dictionary = IK.solve_chain(ray, deep, rest,
					{"arm": true, "f_lo": flo})
				var pp: Dictionary = press["pose"]
				var hover: Dictionary
				if ray == "I":
					hover = pp.duplicate(true)
					hover["thumb_f"] = clampf(
						float(hover["thumb_f"]) + THUMB_HOVER_LIFT, -1.0, 1.0)
				else:
					var hv := face + Vector3(0.0, 0.0, KEY_HOVER)
					var h: Dictionary = IK.solve_chain(ray, hv, pp, {"arm": true})
					hover = h["pose"]
					var hf: Dictionary = IK.solve_chain(ray, hv, pp,
						{"arm": false})
					var df := _pad(ray, hf["pose"]).distance_to(face)
					var sp := df - _pad(ray, pp).distance_to(face)
					if sp <= 0.5:
						frozen_flat.append("%d,%d(%.1f)" % [ix, iy, sp])
					if sp < frozen_span:
						frozen_span = sp
						frozen_at = "%d,%d" % [ix, iy]
				var dp := _pad(ray, pp).distance_to(face)
				var dh := _pad(ray, hover).distance_to(face)
				var span := dh - dp
				if float(press["error"]) > 0.5:
					miss.append("%d,%d(%.1f)" % [ix, iy, float(press["error"])])
				if span <= 0.5:
					flat.append("%d,%d(%.1f)" % [ix, iy, span])
				if span < worst_span:
					worst_span = span
					span_at = "%d,%d" % [ix, iy]
				var a0: Dictionary = pp["arm"]
				var a1: Dictionary = hover["arm"]
				var dw := absf(float(a1["wrist_flex"]) - float(a0["wrist_flex"])) \
					+ absf(float(a1["wrist_dev"]) - float(a0["wrist_dev"]))
				var dpr := absf(float(a1["pronation"]) - float(a0["pronation"]))
				var df := absf(float(a1["forearm_flex"]) - float(a0["forearm_flex"])) \
					+ absf(float(a1["forearm_abd"]) - float(a0["forearm_abd"]))
				var de := absf(float(a1["elbow_x"]) - float(a0["elbow_x"])) \
					+ absf(float(a1["elbow_y"]) - float(a0["elbow_y"])) \
					+ absf(float(a1["elbow_z"]) - float(a0["elbow_z"]))
				var mv := dw + dpr + df + de
				if mv > worst_move:
					worst_move = mv
					worst_at = "%d,%d w%.1f p%.1f f%.1f e%.1f" % [ix, iy,
						dw, dpr, df, de]
		var frz := "same (thumb moves alone)"
		if ray != "I":
			frz = "frozen flat %d %s | frozen min span %.2f at %s" % [
				frozen_flat.size(), str(frozen_flat), frozen_span, frozen_at]
		print("%s: miss %d %s | flat %d %s | min span %.2f mm at %s | max hand move %.1f at %s | %s" % [
			ray, miss.size(), str(miss), flat.size(), str(flat),
			worst_span, span_at, worst_move, worst_at, frz])
	quit(0)


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf: Transform3D = ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))
