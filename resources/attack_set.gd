extends Resource
class_name AttackSet

# A loadout that maps category -> chosen move id from AttackLibrary.
@export_category("Equipped Moves")
@export var light_id: StringName = &""
@export var medium_id: StringName = &""
@export var heavy_id: StringName = &""
@export var special_id: StringName = &""

func get_id_for_category(cat: StringName) -> StringName:
	var c := String(cat).to_lower()
	match c:
		"light": return light_id
		"medium": return medium_id
		"heavy": return heavy_id
		"special": return special_id
		_: return StringName("")

func set_id_for_category(cat: StringName, id: StringName) -> void:
	var c := String(cat).to_lower()
	match c:
		"light": light_id = id
		"medium": medium_id = id
		"heavy": heavy_id = id
		"special": special_id = id
		_: pass
