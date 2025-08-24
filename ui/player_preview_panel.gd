extends HBoxContainer
class_name PlayerPreviewPanel

var _source_id: int = -1
var _swatch: ColorRect
var _player_label: Label
var _char_label: Label
var _set_label: Label

func _ready() -> void:
	# Build minimal UI
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(24, 24)
	add_child(_swatch)

	_player_label = Label.new()
	_player_label.custom_minimum_size = Vector2(90, 0)
	add_child(_player_label)

	_char_label = Label.new()
	_char_label.text = "Character: -"
	_char_label.custom_minimum_size = Vector2(220, 0)
	add_child(_char_label)

	_set_label = Label.new()
	_set_label.text = "Set: -"
	_set_label.custom_minimum_size = Vector2(160, 0)
	add_child(_set_label)

func setup(source_id: int, color: Color) -> void:
	_source_id = source_id
	_swatch.color = color
	_player_label.text = "P" + str(source_id)

func set_character(name: String) -> void:
	if _char_label:
		_char_label.text = "Character: " + name

func set_attack_set(name: String) -> void:
	if _set_label:
		_set_label.text = "Set: " + name

# Placeholder for later 3D model hookup
func set_model(_scene: PackedScene) -> void:
	# TODO: Replace a placeholder control with a SubViewportContainer that renders the 3D model.
	pass
