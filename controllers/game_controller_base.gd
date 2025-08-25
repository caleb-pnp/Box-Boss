extends Node
class_name GameControllerBase

@export var requires_map_ready: bool = true

var game: Game
var _map: Node3D = null
var _entered: bool = false
var _params: Dictionary = {}

func attach_to_game(g: Game) -> void:
	game = g

# Lifecycle hooks
func on_enter(params: Dictionary) -> void:
	_entered = true
	_params = params

func on_exit() -> void:
	_entered = false
	_params = {}
	_map = null

func on_map_ready(map_instance: Node3D) -> void:
	_map = map_instance

func tick(_delta: float) -> void:
	pass

func on_punch(_source_id: int, _force: float) -> void:
	pass

# Convenience
func get_map() -> Node3D:
	return _map

func get_params() -> Dictionary:
	return _params

# Loading overlay helpers (non-map long ops)
func show_loading(progress: float = 0.0, message: String = "") -> void:
	if Main.instance:
		Main.instance.show_loading(progress, message)

func hide_loading() -> void:
	if Main.instance:
		Main.instance.hide_loading()

# UI helpers via Main’s UIContainer
func mount_ui(scene: PackedScene) -> Control:
	if not Main.instance:
		return null
	return Main.instance.mount_ui(scene)

func add_ui(node: Control) -> void:
	if Main.instance:
		Main.instance.add_ui(node)

func remove_ui(node: Node) -> void:
	if Main.instance:
		Main.instance.remove_ui(node)

func clear_ui() -> void:
	if Main.instance:
		Main.instance.clear_ui()

# Controller jump helpers
func begin_controller_by_key(key: String, map_ref: String, params: Dictionary) -> void:
	if not game: return
	if game.has_method("begin_local_controller"):
		game.begin_local_controller(key, map_ref, params)

func begin_controller_scene(scene: PackedScene, map_ref: String, params: Dictionary) -> void:
	if not game: return
	if game.has_method("begin_local_controller_scene"):
		game.begin_local_controller_scene(scene, map_ref, params)
	else:
		push_warning("begin_controller_scene not supported by Game.")

func begin_controller_script(script: Script, map_ref: String, params: Dictionary) -> void:
	if not game: return
	if game.has_method("begin_local_controller_script"):
		game.begin_local_controller_script(script, map_ref, params)
	else:
		push_warning("begin_controller_script not supported by Game.")
