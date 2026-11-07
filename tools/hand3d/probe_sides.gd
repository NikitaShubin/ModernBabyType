# The hand's wall against the cut rim, split by direction: how much fuller is
# it on each side (thumb +x, pinky -x, back +z, palm -z) as it rises from the
# cut? The side view sees only +-z, the palm view mostly +-x, so the two need
# separate numbers. Headless.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var a: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var used := {}
	for i in idx:
		used[i] = true
	var smooth := ArmView._smoothed_rim(ArmView._cut_rim(src))
	var c0 := Vector3.ZERO
	for p in smooth:
		c0 += p
	c0 /= float(smooth.size())
	var sides := {"+x thumb": 0.0, "-x pinky": 0.0, "+z back": 0.0, "-z palm": 0.0}
	print("dy     n     +x      -x      +z      -z   (max extent over the rim)")
	for k in 24:
		var y0 := float(k)
		var y1 := float(k + 1)
		var ext := {"+x": 0.0, "-x": 0.0, "+z": 0.0, "-z": 0.0}
		var cnt := 0
		for i in v.size():
			if not used.has(i):
				continue
			var dy := v[i].y - ArmView.CUT_Y
			if dy < y0 - 0.001 or dy >= y1 - 0.001:
				continue
			cnt += 1
			ext["+x"] = maxf(ext["+x"], v[i].x - c0.x)
			ext["-x"] = maxf(ext["-x"], c0.x - v[i].x)
			ext["+z"] = maxf(ext["+z"], v[i].z - c0.z)
			ext["-z"] = maxf(ext["-z"], c0.z - v[i].z)
		if cnt == 0:
			continue
		var rim := {"+x": 0.0, "-x": 0.0, "+z": 0.0, "-z": 0.0}
		for p in smooth:
			rim["+x"] = maxf(rim["+x"], p.x - c0.x)
			rim["-x"] = maxf(rim["-x"], c0.x - p.x)
			rim["+z"] = maxf(rim["+z"], p.z - c0.z)
			rim["-z"] = maxf(rim["-z"], c0.z - p.z)
		print("%4.0f %5d  %+6.2f  %+6.2f  %+6.2f  %+6.2f" % [y0, cnt,
			ext["+x"] - rim["+x"], ext["-x"] - rim["-x"],
			ext["+z"] - rim["+z"], ext["-z"] - rim["-z"]])
	quit()
