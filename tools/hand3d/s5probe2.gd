# Compares the measured hand-axis direction for the two arms the search
# produced, so the "splay" number is anchored to real fresh measurements.
# It prints the transform basis, not an interpretation of it.
extends SceneTree

const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ARMS := {
	"D": {
		"wrist_flex": -20.0, "wrist_dev": -20.0, "pronation": 0.0,
		"forearm_flex": 0.0, "forearm_abd": 22.0,
		"elbow_x": -56.1909890123868, "elbow_y": 30.9224218149819,
		"elbow_z": -44.0,
	},
	"E": {
		"wrist_flex": -20.0, "wrist_dev": -20.0, "pronation": 0.5,
		"forearm_flex": 0.0, "forearm_abd": 24.25,
		"elbow_x": -66.1078278920216, "elbow_y": 33.7125535098234,
		"elbow_z": -44.25,
	},
}


func _init() -> void:
	for name in ["D", "E"]:
		var arm: Dictionary = ARMS[name]
		var xf := ArmModel.hand_transform(arm)
		var b: Basis = xf.basis
		var d := b * Vector3(0, 1, 0)
		var n := b * Vector3(0, 0, -1)
		print("%s: distal (deg from +y, atan2(-d.x, d.y) = out+) %.2f, palm normal tilt (atan2(n.x, -n.z) = centre+) %.2f"
			% [name, rad_to_deg(atan2(-d.x, d.y)),
			rad_to_deg(atan2(n.x, -n.z))])
		print("   basis_x %s | basis_y %s | basis_z %s" % [str(b.x), str(b.y),
			str(b.z)])
		var f := ArmModel.frames(arm)
		var wv: Vector3 = f["wrist"]
		var ev: Vector3 = f["elbow"]
		print("   wrist %s elbow %s forearm dir %s" % [str(wv), str(ev),
			str((wv - ev).normalized())])
	quit(0)
