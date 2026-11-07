# TEMP probe: the simulator's typed stroke, headless.
# Drives _sim_key with fabricated InputEventKey events exactly as real typing
# does, then advances _process(1/60) by hand (fixed dt — the headless engine's
# frame rate must not matter). Each test is a list of ops:
#
#   ["press", KEY_X] / ["release", KEY_X] / ["press", KEY_SHIFT, 1]
#       one fabricated key event (location in the third slot for the right
#       shift); the probe prints the state right at the event
#   ["wait", n]     the next n frames, sampled
#   ["settle"]      step until every anim and every cap rider is gone
#
# Per frame the probe samples: the display pad of every held/ridden key, its
# sunk share (u), the cap face, and the residual plane lift the next sampler
# frame would apply — the profile the eye has to read: when the key begins to
# sink, when contact happens, when the hit lands, and what the rider does on
# release. It also measures the END SNAP: the pad at the last guarded sample
# versus the raw end the anim snaps to.
extends SceneTree

const THICK := 2.0
const FACE_Z := -69.0
const ClickPath := preload("res://click_path.gd")
const HandModel := preload("res://hand_model.gd")
const CLEAR_ZI := FACE_Z          # the caps' top plane, probe-side
const CLEAR_SANC := FACE_Z + 3.0  # the solver's sanctity line, for comparison

var v: Node
var tests := [
	{"name": "о hold", "ops": [
		["press", KEY_J], ["settle"], ["wait", 25],
		["release", KEY_J], ["settle"]]},
	{"name": "1 hold (top row)", "ops": [
		["press", KEY_1], ["settle"], ["wait", 25],
		["release", KEY_1], ["settle"]]},
	{"name": "5 hold (shortfall case)", "ops": [
		["press", KEY_5], ["settle"], ["wait", 25],
		["release", KEY_5], ["settle"]]},
	{"name": "0 hold (top row)", "ops": [
		["press", KEY_0], ["settle"], ["wait", 25],
		["release", KEY_0], ["settle"]]},
	{"name": "Tab+ф same hand", "ops": [
		["press", KEY_TAB], ["settle"], ["wait", 10],
		["press", KEY_A], ["settle"], ["wait", 20],
		["release", KEY_A], ["settle"], ["wait", 10],
		["release", KEY_TAB], ["settle"]]},
	{"name": "о+л same hand", "ops": [
		["press", KEY_J], ["settle"], ["wait", 10],
		["press", KEY_K], ["settle"], ["wait", 20],
		["release", KEY_K], ["settle"], ["wait", 10],
		["release", KEY_J], ["settle"]]},
	{"name": "о early keyup at 2 frames", "ops": [
		["press", KEY_J], ["wait", 1], ["release", KEY_J], ["settle"]]},
	{"name": "shift+а chord", "ops": [
		["press", KEY_SHIFT, 1], ["settle"], ["wait", 5],
		["press", KEY_A], ["settle"], ["wait", 20],
		["release", KEY_A], ["settle"], ["wait", 10],
		["release", KEY_SHIFT, 1], ["settle"]]},
	{"name": "з three times (same pose)", "ops": [
		["press", KEY_P], ["settle"], ["wait", 8],
		["release", KEY_P], ["settle"], ["wait", 8],
		["press", KEY_P], ["settle"], ["wait", 8],
		["release", KEY_P], ["settle"], ["wait", 8],
		["press", KEY_P], ["settle"], ["wait", 8],
		["release", KEY_P], ["settle"]]},
	{"name": "backspace reach (pinky fan)", "ops": [
		["press", KEY_BACKSPACE], ["settle"], ["wait", 25],
		["release", KEY_BACKSPACE], ["settle"]]},
]
var t := -1            # test index
var op_i := 0
var frames := 0
var wait_left := 0
var touched := {}
var guard_seen := {}   # side -> last anim total the END GUARD was printed for


func _init() -> void:
	var scn: PackedScene = load("res://board.tscn")
	v = scn.instantiate()
	root.add_child(v)
	# The engine ALSO ticks every node's _process per frame; with the viewer in
	# the tree the anim advanced twice per step (the engine's own delta plus
	# this probe's 1/60) and every second in the log was fiction. The probe
	# drives _process manually; the viewer's own loop goes off entirely.
	v.process_mode = Node.PROCESS_MODE_DISABLED


func _ev(code: int, pressed: bool, loc := 0) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.location = loc
	return ev


