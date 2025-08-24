extends Resource
class_name AttackSetLibrary

@export var sets: Array[Resource] = [] # AttackSetData items

func all() -> Array[AttackSetData]:
	var arr: Array[AttackSetData] = []
	for r in sets:
		if r is AttackSetData:
			arr.append(r as AttackSetData)
	return arr

func ids() -> Array[StringName]:
	var arr: Array[StringName] = []
	for s in all():
		arr.append(s.id)
	return arr

func get_set(id: StringName) -> AttackSetData:
	for s in all():
		if s.id == id:
			return s
	return null
