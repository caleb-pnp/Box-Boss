extends Control
class_name CountdownOverlay

@export var default_seconds: int = 5
@export var fight_text: String = "FIGHT!"
@export var appear_time: float = 0.25
@export var hold_time: float = 0.5
@export var disappear_time: float = 0.2
@export var color_normal: Color = Color(1, 1, 1, 1)
@export var color_final: Color = Color(1, 0.3, 0.3, 1)
@export var font_size: int = 96         # make it big
@export var outline_size: int = 6
@export var outline_color: Color = Color(0, 0, 0, 0.8)

var _label: Label

func _ready() -> void:
	# Make this overlay cover the whole screen
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_label = $Label if has_node("Label") else null
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		add_child(_label)

	# Make label fill the screen and center text
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Visuals: big font and outline for readability
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_outline_color", outline_color)
	_label.add_theme_constant_override("outline_size", outline_size)

	_label.modulate = Color(1, 1, 1, 0)
	_label.scale = Vector2.ONE
	visible = false

	# Debug sizes next frame
	call_deferred("_debug_print_rects")

func _debug_print_rects() -> void:
	await get_tree().process_frame
	print("[CountdownOverlay] rect_size: ", str(size), " label_rect: ", str(_label.size))

func play(seconds: int = -1) -> void:
	var secs := seconds
	if secs <= 0:
		secs = default_seconds
	print("[CountdownOverlay] play() start. seconds=", str(secs))

	# Ensure layout is ready before first tween
	visible = true
	await get_tree().process_frame
	print("[CountdownOverlay] (after layout) rect_size=", str(size), " label=", str(_label.size))

	for n in range(secs, 0, -1):
		var is_final := (n == 1)
		print("[CountdownOverlay] tick: ", str(n))
		await _pop_in_out(str(n), is_final)
	print("[CountdownOverlay] showing: ", fight_text)
	await _pop_in_out(fight_text, true)
	visible = false
	print("[CountdownOverlay] play() end")

func flash_text(text: String) -> void:
	print("[CountdownOverlay] flash_text: ", text)
	visible = true
	await get_tree().process_frame
	await _pop_in_out(text, true)
	visible = false

func _pop_in_out(text: String, is_final: bool) -> void:
	_label.text = text
	# Center pivot for the pop scale; use current rect size
	_label.pivot_offset = _label.size * 0.5
	var base_col := (color_final if is_final else color_normal)
	_label.modulate = Color(base_col.r, base_col.g, base_col.b, 0.0)
	_label.scale = Vector2(0.6, 0.6)

	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_label, "modulate:a", 1.0, appear_time)
	tw.parallel().tween_property(_label, "scale", Vector2(1.0, 1.0), appear_time)
	await tw.finished
	print("[CountdownOverlay] pop-in complete: ", text, " label_size=", str(_label.size))

	await get_tree().create_timer(hold_time).timeout

	var tw2 := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.tween_property(_label, "modulate:a", 0.0, disappear_time)
	tw2.parallel().tween_property(_label, "scale", Vector2(1.25, 1.25), disappear_time)
	await tw2.finished
	print("[CountdownOverlay] pop-out complete: ", text)