func _step(n: int) -> void:
	for i in n:
		_guard_probe()
		_anim_times()
		v._process(1.0 / 60.0)
		_sample()
		_anim_pads()


# The stroke path's own times: what the anim will do before the state can say
# anything (printed when the anim is fresh).
func _anim_times() -> void:
	for side in ["L", "R"]:
		var anim: Dictionary = _anim(side)
		if anim.is_empty():
			continue
		var path: Dictionary = anim["path"]
		var stamp := str(path.get("times"))
		if stamp == String(guard_seen.get(side + "times", "")):
			continue
		guard_seen[side + "times"] = stamp
		var pt: Array = path["times"]
		var ray := String(path.get("sray", ""))
		print("      path %s/%s times %s total %.3f" % [side, ray,
			_str_times(pt), float(path["total"])])


func _str_times(pt: Array) -> String:
	var s := ""
	for x in pt:
		s += " %.3f" % float(x)
	return s


# The moving pad frame by frame during a stroke — the profile the eye reads.
func _anim_pads() -> void:
	for side in ["L", "R"]:
		var anim: Dictionary = _anim(side)
		if anim.is_empty():
			continue
		var path: Dictionary = anim["path"]
		var ray := String(path.get("sray", ""))
		var st: Dictionary = v._hands[side]
		var dp: Vector3 = v._pad_of_pose(side, ray, st["disp"])
		var kind := String(anim.get("kind", ""))
		print("      f%3d %s %s pad %+.2f u %.2f" % [frames, kind, ray,
			dp.z, v._sink_u(dp.z)])
		if frames % 2 == 0:
			var raw: Dictionary = ClickPath.at(path, float(anim["t"]))
			print("      parts f%d: %s" % [frames,
				_parts(side, raw, path["key_rects"])])


# The end-of-path guard: at the LAST sample (t = total) the stroke still runs
# the plane/tip guards, and the very next frame the anim hands out the RAW end
# with no guards at all. The pad difference between those two is the single
# frame pop (or nothing) the eye has to catch. Printed once per anim.
func _guard_probe() -> void:
	for side in ["L", "R"]:
		var anim: Dictionary = _anim(side)
		if anim.is_empty():
			continue
		var path: Dictionary = anim["path"]
		var total := float(path["total"])
		if float(guard_seen.get(side, -1.0)) == total \
				and String(path.get("sray", "")) == String(
					guard_seen.get(side + "ray", "?")):
			continue
		guard_seen[side] = total
		guard_seen[side + "ray"] = String(path.get("sray", ""))
		var ray := String(path.get("sray", ""))
		var kind := String(anim.get("kind", ""))
		var guarded: Dictionary = v._sim_sample(path, total, side,
			kind == "press")
		var raw: Dictionary = ClickPath.at(path, total)
		var gp: Vector3 = v._pad_of_pose(side, ray, guarded)
		var rp: Vector3 = v._pad_of_pose(side, ray, raw)
		print("      parts at raw end %s: %s" % [rp.z,
			_parts(side, raw, path["key_rects"])])
		if absf(gp.z - rp.z) > 0.02:
			print("      END GUARD on %s at t=total: guarded pad %+.2f"
				% [side, gp.z], ", raw end %+.2f -> pops %+.2f mm in one frame"
				% [rp.z, rp.z - gp.z])
		else:
			print("      END GUARD on %s: no pop (%+.2f vs %+.2f)"
				% [side, gp.z, rp.z])


func _anim(side: String) -> Dictionary:
	return (v._sim_anim as Dictionary).get(side, {})


func _idle() -> bool:
	return _anim("L").is_empty() and _anim("R").is_empty() \
		and (v._sim_up as Dictionary).is_empty()


func _held() -> Dictionary:
	return v._sim_held


# One line per held/ridden key: display pad, sunk share, contact flag, cap
# face, and the residual plane lift the next sampler frame would apply (a
# zero means the next sample sits where the guards already agree).
func _state_line() -> String:
	var acts := []
	for src_i in 2:
		var src: Dictionary = v._sim_held if src_i == 0 else v._sim_up
		for k in src:
			var rec: Dictionary = src[k]
			var side := String(rec["side"])
			var ray := String(rec["ray"])
			var st: Dictionary = v._hands[side]
			var dp: Vector3 = v._pad_of_pose(side, ray, st["disp"])
			var u: float = v._sink_u(dp.z)
			var face: float = (v._key_nodes[k] as Node3D).position.z \
				+ THICK * 0.5
			var lift: float = v._sim_plane_lift(ray, st["pose"], side,
				v._local_keys(side))
			acts.append("%s/%s/%s pad %+.2f u %.2f down=%s face %+.2f lift %.2f"
				% [String(v._keys[k]["s"]), ray, side, dp.z, u,
				"y" if v._sim_down.has(k) else "n", face, lift])
	return " | ".join(acts)


