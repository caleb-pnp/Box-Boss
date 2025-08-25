extends Resource
class_name MapLibrary

@export var maps: Array[Resource] = []  # Array[MapData]

func all() -> Array[MapData]:
	var out: Array[MapData] = []
	for r in maps:
		if r is MapData:
			out.append(r as MapData)
	return out

func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for m in all():
		out.append(m.id)
	return out

func get_map(id: StringName) -> MapData:
	for m in all():
		if m.id == id:
			return m
	return null
