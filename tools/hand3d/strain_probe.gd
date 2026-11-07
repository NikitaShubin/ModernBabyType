# Edge strain of the skinned hand at the thumb states the click goes through:
# the hover and the press of the new scheme (press solved with f_lo = -0.35,
# hover = press + 0.30). A weight that is wrong shows up as an edge that
# collapses or stretches far more than its neighbours; the report names the
# spot, the bone mix there and the rest/deformed lengths.
#   mbt-godot --headless --path /work/tools/hand3d --script res://strain_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const IK := preload("res://ik.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"

const STATES := [["rest", 0.0], ["open", -1.0], ["hover", -0.05],
	["press", -0.35]]


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var rig := SkinRig.build(rest, src, REST_MESH)
	var arrays: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tris: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var names: Array = rig["names"]
	var idx: PackedInt32Array = rig["weights"]["indices"]
	var wts: PackedFloat32Array = rig["weights"]["weights"]
	print("names ", str(names))
	for st in STATES:
		var pose := HandModel.rest_pose()
		pose["thumb_f"] = float(st[1])
		var m := HandModel.new(1.0, 0.0, pose)
		var pts := SkinRig.cpu_positions(rig, m)
		var worst := []
		var over := 0
		var n := 0
		for t in range(0, tris.size(), 3):
			for e in 3:
				var a := tris[t + e]
				var b := tris[t + (e + 1) % 3]
				var d0 := verts[a].distance_to(verts[b])
				if d0 < 0.05:
					continue
				var d1 := pts[a].distance_to(pts[b])
				var r := d1 / d0
				n += 1
				if r < 0.55 or r > 1.8:
					over += 1
				worst.append([r, a, b])
		worst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		print("== %s  f %.2f  edges %d, extreme %d (%.3f%%)" % [st[0], float(st[1]),
			n, over, float(over) * 100.0 / maxf(float(n), 1.0)])
		for i in 6:
			var r: float = float(worst[i][0])
			var a: int = int(worst[i][1])
			var b: int = int(worst[i][2])
			print("   shrink %.3f  at %s  wA %s  wB %s" % [r, str(verts[a]),
				_ws(idx, wts, names, a), _ws(idx, wts, names, b)])
		var top := []
		for e in worst:
			if float(e[0]) > 1.8:
				top.append(e)
		top.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		for i in mini(4, top.size()):
			var r: float = float(top[i][0])
			var a: int = int(top[i][1])
			var b: int = int(top[i][2])
			print("   stretch %.3f  at %s  wA %s  wB %s" % [r, str(verts[a]),
				_ws(idx, wts, names, a), _ws(idx, wts, names, b)])
	quit(0)


func _ws(idx: PackedInt32Array, wts: PackedFloat32Array, names: Array,
		v: int) -> String:
	var parts := []
	for j in 4:
		var w := wts[v * 4 + j]
		if w > 0.005:
			parts.append("%s %.2f" % [names[idx[v * 4 + j]], w])
	return "[" + ", ".join(parts) + "]"
