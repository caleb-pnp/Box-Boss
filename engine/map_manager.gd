# Map Manager SINGLETON
extends Node

# A signal to announce when a map's PackedScene is ready.
signal map_loaded(packed_scene: PackedScene)
signal map_loaded_and_added_to_scene() # invoked back when added
# A new signal to update a loading bar in your UI (sends a value from 0.0 to 1.0)
signal loading_progress(progress: float)

# --- NEW: Member variables for tracking the background load ---
var _is_loading: bool = false
var _current_loading_path: String

# Dictionary mapping an ID to its preloaded MapInfo resource.
const MAPS = {
	# To add a new map, create its .tres config file and preload it here.
}

# This function now starts the background loading process.
func load_map(map_id: StringName) -> void:
	# Guard against starting a new load while one is in progress.
	if _is_loading:
		print("MAP MANAGER: Already loading a map.")
		return

	if not MAPS.has(map_id):
		print("MAP MANAGER: Map ID not found: ", map_id)
		return

	_is_loading = true
	var map_config = get_map_config(map_id)
	_current_loading_path = map_config.scene_path

	# Start loading the resource on a background thread. This returns immediately.
	ResourceLoader.load_threaded_request(_current_loading_path)
	print("MAP MANAGER: Started background load for: ", _current_loading_path)


# The _process function checks the status of the load every frame.
func _process(delta: float):
	# Do nothing if we aren't currently loading a map.
	if not _is_loading:
		return

	# This array will be populated by the function below.
	var progress_array = []
	# Check the status AND get the progress at the same time.
	var status = ResourceLoader.load_threaded_get_status(_current_loading_path, progress_array)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Safety check to make sure the array is not empty.
			if not progress_array.is_empty():
				# The progress value (0.0 to 1.0) is the first element of the array.
				var progress: float = progress_array[0]
				loading_progress.emit(progress)

		ResourceLoader.THREAD_LOAD_LOADED:
			# The resource is now loaded!
			var packed_scene = ResourceLoader.load_threaded_get(_current_loading_path)

			print("MAP MANAGER: Background load finished.")
			map_loaded.emit(packed_scene)

			# Reset for the next load.
			_is_loading = false
			_current_loading_path = ""

		ResourceLoader.THREAD_LOAD_FAILED:
			print("MAP MANAGER: Background load failed!")
			_is_loading = false
			_current_loading_path = ""

# --- Your existing helper functions remain the same ---

# Returns the fully loaded MapInfo object for a given ID.
func get_map_config(map_id: StringName) -> MapInfo:
	if not MAPS.has(map_id):
		push_error("Map ID '%s' not found in MapDatabase." % map_id)
		return null
	return MAPS[map_id]

# Helper to get all available map IDs for a UI menu.
func get_available_map_ids() -> Array[StringName]:
	# Create an empty array that is explicitly typed.
	var map_ids: Array[StringName] = []

	# Loop through the generic keys and append them to the typed array.
	for key in MAPS.keys():
		# keys to ignore
		if key == &"podium":
			continue

		map_ids.append(key)

	return map_ids

func get_current_map():
	var map = get_tree().get_first_node_in_group("map")
	return map

func map_added_to_scene():
	map_loaded_and_added_to_scene.emit()
