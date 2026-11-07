# Inverse kinematics for the hand study.
#
# The model is a plain forward chain, so IK is built on top of it, not inside
# it: one fixed metacarpal head per finger, then three phalanges bending in the
# finger's own plane (MCP flexion, PIP, DIP) plus the MCP fan, which turns that
# plane sideways. The thumb has ONE coordinate f (see hand_model.gd) — its IK
# is therefore a one-dimensional search along the path the thumb can walk.
#
# The solver works in SHARES OF TRAVEL, not in degrees: every joint gets a
# number in [-1, 1], 0 at the rest pose, +1 at its flexion stop, -1 at its
# extension stop. That is the measure the author asked for — "the load is
# distributed evenly, no joint twisted while its neighbour is almost straight".
# In share space the rule is simply max(s) - min(s) <= BAND: the joints may
# stagger a little (a real finger does: the tip lags), never a lot. The band is
# a HARD constraint, enforced by projecting every solver step back into it — a
# soft penalty was tried first and failed exactly here: for a far target the
# solver traded a huge stagger for a couple of millimetres of reach and ended
# with the MCP folded while the PIP was straight.
#
# Inside the band a mild even-load term (W_EVEN) still prefers equal shares, so
# a target reachable with an even curl is answered with an even curl.
#
# The rest pose is the zero of the energy: a share vector of zeros costs
# nothing, and any deviation from rest costs W_PRIOR per share squared. That is
# what picks the laziest pose among the ones that reach the target, and it is
# why a rest target returns the rest pose instead of "some pose with the same
# fingertip".
#
# Everything is in millimetres and degrees, as in hand_model.gd.
extends RefCounted

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const JOINTS := ["mcp", "pip", "dip"]

# Solver budget and weights. W_PRIOR is in "millimetres squared per share
# squared": a full 100% deviation of one joint costs W_PRIOR mm² of reach. It
# is deliberately small — posture must never win over a target the chain can
# actually touch, it only settles the freedom the chain has left.
const ITERS := 140
const TOL := 0.01             # mm — close enough, well under the skin's 2 mm grid
const STEP_MAX := 0.20        # share units per iteration (≈ 14° at the MCP)
const W_PRIOR := 0.05
# The finger prior actually charged by the chain solve. The bottom-row profile
# raises it (author, #11: the hand must travel, not the finger), everything
# else gets the approved constant. Set per solve in solve_chain.
static var PRIOR := W_PRIOR
# Allowed spread max(s) - min(s), in share units. The original 0.12 was too
# tight for the typing home pose: the ring finger needs its IP joints to carry
# more of the curl than its MCP (the real hand does exactly that when the ring
# lies on "ы"), and 0.12 left it 5.5 mm off the key face while every other
# digit reached. At 0.25 the home pose is reachable and a press still keeps
# the joints together — a full stagger is 1.0, the fold-with-a-straight-
# neighbour pose the author rejected. The wide-elbow arm (SS50h, 03.11.2026)
# needs 0.35: the hand sits 5 mm lower and the index and ring carry their
# home key with a deeper stagger (the drop x band scan in elbow_scan.gd:
# drop 4 / 0.40 and drop 5 / 0.35 both land the four pads within 0.33 mm).
# See BASELINE.md, 31.10.2026 and SS50h.
const BAND := 0.35            # allowed spread max(s) - min(s), in share units
const W_EVEN := 8.0           # even-load preference INSIDE the band
const W_FAN := 1.0
const W_THUMB_PRIOR := 0.05   # per f², mm²
const THUMB_SCAN := 80

# The hierarchical chain: the same finger, plus the arm's five joints. The fan
# is much cheaper in the chain than in the finger-only solver (W_FAN_CHAIN),
# because the author wants the outer fingers to use their side-to-side MCP
# travel to reach a nearby key before the wrist takes over. The arm weights
# are in arm_model.gd; they climb wrist < pronation < forearm root.
const CHAIN_ITERS := 90
const CHAIN_TOL := 0.01
const CHAIN_STEP := 0.20
# A warm drag stops once the pad is this close. It used to stop at 0.5 mm,
# which was fast but left the FIRST pose that reached, not the cheapest one:
# a 5 mm sideways target kept a 0.5° fan and put the rest of the move into the
# wrist and the forearm root. The author's point (28.10.2026) is that the fan
# is the cheap, fast sideways answer, so the warm run polishes the priors too:
# 0.005 mm is far below the skin's 2 mm grid, and the same 5 mm target now
# spends ~3.7° of fan with a tenth of a degree at the wrist and the forearm.
# A jumped target gets the full analytic retry only when the warm answer is
# worse than CHAIN_RETRY.
const CHAIN_WARM_TOL := 0.005
# The comfort polish (see _solve_once): once a pose reaches, run the same cost
# to its own minimum instead of stopping on reach alone. Default ON — the
# author's rule is that any movement obeys the energy minimum. A probe that
# wants the raw warm answer switches it off here rather than in every call.
static var comfort_default := true
const CHAIN_RETRY := 0.5
# When an LM run is done: six accepted steps in a row that each buy less than
# a tenth of a percent of the cost (see _chain_run). Relative, because the cost
# of a guarded pose is dominated by the clearance terms and an absolute
# threshold would mean different things on different keys.
const CHAIN_STALL_GAIN := 1.0e-3
const CHAIN_STALL_RUNS := 6
# How much keyboard violation still counts as "the guard is satisfied" when the
# run decides it is done. The clearance is soft and the skin is 2 mm, so a
# hundredth of a millimetre is nothing; but without a number the run would
# chase float dust for all 90 iterations.
const CHAIN_CLEAR_TOL := 0.01
# The fan is the smallest group in the hierarchy: one finger, moved by the
# intrinsic muscles, while the wrist moves the whole hand and the forearm root
# moves the hand and the forearm. The weight is deliberately far below the
# finger flexors' W_PRIOR so that a few millimetres sideways is answered by the
# fan, not by the wrist. It is an effective inertia, not a joint range; the
# fan's own ROM still stops it at the anatomical limit.
const W_FAN_CHAIN := 0.0005
# How much a millimetre of reach weighs against the joint priors in the chain.
# The priors are measured in millimetres too, so this number decides how much
# residual the solver will trade for a more comfortable pose. It is 3 on
# purpose: the author's rule is that the pad MUST reach, and comfort only
# chooses among poses that do. The last fraction of a millimetre is not this
# weight's business at all — the elbow closes it exactly (see _elbow_close),
# so the weight only has to keep the reach term comparable with the priors
# while the joints are still doing the work.
const CHAIN_REACH_W := 3.0


# How much of its own travel a joint has spent, in [-1, 1]: 0 at rest, +1 at
# its flexion stop, -1 at its extension stop. This is the same measure
# thumb_effort() uses in percent, and the coordinate the finger solver works in.
static func share(q: float, rest: float, lo: float, hi: float) -> float:
	if q >= rest:
		return (q - rest) / maxf(hi - rest, 0.001)
	return (q - rest) / maxf(rest - lo, 0.001)


# Share back to an absolute angle: the inverse of share().
static func angle_of(s: float, rest: float, lo: float, hi: float) -> float:
	if s >= 0.0:
		return rest + s * (hi - rest)
	return rest + s * (rest - lo)


static func _rest_of(ray: String) -> Array:
	var fl: Array = HandModel.FLEX[ray]
	return [float(fl[0]), float(fl[1]), float(fl[2]), float(HandModel.FAN[ray])]


static func _bounds_of(ray: String) -> Array:
	var rom: Dictionary = HandModel.ROM[ray]
	return [[float(rom["mcp"][0]), float(rom["mcp"][1])],
		[float(rom["pip"][0]), float(rom["pip"][1])],
		[float(rom["dip"][0]), float(rom["dip"][1])],
		[float(rom["fan"][0]), float(rom["fan"][1])]]


# The four shares of a pose, so the solver can start exactly where the finger
# already is (a drag must not snap to another branch of the same target).
static func shares_of(ray: String, angles: Dictionary) -> Array:
	var rest := _rest_of(ray)
	var bnd := _bounds_of(ray)
	return [share(float(angles["mcp"]), float(rest[0]), float(bnd[0][0]), float(bnd[0][1])),
		share(float(angles["pip"]), float(rest[1]), float(bnd[1][0]), float(bnd[1][1])),
		share(float(angles["dip"]), float(rest[2]), float(bnd[2][0]), float(bnd[2][1])),
		share(float(angles["fan"]), float(rest[3]), float(bnd[3][0]), float(bnd[3][1]))]


# The absolute pose of a share vector. One source of truth: the solver's
# variables, the FK, and the reported angles all go through here.
static func angles_of_shares(ray: String, q: Array) -> Dictionary:
	var rest := _rest_of(ray)
	var bnd := _bounds_of(ray)
	return {
		"mcp": angle_of(clampf(float(q[0]), -1.0, 1.0), float(rest[0]), float(bnd[0][0]), float(bnd[0][1])),
		"pip": angle_of(clampf(float(q[1]), -1.0, 1.0), float(rest[1]), float(bnd[1][0]), float(bnd[1][1])),
		"dip": angle_of(clampf(float(q[2]), -1.0, 1.0), float(rest[2]), float(bnd[2][0]), float(bnd[2][1])),
		"fan": angle_of(clampf(float(q[3]), -1.0, 1.0), float(rest[3]), float(bnd[3][0]), float(bnd[3][1])),
	}


static func _stagger(a: float, b: float) -> float:
	return a - b


# The thumb in the same share space as a finger: one number per joint, zero at
# rest, ±1 at the joint's own stop. The thumb's joints are not the finger's —
# the saddle has two axes, the MCP and the IP are hinges — so it has its own
# list and its own ROM, and both the solver and the reports read them here.
static func thumb_shares_of(angles: Dictionary, hold: Dictionary = {}) -> Array:
	var out := []
	for j in HandModel.THUMB_JOINTS:
		var rom: Array = HandModel.THUMB_ROM[j]
		var v := float(angles.get(j, HandModel.THUMB_REST[j]))
		if hold.has(j):
			v = float(hold[j])
		out.append(clampf(share(v, float(HandModel.THUMB_REST[j]),
			float(rom[0]), float(rom[1])), -1.0, 1.0))
	return out


static func thumb_angles_of_shares(q: Array, hold: Dictionary = {}) -> Dictionary:
	var out := {}
	for i in HandModel.THUMB_JOINTS.size():
		var j: String = HandModel.THUMB_JOINTS[i]
		if hold.has(j):
			out[j] = float(hold[j])
			continue
		var rom: Array = HandModel.THUMB_ROM[j]
		out[j] = angle_of(clampf(float(q[i]), -1.0, 1.0),
			float(HandModel.THUMB_REST[j]), float(rom[0]), float(rom[1]))
	return out


# Project a step back into the feasible set: shares in [-1, 1] and spread no
# wider than BAND. The spread is compressed toward the mean, which keeps where
# the finger points and bounds max(s) - min(s) by construction. The earlier
# form clamped every share to mean +/- BAND/2, which is STRICTER than the band:
# a legitimate [0.25, 0, 0] (spread exactly BAND) was cut to [0.19, 0, 0], and
# the little finger could not flex its MCP alone enough to reach its home key
# (measured 31.10.2026: the pad stayed 1.8 mm above the face, pinned exactly at
# the old clamp). A real finger's stagger is not centred on its mean.
static func project(q: Array) -> Array:
	var s := [clampf(float(q[0]), -1.0, 1.0), clampf(float(q[1]), -1.0, 1.0),
		clampf(float(q[2]), -1.0, 1.0)]
	var m := (float(s[0]) + float(s[1]) + float(s[2])) / 3.0
	var lo := minf(float(s[0]), minf(float(s[1]), float(s[2])))
	var hi := maxf(float(s[0]), maxf(float(s[1]), float(s[2])))
	var spread := hi - lo
	if spread > BAND:
		var k := BAND / spread
		for i in 3:
			s[i] = m + (float(s[i]) - m) * k
	return [float(s[0]), float(s[1]), float(s[2]), clampf(float(q[3]), -1.0, 1.0)]


# The residual vector of one finger: 3 reach components, 3 rest-prior terms,
# 3 even-load terms (one per joint pair, so their sum is the variance of the
# shares) and 1 fan term. Least squares on this vector is the whole solver.
static func _finger_res(ray: String, q: Array, target: Vector3) -> Dictionary:
	var angles := angles_of_shares(ray, q)
	var fk := HandModel.finger_fk(ray, angles)
	var pad := HandModel.finger_pad(ray, fk)
	var e := pad - target

	var s := [clampf(float(q[0]), -1.0, 1.0), clampf(float(q[1]), -1.0, 1.0),
		clampf(float(q[2]), -1.0, 1.0)]
	var sf := clampf(float(q[3]), -1.0, 1.0)

	var kp := sqrt(W_PRIOR)
	var ke := sqrt(W_EVEN / 3.0)
	var r := [e.x, e.y, e.z,
		kp * float(s[0]), kp * float(s[1]), kp * float(s[2]),
		ke * _stagger(float(s[0]), float(s[1])),
		ke * _stagger(float(s[1]), float(s[2])),
		ke * _stagger(float(s[2]), float(s[0])),
		sqrt(W_FAN) * sf]
	# "fit" is the reach residual alone: it is what solve_finger stops on. The
	# prior and band terms live in "r" and only steer the steps.
	return {"r": r, "pad": pad, "reach": e.length(), "fit": e.length(),
		"shares": s, "fan_share": sf, "angles": angles, "fk": fk}


static func _cost(r: Array) -> float:
	var c := 0.0
	for v in r:
		c += float(v) * float(v)
	return c


static func _jacobian(ray: String, q: Array, target: Vector3) -> Array:
	var base: Array = _finger_res(ray, q, target)["r"]
	var cols := []
	for j in 4:
		var qq: Array = q.duplicate()
		var d := 0.005
		qq[j] = float(qq[j]) + d
		var rr: Array = _finger_res(ray, qq, target)["r"]
		var col := []
		for k in base.size():
			col.append((float(rr[k]) - float(base[k])) / d)
		cols.append(col)
	return cols


