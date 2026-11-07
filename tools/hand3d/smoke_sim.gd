# A few frames of the viewer under MBT_SIM=1, then out: a headless smoke for
# runtime errors in _ready/_process (the scene itself only quits on Esc).
extends SceneTree
var _sim_scene: Node
func _init() -> void:
	var scn: PackedScene = load("res://board.tscn")
	_sim_scene = scn.instantiate()
	root.add_child(_sim_scene)
func _process(_d: float) -> bool:
	if Engine.get_process_frames() > 3:
		quit()
		return true
	return false
