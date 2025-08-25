extends Node
class_name MapLoader

signal map_loaded(packed_scene: PackedScene)
signal map_loaded_and_added_to_scene()
signal loading_progress(progress: float)

@export var map_library: MapLibrary = preload("res://data/MapLibrary.tres")
@export var exclude_ids_from_menu: Array[StringName] = [ &"podium" ]

var _is_loading: bool = false
var _current_loading_path: String = ""
var _current_map_id: StringName = &""
var _current_map_path: String = ""
var _current_map_instance: Node3D = null

func _process(_delta: float) -> void:
	if not _is_loading:
		return

	var progress_array: Array[float] = []
	var status := ResourceLoader.load_threaded_get_status(_current_loading_path, progress_array)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress_array.is_empty():
				var progress: float = clampf(progress_array[0], 0.0, 1.0)
				loading_progress.emit(progress)
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed_scene := ResourceLoader.load_threaded_get(_current_loading_path) as PackedScene
			_is_loading = false
			set_process(false) # stop polling
			loading_progress.emit(1.0)
			map_loaded.emit(packed_scene)
		ResourceLoader.THREAD_LOAD_FAILED:
			push_error("MapManager: Background load failed for: " + _current_loading_path)
			_is_loading = false
			set_process(false) # stop polling
			_current_loading_path = ""
			_current_map_id = &""
			_current_map_path = ""

func load_map(map_id: StringName) -> void:
	if _is_loading:
		print("MapManager: Already loading a map.")
		return
	if map_library == null:
		push_error("MapManager: map_library is not assigned.")
		return

	var data: MapData = map_library.get_map(map_id)
	if data == null:
		push_error("MapManager: Map id not found in library: " + String(map_id))
		return
	if String(data.scene_path) == "":
		push_error("MapManager: MapData has empty scene_path for id: " + String(map_id))
		return

	_current_map_id = map_id
	_current_map_path = String(data.scene_path)
	_start_threaded_load(_current_map_path)

func load_map_by_path(scene_path: String) -> void:
	if _is_loading:
		print("MapManager: Already loading a map.")
		return
	if String(scene_path) == "":
		push_error("MapManager: Empty scene_path.")
		return

	_current_map_id = &""
	_current_map_path = scene_path
	_start_threaded_load(scene_path)

func load_map_ref(ref: String) -> void:
	if _is_scene_path(ref):
		load_map_by_path(ref)
	else:
		load_map(StringName(ref))

func get_map_config(map_id: StringName) -> MapData:
	if map_library == null:
		push_error("MapManager: map_library is not assigned.")
		return null
	return map_library.get_map(map_id)

func get_available_map_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if map_library == null:
		return out
	for id in map_library.ids():
		if exclude_ids_from_menu.has(id):
			continue
		out.append(id)
	return out

func get_current_map() -> Node3D:
	if _current_map_instance and is_instance_valid(_current_map_instance):
		return _current_map_instance
	var by_group := get_tree().get_first_node_in_group("map") as Node3D
	if by_group:
		_current_map_instance = by_group
	return _current_map_instance

func map_added_to_scene(map_instance: Node3D = null) -> void:
	if map_instance and is_instance_valid(map_instance):
		_current_map_instance = map_instance
		if not map_instance.is_in_group("map"):
			map_instance.add_to_group("map")
	else:
		var found := get_tree().get_first_node_in_group("map") as Node3D
		if found:
			_current_map_instance = found
	map_loaded_and_added_to_scene.emit()

func is_loading() -> bool:
	return _is_loading

func current_map_id() -> StringName:
	return _current_map_id

func current_map_path() -> String:
	return _current_map_path

func _start_threaded_load(scene_path: String) -> void:
	_is_loading = true
	_current_loading_path = scene_path
	_current_map_instance = null

	var err := ResourceLoader.load_threaded_request(scene_path)
	if err != OK:
		push_error("MapManager: Failed to start threaded load for: " + scene_path)
		_is_loading = false
		_current_loading_path = ""
		return

	# Ensure _process runs to poll status and emit signals
	set_process(true)

func _is_scene_path(s: String) -> bool:
	return s.begins_with("res://") or s.begins_with("user://")
