extends Resource
class_name BoxerLibrary

@export var boxers: Array[Resource] = [] # BoxerData items

func all() -> Array[BoxerData]:
	var arr: Array[BoxerData] = []
	for r in boxers:
		if r is BoxerData:
			arr.append(r as BoxerData)
	return arr

func ids() -> Array[StringName]:
	var arr: Array[StringName] = []
	for b in all():
		arr.append(b.id)
	return arr

func get_boxer(id: StringName) -> BoxerData:
	for b in all():
		if b.id == id:
			return b
	return null
