# The cut rim of the baked mesh against the SDF's true cross-section at the
# cut plane. The mesher can only sample the field at grid nodes, and the cut
# sits between two rows, so the rim may be inset by up to a voxel. Headless.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var mesh: ArrayMesh = load(REST_MESH)
	var rim := ArmView._cut_rim(mesh)
	var c := Vector3.ZERO
	for p in rim:
		c += p
	c /= float(rim.size())
	print("rim %d, centre %s" % [rim.size(), str(c)])
	var model := HandModel.new(1.0, 0.0)
	var worst := 0.0
	var sum := 0.0
	var minx := 1e9
	var maxx := -1e9
	var minz := 1e9
	var maxz := -1e9
	for p in rim:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z)
		maxz = maxf(maxz, p.z)
		var ang := atan2(p.z - c.z, p.x - c.x)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		# The field AT the cut plane is max(d, 0): never negative, so the
		# contour is measured half a millimetre above the plane.
		var base := Vector3(0.0, ArmView.CUT_Y + 0.5, 0.0)
		var lo := 0.0
		var hi := 0.0
		var r := 1.0
		while r < 60.0 and model.field(base + dir * r) < 0.0:
			r += 1.0
		hi = r
		for i in 30:
			var mid := 0.5 * (lo + hi)
			if model.field(base + dir * mid) < 0.0:
				lo = mid
			else:
				hi = mid
		var want := base + dir * hi
		var got := Vector3(p.x, ArmView.CUT_Y, p.z)
		var d := got.distance_to(want)
		sum += d
		worst = maxf(worst, d)
	print("rim x [%.2f %.2f]  z [%.2f %.2f]" % [minx, maxx, minz, maxz])
	print("SDF contour vs mesh rim: mean %.3f mm, worst %.3f mm" % [
		sum / float(rim.size()), worst])
	quit()
