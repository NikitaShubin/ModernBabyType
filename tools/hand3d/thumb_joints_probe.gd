extends SceneTree

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")

func _init() -> void:
	print("joints %s" % str(HandModel.THUMB_JOINTS))
	print("rest %s" % str(HandModel.THUMB_REST))
	var th := HandModel.thumb_of_pose({"thumb_dof": 4,
		"thumb": {"cmc_flex": 0.0, "cmc_abd": 0.0, "mcp": 16.0, "ip": 34.0}})
	print("of_pose %s" % str(th))
	print("shares %s" % str(IK.thumb_shares_of(th)))
	var fk := HandModel.thumb_fk(th)
	print("tip %s" % str((fk["pts"] as PackedVector3Array)[3]))
	quit(0)
