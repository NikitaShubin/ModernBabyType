# Can the ring and little fingers reach their home keys AT ALL from this arm?
# Sweeps the two band coordinates (MCP share, and the shared IP share) and
# prints the closest pad to the target. If the target is on the reachable
# curve, the IK is stuck; if it is not, the arm has to move.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://finger_curve_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const HOME_LABELS := {"II": "а", "III": "в", "IV": "ы", "V": "ф"}
const TOUCH := 0.3


func _target(ray: String) -> Vector3:
	var ks := Kbd3D.keys()
	var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, HOME_LABELS[ray])])
	return Vector3(c.x, c.y, Kbd3D.FACE_Z + TOUCH)


func _angles(ray: String, sm: float, si: float) -> Dictionary:
	var rest: Array = HandModel.FLEX[ray]
	var rom: Dictionary = HandModel.ROM[ray]
	var out := {}
	for j in ["mcp", "pip", "dip"]:
		var i := ["mcp", "pip", "dip"].find(j)
		var r := float(rest[i])
		var lo := float(rom[j][0])
		var hi := float(rom[j][1])
		var s := sm if j == "mcp" else si
		out[j] = r + s * (hi - r) if s >= 0.0 else r + s * (r - lo)
	out["fan"] = float(HandModel.FAN[ray])
	return out


func _pad(ray: String, angles: Dictionary, xf: Transform3D) -> Vector3:
	var pad: Vector3 = xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, angles))
	pad.x += ROOT_L
	return pad


func _init() -> void:
	var arm := ArmModel.rest_arm()
	arm["forearm_abd"] = 23.875
	arm["wrist_dev"] = -22.0
	arm["wrist_flex"] = -20.0
	arm["pronation"] = -0.75
	arm["elbow_x"] = -ArmModel.FOREARM_L * sin(deg_to_rad(23.875))
	arm["elbow_y"] = 19.25 + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(deg_to_rad(23.875))
	arm["elbow_z"] = -46.125
	var xf := ArmModel.hand_transform(arm)
	for ray in ["IV", "V"]:
		var t := _target(ray)
		var best := 1e9
		var best_m := 0.0
		var best_i := 0.0
		var best_pad := Vector3.ZERO
		for mi in 25:
			for ii in 25:
				var sm := -0.2 + 0.05 * mi
				var si := -0.2 + 0.05 * ii
				if absf(sm - si) > 0.30:
					continue
				var pad := _pad(ray, _angles(ray, sm, si), xf)
				var d := pad.distance_to(t)
				if d < best:
					best = d
					best_m = sm
					best_i = si
					best_pad = pad
		print("%s target %s  best d %6.2f at mcp share %5.2f ip share %5.2f  pad %s"
			% [ray, str(t), best, best_m, best_i, str(best_pad)])
		# The same, with the fan free: the fan can be set by the IK anyway.
		var best2 := 1e9
		var best2_f := 0.0
		var best2_m := 0.0
		var best2_i := 0.0
		var best2_pad := Vector3.ZERO
		var rom: Dictionary = HandModel.ROM[ray]
		for fi in 25:
			var fan := float(rom["fan"][0]) + (float(rom["fan"][1])
				- float(rom["fan"][0])) * float(fi) / 24.0
			for mi in 25:
				for ii in 25:
					var sm := -0.2 + 0.05 * mi
					var si := -0.2 + 0.05 * ii
					if absf(sm - si) > 0.30:
						continue
					var a := _angles(ray, sm, si)
					a["fan"] = fan
					var pad := _pad(ray, a, xf)
					var d := pad.distance_to(t)
					if d < best2:
						best2 = d
						best2_f = fan
						best2_m = sm
						best2_i = si
						best2_pad = pad
		print("   with fan: d %6.2f at fan %5.2f mcp %5.2f ip %5.2f  pad %s"
			% [best2, best2_f, best2_m, best2_i, str(best2_pad)])
		# The same WITHOUT the band: are the joints alone enough?
		var best3 := 1e9
		var best3_f := 0.0
		var best3_m := 0.0
		var best3_i := 0.0
		var best3_pad := Vector3.ZERO
		for fi in 25:
			var fan := float(rom["fan"][0]) + (float(rom["fan"][1])
				- float(rom["fan"][0])) * float(fi) / 24.0
			for mi in 25:
				for ii in 25:
					var sm := -0.2 + 0.05 * mi
					var si := -0.2 + 0.05 * ii
					var a := _angles(ray, sm, si)
					a["fan"] = fan
					var pad := _pad(ray, a, xf)
					var d := pad.distance_to(t)
					if d < best3:
						best3 = d
						best3_f = fan
						best3_m = sm
						best3_i = si
						best3_pad = pad
		print("   no band:  d %6.2f at fan %5.2f mcp %5.2f ip %5.2f  pad %s"
			% [best3, best3_f, best3_m, best3_i, str(best3_pad)])
	quit(0)