# The caps-scoped per-chain measure, probe-side (the same prism arithmetic as
# the viewer's `_sim_plane_lift`): which chain carries the lift, and where.
const IKPROBE := preload("res://arm_model.gd")

func _parts(side: String, p: Dictionary, rects: Array) -> String:
	var xf: Transform3D = IKPROBE.hand_transform(p.get("arm", {}))
	var out := [" hands " + side]
	for other in ["II", "III", "IV", "V"]:
		var pts: PackedVector3Array = HandModel.finger_fk(other,
			p["fingers"][other])["pts"]
		var radii: Array = HandModel.SKIN_R[other]
		var worst := 0.0
		var where := -1
		var sanc := 0.0
		for i in rects.size():
			for j in 4:
				var w: Vector3 = xf * pts[j]
				var d: float = v._sim_prism(w, float(radii[j])
					+ ClickPath.SKIN_MARGIN, rects[i], CLEAR_ZI)
				if d > worst:
					worst = d
					where = i
				sanc = maxf(sanc, maxf(0.0, float(radii[j])
					+ ClickPath.SKIN_MARGIN - (w.z - CLEAR_SANC)))
		out.append("%s %.2f at k%d (sanc %.2f)"
			% [other, worst, where, sanc])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var tradii := [11.8, 10.8, 9.6, 6.6]
	var tworst := 0.0
	for j in 4:
		var tw: Vector3 = xf * tpts[j]
		for i in rects.size():
			tworst = maxf(tworst, v._sim_prism(tw, float(tradii[j])
				+ ClickPath.SKIN_MARGIN, rects[i], CLEAR_ZI))
	out.append("TH %.2f" % tworst)
	return " | ".join(out)


# The eye's contact event: a display pad crossing the cap face plane. Fires
# once per key per test.
func _sample() -> void:
	for k in v._sim_held:
		var rec: Dictionary = v._sim_held[k]
		var side := String(rec["side"])
		var key := String(v._keys[k]["s"])
		var dp: Vector3 = v._pad_of_pose(side, String(rec["ray"]),
			v._hands[side]["disp"])
		if dp.z <= FACE_Z and not touched.has(side + key):
			touched[side + key] = frames
			print("      CONTACT at t %.3f s (frame %d) u %.2f face %+.2f"
				% [frames / 60.0, frames, v._sink_u(dp.z),
				(v._key_nodes[k] as Node3D).position.z + THICK * 0.5])


func _process(_d: float) -> bool:
	if Engine.get_process_frames() < 4:
		return false
	_step(1)
	frames += 1
	if t < 0:
		_next_test()
		return false
	if wait_left > 0:
		wait_left -= 1
		if frames % 5 == 0:
			print("    f%3d %s" % [frames, _state_line()])
		return false
	var ops: Array = tests[t]["ops"]
	if op_i >= ops.size():
		print("  TEST DONE (held left: ", (v._sim_held as Dictionary).size(),
			")")
		_next_test()
		return false
	var op: Array = ops[op_i]
	var tag := String(op[0])
	if tag == "press" or tag == "release":
		var code: int = int(op[1])
		var loc: int = int(op[2]) if op.size() > 2 else 0
		v._sim_key(_ev(code, tag == "press", loc))
		print("  %s kod %d loc %d at t %.3f s:"
			% ["press" if tag == "press" else "release", code, loc,
			frames / 60.0])
		print("      ", _state_line())
		op_i += 1
	elif tag == "wait":
		wait_left = int(op[1])
		op_i += 1
	elif tag == "settle":
		if _idle():
			print("  settled at t %.3f s: " % [frames / 60.0],
				_state_line())
			op_i += 1
		if frames > 900:
			print("  !! settle over 900 frames")
			op_i += 1
	return false


func _next_test() -> void:
	touched.clear()
	frames = 0
	op_i = 0
	wait_left = 0
	t += 1
	if t >= tests.size():
		print("TRACE DONE")
		quit()
		return
	print("=== TEST ", String(tests[t]["name"]), " ===")
