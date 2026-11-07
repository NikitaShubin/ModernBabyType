# Numeric check of the wrist Euler decomposition used by seed_hand.
extends SceneTree


func _decomp(r: Basis) -> Dictionary:
	var dev := -asin(clampf(r.x.y, -1.0, 1.0))
	var flex := atan2(r.z.y, r.y.y)
	var pron := atan2(-r.x.z, r.x.x)
	return {"dev": dev, "flex": flex, "pron": pron}


func _build(p: float, a: float, b: float) -> Basis:
	return Basis(Vector3.UP, p) * Basis(Vector3.BACK, -a) * Basis(Vector3.RIGHT, -b)


func _diff(r: Basis, r2: Basis) -> float:
	var err := 0.0
	for v in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		err = maxf(err, (r * v).distance_to(r2 * v))
	return err


func _init() -> void:
	var cases := [[0.0, 0.0, 0.0], [0.4, 0.0, 0.0], [0.0, 0.3, 0.0],
		[0.0, 0.0, 0.5], [0.3, 0.2, -0.4], [-0.7, 0.35, 1.1]]
	for c in cases:
		var p: float = c[0]
		var a: float = c[1]
		var b: float = c[2]
		var r := _build(p, a, b)
		var d := _decomp(r)
		var r2 := _build(float(d["pron"]), float(d["dev"]), float(d["flex"]))
		print("p %.2f a %.2f b %.2f -> p %.2f a %.2f b %.2f err %.5f" % [p, a, b,
			float(d["pron"]), float(d["dev"]), float(d["flex"]), _diff(r, r2)])
	quit()