static func _normal_equations(cols: Array, lam: float, scaled: bool = false) -> Array:
	var n := cols.size()
	var a := []
	for i in n:
		var row := []
		for j in n:
			var s := 0.0
			for k in (cols[i] as Array).size():
				s += float(cols[i][k]) * float(cols[j][k])
			row.append(s)
		a.append(row)
	# Marquardt scaling: the damping is a fraction of each variable's OWN
	# curvature instead of an absolute number. Absolute damping couples the
	# step to the units of the residual: in the chain the reach term is
	# weighted (CHAIN_REACH_W) and the cheap joints' columns are far
	# smaller than the wrist's, so one absolute lambda either does nothing
	# to the reach or freezes the fan. Scaling by the diagonal keeps every
	# joint on the same relative footing, so the hierarchy decides which
	# joint moves and the damping only decides how far a step is trusted.
	# The finger solver keeps the absolute form: its columns are all of
	# order one and its tests are calibrated on that behaviour.
	#
	# A variable pinned at its clamp has a zero column, so its curvature is
	# zero. Scaling that zero by lambda leaves a pivot under the solver's
	# tolerance and the whole run reads as singular — which is what happened
	# when the fan share hit its stop during a drag: the warm run died after
	# one step, the retry from the analytic seed won, and the hand jumped to
	# another branch. Such a variable is decoupled (its whole row and its
	# gradient are zero), so any positive damping on its diagonal pins it at
	# zero without touching the others. Use the largest curvature for that
	# pin: it is numerically loud and, being decoupled, harmless. A variable
	# that merely has SMALL curvature keeps its own scaling — a common floor
	# would damp the fan relative to the wrist and quietly hand its work up.
	var mx := 0.0
	for i in n:
		mx = maxf(mx, float(a[i][i]))
	for i in n:
		var diag := float(a[i][i])
		var d := 1.0
		if scaled:
			d = diag if diag > mx * 1e-12 else mx
		a[i][i] = diag + lam * d
	return a


static func _gradient(cols: Array, r: Array) -> Array:
	var g := []
	for i in cols.size():
		var s := 0.0
		for k in r.size():
			s += float(cols[i][k]) * float(r[k])
		g.append(s)
	return g


# 4x4 Gaussian elimination with partial pivoting. The system is tiny and
# positive definite before the damping, so this is all the linear algebra the
# solver needs — and it keeps the script free of a dependency.
static func _solve4(a_in: Array, b_in: Array) -> Array:
	var a := []
	for row in a_in:
		a.append((row as Array).duplicate())
	var b := b_in.duplicate()
	var n := 4
	for col in n:
		var piv := col
		for row in range(col + 1, n):
			if absf(float(a[row][col])) > absf(float(a[piv][col])):
				piv = row
		if absf(float(a[piv][col])) < 1e-12:
			return []
		if piv != col:
			var t: Array = a[piv]
			a[piv] = a[col]
			a[col] = t
			var tb: float = b[piv]
			b[piv] = b[col]
			b[col] = tb
		var d: float = a[col][col]
		for j in range(col, n):
			a[col][j] = float(a[col][j]) / d
		b[col] = float(b[col]) / d
		for row in n:
			if row == col:
				continue
			var f: float = a[row][col]
			if is_zero_approx(f):
				continue
			for j in range(col, n):
				a[row][j] = float(a[row][j]) - f * float(a[col][j])
			b[row] = float(b[row]) - f * float(b[col])
	return b


# Solve one finger to the target. The start pose is the current one, so a
# drag is continuous: the solver refines where the finger already is instead
# of jumping to a different branch of the same target.
static func solve_finger(ray: String, target: Vector3, pose: Dictionary) -> Dictionary:
	var q: Array = project(shares_of(ray, pose["fingers"][ray]))
	var lambda := 0.05
	var iters := 0
	var trace := []
	var cur: Dictionary = _finger_res(ray, q, target)
	for it in ITERS:
		iters = it + 1
		if float(cur["fit"]) <= TOL:
			break
		var cols := _jacobian(ray, q, target)
		var a := _normal_equations(cols, lambda)
		var g := _gradient(cols, cur["r"])
		var delta := _solve4(a, [-float(g[0]), -float(g[1]), -float(g[2]), -float(g[3])])
		if delta.is_empty():
			trace.append([it, float(cur["fit"]), lambda, -1.0, false])
			break
		var step_len := 0.0
		var qn := []
		for i in 4:
			var step := clampf(float(delta[i]), -STEP_MAX, STEP_MAX)
			step_len = maxf(step_len, absf(step))
			qn.append(clampf(float(q[i]) + step, -1.0, 1.0))
		qn = project(qn)
		var next: Dictionary = _finger_res(ray, qn, target)
		var accepted := _cost(next["r"]) < _cost(cur["r"]) - 1e-12
		trace.append([it, float(cur["fit"]), lambda, step_len, accepted])
		if accepted:
			q = qn
			cur = next
			lambda = maxf(lambda * 0.6, 1e-6)
		else:
			lambda *= 5.0
			if lambda > 1e7:
				break

	var s: Array = cur["shares"]
	var energy := 0.0
	for v in s:
		energy += float(v) * float(v)
	var spread := maxf(float(s[0]), maxf(float(s[1]), float(s[2]))) \
		- minf(float(s[0]), minf(float(s[1]), float(s[2])))
	var at_rom := {}
	for i in 3:
		at_rom[JOINTS[i]] = absf(float(s[i])) >= 0.999

	var out := pose.duplicate(true)
	out["fingers"][ray] = (cur["angles"] as Dictionary).duplicate(true)
	return {"pose": out, "angles": out["fingers"][ray], "pad": cur["pad"],
		"error": float(cur["reach"]), "energy": energy, "shares": s,
		"fan_share": float(cur["fan_share"]), "spread": spread,
		"stagger": maxf(0.0, spread - BAND), "iterations": iters,
		"at_rom": at_rom, "trace": trace}


# The thumb walks one coordinate, so its IK is a scan plus a golden-section
# refinement on the same kind of cost: distance to the target, plus a small
# preference for the rest pose. The joints cannot twist independently by
# construction — thumb_at() gives all three the same share — and the result
# reports that share so the viewer can show it.
static func solve_thumb(target: Vector3, pose: Dictionary) -> Dictionary:
	var best_f := 0.0
	var best_d := INF
	for i in THUMB_SCAN + 1:
		var f := -1.0 + 2.0 * float(i) / float(THUMB_SCAN)
		var d := _thumb_cost(f, target)
		if d < best_d:
			best_d = d
			best_f = f

	var step := 2.0 / float(THUMB_SCAN)
	var a := maxf(-1.0, best_f - step)
	var b := minf(1.0, best_f + step)
	for i in 40:
		var m1 := a + (b - a) * 0.382
		var m2 := a + (b - a) * 0.618
		if _thumb_cost(m1, target) <= _thumb_cost(m2, target):
			b = m2
		else:
			a = m1
	var f := clampf((a + b) * 0.5, -1.0, 1.0)

	var fk := HandModel.thumb_fk(f)
	var pad := HandModel.thumb_pad(fk)
	var th := HandModel.thumb_at(f)
	var eff := HandModel.thumb_effort(th)
	var out := pose.duplicate(true)
	out["thumb_f"] = f
	return {"pose": out, "thumb_f": f, "angles": th, "effort": eff,
		"pad": pad, "error": pad.distance_to(target), "at_limit": absf(absf(f) - 1.0) < 0.001,
		"cost": _thumb_cost(f, target)}


static func _thumb_cost(f: float, target: Vector3) -> float:
	var pad := HandModel.thumb_pad(HandModel.thumb_fk(f))
	return pad.distance_squared_to(target) + W_THUMB_PRIOR * f * f


# ---- the hierarchical chain: finger + wrist + forearm + elbow root ----
#
# The variables are the finger's shares followed by the arm's eight shares, in
# arm_model.gd's distal-to-proximal order: five rotations, then the elbow's
# three translations. The target is in the same world space the hand lives in
# (the rest hand is the world; the arm transform moves it). The residual is the
# same three reach components plus the finger's own coordination and prior
# terms, plus one prior term per arm joint. The weights are what makes the
# chain climb: a fan share costs 0.005, a finger share 0.05, a wrist share 1.5,
# a pronation share 4, a forearm-root share 30, an elbow millimetre 0.59, so
# the solver only uses a higher joint when the lower ones cannot answer the
# target (or when the finger's hard band stops it). The elbow is a pure
# translation, so it can put the pad on ANY point; it is also the dearest
# level, so the small joints always answer first.
#
# The band is still hard and still only on the three finger flexion shares:
# the arm is not a finger and has no reason to keep a common share.

static func _chain_n(ray: String, free_arm: bool) -> int:
	var nf := 4
	if ray == "I" and thumb_dof != 4:
		nf = 1
	elif ray == "I":
		nf = HandModel.THUMB_JOINTS.size()
	return nf + (ArmModel.ALL_JOINTS.size() if free_arm else 0)


static func _chain_pose(ray: String, q: Array, free_arm: bool,
		base: Dictionary) -> Dictionary:
	var p := {"fingers": {}, "thumb_f": 0.0, "arm": {}}
	var hold: Dictionary = base.get("thumb_hold", {})
	var off := 4
	if ray == "I":
		if thumb_dof == 4:
			var tq := []
			for i in HandModel.THUMB_JOINTS.size():
				tq.append(float(q[i]))
			p["thumb"] = thumb_angles_of_shares(tq, hold)
			p["thumb_dof"] = 4
			if not hold.is_empty():
				p["thumb_hold"] = hold.duplicate(true)
			off = tq.size()
		else:
			p["thumb_f"] = clampf(float(q[0]), thumb_lo, thumb_hi)
			p["thumb"] = HandModel.thumb_at(float(p["thumb_f"]))
			off = 1
			if hover_lift != 0.0:
				p["thumb_df"] = clampf(float(q[1]), 0.0, 1.0)
				off = 2
	else:
		p["fingers"][ray] = angles_of_shares(ray,
			[float(q[0]), float(q[1]), float(q[2]), float(q[3])])
	if free_arm:
		var aq := []
		for i in ArmModel.ALL_JOINTS.size():
			aq.append(float(q[off + i]))
		p["arm"] = ArmModel.angles_of_shares(aq)
	else:
		p["arm"] = ArmModel.clamp_arm(base.get("arm", {}))
	return p


static func _chain_pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


# ONE FORWARD KINEMATICS PER CHAIN PER EVALUATION (author, #9).
# The residual reads the same chain up to six times — the pad, the direction
# term, the keyboard clearance, and each of the ten pairs — and every read used
# to rebuild the chain from its angles: 31 finger_fk calls per evaluation, ~29
# of them redundant. An LM iteration measured 4.2 ms on R «н», which is where
# the freeze on fast typing came from. The memo lives for exactly one
# evaluation: the angles are the same object, so the pose cannot drift.
static func _fk_of(fks: Dictionary, ray: String,
		angles: Dictionary) -> Dictionary:
	if fks.has(ray):
		return fks[ray]
	var fk: Dictionary = HandModel.thumb_fk(angles) if ray == "I" \
		else HandModel.finger_fk(ray, angles)
	fks[ray] = fk
	return fk


