extends Node3D
class_name Game

static var instance: Game

signal state_changed(state)
signal game_ready(game: Game)

const BATCH_SIZE: int = 50

@onready var main = Main.instance
@onready var gui_manager: Control = $GUILayer/GUI_Manager
@onready var level_container: Node3D = $LevelContainer

# Optional container to hold active controller
@export var controllers_container_path: NodePath
var _controllers_container: Node = null

# --- Autostart options (host-only) ---
@export var autostart_on_ready: bool = true
@export var autostart_controller_ref: String = "PreFight" # e.g. "PreFight", "StrongestWins", or a .gd/.tscn path
@export var autostart_map_path: String = ""               # e.g. "res://maps/your_map.tscn" (empty = do not load map)
var autostart_params: Dictionary = {}                     # set via script if needed

# --- Controller orchestration (host-only) ---
var _current_controller: GameControllerBase = null
var _pending_controller_ref: String = ""
var _pending_controller_params: Dictionary = {}
var _pending_map_path: String = ""
var _map_ready_flag: bool = false

# Current map
var _current_map: Node3D

func _enter_tree() -> void:
	Game.instance = self

func _ready() -> void:
	# Resolve controller container
	if String(controllers_container_path) != "":
		_controllers_container = get_node_or_null(controllers_container_path) as Node
	else:
		_controllers_container = self

	# Connect to Command Manager
	main.connect("scene_command", _on_scene_command)

	# Connect to Map Manager
	MapManager.connect("map_loaded", _on_map_manager_map_loaded)
	MapManager.connect("loading_progress", _on_map_manager_loading_progress)

	# Host-only init (no networking branching needed)
	_join_game_as_host()

	# Let others know Game is in scene
	game_ready.emit(self)

	# Optional: auto-launch a controller when the Game scene appears
	if autostart_on_ready:
		begin_local_controller(autostart_controller_ref, autostart_map_path, autostart_params)

func _exit_tree() -> void:
	if main.is_connected("scene_command", _on_scene_command):
		main.disconnect("scene_command", _on_scene_command)

	if MapManager.map_loaded.is_connected(_on_map_manager_map_loaded):
		MapManager.map_loaded.disconnect(_on_map_manager_map_loaded)
	if MapManager.loading_progress.is_connected(_on_map_manager_loading_progress):
		MapManager.loading_progress.disconnect(_on_map_manager_loading_progress)

	if Game.instance == self:
		Game.instance = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		main.execute_command("restart")

func _process(delta: float) -> void:
	if _current_controller:
		_current_controller.tick(delta)

func _on_scene_command(command: String, args: Array) -> void:
	# Host-only command handling
	if command == "leave":
		main.execute_command("restart", [])
		return

	match command:
		"start":
			# args: [controller_ref?, map_path?, params_dict?]
			var controller_ref: String = "PreFight"
			if args.size() > 0:
				controller_ref = String(args[0])

			var map_path: String = ""
			if args.size() > 1:
				map_path = String(args[1])

			var params: Dictionary = {}
			if args.size() > 2 and args[2] is Dictionary:
				params = args[2]

			begin_local_controller(controller_ref, map_path, params)
		_:
			pass

func _join_game_as_host() -> void:
	var player_name: String = main.settings.player_name + " (HOST)"
	# Host prep here if needed.

# Loading progress to GUI
func _on_map_manager_loading_progress(progress: float) -> void:
	gui_manager.show_loading(progress)

# Map finished loading
func _on_map_manager_map_loaded(packed_scene: PackedScene) -> void:
	clear_old_map()
	print("[GAME] Map instance loaded, adding into level container.")
	await get_tree().process_frame

	var instance: Node3D = packed_scene.instantiate() as Node3D
	_current_map = instance
	_map_ready_flag = false

	if not instance.is_connected("map_ready", _on_map_instance_map_ready):
		instance.connect("map_ready", _on_map_instance_map_ready)

	level_container.add_child(instance)

	# Try to spawn controller once map exists
	_try_spawn_pending_controller()

func _on_map_instance_map_ready() -> void:
	_map_ready_flag = true
	if _current_controller and _current_controller.requires_map_ready:
		_current_controller.on_map_ready(_current_map)

func clear_old_map() -> void:
	for child in level_container.get_children():
		child.queue_free()
	_current_map = null

# ---------------------------------------------
# Host-only controller orchestration
# ---------------------------------------------
func begin_local_controller(controller_ref: String, map_path: String, params: Dictionary) -> void:
	_pending_controller_ref = controller_ref
	_pending_controller_params = params
	_pending_map_path = map_path

	# Load map if provided
	if String(map_path) != "" and MapManager.has_method("load_map"):
		MapManager.load_map(map_path)
	else:
		_try_spawn_pending_controller()

func _try_spawn_pending_controller() -> void:
	if String(_pending_controller_ref) == "":
		return

	_destroy_current_controller()

	var ctrl := _instantiate_controller(_pending_controller_ref)
	if ctrl == null:
		push_warning("[GAME] Could not instantiate controller from: " + _pending_controller_ref)
		return

	_current_controller = ctrl
	_current_controller.attach_to_game(self)

	var parent_node: Node = _controllers_container if _controllers_container != null else self
	parent_node.add_child(_current_controller)

	_current_controller.on_enter(_pending_controller_params)

	if _current_controller.requires_map_ready:
		if _current_map != null and _map_ready_flag:
			_current_controller.on_map_ready(_current_map)
	else:
		if _current_map != null:
			_current_controller.on_map_ready(_current_map)

	_pending_controller_ref = ""
	_pending_controller_params = {}
	# keep _pending_map_path for reference

func _instantiate_controller(ref: String) -> GameControllerBase:
	# Support .tscn, .gd, or known ids
	if ref.ends_with(".tscn"):
		var pscene := load(ref) as PackedScene
		if pscene:
			return pscene.instantiate() as GameControllerBase
	if ref.ends_with(".gd"):
		var scr := load(ref)
		if scr:
			return (scr.new() as GameControllerBase)
	match ref:
		"PreFight":
			return PreFightController.new()
		"StrongestWins":
			return ModeStrongestWinsController.new()
		"LiveWindows":
			return ModeLiveWindowsController.new()
		"CommandStyle":
			return ModeCommandStyleController.new()
		_:
			return null

func _destroy_current_controller() -> void:
	if _current_controller:
		_current_controller.on_exit()
		_current_controller.queue_free()
		_current_controller = null

# External input pass-through (optional route from hardware to game to controller)
func on_punch(source_id: int, force: float) -> void:
	if _current_controller:
		_current_controller.on_punch(source_id, force)

# Debug flag helper
func debug_enabled() -> bool:
	if gui_manager and gui_manager.has_method("is_debug_enabled"):
		return bool(gui_manager.call("is_debug_enabled"))
	return OS.is_debug_build()
