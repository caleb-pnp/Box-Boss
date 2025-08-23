extends Resource
class_name AttackLibrary

@export_category("Attacks")
@export var attacks: Array[AttackSpec] = []

var _map: Dictionary = {}

func _rebuild() -> void:
	_map.clear()
	for spec in attacks:
		if spec and String(spec.id) != "":
			_map[spec.id] = spec

func get_spec(id: StringName) -> AttackSpec:
	if _map.is_empty():
		_rebuild()
	return _map.get(id, null)

func has_id(id: StringName) -> bool:
	if _map.is_empty():
		_rebuild()
	return _map.has(id)

func ids() -> Array:
	if _map.is_empty():
		_rebuild()
	return _map.keys()
