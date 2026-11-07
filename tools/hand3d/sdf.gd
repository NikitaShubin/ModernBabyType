# SDF primitives for the hand study. All numbers are millimetres.
extends RefCounted


static func cone(p: Vector3, a: Vector3, b: Vector3, ra: float, rb: float) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 0.000001:
		t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t) - lerpf(ra, rb, t)


static func sphere(p: Vector3, c: Vector3, r: float) -> float:
	return p.distance_to(c) - r


static func ellipsoid(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := p - c
	var qx := q.x / r.x
	var qy := q.y / r.y
	var qz := q.z / r.z
	var k0 := sqrt(qx * qx + qy * qy + qz * qz)
	var k1 := sqrt(
		(q.x / (r.x * r.x)) * (q.x / (r.x * r.x))
		+ (q.y / (r.y * r.y)) * (q.y / (r.y * r.y))
		+ (q.z / (r.z * r.z)) * (q.z / (r.z * r.z))
	)
	if k1 < 0.000001:
		return -minf(r.x, minf(r.y, r.z))
	return k0 * (k0 - 1.0) / k1


# Ellipsoid in its own frame: the axes are given, so a plate can lie on a
# curved finger instead of being aligned to the world.
static func ellipsoid_oriented(p: Vector3, c: Vector3, r: Vector3,
		xa: Vector3, ya: Vector3, za: Vector3) -> float:
	var q := p - c
	return ellipsoid(Vector3(q.dot(xa), q.dot(ya), q.dot(za)), Vector3.ZERO, r)


# Rounded box, optionally turned about Z (the palm's knuckle line is oblique).
static func box_rot_z(p: Vector3, c: Vector3, half: Vector3, r: float, ang: float) -> float:
	var q := p - c
	var ca := cos(-ang)
	var sa := sin(-ang)
	var x := q.x * ca - q.y * sa
	var y := q.x * sa + q.y * ca
	var dx := absf(x) - half.x + r
	var dy := absf(y) - half.y + r
	var dz := absf(q.z) - half.z + r
	var ox := maxf(dx, 0.0)
	var oy := maxf(dy, 0.0)
	var oz := maxf(dz, 0.0)
	var out := sqrt(ox * ox + oy * oy + oz * oz)
	var ins := minf(maxf(dx, maxf(dy, dz)), 0.0)
	return out + ins - r


# Capsule with the cross-section squashed along the axes of s.
static func capsule_scaled(p: Vector3, a: Vector3, b: Vector3, ra: float, rb: float, s: Vector3) -> float:
	var qp := Vector3(p.x / s.x, p.y / s.y, p.z / s.z)
	var qa := Vector3(a.x / s.x, a.y / s.y, a.z / s.z)
	var qb := Vector3(b.x / s.x, b.y / s.y, b.z / s.z)
	return cone(qp, qa, qb, ra, rb) * minf(s.x, minf(s.y, s.z))


static func smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


# Smooth subtraction: b eats into a without a crease. Callers negate b
# themselves (smax(d, -hollow, k)) — the sign lives in one place only.
static func smax(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 - 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) + k * h * (1.0 - h)
