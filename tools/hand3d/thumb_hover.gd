# The thumb's press and hover as ONE solve: the press pad at the key, the
# hover pad hover_lift above it, with the same arm and f - df. Prints where
# both pads land, the df the solver chose, and how much the hover drifts
# sideways from the press.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_hover.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_TRAVEL := 2.6
const KEY_HOVER := 12.0
const LIFT := KEY_HOVER + KEY_TRAVEL + 1.0
const CLEAR_Z := KEY_FACE + 3.0
const CLEAR_W := 100.0
const DIR_W := 30.0

const KEYS := [0, 4, 5, 9, 20, 24, 25, 29, 40, 44, 45, 49]


func _init() -> void:
	var rest := HandModel.rest_pose()
	for k in KEYS:
		var ix: int = k % 10
		var iy: int = k / 10
		var c := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_Z)
		var face := Vector3(c.x, c.y, KEY_FACE)
		var deep := Vector3(c.x, c.y, KEY_FACE - KEY_TRAVEL - 1.0)
		var pr: Dictionary = IK.solve_chain("I", deep, rest,
			{"arm": true, "f_lo": -0.65, "clear_z": CLEAR_Z,
			"clear_w": CLEAR_W, "dir_w": DIR_W, "hover_lift": LIFT,
			"hover_df": 0.30})
		var p: Dictionary = pr["pose"]
		var f := float(p["thumb_f"])
		var df := float(p.get("thumb_df", 0.0))
		var xf := ArmModel.hand_transform(p["arm"])
		var press := xf * HandModel.thumb_pad(HandModel.thumb_fk(f))
		var hover := xf * HandModel.thumb_pad(HandModel.thumb_fk(f - df))
		var lat := Vector2(hover.x - press.x, hover.y - press.y).length()
		print("k%-2d err %4.2f f %6.3f df %5.3f | press (%.1f %.1f %.1f) d %.2f | hover (%.1f %.1f %.1f) d %.2f | lat %.2f lift %.2f | wrist %.1f/%.1f pron %.1f fore %.1f/%.1f elbow %.1f/%.1f/%.1f" % [
			k, float(pr["error"]), f, df, press.x, press.y, press.z,
			press.distance_to(face), hover.x, hover.y, hover.z,
			hover.distance_to(face), lat, hover.z - press.z,
			float(p["arm"]["wrist_flex"]), float(p["arm"]["wrist_dev"]),
			float(p["arm"]["pronation"]), float(p["arm"]["forearm_flex"]),
			float(p["arm"]["forearm_abd"]), float(p["arm"]["elbow_x"]),
			float(p["arm"]["elbow_y"]), float(p["arm"]["elbow_z"])])
	quit(0)
