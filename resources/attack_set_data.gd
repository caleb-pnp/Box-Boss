extends SelectableData
class_name AttackSetData

@export var description: String = ""

@export_category("Equipped Moves (Arrays)")
@export var light_attack_ids: Array[StringName] = []
@export var medium_attack_ids: Array[StringName] = []
@export var heavy_attack_ids: Array[StringName] = []
@export var special_attack_ids: Array[StringName] = []

# Only moves listed here are allowed to trigger via combo logic.
@export var combo_attack_ids: Array[StringName] = []

# All non-combo (basic) ids available in this set, de-duplicated.
func get_basic_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for arr in [light_attack_ids, medium_attack_ids, heavy_attack_ids, special_attack_ids]:
		for id in arr:
			if String(id) != "" and not out.has(id):
				out.append(id)
	return out

# Only the ids eligible to trigger via combo logic.
func get_combo_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in combo_attack_ids:
		if String(id) != "" and not out.has(id):
			out.append(id)
	return out