# The pad of the chain being solved, from the same memo _chain_res fills.
static func _chain_pad_cached(ray: String, p: Dictionary,
		fks: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(_fk_of(fks, "I",
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray, _fk_of(fks, ray, p["fingers"][ray]))


static func _chain_res(ray: String, q: Array, target: Vector3, free_arm: bool,
		base: Dictionary) -> Dictionary:
	var p := _chain_pose(ray, q, free_arm, base)
	var fks := {}
	var pad := _chain_pad_cached(ray, p, fks)
	var e := pad - target
	var r := [e.x * CHAIN_REACH_W, e.y * CHAIN_REACH_W, e.z * CHAIN_REACH_W]
	# The convergence measure. For an ordinary drag it is the press error alone;
	# for the thumb's click it must also count the hover target, otherwise the
	# loop stops the moment the press is exact and never spends the freedom it
	# has left on making the thumb's arc vertical (k9 stopped with a perfect
	# press and a hover that went 4.9 mm the WRONG way).
	var fit := e.length()
	var clr := 0.0
	var s := []
	var sf := 0.0
	var f := 0.0
	if ray == "I":
		var th: Dictionary = HandModel.thumb_of_pose(p)
		if thumb_dof == 4:
			s = thumb_shares_of(th, base.get("thumb_hold", {}))
			for v in s:
				r.append(sqrt(W_PRIOR) * float(v))
		else:
			f = clampf(float(q[0]), thumb_lo, thumb_hi)
			r.append(sqrt(W_THUMB_PRIOR) * f)
		if dir_w > 0.0:
			# The thumb presses with its palmar pad, so the distal phalanx
			# should lie roughly ALONG the key face, not point into it: the
			# palmar side faces the key only while the bone is near-parallel
			# to it. The old form demanded exactly horizontal (d2.z = 0) and
			# paid for the last degrees with millimetres of reach (k9 stopped
			# 1.1 mm short, k44 0.6). A threshold keeps the pad facing the key
			# and lets the phalanx tilt up to 55 degrees off the face.
			var tfk := _fk_of(fks, "I", th)
			var txf := ArmModel.hand_transform(p["arm"])
			var td2 := (txf.basis * (tfk["dirs"][2] as Vector3)).normalized()
			r.append(dir_w * maxf(0.0, thumb_min - td2.z))
		if hover_lift != 0.0 and thumb_dof != 4:
			# The hover pad: the same arm, the thumb's own coordinate moved
			# back by df. Both targets are on the same vertical line, so a
			# solution exists only if the thumb's arc at this arm pose runs
			# along the key normal.
			var df := clampf(float(q[1]), 0.0, 1.0)
			var hpad: Vector3 = ArmModel.hand_transform(p["arm"]) \
				* HandModel.thumb_pad(HandModel.thumb_fk(f - df))
			var he := hpad - (target + Vector3(0.0, 0.0, hover_lift))
			r.append(he.x * CHAIN_REACH_W)
			r.append(he.y * CHAIN_REACH_W)
			r.append(he.z * CHAIN_REACH_W)
			fit += he.length()
	else:
		s = [clampf(float(q[0]), -1.0, 1.0), clampf(float(q[1]), -1.0, 1.0),
			clampf(float(q[2]), -1.0, 1.0)]
		sf = clampf(float(q[3]), -1.0, 1.0)
		var kp := sqrt(PRIOR)
		var ke := sqrt(W_EVEN / 3.0)
		r.append(kp * float(s[0]))
		r.append(kp * float(s[1]))
		r.append(kp * float(s[2]))
		r.append(ke * (float(s[0]) - float(s[1])))
		r.append(ke * (float(s[1]) - float(s[2])))
		r.append(ke * (float(s[2]) - float(s[0])))
		r.append(sqrt(W_FAN_CHAIN) * sf)
		if dir_w > 0.0:
			# The distal phalanx must point at the keyboard, not lie along it.
			# The old form penalised d3.x and d3.y separately, which drives
			# d3.z to -1: it demanded the finger be exactly perpendicular to
			# the face, and on a far key it paid for that with millimetres of
			# reach (V k5 stopped 5.7 mm short). A threshold says what is
			# actually wanted — the phalanx meets the key at least 60 degrees
			# off the face — and leaves the last 30 degrees free.
			var fk := _fk_of(fks, ray, p["fingers"][ray])
			var xf := ArmModel.hand_transform(p["arm"])
			var d3 := (xf.basis * (fk["dirs"][2] as Vector3)).normalized()
			r.append(dir_w * maxf(0.0, d3.z - dir_min))
	if free_arm:
		# The arm's shares start AFTER the chain's own variables, and how many
		# those are depends on the chain: four thumb joints in the 4-DOF
		# thumb, one f (plus the hover's df when it is used) for the 1-DOF
		# thumb, four for a finger. Reading from a fixed 1 put the thumb's
		# own angles where the arm's priors are read: the elbow's translation
		# then cost nothing at all, and a far press was answered by sliding
		# the whole arm while the thumb stayed tucked (the author's complaint,
		# 31.10.2026). One rule, the same as _chain_pose and _project_chain.
		var off := 4
		if ray == "I":
			if thumb_dof == 4:
				off = HandModel.THUMB_JOINTS.size()
			else:
				off = 1
				if hover_lift != 0.0:
					off = 2
		# The priors are measured from the BASE pose, not from the model's
		# zero. The elbow's three translations are the hand's PLACEMENT over
		# the board, not a bend: the model's zero puts the wrist at the origin
		# of the hand's own space, which is nowhere near the keyboard. With an
		# absolute zero every solve dragged the placement back there — a press
		# on «а» lifted the whole wrist 35 mm off the board while the pad went
		# 15 mm down (measured 31.10.2026). The base is the posture the hand
		# holds (the home pose), so "minimal change from the pose you are in"
		# is the same rule the author asks for: the small joints answer first,
		# the wrist follows, and the elbow only closes what they cannot.
		var bsh := ArmModel.shares_of(base.get("arm", {}))
		for i in ArmModel.ALL_JOINTS.size():
			var j: String = ArmModel.ALL_JOINTS[i]
			var d := clampf(float(q[off + i]), -1.0, 1.0) \
				- clampf(float(bsh[i]), -1.0, 1.0)
			r.append(sqrt(float(ArmModel.weight_of(j))) * d)
			if j == "wrist_dev":
				# Beyond the comfortable window the wrist stops being the cheap
				# answer and the forearm takes the reach (author, #11).
				r.append(ArmModel.dev_soft_cost(d))
	var xf := ArmModel.hand_transform(p["arm"])
	var fingers: Dictionary = base["fingers"]
	if free_arm and clear_w > 0.0:
		# Every joint of every idle finger is a capsule end: the surface is
		# the joint minus its soft-tissue radius. The TARGET finger's tip is
		# the pressing part and is exempt; its proximal joints are not.
		# Constraining only the knuckles let the idle fingers hang through
		# the keyboard whenever the palm had to come forward (V k44: the ring
		# finger's PIP at z = -101 mm). A real hand raises the palm and curls
		# the idle fingers instead.
		for other in ["II", "III", "IV", "V"]:
			var angles: Dictionary = p["fingers"][other] if other == ray \
				else fingers[other]
			var pts: PackedVector3Array = _fk_of(fks, other, angles)["pts"]
			var radii: Array = HandModel.SKIN_R[other]
			var last := 4
			var sink := idle_sink
			if other == ray:
				last = 3
				sink = 0.0
			for j in last:
				var w: Vector3 = xf * pts[j]
				var cv := _joint_violation(w.x, w.y, w.z + sink,
					float(radii[j]), clear_z)
				clr = maxf(clr, cv)
				r.append(sqrt(clear_w) * cv)
		var tf: Dictionary = HandModel.thumb_of_pose(p) if ray == "I" \
			else HandModel.thumb_of_pose(base)
		var tpts: PackedVector3Array = _fk_of(fks, "I", tf)["pts"]
		var tradii := [11.8, 10.8, 9.6, 6.6]
		var tlast := 3 if ray == "I" else 4
		var tsink := 0.0 if ray == "I" else idle_sink
		for j in tlast:
			var tw: Vector3 = xf * tpts[j]
			var tv := _joint_violation(tw.x, tw.y, tw.z + tsink,
				float(tradii[j]), clear_z)
			clr = maxf(clr, tv)
			r.append(sqrt(clear_w) * tv)
	# The hand's own pairs: the same guard, one row per pair (see PAIR_W). It
	# runs on the SAME pose the clearance does, so the two guards share one
	# gradient and the arm answers both — lift the palm, turn the wrist — while
	# the pressing finger keeps its pad on the key.
	var pen := 0.0
	if free_arm and pair_w > 0.0:
		pen = _pair_residuals(xf, p, base, r, fks)
	return {"r": r, "pose": p, "pad": pad, "reach": e.length(), "fit": fit,
		"shares": s, "fan_share": sf, "thumb_f": f, "clr": clr,
		"pen": maxf(0.0, pen - PAIR_TOL)}


# How far the thumb's hover pad is from its own target, for the poses the
# solver builds: zero when the thumb is not the clicking finger or the click has
# no hover.
static func _hover_err(ray: String, p: Dictionary, target: Vector3) -> float:
	if ray != "I" or hover_lift == 0.0:
		return 0.0
	var f := clampf(float(p.get("thumb_f", 0.0)), thumb_lo, thumb_hi)
	var df := clampf(float(p.get("thumb_df", 0.0)), 0.0, 1.0)
	var hpad: Vector3 = ArmModel.hand_transform(p.get("arm", {})) \
		* HandModel.thumb_pad(HandModel.thumb_fk(f - df))
	return (hpad - (target + Vector3(0.0, 0.0, hover_lift))).length()


# The worst keyboard violation (mm) of every non-pressing joint in a pose. Used
# by solve_chain's final elbow nudge: the nudge is a rigid translation of the
# whole hand, so it can close the last fraction of a millimetre of reach by
# pushing the idle fingers through the keyboard. It must not.
static func _clear_violation(ray: String, p: Dictionary,
		base: Dictionary) -> float:
	if clear_w <= 0.0:
		return 0.0
	return _clearance_now(ray, _complete(ray, p, base), clear_z, idle_sink)


# A solver pose only carries the finger it is solving: the idle fingers stay in
# the base pose, and the thumb is the base's unless the thumb is the target.
# clearance() wants a whole pose, so the missing parts are filled in from base.
static func _complete(ray: String, p: Dictionary, base: Dictionary) -> Dictionary:
	var out := p.duplicate(true)
	if not out.has("fingers"):
		out["fingers"] = {}
	for other in HandModel.FINGERS:
		if not out["fingers"].has(other):
			out["fingers"][other] = base["fingers"][other]
	if not out.has("thumb_f"):
		out["thumb_f"] = base.get("thumb_f", 0.0)
	if ray != "I":
		# A finger solve does not touch the thumb: the base's thumb state is
		# carried over whole, whichever kind it is (the legacy f or the four
		# joints), and the tuck may then change it.
		out["thumb_f"] = base.get("thumb_f", 0.0)
		if int(base.get("thumb_dof", 0)) == 4 and base.has("thumb"):
			out["thumb"] = (base["thumb"] as Dictionary).duplicate(true)
			out["thumb_dof"] = 4
		else:
			out.erase("thumb")
			out.erase("thumb_dof")
	return out


# The worst keyboard violation (mm) of a pose against the plane z = zc. Every
# joint of every idle finger counts as its bone point minus its soft-tissue
# radius, and the whole thumb counts when it is not the pressing finger; the
# pressing fingertip is exempt, because it is the one part allowed to touch the
# key.
#
# Public because the click path uses the same rule to lift the whole hand clear
# of the keyboard on the way to a key: a straight joint interpolation can dip an
# idle finger through the face even when both ends are clean, and the lift is
# exactly this number. `rect` is the keyboard's footprint (centre plus half
# size): when given, the rule is the same prism the solver uses, so the path
# lifts the hand only where a key is actually in the way — a finger hanging
# below the bottom row may pass behind the face without touching anything.
static func clearance(ray: String, p: Dictionary, zc: float,
		rect: Rect2 = Rect2(), skin: float = 0.0) -> float:
	var ccx := clear_cx
	var ccy := clear_cy
	var chx := clear_hx
	var chy := clear_hy
	var cs := clear_skin
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		clear_cx = rect.position.x
		clear_cy = rect.position.y
		clear_hx = rect.size.x
		clear_hy = rect.size.y
	else:
		clear_hx = -1.0
	clear_skin = skin
	var v := _clearance_now(ray, p, zc)
	clear_cx = ccx
	clear_cy = ccy
	clear_hx = chx
	clear_hy = chy
	clear_skin = cs
	return v


# clearance() with the footprint already in the static vars: the solver sets
# them once per call, and asking per pose must not reset them.
static func _clearance_now(ray: String, p: Dictionary, zc: float,
		sink: float = 0.0) -> float:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var worst := 0.0
	for other in ["II", "III", "IV", "V"]:
		var angles: Dictionary = p["fingers"][other]
		var pts: PackedVector3Array = HandModel.finger_fk(other, angles)["pts"]
		var radii: Array = HandModel.SKIN_R[other]
		var last := 4
		if other == ray:
			last = 3
		# The skin margin belongs to IDLE fingers only. The target finger is
		# heading for its own key, where the flattened pad is contact, not a
		# crossing (click_clear allows PRESS_TOL there); giving its joints the
		# margin lifted the whole hand during the press and cut the stroke
		# short (V k39: pad reached -69.7 instead of -71.5).
		var skin := 0.0 if other == ray else clear_skin
		var idle := 0.0 if other == ray else sink
		for j in last:
			var w: Vector3 = xf * pts[j]
			worst = maxf(worst, _joint_violation(w.x, w.y, w.z + idle,
				float(radii[j]) + skin, zc))
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var tradii := [11.8, 10.8, 9.6, 6.6]
	var tlast := 3 if ray == "I" else 4
	var tskin := 0.0 if ray == "I" else clear_skin
	var tidle := 0.0 if ray == "I" else sink
	for j in tlast:
		var tw: Vector3 = xf * tpts[j]
		worst = maxf(worst, _joint_violation(tw.x, tw.y, tw.z + tidle,
			float(tradii[j]) + tskin, zc))
	return worst


# How far the skin of an idle finger reaches past its bone capsule. The linear
# blend rounds a bent joint outward (measured up to 1.8 mm at a curled tip on
# the skinned mesh), so a tuck that stops at capsule-minus-zero leaves the skin
# inside the keycap: the ring fingertip sat 1.6 mm into the top-row key on
# V k43. The tuck aims past it, and only the tuck uses this margin — the
# solver's clearance and the path guard keep measuring bones, as before.
const TUCK_MARGIN := 2.0

# ---- same-hand capsule separation -------------------------------------
# The keyboard is not the only thing a hand can cross: two fingers of the same
# hand must not pass through each other either (the author, 01.11.2026: "при
# любой анимации касаний, а тем более пересечений рук и пальцев быть не
# должно"). The measure is the one intersect_test.gd uses — a capsule per bone
# with the skin's own radii, the segment-to-segment distance (Ericson,
# Real-Time Collision Detection 5.1.9), and the same pair rules: adjacent
# fingers are checked from the PIP outward (their proximal segments share the
# web), non-adjacent fingers in full, the thumb against every finger in full.
# A pair at exactly zero is CONTACT; only penetration counts.
const PAIR_TOL := 0.1           # mm of penetration that counts as a crossing
# The tuck may spread the idle finger sideways as well as straighten it. The
# fan is the MCP's abduction, and the author's hierarchy makes it the cheapest
# answer after the finger itself — much cheaper than 30 degrees of flexion.
# Without it, uncurling the index (fan -8, at its stop) swings its extended
# phalanges INTO the pressing middle finger: the two distal segments sat
# 3.0 mm inside each other on L "3" (measured 01.11.2026).
const TUCK_FAN := 12.0          # degrees each way
const TUCK_FAN_STEPS := 16      # 1.5 degree steps

# THE CROSSING IS PART OF THE SOLVE, NOT ONLY OF THE TUCK. The tuck can only
# move one idle part at a time by its own joints, and the two answers it has —
# straighten, or spread sideways — both swing the part THROUGH its neighbour
# when the neighbour is the thing in the way: on L "3" the thumb had to rise
# 1.6 mm off the space bar and the only flexion that did it drove it 0.6 mm
# into the index (measured 01.11.2026). A real hand does not solve that with
# the thumb; it raises the palm. So the pair penetration is a residual of the
# chain, exactly like the keyboard clearance: the same capsules, the same pair
# rules as intersect_test.gd, one row per pair so that two crossings are two
# gradients. The weight is far above the reach's 3 per millimetre on purpose —
# a pose that reaches by passing through a finger is not a pose.
const PAIR_W := 100.0           # residual per mm of crossing, sqrt-weighted


# Shortest distance between two segments, the geometric core of every capsule
# pair. Same code as the test's _seg_dist, so the two cannot disagree.
#
# The closed form is written out instead of calling _seg_pts (author, #9): the
# pair guard asks for a distance ninety times per residual evaluation, and
# _seg_pts builds a three-element Array every time. Measured on one residual:
# the pairs were 100 of 176 us, most of it that allocation.
static func _seg_dist(p1: Vector3, q1: Vector3, p2: Vector3,
		q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	elif e <= 1e-12:
		s = clampf(-d1.dot(r) / a, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		var b := d1.dot(d2)
		var denom := a * e - b * b
		if absf(denom) > 1e-12:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


# The closest points of two segments, plus their parameters: [distance, s, t]
# with the point on the first at p1 + (q1-p1)*s. The parameters are what lets
# a capsule's radius taper from one joint to the next (see _thumb_foreign).
static func _seg_pts(p1: Vector3, q1: Vector3, p2: Vector3,
		q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return [r.length(), 0.0, 0.0]
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	elif e <= 1e-12:
		s = clampf(-d1.dot(r) / a, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		var b := d1.dot(d2)
		var denom := a * e - b * b
		if absf(denom) > 1e-12:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	return [((p1 + d1 * s) - (p2 + d2 * t)).length(), s, t]


static func _adjacent_rays(a: String, b: String) -> bool:
	var ia := HandModel.FINGERS.find(a)
	var ib := HandModel.FINGERS.find(b)
	return ia >= 0 and ib >= 0 and absi(ia - ib) == 1


# The worst capsule penetration between two fingers of one hand, mm.
static func _pair_pen(xf: Transform3D, ray: String, a: Dictionary,
		other: String, b: Dictionary) -> float:
	return _pair_pen_pts(xf, ray, HandModel.finger_fk(ray, a)["pts"],
		other, HandModel.finger_fk(other, b)["pts"])


# The same measure on chains that are already in hand (see _fk_of).
static func _pair_pen_pts(xf: Transform3D, ray: String, pa: PackedVector3Array,
		other: String, pb: PackedVector3Array) -> float:
	var ra: Array = HandModel.SKIN_R[ray]
	var rb: Array = HandModel.SKIN_R[other]
	var first := 1 if _adjacent_rays(ray, other) else 0
	var worst := 0.0
	for i in range(first, 3):
		for j in range(first, 3):
			var d := _seg_dist(xf * pa[i], xf * pa[i + 1],
				xf * pb[j], xf * pb[j + 1])
			var pen := maxf(float(ra[i]), float(ra[i + 1])) \
				+ maxf(float(rb[j]), float(rb[j + 1])) - d
			worst = maxf(worst, pen)
	return worst


# The worst capsule penetration between the thumb and one finger, mm.
static func _thumb_pair_pen(xf: Transform3D, tfk: Dictionary,
		ray: String, a: Dictionary) -> float:
	return _thumb_pair_pen_pts(xf, tfk["pts"], ray,
		HandModel.finger_fk(ray, a)["pts"])


static func _thumb_pair_pen_pts(xf: Transform3D, tp: PackedVector3Array,
		ray: String, pa: PackedVector3Array) -> float:
	var tr := [11.8, 10.8, 9.6, 6.6]
	var ra: Array = HandModel.SKIN_R[ray]
	var worst := 0.0
	for i in 3:
		for j in 3:
			var d := _seg_dist(xf * tp[i], xf * tp[i + 1],
				xf * pa[j], xf * pa[j + 1])
			var pen := maxf(float(tr[i]), float(tr[i + 1])) \
				+ maxf(float(ra[j]), float(ra[j + 1])) - d
			worst = maxf(worst, pen)
	return worst


# The worst pair penetration of one finger against the rest of its hand.
static func _finger_pairs(xf: Transform3D, ray: String, a: Dictionary,
		fingers: Dictionary, tfk: Dictionary) -> float:
	var worst := 0.0
	for other in HandModel.FINGERS:
		if other == ray:
			continue
		worst = maxf(worst, _pair_pen(xf, ray, a, other, fingers[other]))
	worst = maxf(worst, _thumb_pair_pen(xf, tfk, ray, a))
	return worst


# The worst pair penetration of a thumb pose against all four fingers.
static func _thumb_pairs(xf: Transform3D, tfk: Dictionary,
		fingers: Dictionary) -> float:
	var worst := 0.0
	for ray in HandModel.FINGERS:
		worst = maxf(worst, _thumb_pair_pen(xf, tfk, ray, fingers[ray]))
	return worst


# THE OTHER HAND IS AN OBSTACLE TOO. The two hands share one board and their
# thumbs come within 16.5 mm of flesh at home; a press that shifts the palm
# 30 mm inboard carries the thumb with it, and on L "и" / L Alt the left
# thumb ended up 4.4 / 14.5 mm inside the right one's knuckle (measured
# 01.11.2026). The solver cannot see that on its own: it models ONE hand. So
# the caller — the scene is the only place that has both — hands over the
# other hand's capsules ALREADY MIRRORED INTO THIS HAND'S FRAME (the same
# frame as `target`, see set_foreign), and the thumb treats them like any
# other thing it must not be inside. The arm is deliberately not a residual
# here: the thumb can answer by itself (adduction plus a curl of the MCP),
# and the arm answering instead would drag the whole hand off its key.
const FOREIGN_TOL := 0.1        # mm of allowed touch, the pair rule's own
static var dbg := false
static var foreign_a := PackedVector3Array()
static var foreign_b := PackedVector3Array()
static var foreign_r := PackedFloat32Array()
# THE CAPSULE TAPERS. A bone's radius runs from one joint's skin radius to the
# next one's, not the larger of the two: a thumb's distal phalanx is 9.6 mm at
# the DIP and 6.6 at the tip, and the two resting thumbs converge tip-to-tip.
# Measured with the max radius, the SS50h home pose read 0.92 mm of penetration
# (03.11.2026) and the press of any other key tucked the resting thumb 13.58 mm
# off the bar — a pose jump caused by a collision the flesh does not have (the
# same bones, tapered, are 5.08 mm apart). The radii travel with the capsule;
# `r` stays for callers that only know one number.
static var foreign_ra := PackedFloat32Array()
static var foreign_rb := PackedFloat32Array()


# `caps`: [{a: Vector3, b: Vector3, r: float, ra: float, rb: float}, ...] in
# this hand's model frame. `ra`/`rb` default to `r`. Returns the previous set
# so a caller can put it back.
static func set_foreign(caps) -> Array:
	var old := [foreign_a, foreign_b, foreign_r, foreign_ra, foreign_rb]
	foreign_a = PackedVector3Array()
	foreign_b = PackedVector3Array()
	foreign_r = PackedFloat32Array()
	foreign_ra = PackedFloat32Array()
	foreign_rb = PackedFloat32Array()
	if caps is Array:
		for c in caps:
			var cap: Dictionary = c
			var rr := float(cap["r"])
			foreign_a.append(cap["a"])
			foreign_b.append(cap["b"])
			foreign_r.append(rr)
			foreign_ra.append(float(cap.get("ra", rr)))
			foreign_rb.append(float(cap.get("rb", rr)))
	return old


static func restore_foreign(old: Array) -> void:
	foreign_a = old[0]
	foreign_b = old[1]
	foreign_r = old[2]
	foreign_ra = old[3]
	foreign_rb = old[4]


# The worst capsule penetration between this hand's thumb and the other hand,
# mm. Zero when no other hand was given.
#
# THE WHOLE CLICK COUNTS, NOT JUST THE PRESS. A finger's hover is the press pose
# lifted straight up by the hover height (the viewer's and the test's rule), so
# the thumb travels with it — and on L Alt the press cleared the other thumb by
# 0.09 mm while the hover drove the same thumb 0.72 mm into it (measured
# 01.11.2026). A tuck that only answers for the press leaves the crossing to the
# one part of the click nobody solves. `thumb_lift` is how much higher the same
# pose will be at the hover, and the tuck must be clear at both heights.
static var thumb_lift := 0.0
static func _thumb_foreign(xf: Transform3D, tfk: Dictionary) -> float:
	var n := foreign_a.size()
	if n == 0:
		return 0.0
	var pts: PackedVector3Array = tfk["pts"]
	var rad := [11.8, 10.8, 9.6, 6.6]
	var worst := 0.0
	var lifts := [0.0]
	if thumb_lift > 0.0:
		lifts.append(thumb_lift)
	for dz in lifts:
		var up := Vector3(0.0, 0.0, float(dz))
		for i in 3:
			var p := (xf * pts[i]) + up
			var q := (xf * pts[i + 1]) + up
			for k in n:
				var c := _seg_pts(p, q, foreign_a[k], foreign_b[k])
				var s := float(c[1])
				var t := float(c[2])
				var rr := lerpf(float(rad[i]), float(rad[i + 1]), s) \
					+ lerpf(foreign_ra[k], foreign_rb[k], t)
				worst = maxf(worst, rr - float(c[0]))
	return worst


# The thumb's three obstacles at once, so the tuck compares like with like.
static func _thumb_eval(xf: Transform3D, a, fingers: Dictionary) -> Dictionary:
	var fk: Dictionary = HandModel.thumb_fk(a)
	return {"v": _thumb_violation(xf, a), "p": _thumb_pairs(xf, fk, fingers),
		"f": _thumb_foreign(xf, fk)}


# The tuck's rule in one place: clear the keyboard, the hand's own pairs and the
# other hand, and among clear candidates take the smallest move. `ab` is the
# squared distance travelled in share space, so joints with a wide range are
# the cheap ones to move — the same convention the chain's own priors use.
#
# THE RULE IS A SUM, NOT A LEXICOGRAPHIC ORDER, and that is the whole point.
# Ordering "keyboard, then own pairs, then the other hand" cannot walk THROUGH
# a violated pose: on L Alt the only way out of the other hand's thumb is to
# uncurl the CMC while curling the MCP, and the first half of that move crosses
# its own index by 2 mm. The ordered rule rejected every such candidate (the
# pose it started from had p = 0), so the descent sat still with the thumb
# 5.3 mm inside the other hand while a clear pose existed 30 mm away (measured
# 01.11.2026). A sum of squared violations lets the search pay a temporary
# 2 mm on one pair to collect 5 mm on another; the weights keep the order that
# matters — a millimetre through the keyboard is worth a hundred through flesh
# — and any clear pose costs only `ab`, so the smallest clear move still wins.
# A violation inside its own tolerance is free: the pair rule's 0.1 mm and the
# other hand's 0.1 mm are contact, not a crossing, and charging for them made
# the thumb chase float dust.
const THUMB_W_KEY := 1.0e6     # per mm² of keyboard violation
const THUMB_W_PAIR := 1.0e4    # per mm² of own-pair penetration
const THUMB_W_FOREIGN := 1.0e4 # per mm² of penetration into the other hand
static func _thumb_clear_cost(e: Dictionary, ab: float) -> float:
	var v := maxf(0.0, float(e["v"]))
	var p := maxf(0.0, float(e["p"]) - PAIR_TOL)
	var f := maxf(0.0, float(e["f"]) - FOREIGN_TOL)
	return THUMB_W_KEY * v * v + THUMB_W_PAIR * p * p \
		+ THUMB_W_FOREIGN * f * f + ab


static func _thumb_better(e: Dictionary, ab: float, best: Dictionary,
		best_ab: float) -> bool:
	return _thumb_clear_cost(e, ab) < _thumb_clear_cost(best, best_ab) - 1e-9


# Every pair of the hand as one-sided residuals, appended to `out`: a pair that
# touches is contact, a pair that crosses is an error. The pose is PARTIAL — it
# carries the finger being solved and the thumb only when the thumb is the
# target — so the missing parts come from the base, the same rule
# _chain_res's clearance uses. The measure and the pair rules are
# intersect_test.gd's own, so the solver and the test cannot disagree about
# what a crossing is.
static func _pair_residuals(xf: Transform3D, p: Dictionary,
		base: Dictionary, out: Array, fks: Dictionary = {}) -> float:
	var f := {}
	for r in HandModel.FINGERS:
		f[r] = p["fingers"][r] if p["fingers"].has(r) else base["fingers"][r]
	var tfk: Dictionary = _fk_of(fks, "I",
		HandModel.thumb_of_pose(p) if p.has("thumb") else HandModel.thumb_of_pose(base))
	var w := sqrt(pair_w)
	var worst := 0.0
	var n: int = HandModel.FINGERS.size()
	for i in n:
		var a: String = HandModel.FINGERS[i]
		var pa: PackedVector3Array = _fk_of(fks, a, f[a])["pts"]
		var tv := _thumb_pair_pen_pts(xf, tfk["pts"], a, pa)
		worst = maxf(worst, tv)
		out.append(w * maxf(0.0, tv - PAIR_TOL))
		for j in range(i + 1, n):
			var b: String = HandModel.FINGERS[j]
			var fv := _pair_pen_pts(xf, a, pa, b, _fk_of(fks, b, f[b])["pts"])
			worst = maxf(worst, fv)
			out.append(w * maxf(0.0, fv - PAIR_TOL))
	return worst


# The worst keyboard violation of one finger's joints, in millimetres.
static func _finger_violation(xf: Transform3D, ray: String,
		angles: Dictionary, margin: float = 0.0) -> float:
	var pts: PackedVector3Array = HandModel.finger_fk(ray, angles)["pts"]
	var radii: Array = HandModel.SKIN_R[ray]
	var worst := 0.0
	for j in 4:
		var w: Vector3 = xf * pts[j]
		worst = maxf(worst, _joint_violation(w.x, w.y, w.z,
			float(radii[j]) + margin, clear_z))
	return worst


# Curl the idle fingers until they are in front of the keyboard. The target
# finger is the one the solve was for and is left exactly as solved. The curl
# is a uniform increase of the three flexion shares, the same "all joints give
# the same share" rule the thumb and the IK energy use — not an arbitrary
# fold of one joint. This is what a real hand does when one finger reaches a
# far key: the others tuck in instead of hanging through the keyboard.
static func _tuck_others(ray: String, p: Dictionary,
		margin: float = 0.0, with_thumb: bool = true) -> void:
	if clear_w <= 0.0:
		return
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var fingers: Dictionary = p["fingers"]
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	for other in ["II", "III", "IV", "V"]:
		if other == ray:
			continue
		var angles: Dictionary = fingers[other]
		# A pad resting ON its key is contact, not a crossing: the home pose
		# lays all four idle pads within 0.05 mm of the face, and without the
		# dead zone every press triggered a full TUCK_MARGIN curl of all of
		# them — which folded the idle fingers into their neighbours (42 of 58
		# cases crossed II_1/III_1 or I/II_0, measured 01.11.2026). The same
		# skip must also ask about the NEIGHBOURS: a finger can be well above
		# the keyboard and still be inside its neighbour, and that is the pair
		# the tuck has to answer.
		if _finger_violation(xf, other, angles, 0.0) <= idle_sink \
				and _finger_pairs(xf, other, angles, fingers, tfk) <= PAIR_TOL:
			continue
		var s := shares_of(other, angles)
		var top := maxf(float(s[0]), maxf(float(s[1]), float(s[2])))
		var hi := maxf(0.0, 1.0 - top)
		var fan0 := float(angles["fan"])
		var rom: Array = HandModel.ROM[other]["fan"]
		var v0 := _finger_violation(xf, other, angles, margin)
		var p0 := _finger_pairs(xf, other, angles, fingers, tfk)
		# The smallest change that leaves the keycap, not the largest one that
		# fits: a finger beside a key often has to RELAX (straighten) rather
		# than curl, because folding it swings the tip behind the plane and
		# deeper into the prism (V k43: a full curl measured 3.6 mm inside,
		# while a 10% uncurl cleared it). Candidates that clear are preferred
		# over ones that merely improve, and among them the smallest change;
		# if nothing clears, the least bad pose wins.
		#
		# THE SIDEWAYS SPREAD IS PART OF THE ANSWER. Straightening an idle
		# finger is what lifts its pad off the key, but a finger fanned toward
		# its neighbour (the index at -8 degrees is at its stop on the home
		# row) swings its extended phalanges THROUGH that neighbour: on L "3"
		# the tuck straightened the index into the pressing middle finger by
		# 3.0 mm (measured 01.11.2026). The same scan therefore also tries the
		# MCP's abduction, and a candidate that keeps the fingers apart wins
		# over one that is a degree closer to the old pose. The change is
		# measured in DEGREES, not shares: 3 degrees of fan is a far smaller
		# move than 0.3 of a share (about 20 degrees of flexion).
		var best := angles
		var best_v := v0
		var best_pen := p0
		var best_ang := 0.0
		var best_clear := v0 <= 0.0
		var best_pair := p0 <= PAIR_TOL
		for it in 33:
			var add := -1.0 + (1.0 + hi) * float(it) / 32.0
			if add > hi:
				add = hi
			var a := _curled(other, s, add)
			for fi in TUCK_FAN_STEPS + 1:
				var df := -TUCK_FAN + 2.0 * TUCK_FAN \
					* float(fi) / float(TUCK_FAN_STEPS)
				var af := a.duplicate()
				af["fan"] = clampf(fan0 + df, float(rom[0]), float(rom[1]))
				var v := _finger_violation(xf, other, af, margin)
				var clear := v <= 0.0
				var pen := 0.0
				if clear:
					pen = _finger_pairs(xf, other, af, fingers, tfk)
				var pair := pen <= PAIR_TOL
				var ang := absf(float(af["mcp"]) - float(angles["mcp"])) \
					+ absf(float(af["pip"]) - float(angles["pip"])) \
					+ absf(float(af["dip"]) - float(angles["dip"])) \
					+ absf(float(af["fan"]) - fan0)
				var better := false
				if clear != best_clear:
					better = clear
				elif clear:
					if pair != best_pair:
						better = pair
					elif pair:
						better = ang < best_ang - 0.001
					else:
						better = pen < best_pen - 0.01 \
							or (pen <= best_pen + 0.01 and ang < best_ang - 0.001)
				else:
					better = v < best_v - 0.01 \
						or (v <= best_v + 0.01 and ang < best_ang - 0.001)
				if better:
					best = af
					best_v = v
					best_pen = pen
					best_ang = ang
					best_clear = clear
					best_pair = pair
		fingers[other] = best
	if ray != "I" and with_thumb:
		_tuck_thumb(p)


# The idle finger with every flexion share raised by the same amount.
static func _curled(ray: String, s: Array, add: float) -> Dictionary:
	return angles_of_shares(ray, [
		clampf(float(s[0]) + add, -1.0, 1.0),
		clampf(float(s[1]) + add, -1.0, 1.0),
		clampf(float(s[2]) + add, -1.0, 1.0),
		float(s[3])])


# The thumb's tuck is the same rule as the fingers': the smallest change of
# its own joints that brings the whole tube in front of the keyboard. For the
# old one-coordinate thumb that is a scan of f; for the four joints it is a
# short coordinate descent over their shares. The target thumb is never
# tucked — it is the pressing part.
static func _tuck_thumb(p: Dictionary) -> void:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var cur := HandModel.thumb_of_pose(p)
	if _thumb_violation(xf, cur) <= idle_sink \
			and _thumb_pairs(xf, HandModel.thumb_fk(cur), p["fingers"]) <= PAIR_TOL \
			and _thumb_foreign(xf, HandModel.thumb_fk(cur)) <= FOREIGN_TOL:
		return
	var hold: Dictionary = p.get("thumb_hold", {})
	# The kind of thumb lives in the POSE, not in the global. solve_chain's
	# final margin pass runs after _solve_once has restored the statics, so the
	# global is back to 1 there; keying off it turned a solved five-joint thumb
	# into the legacy arc — and the arc has no `twist`, so the held opposition
	# was silently dropped on every click (01.11.2026: the thumbs collided by
	# 20 mm mid-press while the home pose itself was clean).
	if int(p.get("thumb_dof", 0)) != 4 or not p.has("thumb"):
		var f := float(p.get("thumb_f", 0.0))
		var best := f
		var best_d := 2.0
		for i in 41:
			var fv := -1.0 + 2.0 * float(i) / 40.0
			if _thumb_violation(xf, fv) <= 0.0:
				var d := absf(fv - f)
				if d < best_d:
					best_d = d
					best = fv
		p["thumb_f"] = best
		p["thumb"] = HandModel.thumb_at(best)
		return
	# THE LIFT IS AN EXTENSION, ONE SHARE FOR ALL THE FREE FLEXION JOINTS — the
	# same rule the idle fingers follow. The old scan walked every joint over a
	# coarse nine-point grid and accepted any candidate that lowered the
	# violation at all, so a two-millimetre lift drove the thumb to its stops:
	# R "6" went from cmc_abd -24.7 to +30 and mcp 42 to -4, and the thumb
	# swept across the centre line into the other hand (22.4 mm, 01.11.2026).
	# A hand lifting its thumb off the space bar straightens it; it does not
	# re-oppose it. cmc_abd and twist are the posture and never move here: they
	# are what keeps the thumb clear of its neighbours in the first place.
	# THE MOVE IS FOUND JOINT BY JOINT, NOT AS ONE SHARE FOR ALL. The old scan
	# raised every free flexion joint by the same amount, which is the right
	# shape for a lift off the keyboard — a hand straightening a finger — but
	# the wrong one for getting out of the other hand's way: on L Alt the
	# answer is "adduct the CMC to its stop and curl the MCP 21°", two joints
	# moving by very different amounts (measured 01.11.2026). A coordinate
	# descent over the shares finds it, and _thumb_better keeps the smallest
	# move that is actually clear.
	#
	# cmc_abd USED TO BE FROZEN HERE, and is not any more. It was frozen
	# because free abduction was the cheapest way off the keyboard and it
	# drove the thumb across the centre line into the other hand (22.4 mm on
	# R "6", 01.11.2026) — the other hand was invisible to the tuck. Now it is
	# visible, so abduction into it is rejected like any other crossing, and
	# ADDUCTION is exactly what a hand does when its palm comes over. The
	# twist stays a posture: it is the plane the distal phalanges fold in, and
	# nothing here needs to turn that plane.
	var free := []
	for j in ["cmc_flex", "cmc_abd", "mcp", "ip"]:
		if not hold.has(j):
			free.append(HandModel.THUMB_JOINTS.find(j))
	var q0 := thumb_shares_of(cur, hold)
	var best_sh := q0.duplicate()
	var best_e := _thumb_eval(xf, cur, p["fingers"])
	var best_ab := 0.0
	var step := 0.25
	if dbg:
		print("TUCK start %s v %.2f p %.2f f %.2f free %s" % [
			str(thumb_angles_of_shares(q0, hold)), float(best_e["v"]),
			float(best_e["p"]), float(best_e["f"]), str(free)])
	for pass_i in 5:
		var guard := 0
		var moved := true
		while moved and guard < 8:
			moved = false
			guard += 1
			for i in free:
				for dir in [-1.0, 1.0]:
					var cand := best_sh.duplicate()
					cand[i] = clampf(float(best_sh[i]) + dir * step, -1.0, 1.0)
					if absf(float(cand[i]) - float(best_sh[i])) < 1e-9:
						continue
					var a := thumb_angles_of_shares(cand, hold)
					var e := _thumb_eval(xf, a, p["fingers"])
					var ab := 0.0
					for k in free:
						var d := float(cand[k]) - float(q0[k])
						ab += d * d
					if dbg:
						print("  try %d %+.3f step %.3f f %.2f v %.2f p %.2f ab %.3f cost %.1f vs %.1f -> %s" % [
							i, dir, step, float(e["f"]), float(e["v"]),
							float(e["p"]), ab, _thumb_clear_cost(e, ab),
							_thumb_clear_cost(best_e, best_ab),
							"TAKE" if _thumb_better(e, ab, best_e,
								best_ab) else "no"])
					if _thumb_better(e, ab, best_e, best_ab):
						best_sh = cand
						best_e = e
						best_ab = ab
						moved = true
		step *= 0.5
	p["thumb"] = thumb_angles_of_shares(best_sh, hold)
	p["thumb_dof"] = 4


# ---- the arm yields to the other hand -----------------------------------
# The tuck can only move the thumb, and on L Alt the thumb has nowhere to go:
# with the hand where the pinky's press put it, every pose of the thumb that
# clears the other hand goes through the keyboard (the whole cmc_flex x mcp
# grid at cmc_abd -25 has no clean cell, measured 01.11.2026). The freedom is
# one level up: the hand itself may move a little, as long as the pressing pad
# stays on its key. The scan (probe_yield2) shows that six more degrees of
# ulnar deviation with the elbow put back ten millimetres outboard clears the
# other thumb completely — the same press, held a little differently.
#
# THE PAD IS KEPT BY THE ELBOW, NOT BY THE FINGERS. The elbow's three
# translations move the whole hand rigidly, so a candidate arm pose needs no
# finger solve at all: rotate the arm, measure where the pad went, and put the
# elbow back by exactly that vector. The press stays exact, the finger angles
# stay the ones the press found, and one FK per candidate is the whole cost.
#
# The rule is the tuck's own, one level up: a sum of squared violations (the
# keyboard, the hand's own pairs, the other hand) plus the arm's energy from
# the pose it started in. The energy is what keeps the arm from wandering: it
# is the hierarchy the solver already uses, so a wrist degree is cheap and an
# elbow millimetre is dear, and the cheapest clear hand wins. Only the arm's
# five rotations are searched — the three elbow coordinates are spoken for by
# the pad, which leaves exactly the freedom the press has to spare.
const YIELD_STEP := 4.0        # degrees per pattern step
const YIELD_PASSES := 4
const YIELD_GUARD := 8
static func _yield_cost(p: Dictionary, ray: String, base: Dictionary) -> float:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	var f := maxf(0.0, _thumb_foreign(xf, tfk) - FOREIGN_TOL)
	var v := maxf(0.0, _clearance_now(ray, p, clear_z, TUCK_MARGIN))
	var pw := pair_w
	pair_w = PAIR_W
	var tmp := []
	var pen := maxf(0.0, _pair_residuals(xf, p, base, tmp) - PAIR_TOL)
	pair_w = pw
	var sh := ArmModel.shares_of(p.get("arm", {}))
	var bsh := ArmModel.shares_of(base.get("arm", {}))
	var e := 0.0
	for i in ArmModel.ALL_JOINTS.size():
		var d := clampf(float(sh[i]), -1.0, 1.0) \
			- clampf(float(bsh[i]), -1.0, 1.0)
		e += float(ArmModel.weight_of(ArmModel.ALL_JOINTS[i])) * d * d
		if ArmModel.ALL_JOINTS[i] == "wrist_dev":
			var sc := ArmModel.dev_soft_cost(d)
			e += sc * sc
	return THUMB_W_FOREIGN * f * f + THUMB_W_KEY * v * v \
		+ THUMB_W_PAIR * pen * pen + e


# One candidate: turn one joint of `from` by `d` degrees and put the elbow back
# so the pressing pad stays exactly where `pad0` says. The thumb starts from
# `seed`'s pose every time, so candidates are compared as if from the same
# hand — a tuck found for one arm must not become another's starting point.
static func _yield_try(seed: Dictionary, from: Dictionary, j: String,
		d: float, pad0: Vector3, ray: String) -> Dictionary:
	var rom: Array = ArmModel.ROM[j]
	var a: Dictionary = (from["arm"] as Dictionary).duplicate(true)
	a[j] = clampf(float(a[j]) + d, float(rom[0]), float(rom[1]))
	if absf(float(a[j]) - float(from["arm"][j])) < 1e-9:
		return {}
	var cand: Dictionary = from.duplicate(true)
	cand["arm"] = a
	var xf := ArmModel.hand_transform(a)
	var pad: Vector3 = xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, cand["fingers"][ray]))
	var e := pad0 - pad
	var lim := ArmModel.ELBOW_RANGE
	a["elbow_x"] = clampf(float(a["elbow_x"]) + e.x, -lim, lim)
	a["elbow_y"] = clampf(float(a["elbow_y"]) + e.y, -lim, lim)
	a["elbow_z"] = clampf(float(a["elbow_z"]) + e.z, -lim, lim)
	cand["arm"] = a
	if seed.has("thumb"):
		cand["thumb"] = (seed["thumb"] as Dictionary).duplicate(true)
	cand["thumb_dof"] = int(seed.get("thumb_dof", 0))
	cand["thumb_f"] = float(seed.get("thumb_f", 0.0))
	_tuck_thumb(cand)
	return cand


static func _yield_arm(ray: String, p: Dictionary, base: Dictionary) -> Dictionary:
	var xf0 := ArmModel.hand_transform(p.get("arm", {}))
	var f0 := _thumb_foreign(xf0, HandModel.thumb_fk(
		HandModel.thumb_of_pose(p)))
	if f0 <= FOREIGN_TOL:
		return p
	var pad0 := _chain_pad(ray, p)
	var seed: Dictionary = p.duplicate(true)
	var best: Dictionary = p.duplicate(true)
	var best_c := _yield_cost(best, ray, base)
	var step := YIELD_STEP
	for pass_i in YIELD_PASSES:
		var moved := true
		var guard := 0
		while moved and guard < YIELD_GUARD:
			moved = false
			guard += 1
			for j in ArmModel.JOINTS:
				for dir in [-1.0, 1.0]:
					var cand := _yield_try(seed, best, j, dir * step, pad0,
						ray)
					if cand.is_empty():
						continue
					var c := _yield_cost(cand, ray, base)
					if c < best_c - 1e-9:
						best = cand
						best_c = c
						moved = true
		step *= 0.5
	# A hand that moved but is no better off than before is not an answer.
	var xfb := ArmModel.hand_transform(best.get("arm", {}))
	var fb := _thumb_foreign(xfb, HandModel.thumb_fk(
		HandModel.thumb_of_pose(best)))
	if fb >= f0 - 1e-9:
		return p
	return best


static func _thumb_violation(xf: Transform3D, arg) -> float:
	var pts: PackedVector3Array = HandModel.thumb_fk(arg)["pts"]
	var radii := [11.8, 10.8, 9.6, 6.6]
	var worst := 0.0
	for j in 4:
		var w: Vector3 = xf * pts[j]
		worst = maxf(worst, _joint_violation(w.x, w.y, w.z,
			float(radii[j]), clear_z))
	return worst


static func _chain_jacobian(ray: String, q: Array, target: Vector3,
		free_arm: bool, base: Dictionary) -> Array:
	var base_r: Array = _chain_res(ray, q, target, free_arm, base)["r"]
	var cols := []
	for j in q.size():
		var qq: Array = q.duplicate()
		qq[j] = float(qq[j]) + 0.005
		var rr: Array = _chain_res(ray, qq, target, free_arm, base)["r"]
		var col := []
		for k in base_r.size():
			col.append((float(rr[k]) - float(base_r[k])) / 0.005)
		cols.append(col)
	return cols


# Gaussian elimination with partial pivoting for the chain's 7×7 or 10×10
# normal equations. The old finger solver keeps its 4×4 version above; this
# one is the general form and is used by the hierarchy only.
static func _solve_n(a_in: Array, b_in: Array) -> Array:
	var n := b_in.size()
	var a := []
	for row in a_in:
		a.append((row as Array).duplicate())
	var b := b_in.duplicate()
	for col in n:
		var piv := col
		for row in range(col + 1, n):
			if absf(float(a[row][col])) > absf(float(a[piv][col])):
				piv = row
		if absf(float(a[piv][col])) < 1e-12:
			return []
		if piv != col:
			var t: Array = a[piv]
			a[piv] = a[col]
			a[col] = t
			var tb: float = b[piv]
			b[piv] = b[col]
			b[col] = tb
		var d: float = a[col][col]
		for j in range(col, n):
			a[col][j] = float(a[col][j]) / d
		b[col] = float(b[col]) / d
		for row in n:
			if row == col:
				continue
			var fac: float = a[row][col]
			if is_zero_approx(fac):
				continue
			for j in range(col, n):
				a[row][j] = float(a[row][j]) - fac * float(a[col][j])
			b[row] = float(b[row]) - fac * float(b[col])
	return b


# Optional limits on the thumb's OWN coordinate for one solve (see
# solve_chain). A click needs a press pose the thumb can still flex into, so
# the press is solved with its extension capped instead of letting the thumb
# sit at full stretch and dragging the whole hand to the key.
static var thumb_lo := -1.0
static var thumb_hi := 1.0
# The thumb's solver: 1 keeps the study's one-coordinate arc (the old viewer
# and its probes), 4 gives its four joints the same independent shares as a
# finger's. The board viewer asks for 4; nothing else has to change.
static var thumb_dof := 1
# A joint HELD at a posture angle travels in the POSE (`pose["thumb_hold"]`,
# a joint -> angle dictionary), not in a global: the typing posture fixes the
# thumb's opposition ONCE — a hand does not re-oppose per key — and every
# press of that hand keeps it. A held joint reads the same angle for every
# share, so it costs its posture prior and the solver cannot move it. Absent
# by default: the model is free everywhere. The home scan pins `twist`
# (01.11.2026): left free, the energy rule folds the thumb ACROSS the palm
# (IP lands at world x 0) and the two thumbs collide; held, the opposition
# only turns the fold plane.

# Optional keyboard clearance for a click. When clear_w > 0 the solver is told
# that the keyboard's front face is the plane z = clear_z and that every
# finger EXCEPT the one being solved must stay in front of it. The pads are
# enough: a curled finger's pad is its deepest point, and keeping the pads
# clear keeps the whole non-target hand clear of the keys. This is what stops
# the free-arm solve from parking the palm far enough forward that the other
# fingers stab through the keyboard (measured: the ring finger at z = -126 mm
# while the little finger pressed a far key). Disabled (clear_w = 0) for every
# ordinary drag; only the click sets it.
static var clear_z := -1e9
static var clear_w := 0.0
# The weight of the hand's own pairs (see PAIR_W). Zero turns the guard off;
# solve_chain turns it on for a click, where the tuck used to be the only
# thing that knew about fingers crossing.
static var pair_w := 0.0
# Extra radius the path guard adds to every bone: the skinned surface bulges
# past the capsule by up to 1.9 mm at a bent joint, and the guard models the
# skin, not the bone. The solver keeps clear_skin = 0 — it reasons about the
# bones and the post-solve tuck folds the idle fingers with TUCK_MARGIN.
static var clear_skin := 0.0
# The keyboard is not an infinite wall: it is a slab of keys. A finger below the
# bottom row or left of the left column can go behind the face without touching
# anything, and forbidding that made the far keys unreachable (V k5: the idle
# ring finger hung 14 mm below the keyboard, the plane held the hand back and
# the pad stopped 6.6 mm short). When clear_hx > 0 the plane is clipped to the
# keyboard's footprint — a rectangle in x/y given as centre plus half size — and
# a joint counts only when its soft-tissue sphere reaches the prism
# z < clear_z inside that rectangle.
static var dir_min := -0.5
static var thumb_min := -0.7
# A dead zone for the IDLE parts of the hand, in millimetres. The home pose
# lays the idle pads on the key face, and the pad centre is not exactly the
# sphere's bottom: the rotated local normal puts the world low point a few
# hundredths of a millimetre below the face (measured: II -0.032, III -0.047,
# IV -0.027, V +0.014). With a hard clearance the residual sits exactly on the
# kink max(0, x) and the finite-difference Jacobian there is one-sided: the
# first LM steps are rejected, lambda grows, and the solve crawls into a
# different valley (L «в»: the palm lifted from elbow_z -44 to -19.5, the fan
# spread to both stops, and the neighbouring fingers collapsed into each
# other). The dead zone is the soft tissue's own give: a pad may sink this far
# into the face before the solver pays anything. The TARGET finger and the
# pressing thumb keep the hard rule — they are the parts that must not cross.
static var idle_sink := 0.0
# The default dead zone when the clearance is on. Half a millimetre is the
# pad's own give: the home pose's idle pads sit within 0.05 mm of the face,
# and the skin is soft, so a graze of this size is contact, not a crossing.
const IDLE_SINK := 0.5
static var clear_cx := 0.0
static var clear_cy := 0.0
static var clear_hx := -1.0
static var clear_hy := -1.0


# How far a joint's soft-tissue sphere (radius r) is inside the forbidden
# prism. Zero in front of the face and zero beside the keyboard; exactly
# clear_z - (z - r) over the keys. Continuous everywhere, so a finger can slide
# off the keyboard's edge without a cliff in the cost.
static func _joint_violation(x: float, y: float, z: float, r: float,
		zc: float) -> float:
	if clear_hx < 0.0:
		return maxf(0.0, zc - (z - r))
	var qx := absf(x - clear_cx) - clear_hx
	var qy := absf(y - clear_cy) - clear_hy
	var qz := z - zc
	var ox := maxf(qx, 0.0)
	var oy := maxf(qy, 0.0)
	var oz := maxf(qz, 0.0)
	var sdf := sqrt(ox * ox + oy * oy + oz * oz) \
		+ minf(maxf(qx, maxf(qy, qz)), 0.0)
	return maxf(0.0, r - sdf)

# The press of a key has a DIRECTION as well as a point. A finger that reaches
# the key from the side lies along the keyboard: its distal phalanx crosses the
# face almost horizontally, and its tube sweeps over the neighbouring key (the
# measured II_D over k14, 293 vertices). A finger that presses from above comes
# down on its own key: the distal phalanx is vertical, the pad is the lowest
# point of the tip, and nothing of the finger is over a neighbour. dir_w is the
# weight of "the distal phalanx points at the key" (the two horizontal
# components of the world direction must be zero); it is 0 for every ordinary
# drag, where the target is a free point in the air.
static var dir_w := 0.0

# A click also needs a HOVER pose: the same hand, the same finger, lifted off
# the key along its normal. For the four fingers the hover is a separate solve
# of the pad at target + (0, 0, hover_lift); for the thumb the author's rule is
# that the hand must not sink with the thumb, so the hover is the SAME arm pose
# with the thumb's own coordinate moved by hover_df. hover_lift > 0 asks the
# solver to satisfy BOTH pad targets at once: the press at `target`, the hover
# at `target + (0, 0, hover_lift)` with f - hover_df. That is what makes the
# thumb's own arc vertical instead of sliding sideways across the key plane.
# hover_df is a variable of the solve (bounded 0..1), so the arc length is
# free to match the lift. Disabled (hover_lift = 0) everywhere else.
static var hover_lift := 0.0
static var hover_df := 0.30


static func _project_chain(q: Array, ray: String, free_arm: bool,
		hold: Dictionary = {}) -> Array:
	var out := []
	if ray == "I":
		if thumb_dof == 4:
			for i in HandModel.THUMB_JOINTS.size():
				var j: String = HandModel.THUMB_JOINTS[i]
				if hold.has(j):
					var rom: Array = HandModel.THUMB_ROM[j]
					out.append(clampf(share(float(hold[j]),
						float(HandModel.THUMB_REST[j]), float(rom[0]),
						float(rom[1])), -1.0, 1.0))
				else:
					out.append(clampf(float(q[i]), -1.0, 1.0))
		else:
			out.append(clampf(float(q[0]), thumb_lo, thumb_hi))
			if hover_lift != 0.0:
				out.append(clampf(float(q[1]), 0.0, 1.0))
	else:
		out = project([float(q[0]), float(q[1]), float(q[2]), float(q[3])])
	if free_arm:
		var off := out.size()
		for i in ArmModel.ALL_JOINTS.size():
			out.append(clampf(float(q[off + i]), -1.0, 1.0))
	return out


# Solve the whole chain for one target. `opts["arm"] = false` freezes the arm
# and solves the finger alone (the old behaviour), which the tests use to keep
# the finger's own promises separate from the hierarchy's.
# One LM run from one starting point. Split out of solve_chain because the
# hierarchy tries two starts — the warm one and the analytic arm seed — and
# keeps the cheaper answer.
static func _chain_run(ray: String, target: Vector3, base: Dictionary,
		q0: Array, free_arm: bool, comfort: bool = false) -> Dictionary:
	var q: Array = q0.duplicate()
	# The damping is a fraction of each variable's own curvature (see
	# _normal_equations), so it is dimensionless and small at the start: the
	# first step is nearly Gauss-Newton, which is what lets the CHEAP joint
	# answer first. Damping is only the trust region — it must not decide
	# which joint moves, or a sideways target would be answered by the wrist
	# simply because the fan's column is smaller.
	var lambda := 0.001
	var cur: Dictionary = _chain_res(ray, q, target, free_arm, base)
	var iters := 0
	var trace := []
	var stall := 0
	for it in CHAIN_ITERS:
		iters = it + 1
		var c0 := _cost(cur["r"])
		# A warm start that already reaches is done: the common case is a
		# target near the rest pad, and 90 iterations of prior polishing would
		# only burn frames. A comfort run is the opposite: the seed reaches by
		# construction, and the whole point is to keep going until the priors
		# stop falling.
		#
		# THE GUARD IS PART OF "DONE". The continuation in solve_chain reaches
		# first and refines with the keyboard clearance on; that refine starts
		# with fit = 0, so stopping on reach alone meant the clearance was
		# NEVER optimised — the arm did not move a bit (measured 01.11.2026:
		# the refine pose was bit-identical to the natural press), and the
		# post-solve tuck had to uncurl the idle fingers to clear the board,
		# which folded the index into the pressing middle finger (3.0 mm).
		# With the violation in the test, the arm lifts the idle pads out
		# while the target finger keeps its pad on the key.
		if not comfort and float(cur["fit"]) <= CHAIN_WARM_TOL \
				and float(cur.get("clr", 0.0)) <= CHAIN_CLEAR_TOL \
				and float(cur.get("pen", 0.0)) <= CHAIN_CLEAR_TOL:
			break
		var cols := _chain_jacobian(ray, q, target, free_arm, base)
		var a := _normal_equations(cols, lambda, true)
		var g := _gradient(cols, cur["r"])
		var b := []
		for i in g.size():
			b.append(-float(g[i]))
		var delta := _solve_n(a, b)
		if delta.is_empty():
			trace.append([it, float(cur["fit"]), lambda, -1.0, false])
			break
		var qn := []
		var step_len := 0.0
		for i in q.size():
			var step := clampf(float(delta[i]), -CHAIN_STEP, CHAIN_STEP)
			step_len = maxf(step_len, absf(step))
			qn.append(float(q[i]) + step)
		qn = _project_chain(qn, ray, free_arm, base.get("thumb_hold", {}))
		var next: Dictionary = _chain_res(ray, qn, target, free_arm, base)
		var c1 := _cost(next["r"])
		var accepted := c1 < c0 - 1e-12
		trace.append([it, float(cur["fit"]), lambda, step_len, accepted])
		if accepted:
			q = qn
			cur = next
			lambda = maxf(lambda * 0.3, 1e-9)
			# CONVERGENCE IS A RELATIVE GAIN, NOT A POSE DISTANCE (author, #9).
			# LM's asymptotic tail shaves a thousandth of the cost per step
			# while the step itself is still a visible fraction of a degree, so
			# a step-length test never fires, and a pose-distance test would
			# stop in the middle of a real move. The standard test is the
			# relative cost gain: when six accepted steps in a row buy less
			# than a tenth of a percent, the minimum is where it is. Measured
			# on R «н» (03.11.2026): the guarded refine fell 211676 → 200.6 in
			# 50 iterations and then spent 40 more buying 197.8 (1.4%) — 1.1 s
			# of the 2.5 s one press cost, and that tail is what froze the
			# simulator on fast typing.
			if c0 - c1 <= CHAIN_STALL_GAIN * (1.0 + c0):
				stall += 1
				if stall >= CHAIN_STALL_RUNS:
					break
			else:
				stall = 0
		else:
			lambda *= 10.0
			if lambda > 1e4:
				break
	return {"q": q, "cur": cur, "iters": iters, "trace": trace}


# The active finger's pad in hand-local space (no arm transform), used to guess
# where the wrist must go for the analytic seed.
static func _pad_local(ray: String, p: Dictionary) -> Vector3:
	if ray == "I":
		return HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))


# Curl levels the analytic seed tries. The pad's offset from the wrist depends
# on how far the finger is curled, and that offset decides where the wrist must
# sit: a straight finger puts the wrist a long way behind the target, which for
# a far target is outside the arm's reach and forces the arm to its limits. A
# curled finger pulls the wrist nearer the shoulder — the same reach with the
# arm less extended. So the seed is built for several curls and the cheapest
# full pose (finger + arm) wins. The finger shares travel with the seed, so the
# solver starts in the basin it would settle in instead of fighting its way
# there from a straight finger.
const SEED_CURLS := [0.0, 0.3, 0.6, 0.9]
const SEED_THUMBS := [-1.0, -0.5, 0.0, 0.4, 1.0]
# The full-joint thumb starts from the same idea: a few coordinated states of
# its own joints (rest, a press, a full press), so the analytic seed is built
# for the basin the target needs. The solver still decides the final angles.
# Order: cmc_flex, cmc_abd, twist, mcp, ip. One seed carries the opposition
# turn already open, because a target under the palm needs it and the plain
# seeds sit in the hooked basin (01.11.2026).
const SEED_THUMB_SHARES := [[0.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, -0.3, 0.0, 0.4, 0.4], [0.0, -0.5, 0.0, 0.8, 0.8],
	[0.0, -0.3, 0.6, 0.4, 0.4]]


static func _chain_seed(ray: String, target: Vector3, base: Dictionary) -> Array:
	var levels: Array = SEED_CURLS
	if ray == "I":
		levels = SEED_THUMB_SHARES if thumb_dof == 4 else SEED_THUMBS
	var best := []
	var best_cost := INF
	for c in levels:
		var q := []
		var p := base.duplicate(true)
		if ray == "I":
			if thumb_dof == 4:
				var sh: Array = (c as Array).duplicate()
				q += sh
				p["thumb"] = thumb_angles_of_shares(sh, base.get("thumb_hold", {}))
				p["thumb_dof"] = 4
			else:
				q.append(clampf(float(c), -1.0, 1.0))
				p["thumb_f"] = float(q[0])
				p["thumb"] = HandModel.thumb_at(float(q[0]))
				if hover_lift != 0.0:
					q.append(clampf(hover_df, 0.0, 1.0))
		else:
			var sh := [float(c), float(c), float(c), 0.0]
			q += sh
			p["fingers"][ray] = angles_of_shares(ray, sh)
		var pad_local := _pad_local(ray, p)
		q += ArmModel.shares_of(ArmModel.seed_hand(pad_local, target))
		q = _project_chain(q, ray, true, base.get("thumb_hold", {}))
		var cost := _cost(_chain_res(ray, q, target, true, base)["r"])
		if cost < best_cost:
			best_cost = cost
			best = q
	return best


static func _solve_once(ray: String, target: Vector3, pose: Dictionary,
		opts: Dictionary = {}) -> Dictionary:
	var free_arm := bool(opts.get("arm", true))
	var lo := thumb_lo
	var hi := thumb_hi
	var td := thumb_dof
	var cz := clear_z
	var cw := clear_w
	var pw := pair_w
	var cs := clear_skin
	var ccx := clear_cx
	var ccy := clear_cy
	var chx := clear_hx
	var chy := clear_hy
	var dw := dir_w
	var dm := dir_min
	var tm := thumb_min
	var hl := hover_lift
	var hd := hover_df
	var isk := idle_sink
	var tl := thumb_lift
	var fo := set_foreign(opts.get("foreign", []))
	thumb_lo = clampf(float(opts.get("f_lo", -1.0)), -1.0, 1.0)
	thumb_hi = clampf(float(opts.get("f_hi", 1.0)), -1.0, 1.0)
	thumb_dof = 4 if int(opts.get("thumb_dof", 1)) == 4 else 1
	thumb_lift = float(opts.get("thumb_lift", 0.0))
	clear_z = float(opts.get("clear_z", -1e9))
	clear_w = float(opts.get("clear_w", 0.0))
	pair_w = float(opts.get("pair_w", 0.0))
	clear_skin = float(opts.get("clear_skin", 0.0))
	idle_sink = float(opts.get("idle_sink", IDLE_SINK))
	dir_min = float(opts.get("dir_min", -0.5))
	thumb_min = float(opts.get("thumb_min", -0.7))
	var rect: Rect2 = opts.get("clear_rect", Rect2())
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		clear_cx = rect.position.x
		clear_cy = rect.position.y
		clear_hx = rect.size.x
		clear_hy = rect.size.y
	else:
		# No footprint: the wall is the WHOLE plane (`clear_hx < 0` means
		# "not clipped"). Leaving clear_hx = rect.size.x = 0 made the prism a
		# razor-thin rectangle at the origin, so the clearance term was dead
		# for every caller that passed no clear_rect — which is exactly the
		# click and the viewer. Measured: clear_w 100/1000/10000 gave
		# bit-identical poses while the thumb sat 60 mm under the key face.
		clear_hx = -1.0
	dir_w = float(opts.get("dir_w", 0.0))
	hover_lift = float(opts.get("hover_lift", 0.0))
	hover_df = float(opts.get("hover_df", 0.30))
	var base := pose.duplicate(true)
	var q := []
	if ray == "I":
		if thumb_dof == 4:
			q += thumb_shares_of(HandModel.thumb_of_pose(base),
				base.get("thumb_hold", {}))
		else:
			q.append(clampf(float(base.get("thumb_f", 0.0)), thumb_lo, thumb_hi))
			if hover_lift != 0.0:
				q.append(clampf(hover_df, 0.0, 1.0))
	else:
		q += shares_of(ray, base["fingers"][ray])
	if free_arm:
		q += ArmModel.shares_of(base.get("arm", {}))
	q = _project_chain(q, ray, free_arm, base.get("thumb_hold", {}))

	var run := _chain_run(ray, target, base, q, free_arm)
	# A warm start is normally enough. When it is not (a jumped target, a new
	# finger, the demo's waypoints) the straight-arm singularity can trap it:
	# retry from the analytic two-bone seed and keep the answer that reaches.
	# The seed is only a start — the same cost and the same hierarchy decide
	# the final pose. The seed run is a comfort run: it starts at a pose that
	# already reaches, so it must not stop on reach alone, it must go on until
	# the priors stop falling.
	if free_arm and float(run["cur"]["reach"]) > CHAIN_RETRY:
		var qs := _chain_seed(ray, target, base)
		var run2 := _chain_run(ray, target, base, qs, free_arm, true)
		# Reach first, comfort second. The cost already contains both, but a
		# soft sum can prefer a comfortable pose that misses by a millimetre
		# over a reaching pose that costs a little more. The author's rule is
		# the other way round: a pose that reaches wins, and only among poses
		# that reach does the cheaper one win.
		var r1 := float(run["cur"]["reach"])
		var r2 := float(run2["cur"]["reach"])
		var ok1 := r1 <= CHAIN_RETRY
		var ok2 := r2 <= CHAIN_RETRY
		if ok2 and not ok1:
			run = run2
		elif ok1 and ok2:
			# Both press the key. The hover is what is left to choose on:
			# a pose whose thumb arc runs along the key normal makes the
			# thumb-only hover possible, and that is the author's rule.
			var f1 := float(run["cur"].get("fit", r1))
			var f2 := float(run2["cur"].get("fit", r2))
			if absf(f2 - f1) > 0.01:
				if f2 < f1:
					run = run2
			elif _cost(run2["cur"]["r"]) < _cost(run["cur"]["r"]):
				run = run2
		elif not ok1 and not ok2 and r2 < r1 - 0.05:
			run = run2
	elif not free_arm and float(run["cur"]["reach"]) > CHAIN_RETRY:
		# The same retry with the arm frozen. The finger's own landscape has
		# more than one valley (a curled pose and an extended one can both
		# bring the pad near the target), and the warm start alone can settle
		# in the wrong one: the ring finger stopped 2.4 mm short of its home
		# key from the rest pose, while an extended start reached it to
		# 0.2 mm (31.10.2026). The analytic curls are the same starts the
		# arm solve uses; the arm itself does not move.
		var best_run: Dictionary = run
		# The seeds belong to the RAY, not to the four fingers: the thumb has
		# its own list (and the full-joint thumb one number per joint), and a
		# finger seed fed to it indexes past the array.
		var retry: Array = SEED_CURLS
		if ray == "I":
			retry = SEED_THUMB_SHARES if thumb_dof == 4 else SEED_THUMBS
		for c in retry:
			var seed_q := []
			if ray == "I" and thumb_dof != 4:
				seed_q = [clampf(float(c), -1.0, 1.0)]
			elif ray == "I":
				seed_q = (c as Array).duplicate()
			else:
				seed_q = [float(c), float(c), float(c), 0.0]
			var qs := _project_chain(seed_q, ray, false, base.get("thumb_hold", {}))
			var run2 := _chain_run(ray, target, base, qs, false, true)
			var rr := float(run2["cur"]["reach"])
			var rb := float(best_run["cur"]["reach"])
			if rr < rb - 0.02 or (rr <= rb + 0.02
					and _cost(run2["cur"]["r"]) < _cost(best_run["cur"]["r"])):
				best_run = run2
		run = best_run

	# COMFORT: once a pose REACHES, spend the freedom it has left.
	#
	# The warm run stops the moment the pad touches (CHAIN_WARM_TOL), and the
	# posture terms — the joint prior, the even-load band, the thumb's
	# tangency — are worth so little per millimetre (W_PRIOR 0.05 mm² for a
	# full 100% deviation of a joint) that they never get to spend even a
	# fraction of one. The pose the author sees is therefore whichever
	# reaching pose the warm start happened to stand near, not the cheapest
	# one: that is why the same key struck twice could come out in two
	# different shapes (author, #5) and why the thumb's posture read as a
	# corkscrew (author, #6: "выясни, как у тебя работает минимизация затрат
	# энергии").
	#
	# So after the reach has settled, run the SAME cost to its own minimum —
	# the same residual, the same LM, the same hierarchy — and keep that
	# answer only if it still reaches. The author's order is preserved: a
	# pose that reaches wins, and only among poses that reach does the
	# cheaper one win. A finger with four joints on a three-number target has
	# exactly one degree left, so the polish moves it along that freedom and
	# the pad does not leave the key; the tolerance is there for the thumb,
	# whose three free joints have none.
	if bool(opts.get("comfort", comfort_default)):
		var r0 := float(run["cur"]["reach"])
		if r0 <= CHAIN_RETRY:
			var pol := _chain_run(ray, target, base, run["q"], free_arm, true)
			if float(pol["cur"]["reach"]) <= r0 + 0.05 \
					and _cost(pol["cur"]["r"]) < _cost(run["cur"]["r"]) - 1e-9:
				run = pol

	var cur: Dictionary = run["cur"]
	# The elbow is a translation of the whole arm: moving it by one millimetre
	# moves the pad by exactly one millimetre, whatever the joints above are
	# doing. So the last fraction of a millimetre is not a solver problem —
	# the last resort closes it exactly. This is the author's rule
	# (29.10.2026) taken literally: the joints answer while they can, and the
	# elbow carries whatever is left. Without it the soft cost stops a fraction
	# short (the elbow's own prior buys the last tenth of a millimetre), and a
	# target at the edge of the joint stops reads as unreachable when one rigid
	# nudge would land it. The clamp is the honest limit: past it the target is
	# outside the arm's reach and the residual says so.
	# `nudge: false` is a diagnostic switch, not a behaviour: it reports the
	# pose the joints alone reach, without the elbow's exact closing nudge.
	# The viewer and the game always take the nudge; a probe needs to see how
	# much of the move the joints actually did and how much the elbow carried.
	if free_arm and bool(opts.get("nudge", true)):
		var pa: Dictionary = cur["pose"]["arm"]
		var old := Vector3(float(pa["elbow_x"]), float(pa["elbow_y"]),
			float(pa["elbow_z"]))
		var e: Vector3 = target - cur["pad"]
		var lim := ArmModel.ELBOW_RANGE
		var nw := Vector3(clampf(old.x + e.x, -lim, lim),
			clampf(old.y + e.y, -lim, lim), clampf(old.z + e.z, -lim, lim))
		if clear_w > 0.0 and nw != old:
			# The nudge may not push the non-target fingers through the
			# keyboard. First try the full nudge; if it costs clearance, keep
			# the lateral part and leave the depth alone; if even that fails,
			# leave the elbow where the solver put it and report the residual.
			var before := _clear_violation(ray, cur["pose"], base)
			var cand := nw
			var took := false
			for attempt in 2:
				pa["elbow_x"] = cand.x
				pa["elbow_y"] = cand.y
				pa["elbow_z"] = cand.z
				if _clear_violation(ray, cur["pose"], base) <= before + 1e-6:
					nw = cand
					took = true
					break
				cand = Vector3(nw.x, nw.y, old.z)
			if not took:
				pa["elbow_x"] = old.x
				pa["elbow_y"] = old.y
				pa["elbow_z"] = old.z
				nw = old
		elif nw != old:
			pa["elbow_x"] = nw.x
			pa["elbow_y"] = nw.y
			pa["elbow_z"] = nw.z
		if nw != old:
			cur["pad"] = (cur["pad"] as Vector3) + (nw - old)
			cur["reach"] = (target - (cur["pad"] as Vector3)).length()
			cur["fit"] = float(cur["reach"]) \
				+ _hover_err(ray, cur["pose"], target)
	var iters: int = int(run["iters"])
	var trace: Array = run["trace"]

	var p: Dictionary = cur["pose"]
	var arm_angles: Dictionary = (p["arm"] as Dictionary).duplicate(true)
	var arm_shares := ArmModel.shares_of(arm_angles)
	var arm_levels := ArmModel.levels(arm_angles)
	var out := base.duplicate(true)
	if ray == "I":
		if thumb_dof == 4:
			out["thumb"] = (p["thumb"] as Dictionary).duplicate(true)
			out["thumb_f"] = 0.0
			out["thumb_dof"] = 4
		else:
			out["thumb_f"] = float(p["thumb_f"])
			out["thumb"] = HandModel.thumb_at(float(p["thumb_f"]))
			out.erase("thumb_dof")
			if hover_lift != 0.0:
				# The hover is the same arm with the thumb moved back by this
				# much; the caller needs it to build the hover pose.
				out["thumb_df"] = float(p.get("thumb_df", 0.0))
	else:
		out["fingers"][ray] = (p["fingers"][ray] as Dictionary).duplicate(true)
	out["arm"] = arm_angles
	# The idle fingers tuck in so the palm can come as close as the target
	# finger needs without any of them hanging through the keyboard. A HOME
	# pose is the opposite job: every finger has its own target and none may
	# be moved behind another's back, so the caller can switch the tuck off.
	if bool(opts.get("tuck", true)):
		_tuck_others(ray, out)

	var s: Array = cur["shares"]
	var energy := 0.0
	var spread := 0.0
	var fan_share := float(cur["fan_share"])
	var levels := arm_levels.duplicate(true)
	var chain_energy := 0.0
	if ray == "I":
		if thumb_dof == 4:
			for v in s:
				energy += float(v) * float(v)
			var mx := 0.0
			for v in s:
				mx = maxf(mx, absf(float(v)))
				chain_energy += W_PRIOR * float(v) * float(v)
			levels["thumb"] = mx * 100.0
		else:
			var f := float(cur["thumb_f"])
			energy = f * f
			levels["thumb"] = absf(f) * 100.0
			chain_energy += W_THUMB_PRIOR * f * f
	else:
		for v in s:
			energy += float(v) * float(v)
		spread = maxf(float(s[0]), maxf(float(s[1]), float(s[2]))) \
			- minf(float(s[0]), minf(float(s[1]), float(s[2])))
		levels["finger"] = maxf(absf(float(s[0])), maxf(absf(float(s[1])),
			absf(float(s[2])))) * 100.0
		levels["fan"] = absf(fan_share) * 100.0
		for v in s:
			chain_energy += W_PRIOR * float(v) * float(v)
		chain_energy += W_FAN_CHAIN * fan_share * fan_share
	for i in ArmModel.ALL_JOINTS.size():
		var j: String = ArmModel.ALL_JOINTS[i]
		chain_energy += float(ArmModel.weight_of(j)) * float(arm_shares[i]) * float(arm_shares[i])

	var at_rom := {}
	if ray != "I":
		for i in 3:
			at_rom[JOINTS[i]] = absf(float(s[i])) >= 0.999
	for i in ArmModel.ALL_JOINTS.size():
		at_rom[ArmModel.ALL_JOINTS[i]] = absf(float(arm_shares[i])) >= 0.999

	var result := {
		"pose": out, "pad": cur["pad"], "error": float(cur["reach"]),
		"energy": energy, "chain_energy": chain_energy,
		"shares": s, "fan_share": fan_share, "spread": spread,
		"stagger": maxf(0.0, spread - BAND), "iterations": iters,
		"arm": arm_angles, "arm_shares": arm_shares, "arm_levels": arm_levels,
		"levels": levels, "at_rom": at_rom, "trace": trace,
	}
	if ray == "I":
		if thumb_dof == 4:
			result["thumb_f"] = 0.0
			result["thumb"] = (out["thumb"] as Dictionary).duplicate(true)
			result["angles"] = result["thumb"]
			result["effort"] = HandModel.thumb_effort(result["angles"])
		else:
			var f := float(cur["thumb_f"])
			result["thumb_f"] = f
			result["thumb"] = HandModel.thumb_at(f)
			result["angles"] = result["thumb"]
			result["effort"] = HandModel.thumb_effort(result["angles"])
	else:
		result["angles"] = out["fingers"][ray]
	thumb_lo = lo
	thumb_hi = hi
	thumb_dof = td
	clear_z = cz
	clear_w = cw
	pair_w = pw
	clear_skin = cs
	clear_cx = ccx
	clear_cy = ccy
	clear_hx = chx
	clear_hy = chy
	idle_sink = isk
	dir_w = dw
	dir_min = dm
	thumb_min = tm
	hover_lift = hl
	hover_df = hd
	thumb_lift = tl
	restore_foreign(fo)
	return result


# The click solver wraps the single solve in a fixed-point iteration: the idle
# fingers are tucked into the pose the solve found, and the solve is run again
# with those tucked fingers as the base, so the clearance residual sees them.
# Without it the solver keeps the palm high to protect the REST idle fingers
# (which it cannot move) and the target finger stops several millimetres short
# of a near key (V k5, 8.05 mm).
# Run the tuck with the clearance statics set from the solve's options. The
# tuck reads clear_z / clear_w / idle_sink / the footprint from the statics,
# and solve_chain runs it outside _solve_once, where those have already been
# restored. A helper keeps the set-and-restore in one place.
#
# THE PRE-TUCK RUNS ON THE NATURAL PRESS, BEFORE THE GUARDED REFINE. The
# refine cannot move the idle fingers — they are the base's angles — so the
# only way its clearance gradient can answer a hanging pinky is to lift the
# palm, and once lifted the arm prior (measured from the base) keeps it there:
# on L «е» the index then stopped 0.64 mm short (measured 01.11.2026). The
# tuck can fold the idle fingers first; the refine then starts from a pose
# whose idle parts are already in front of the board and only has to hold
# them, which it does at the home arm pose. This was tried once before and
# reverted: the tuck drove the idle thumb into the index while the arm stayed
# where the natural press left it. The thumb is therefore NOT part of this
# pass (see the body); the fingers are, and the refine's pair residuals
# (PAIR_W) still hold them apart from each other and from the thumb.
static func _pretuck(ray: String, p: Dictionary, opts: Dictionary) -> void:
	var cz := clear_z
	var cw := clear_w
	var isk := idle_sink
	var ccx := clear_cx
	var ccy := clear_cy
	var chx := clear_hx
	var chy := clear_hy
	clear_z = float(opts.get("clear_z", -1e9))
	clear_w = float(opts.get("clear_w", 0.0))
	idle_sink = float(opts.get("idle_sink", IDLE_SINK))
	var rect: Rect2 = opts.get("clear_rect", Rect2())
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		clear_cx = rect.position.x
		clear_cy = rect.position.y
		clear_hx = rect.size.x
		clear_hy = rect.size.y
	else:
		clear_hx = -1.0
	# The THUMB is left to the refine's own in-loop tuck. The pre-tuck runs at
	# the natural arm, and a thumb folded to clear the board there keeps that
	# fold after the arm has moved — on L Alt it started the final tuck from
	# mcp 29 instead of the 4 the refined arm would allow, and the two thumbs
	# ended 0.07 mm into each other (measured 01.11.2026). The fingers have no
	# such history: their tuck is the same curl wherever the palm is. The
	# thumb still takes part as the NEIGHBOUR of every finger pair.
	_tuck_others(ray, p, 0.0, false)
	clear_z = cz
	clear_w = cw
	idle_sink = isk
	clear_cx = ccx
	clear_cy = ccy
	clear_hx = chx
	clear_hy = chy


# A PRE-TUCK IS ONLY WORTH TAKING IF THE HAND CAN GET THERE FROM WHERE IT IS.
# The tuck guarantees its ENDPOINTS — the press pose is pair-clean — but the
# click path interpolates the idle fingers from the rest pose to the press
# pose, and a tuck that uncurls the index and middle swings their PIP segments
# through each other on the way: on R "9" the path crossed by 0.64 mm a third
# of the way in, while both ends were clean (measured 01.11.2026). The arm
# moves rigidly along the path and a rigid motion does not change a distance
# between two fingers of the same hand, so the check needs only the finger
# angles: sample the straight line between the rest pose and the pre-tucked
# press and refuse the pre-tuck if any pair crosses. The old flow then runs
# instead — the refine lifts the palm to protect the idle fingers, which is
# the right answer when they cannot uncurl without passing through each other.
const PRETUCK_SAMPLES := 8
static func _pretuck_safe(from: Dictionary, to: Dictionary) -> bool:
	var fa: Dictionary = from["fingers"]
	var fb: Dictionary = to["fingers"]
	var pw := pair_w
	pair_w = 1.0
	var out := []
	for i in range(1, PRETUCK_SAMPLES):
		var t := float(i) / float(PRETUCK_SAMPLES)
		var p: Dictionary = to.duplicate(true)
		p["fingers"] = {}
		for f in HandModel.FINGERS:
			var a: Dictionary = fa[f]
			var b: Dictionary = fb[f]
			var q := {}
			for j in ["mcp", "pip", "dip", "fan"]:
				q[j] = lerpf(float(a[j]), float(b[j]), t)
			p["fingers"][f] = q
		out.clear()
		if _pair_residuals(Transform3D(), p, to, out) > PAIR_TOL:
			pair_w = pw
			return false
	pair_w = pw
	return true


static func solve_chain(ray: String, target: Vector3, pose: Dictionary,
		opts: Dictionary = {}) -> Dictionary:
	# Continuation: the keyboard clearance is a guard, not the goal, and a cold
	# start with it on is bistable. The home pose rests the idle pads ON the
	# key face, so the first LM step is decided at a one-sided kink: the wrist
	# rotation that helps the press is blind to the clearance (the finite
	# difference probes one side only), the step is rejected, and the solver
	# crawls into a different valley — L «в» ended with the elbow lifted 8 mm,
	# the fan at both stops and the neighbouring fingers collapsed (measured
	# 01.11.2026; the same call with clear_w = 0 lands in the natural valley,
	# elbow_z -44, fan -2.2). So solve the natural press first, then refine it
	# with the guard on. The refine starts from a pose that already reaches and
	# whose idle pads are usually well above the face (the press bends the
	# target finger, not the palm), so it has nothing to undo. When the natural
	# press does hang an idle finger through the board, the refine starts with
	# a real violation and its gradient points out — which is the job.
	# The hand's own pairs are part of the same guard: a click may not pass one
	# finger through another (PAIR_W). A caller that wants a different weight
	# says so; everything else gets the click's own.
	var o: Dictionary = opts.duplicate(true)
	# The wrist's sideways stop (author, #11) is the caller's switch: the
	# simulator turns it on for the bottom row, whose outer keys are the ones
	# the author asked about. Every solve states it, so the static can never
	# leak from one call into the next.
	ArmModel.DEV_STOP = bool(o.get("dev_stop", false))
	# The bottom row's own price list (#11 follow-up). Empty by default, so
	# every other key keeps the approved hierarchy; stated on every call so a
	# static can never leak from one solve into the next.
	ArmModel.WEIGHT_OVERRIDE = (o.get("weights", {}) as Dictionary)
	PRIOR = float(o.get("prior", W_PRIOR))
	if not o.has("pair_w") and float(o.get("clear_w", 0.0)) > 0.0:
		o["pair_w"] = PAIR_W
	opts = o
	# THE CONTINUATION IS FOR THE ARM. The warm pass solves without the guard
	# and the guarded refine answers the clearance by moving the arm; the extras
	# converge the idle-finger tuck. With the arm frozen the clearance and pair
	# rows are not even in the residual (_chain_res skips them when `free_arm`
	# is false — a finger cannot move the palm, so those rows have no gradient),
	# so every pass re-solves the identical finger problem from a base that
	# differs only in idle fingers the residual does not read. Measured
	# 03.11.2026: the guard and both extras returned bit-identical poses for
	# four times the cost (327 ms → 82 ms for one press of «о»), and that
	# multiplication is what froze the simulator on fast typing (author, #9).
	# A frozen arm therefore gets ONE solve; the final margin tuck below still
	# runs, because it is the tuck — not the solve — that folds the idle
	# fingers clear of the caps.
	var guarded := bool(opts.get("arm", true)) \
		and float(opts.get("clear_w", 0.0)) > 0.0
	var start := pose
	if guarded:
		var warm_opts := opts.duplicate(true)
		warm_opts["clear_w"] = 0.0
		warm_opts["tuck"] = false
		start = (_solve_once(ray, target, pose, warm_opts)["pose"] as Dictionary)
		# The idle fingers tuck BEFORE the guarded refine, so its clearance
		# and pair residuals see the pose that will actually be drawn. See
		# _pretuck: without it the refine lifts the palm to protect the rest
		# fingers it cannot move, and a near key stops short.
		if bool(opts.get("tuck", true)) and bool(opts.get("pretuck", true)):
			var pre: Dictionary = start.duplicate(true)
			_pretuck(ray, pre, opts)
			if _pretuck_safe(pose, pre):
				start = pre
	var r := _solve_once(ray, target, start, opts)
	if not guarded:
		if float(opts.get("clear_w", 0.0)) <= 0.0:
			return r
	else:
		# TWO continuations (author, #9: kept after measuring). The first
		# carries the guarded pose the last of the way (0.17 mm → 0.002 mm on
		# R «н»), the second buys 0.002 → 0.0009 mm. Cutting the second was
		# measured on all 40 keys: the dump went 16.14 → 16.25 s (noise) and
		# 28 of 40 poses moved, so the cut bought nothing and cost the
		# approved SS50h answers. The tail that was actually worth cutting is
		# in _chain_run's stall break, not here.
		for it in 2:
			var r2 := _solve_once(ray, target, r["pose"], opts)
			if float(r2["error"]) > float(r["error"]) + 1.0:
				break
			r = r2
	# A last tuck with the skin margin. The in-loop tuck stops where the bone
	# capsule leaves the keyboard, and the blend bulges past it by up to 1.8 mm
	# at a curled tip; doing the margin pass AFTER the solve keeps the target's
	# error untouched (the pressing pad does not move) and only folds the idle
	# fingers that were grazing a keycap.
	#
	# _solve_once restores clear_z / clear_w / the footprint on its way out, so
	# they must be set again here: with clear_z = -1e9 the tuck measures against
	# a plane a billion millimetres away and never fires (the same class of bug
	# that once made the path guard blind).
	var cz := clear_z
	var cw := clear_w
	var isk := idle_sink
	var ccx := clear_cx
	var ccy := clear_cy
	var chx := clear_hx
	var chy := clear_hy
	clear_z = float(opts.get("clear_z", -1e9))
	clear_w = float(opts.get("clear_w", 0.0))
	idle_sink = float(opts.get("idle_sink", IDLE_SINK))
	var rect: Rect2 = opts.get("clear_rect", Rect2())
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		clear_cx = rect.position.x
		clear_cy = rect.position.y
		clear_hx = rect.size.x
		clear_hy = rect.size.y
	else:
		clear_hx = -1.0
	var out: Dictionary = (r["pose"] as Dictionary).duplicate(true)
	# The margin pass runs outside _solve_once, which has already put the
	# other hand back: set it again for the duration, or the last tuck is the
	# one place that does not know the other hand is there.
	#
	# The hover counts too. A finger's hover is this same pose lifted by
	# `hover_z - pad.z` (the caller's rule), so the idle thumb has to be clear
	# not only where it is but where the lift will carry it. The pad is the
	# pressing finger's, which the thumb's tuck never moves, so the height is
	# known before the tuck runs.
	var fo := set_foreign(opts.get("foreign", []))
	var hz := float(opts.get("hover_z", -1e9))
	var tl := thumb_lift
	if hz > -1e8 and ray != "I":
		thumb_lift = maxf(0.0, hz - _chain_pad(ray, out).z)
	_tuck_others(ray, out, TUCK_MARGIN)
	# The thumb has nowhere left to go: let the HAND answer. The tuck only
	# moves the thumb's own joints, and when the hand itself is in the other
	# hand's way, every clear thumb pose goes through the keyboard. The arm
	# may shift by a few millimetres instead — the pressing pad does not
	# move, so the click is unchanged, and a hand that got out of the way is
	# what a person does with it. See _yield_arm.
	if ray != "I" and foreign_a.size() > 0 and bool(opts.get("arm_yield", true)):
		out = _yield_arm(ray, out, pose)
	thumb_lift = tl
	restore_foreign(fo)
	r["pose"] = out
	clear_z = cz
	clear_w = cw
	idle_sink = isk
	clear_cx = ccx
	clear_cy = ccy
	clear_hx = chx
	clear_hy = chy
	return r


# Convenience: one call for whichever chain the viewer has selected. The
# hierarchy is the default; `opts["arm"] = false` asks for the finger alone.
static func solve(ray: String, target: Vector3, pose: Dictionary,
		opts: Dictionary = {}) -> Dictionary:
	if bool(opts.get("arm", true)):
		return solve_chain(ray, target, pose, opts)
	if ray == "I":
		return solve_thumb(target, pose)
	return solve_finger(ray, target, pose)
