# TEMP probe: per finger, the closest band-legal pose to its home key for a few
# (hand drop, band) pairs, with the angles and the spread it spends. The worst
# digit is the one that sets the pair.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT0 := {"L": -122.51, "R": 93.94}
const FANS := {"II": -12.0, "III": -7.5, "IV": -3.0, "V": 0.5}
const PAIRS := [[4.0, 0.40], [4.0, 0.35], [5.0, 0.35], [3.0, 0.50]]


func _share(q: float, rest: float, lo: float, hi: float) -> float:
	return (q - rest) / (hi - rest) if q >= rest else (q - rest) / (rest - lo)


func _init() -> void:
	for pair in PAIRS:
		var drop: float = float(pair[0])
		var band: float = float(pair[1])
		var arm: Dictionary = (HomePose.ARM as Dictionary).duplicate(true)
		arm["elbow_z"] = float(arm["elbow_z"]) - drop
		var xf := ArmModel.hand_transform(arm)
		print("== drop %.1f band %.2f" % [drop, band])
		for ray in ["II", "III", "IV", "V"]:
			var tw := HomePose.target("L", ray, float(ROOT0["L"]))
			var key := Vector3(tw.x, tw.y, -69.0 + 0.3)
			var bm := 1e9
			var ba := {}
			var m: float = -10.0
			while m <= 90.0:
				var p: float = -5.0
				while p <= 110.0:
					var d: float = -5.0
					while d <= 70.0:
						var s0 := _share(m, 20.0, -10.0, 90.0)
						var s1 := _share(p, 34.0, -5.0, 110.0)
						var s2 := _share(d, 14.0, -5.0, 70.0)
						var spread: float = maxf(s0, maxf(s1, s2)) \
							- minf(s0, minf(s1, s2))
						if spread <= band + 1e-6:
							var fk := HandModel.finger_fk(ray,
								{"fan": float(FANS[ray]), "mcp": m, "pip": p,
								"dip": d})
							var w: Vector3 = xf * HandModel.finger_pad(ray, fk)
							var e := w.distance_to(key)
							if e < bm:
								bm = e
								ba = {"mcp": m, "pip": p, "dip": d,
									"spread": spread, "w": w}
						d += 2.0
					p += 2.0
				m += 2.0
			print("  %s %.2f at mcp %4.1f pip %4.1f dip %4.1f spread %.2f | %s" \
				% [ray, bm, float(ba["mcp"]), float(ba["pip"]),
					float(ba["dip"]), float(ba["spread"]), str(ba["w"])])
	quit(0)
