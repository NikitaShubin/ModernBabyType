# The home key's reachable set with the pad's DEPTH FREE: how close can each
# finger's pad come to the key's column and face (x, z) while staying anywhere
# over the key's depth? Sweeps the band coordinates (MCP share, shared IP
# share) and the fan; reports the best x/z distance and the depth it lands at.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://free_y_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const HOME_LABELS := {"II": "а", "III": "в", "IV": "ы", "V": "ф"}
const TOUCH := 0.3
const Y_FREE := 9.0


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
	arm["forearm_abd"] = 21.5
	arm["wrist_dev"] = -20.0
	arm["wrist_flex"] = -20.0
	arm["pronation"] = -0.25
	arm["elbow_x"] = -0.5 - ArmModel.FOREARM_L * sin(deg_to_rad(21.5))
	arm["elbow_y"] = 20.0 + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(deg_to_rad(21.5))
	arm["elbow_z"] = -42.5
	var xf := ArmModel.hand_transform(arm)
	for ray in ["II", "III", "IV", "V"]:
		var t := _target(ray)
		var best := 1e9
		var best_f := 0.0
		var best_m := 0.0
		var best_i := 0.0
		var best_pad := Vector3.ZERO
		var best_ok := 1e9
		var ok_f := 0.0
		var ok_m := 0.0
		var ok_i := 0.0
		var ok_pad := Vector3.ZERO
		var rom: Dictionary = HandModel.ROM[ray]
		for fi in 25:
			var fan := float(rom["fan"][0]) + (float(rom["fan"][1])
				- float(rom["fan"][0])) * float(fi) / 24.0
			for mi in 49:
				for ii in 49:
					var sm := -0.4 + 0.025 * mi
					var si := -0.4 + 0.025 * ii
					if absf(sm - si) > 0.25:
						continue
					var a := _angles(ray, sm, si)
					a["fan"] = fan
					var pad := _pad(ray, a, xf)
					var dx := pad.x - t.x
					var dz := pad.z - t.z
					var d := sqrt(dx * dx + dz * dz)
					if d < best:
						best = d
						best_f = fan
						best_m = sm
						best_i = si
						best_pad = pad
					if absf(pad.y - t.y) <= Y_FREE and d < best_ok:
						best_ok = d
						ok_f = fan
						ok_m = sm
						ok_i = si
						ok_pad = pad
		print("%s key %s" % [ray, str(t)])
		print("   free y:  d(x,z) %5.2f at fan %5.2f mcp %5.2f ip %5.2f  pad %s  dy %6.2f"
			% [best, best_f, best_m, best_i, str(best_pad), best_pad.y - t.y])
		print("   in key:  d(x,z) %5.2f at fan %5.2f mcp %5.2f ip %5.2f  pad %s  dy %6.2f"
			% [best_ok, ok_f, ok_m, ok_i, str(ok_pad), ok_pad.y - t.y])
	quit(0)
