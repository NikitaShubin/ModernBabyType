# Compares the raw SDF weights with a Laplacian-smoothed copy on the same pose:
# how much each vertex's mix moved, and what that does to the worst edge strain.
# The smoothing lived in skin_rig.gd during the 30.10.2026 experiment and was
# rejected; it is reproduced here locally so the measurement stays repeatable
# without shipping dead code in the rig. The numbers of the original run are in
# BASELINE.md.
# Strain is measured BOTH ways: relative (ratio) and absolute (mm of length
# change), and the relative one is reported only for edges longer than
# 0.25 mm — marching tetrahedra leaves 0.05 mm edges whose ratio explodes on a
# 0.03 mm move that nobody can see.
#   mbt-godot --headless --path /work/tools/hand3d --script res://smooth_cmp.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const SkinRig := preload("res://skin_rig.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const MIN_EDGE := 0.25

# The rejected rule: one Laplacian pass over the whole mesh, half the
# neighbour average mixed in, weights renormalised back to four bones. That is
# what spread I_MC/I_P down the graph to the wrist and made the clamp at
# (34.244, 72, -9).
const SMOOTH_LAMBDA := 0.5
const SMOOTH_PASSES := 2


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var arrays: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tris: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var wr := SkinRig.compute_weights(rest, verts)
	var ws := _smooth(wr, tris)
	var rig := SkinRig.build(rest, src, REST_MESH)
	var names: Array = ws["names"]
	for f in [-0.65, -0.35, 0.0, 0.55]:
		var pose := HandModel.rest_pose()
		pose["thumb_f"] = float(f)
		var m := HandModel.new(1.0, 0.0, pose)
		rig["weights"] = ws
		var ps := SkinRig.cpu_positions(rig, m)
		rig["weights"] = wr
		var pr := SkinRig.cpu_positions(rig, m)
		print("== f %.2f" % float(f))
		for tag in [["raw", pr, wr], ["smooth", ps, ws]]:
			var pts: PackedVector3Array = tag[1]
			var w: Dictionary = tag[2]
			var n := 0
			var bad_rel := 0
			var worst_rel := 1.0
			var worst_rel_at := Vector3.ZERO
			var worst_abs := 0.0
			var worst_abs_at := Vector3.ZERO
			var over_abs := 0
			for t in range(0, tris.size(), 3):
				for e in 3:
					var a := tris[t + e]
					var b := tris[t + (e + 1) % 3]
					var d0 := verts[a].distance_to(verts[b])
					var d1 := pts[a].distance_to(pts[b])
					var ad := absf(d1 - d0)
					if ad > worst_abs:
						worst_abs = ad
						worst_abs_at = verts[a]
					if ad > 0.5:
						over_abs += 1
					if d0 < MIN_EDGE:
						continue
					n += 1
					var r := d1 / d0
					if r < 0.55 or r > 1.8:
						bad_rel += 1
					if absf(log(r)) > absf(log(worst_rel)):
						worst_rel = r
						worst_rel_at = verts[a]
			print("%s: long edges %d, extreme %d (%.3f%%), worst ratio %.3f at %s" % [
				tag[0], n, bad_rel, float(bad_rel) * 100.0 / maxf(float(n), 1.0),
				worst_rel, str(worst_rel_at)])
			print("    max |dl| %.3f mm at %s, edges over 0.5 mm: %d" % [worst_abs,
				str(worst_abs_at), over_abs])
			print("    mix there: %s" % _ws(w["indices"], w["weights"], names, _near(
				verts, worst_abs_at)))
	quit(0)


# Laplacian smoothing of the weight field. The weights are expanded to a dense
# bone vector per vertex, averaged over the one-ring, mixed half-and-half with
# the original, and collapsed back to the four strongest bones.
func _smooth(rig: Dictionary, tris: PackedInt32Array) -> Dictionary:
	var idx: PackedInt32Array = rig["indices"]
	var wts: PackedFloat32Array = rig["weights"]
	var names: Array = rig["names"]
	var nb := names.size()
	var n := wts.size() / SkinRig.MAX_W
	var adj := []
	adj.resize(n)
	for i in n:
		adj[i] = {}
	for t in range(0, tris.size(), 3):
		for e in 3:
			var a := tris[t + e]
			var b := tris[t + (e + 1) % 3]
			(adj[a] as Dictionary)[b] = true
			(adj[b] as Dictionary)[a] = true
	var dense := PackedFloat32Array()
	dense.resize(n * nb)
	for v in n:
		for j in SkinRig.MAX_W:
			var w := wts[v * SkinRig.MAX_W + j]
			if w > 0.0:
				dense[v * nb + idx[v * SkinRig.MAX_W + j]] = w
	for it in SMOOTH_PASSES:
		var nxt := dense.duplicate()
		for v in n:
			var nbrs: Dictionary = adj[v]
			if nbrs.is_empty():
				continue
			var avg := PackedFloat32Array()
			avg.resize(nb)
			for u in nbrs.keys():
				var off := int(u) * nb
				for b in nb:
					avg[b] += dense[off + b]
			var inv := 1.0 / float(nbrs.size())
			var off2 := v * nb
			for b in nb:
				nxt[off2 + b] = dense[off2 + b] * (1.0 - SMOOTH_LAMBDA) \
					+ avg[b] * inv * SMOOTH_LAMBDA
		dense = nxt
	var out_idx := PackedInt32Array()
	out_idx.resize(n * SkinRig.MAX_W)
	var out_w := PackedFloat32Array()
	out_w.resize(n * SkinRig.MAX_W)
	for v in n:
		var pairs := []
		for b in nb:
			var w := dense[v * nb + b]
			if w > 0.0005:
				pairs.append([w, b])
		pairs.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		var total := 0.0
		for j in mini(SkinRig.MAX_W, pairs.size()):
			total += float(pairs[j][0])
		for j in SkinRig.MAX_W:
			if j < pairs.size():
				out_idx[v * SkinRig.MAX_W + j] = int(pairs[j][1])
				out_w[v * SkinRig.MAX_W + j] = float(pairs[j][0]) \
					/ maxf(total, 0.0001)
	return {"indices": out_idx, "weights": out_w, "names": names}


func _near(verts: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in verts.size():
		var d := verts[i].distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _ws(idx: PackedInt32Array, wts: PackedFloat32Array, names: Array,
		v: int) -> String:
	var parts := []
	for j in SkinRig.MAX_W:
		var w := wts[v * SkinRig.MAX_W + j]
		if w > 0.005:
			parts.append("%s %.2f" % [names[idx[v * SkinRig.MAX_W + j]], w])
	return "[" + ", ".join(parts) + "]"
