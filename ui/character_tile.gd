extends PanelContainer
class_name CharacterTile

var _character_id: StringName = &""
@export var character_id: StringName:
	set(value):
		_character_id = value
		_update_label()
	get:
		return _character_id

@export var display_name: String = "":
	set(value):
		display_name = value
		_update_label()

var _icon: Texture2D
@export var icon: Texture2D:
	set(value):
		_icon = value
		if _icon_rect:
			_icon_rect.texture = _icon
	get:
		return _icon

var _occupants: Dictionary = {} # source_id -> Color

@onready var _icon_rect: TextureRect = get_node_or_null("VBox/Icon")
@onready var _name_label: Label = get_node_or_null("VBox/Name")
@onready var _badges: HBoxContainer = get_node_or_null("VBox/Badges")

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.08)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.35, 0.35)
	add_theme_stylebox_override("panel", style)
	_update_badges()
	_update_label()

func set_from_data(data: SelectableData) -> void:
	if data == null: return
	character_id = data.id
	display_name = data.display_name
	icon = data.icon

func set_occupied(source_id: int, color: Color, occupied: bool) -> void:
	if occupied:
		_occupants[source_id] = color
	else:
		_occupants.erase(source_id)
	_update_badges()

func clear_all_occupants() -> void:
	_occupants.clear()
	_update_badges()

func _update_label() -> void:
	if _name_label == null:
		return
	_name_label.text = (display_name if display_name != "" else String(_character_id))

func _update_badges() -> void:
	if _badges == null:
		return
	for child in _badges.get_children():
		child.queue_free()
	for color in _occupants.values():
		var c := ColorRect.new()
		c.color = color
		c.custom_minimum_size = Vector2(12, 12)
		c.modulate.a = 0.95
		_badges.add_child(c)
