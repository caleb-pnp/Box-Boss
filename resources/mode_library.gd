extends Resource
class_name ModeLibrary

@export var modes: Array[Resource] = [] # ModeData items

func all() -> Array[ModeData]:
	var out: Array[ModeData] = []
	for r in modes:
		if r is ModeData:
			out.append(r as ModeData)
	return out

func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for m in all():
		out.append(m.id)
	return out

func get_mode(id: StringName) -> ModeData:
	for m in all():
		if m.id == id:
			return m
	return null
