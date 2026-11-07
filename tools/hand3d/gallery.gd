extends Control

# The author's picture feeder: cycles the still cards full-screen with the
# arrow keys. The host has no image viewer installed, and packages cannot be
# installed system-wide, so Godot itself does the job.

var shots: Array[Texture2D] = []
var titles: PackedStringArray = []
var idx := 0

var _image: TextureRect
var _lbl: Label


func _ready() -> void:
	var scr := DisplayServer.screen_get_size()
	get_window().size = scr
	get_window().title = "Кадры · ←/→ листать · Esc — выход"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#111418")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_image = TextureRect.new()
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.offset_left = 12.0
	_image.offset_top = 12.0
	_image.offset_right = -12.0
	_image.offset_bottom = -48.0
	add_child(_image)

	_lbl = Label.new()
	_lbl.add_theme_font_size_override("font_size", 22)
	_lbl.add_theme_color_override("font_color", Color("#e6e9ee"))
	_lbl.position = Vector2(16.0, float(scr.y) - 44.0)
	add_child(_lbl)

	var spec := OS.get_environment("MBT_GALLERY")
	if spec == "":
		push_error("MBT_GALLERY пуст")
		get_tree().quit()
		return
	for entry in spec.split(";", false):
		var path := String(entry)
		var bytes := FileAccess.get_file_as_bytes(path)
		var img := Image.new()
		if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
			push_error("не открылся кадр: " + path)
			continue
		shots.append(ImageTexture.create_from_image(img))
		titles.append(String(path).get_file())
	if shots.is_empty():
		push_error("ни одного кадра")
		get_tree().quit()
		return
	_show()


func _show() -> void:
	_image.texture = shots[idx]
	_lbl.text = "%d/%d  ·  %s  ·  ←/→ листать, Esc — выход" % [
		idx + 1, shots.size(), titles[idx]]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_RIGHT:
				idx = (idx + 1) % shots.size()
				_show()
			KEY_LEFT:
				idx = (idx - 1 + shots.size()) % shots.size()
				_show()
			KEY_ESCAPE:
				get_tree().quit()
