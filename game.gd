extends Node3D
class_name Game

static var instance: Game

signal state_changed(state)
signal game_ready(game: Game)

const BATCH_SIZE: int = 50

@onready var main = Main.instance
@onready var level_container: Node3D = $LevelContainer

# Optional container to hold active controller
@export var controllers_container_path: NodePath
var _controllers_container: Node = null

# --- Autostart options (host-only) ---
@export var autostart_on_ready: bool = true
@export var autostart_controller_ref: String = "PreFight" # "prefight", "versus", or a .gd/.tscn path
@export var autostart_map_path: String = ""               # res://... (empty = do not load map)
var autostart_params: Dictionary = {}                     # set via script if needed

# --- Tuning ---
@export var map_ready_timeout_sec: float = 1.0  # Safety: force-ready if map doesn't emit map_ready

# --- Controller orchestration (host-only) ---
var _current_controller: GameControllerBase = null
var _pending_controller_ref: String = ""          # normalized lowercase key or path
var _pending_controller_params: Dictionary = {}
var _pending_map_path: String = ""                # id (lowercase) or scene path
var _map_ready_flag: bool = false

# Direct controller sources (from ModeData paths)
var _pending_controller_scene: PackedScene = null
var _pending_controller_script: Script = null

# Current map and ready timeout
var _current_map: Node3D
var _map_ready_timeout_timer: SceneTreeTimer = null

# Track whether a map load is actively in progress (drives overlay lifecycle)
var _map_loading_active: bool = false

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
	if MapManager:
		if MapManager.has_signal("map_loaded"):
			MapManager.connect("map_loaded", _on_map_manager_map_loaded)
			print("[GAME] Connected to MapManager.map_loaded")
		if MapManager.has_signal("loading_progress"):
			MapManager.connect("loading_progress", _on_map_manager_loading_progress)
			print("[GAME] Connected to MapManager.loading_progress")
	else:
		push_warning("[GAME] MapManager autoload not found. Map loading and overlays will not work.")

	# Host-only init (no networking branching needed)
	_join_game_as_host()

	# Let others know Game is in scene
	game_ready.emit(self)

	# Optional: auto-launch a controller when the Game scene appears
	if autostart_on_ready:
		print("[GAME] Autostart: controller_ref=", autostart_controller_ref, " map=", autostart_map_path)
		begin_local_controller(autostart_controller_ref, autostart_map_path, autostart_params)

func _exit_tree() -> void:
	if main.is_connected("scene_command", _on_scene_command):
		main.disconnect("scene_command", _on_scene_command)

	if MapManager and MapManager.has_signal("map_loaded") and MapManager.map_loaded.is_connected(_on_map_manager_map_loaded):
		MapManager.map_loaded.disconnect(_on_map_manager_map_loaded)
	if MapManager and MapManager.has_signal("loading_progress") and MapManager.loading_progress.is_connected(_on_map_manager_loading_progress):
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
			# args: [controller_ref?, map_path_or_id?, params_dict?]
			var controller_ref: String = "PreFight"
			if args.size() > 0:
				controller_ref = String(args[0])

			var map_ref: String = ""
			if args.size() > 1:
				map_ref = String(args[1])

			var params: Dictionary = {}
			if args.size() > 2 and args[2] is Dictionary:
				params = args[2]

			begin_local_controller(controller_ref, map_ref, params)
		_:
			pass

func _join_game_as_host() -> void:
	var player_name: String = main.settings.player_name + " (HOST)"
	# Host prep here if needed.

# Loading progress to permanent overlay (Main drives the overlay)
func _on_map_manager_loading_progress(progress: float) -> void:
	if Main.instance:
		Main.instance.update_loading(progress)

# Map finished loading (PackedScene is ready to instantiate)
func _on_map_manager_map_loaded(packed_scene: PackedScene) -> void:
	print("[GAME] Map PackedScene loaded. Instancing...")
	clear_old_map()
	await get_tree().process_frame

	var instance: Node3D = packed_scene.instantiate() as Node3D
	_current_map = instance
	_map_ready_flag = false

	if instance == null:
		push_error("[GAME] PackedScene instantiation returned null.")
		return

	# If the map scene emits a custom "map_ready" signal, wait for it to hide loading
	if instance and instance.has_signal("map_ready") and not instance.is_connected("map_ready", _on_map_instance_map_ready):
		instance.connect("map_ready", _on_map_instance_map_ready)
		print("[GAME] Connected to map instance 'map_ready' signal.")
	else:
		print("[GAME] Map has no 'map_ready' signal; will force-ready immediately.")

	level_container.add_child(instance)
	print("[GAME] Map instance added to LevelContainer: ", instance.name)

	# Inform MapManager that the map has been added to the scene for any listeners
	if MapManager and MapManager.has_method("map_added_to_scene"):
		MapManager.map_added_to_scene(instance)

	# Safety: start a timeout to force ready if the map never emits map_ready
	if _map_ready_timeout_timer:
		_map_ready_timeout_timer = null
	_map_ready_timeout_timer = get_tree().create_timer(map_ready_timeout_sec)
	_map_ready_timeout_timer.timeout.connect(_on_map_ready_timeout)

	# If no "map_ready" signal exists, consider it ready immediately
	if not instance.has_signal("map_ready"):
		_on_map_instance_map_ready()

	# Try to spawn controller once map exists
	_try_spawn_pending_controller()

func _on_map_ready_timeout() -> void:
	if _map_ready_flag:
		return
	print("[GAME] Map ready timeout reached; forcing ready now.")
	_on_map_instance_map_ready()

func _on_map_instance_map_ready() -> void:
	if _map_ready_flag:
		return
	_map_ready_flag = true
	_map_loading_active = false
	if Main.instance:
		Main.instance.hide_loading()
	print("[GAME] Map instance reports ready (overlay hidden).")

	if _current_controller and _current_map:
		_current_controller.on_map_ready(_current_map)

func clear_old_map() -> void:
	for child in level_container.get_children():
		child.queue_free()
	if _current_map:
		print("[GAME] Cleared previous map instance.")
	_current_map = null

# ---------------------------------------------
# Host-only controller orchestration
# ---------------------------------------------
func begin_local_controller(controller_ref: String, map_path_or_id: String, params: Dictionary) -> void:
	var norm_ref := String(controller_ref).strip_edges().to_lower()
	var norm_map_ref := String(map_path_or_id).strip_edges()
	if norm_map_ref != "" and not _is_scene_path(norm_map_ref):
		norm_map_ref = norm_map_ref.to_lower()

	print("[GAME] begin_local_controller ref=", norm_ref, " map_ref=", norm_map_ref, " players=", str(params.get("players", [])))

	# Show permanent overlay as we transition controllers (progress will update if a map load starts)
	if Main.instance:
		Main.instance.show_loading(0.0, "Loading")

	# Important: remove current controller immediately to hide its UI under the overlay
	_destroy_current_controller()

	_pending_controller_ref = norm_ref
	_pending_controller_params = params
	_pending_controller_scene = null
	_pending_controller_script = null
	_pending_map_path = norm_map_ref

	_start_map_if_needed(norm_map_ref)

func begin_local_controller_scene(scene: PackedScene, map_path_or_id: String, params: Dictionary) -> void:
	var norm_map_ref := String(map_path_or_id).strip_edges()
	if norm_map_ref != "" and not _is_scene_path(norm_map_ref):
		norm_map_ref = norm_map_ref.to_lower()

	print("[GAME] begin_local_controller_scene map_ref=", norm_map_ref, " scene=", scene)

	if Main.instance:
		Main.instance.show_loading(0.0, "Loading")

	_destroy_current_controller()

	_pending_controller_ref = ""
	_pending_controller_params = params
	_pending_controller_scene = scene
	_pending_controller_script = null
	_pending_map_path = norm_map_ref

	_start_map_if_needed(norm_map_ref)

func begin_local_controller_script(script: Script, map_path_or_id: String, params: Dictionary) -> void:
	var norm_map_ref := String(map_path_or_id).strip_edges()
	if norm_map_ref != "" and not _is_scene_path(norm_map_ref):
		norm_map_ref = norm_map_ref.to_lower()

	print("[GAME] begin_local_controller_script map_ref=", norm_map_ref, " script=", script)

	if Main.instance:
		Main.instance.show_loading(0.0, "Loading")

	_destroy_current_controller()

	_pending_controller_ref = ""
	_pending_controller_params = params
	_pending_controller_scene = null
	_pending_controller_script = script
	_pending_map_path = norm_map_ref

	_start_map_if_needed(norm_map_ref)

func _start_map_if_needed(map_ref: String) -> void:
	# Load map if provided (accept id or path)
	if String(map_ref) != "" and MapManager:
		_map_loading_active = true

		# Ensure overlay is visible at the start of any load
		if Main.instance:
			Main.instance.show_loading(0.0, "Loading map")

		if _is_scene_path(map_ref):
			if MapManager.has_method("load_map_by_path"):
				print("[GAME] Loading map by scene path: ", map_ref)
				MapManager.load_map_by_path(map_ref)
			else:
				print("[GAME] MapManager has no load_map_by_path; attempting load_map with path.")
				MapManager.load_map(map_ref)
		else:
			# Treat as id (lowercase)
			if MapManager.has_method("load_map"):
				print("[GAME] Loading map by id: ", map_ref)
				MapManager.load_map(StringName(map_ref))
			else:
				push_warning("[GAME] MapManager missing load_map method; cannot load by id.")
	else:
		_map_loading_active = false
		print("[GAME] No map ref provided; trying to spawn controller without loading a new map.")
		_try_spawn_pending_controller()

func _is_scene_path(s: String) -> bool:
	# Godot 4 can use res://, user://, and uid://
	return s.begins_with("res://") or s.begins_with("user://") or s.begins_with("uid://")

func _try_spawn_pending_controller() -> void:
	# Nothing to spawn?
	if _pending_controller_scene == null and _pending_controller_script == null and String(_pending_controller_ref) == "":
		print("[GAME] _try_spawn_pending_controller: nothing pending.")
		return

	print("[GAME] Spawning controller...")
	# Previous controller already destroyed in begin_* methods

	var ctrl: GameControllerBase = null

	# Prefer direct sources from ModeData
	if _pending_controller_scene:
		ctrl = _pending_controller_scene.instantiate() as GameControllerBase
		print("[GAME] Controller instantiated from scene: ", ctrl)
	elif _pending_controller_script:
		var obj = _pending_controller_script.new()
		ctrl = obj as GameControllerBase
		print("[GAME] Controller instantiated from script: ", ctrl)
	else:
		print("[GAME] Instantiating controller by key: ", _pending_controller_ref)
		ctrl = _instantiate_controller(_pending_controller_ref)

	if ctrl == null:
		push_warning("[GAME] Could not instantiate controller from pending data.")
		# If we were not loading a map, we should hide the overlay to avoid getting stuck
		if not _map_loading_active and Main.instance:
			Main.instance.hide_loading()
		return

	_current_controller = ctrl

	# Call attach_to_game(self) dynamically if present
	var oc: Object = _current_controller
	if oc.has_method("attach_to_game"):
		oc.call("attach_to_game", self)
	# Optionally set 'game' property if present
	var has_game_prop := false
	for p in _current_controller.get_property_list():
		if typeof(p) == TYPE_DICTIONARY and p.has("name") and String(p["name"]) == "game":
			has_game_prop = true
			break
	if has_game_prop:
		_current_controller.set("game", self)

	var parent_node: Node = _controllers_container if _controllers_container != null else self
	parent_node.add_child(_current_controller)

	_current_controller.on_enter(_pending_controller_params)
	print("[GAME] Controller on_enter called: ", _current_controller)

	# Notify readiness if already ready
	if _current_map != null and _map_ready_flag:
		_current_controller.on_map_ready(_current_map)

	# If we are not waiting on a map load, hide the overlay now
	if not _map_loading_active and Main.instance:
		Main.instance.hide_loading()

	# Clear pending
	_pending_controller_ref = ""
	_pending_controller_params = {}
	_pending_controller_scene = null
	_pending_controller_script = null

func _instantiate_controller(ref: String) -> GameControllerBase:
	# .tscn path?
	if ref.ends_with(".tscn"):
		var pscene := load(ref) as PackedScene
		if pscene:
			return pscene.instantiate() as GameControllerBase
	# .gd path?
	if ref.ends_with(".gd"):
		var scr := load(ref)
		if scr:
			return (scr.new() as GameControllerBase)

	# Key: compare lowercase
	var key := String(ref).to_lower()
	match key:
		"prefight":
			return PreFightController.new()
		"versus":
			return VersusModeController.new()
		"strongestwins":
			return ModeStrongestWinsController.new()
		"livewindows":
			return ModeLiveWindowsController.new()
		"commandstyle":
			return ModeCommandStyleController.new()
		_:
			push_warning("[GAME] Unknown controller key: " + key)
			return null

func _destroy_current_controller() -> void:
	if _current_controller:
		_current_controller.on_exit()
		_current_controller.queue_free()
		print("[GAME] Destroyed previous controller.")
		_current_controller = null

# ---------------------------------------------
# Spawning helpers (local vs. networked)
# ---------------------------------------------
# Spawn a local-only node or scene under the current level container (cleaned with the map).
func spawn_local(thing, parent: Node = null) -> Node:
	var p := parent if parent != null else level_container
	var node: Node = null
	if thing is PackedScene:
		node = thing.instantiate()
	elif thing is Node:
		node = thing
	else:
		push_error("[Game] spawn_local: unsupported type (needs Node or PackedScene).")
		return null
	p.add_child(node)
	return node

# Unified spawn: route to NetRoot for multiplayer, or LevelContainer for local.
func spawn(thing, multiplayer: bool = false, parent: Node = null) -> Node:
	if multiplayer:
		if thing is PackedScene:
			return Main.instance.spawn_networked_scene(thing, parent)
		elif thing is Node:
			var p := parent if parent != null else Main.instance.get_net_root()
			p.add_child(thing)
			return thing
		else:
			push_error("[Game] spawn (multiplayer): unsupported type; use a PackedScene or Node.")
		return null
	else:
		return spawn_local(thing, parent)

# Preferred networked spawning via MultiplayerSpawner by scene id/key.
func spawn_networked_by_id(scene_id: StringName, data:Variant = null) -> Node:
	return Main.instance.spawn_networked_with_spawner(scene_id, data)

# External input pass-through (optional route from hardware to game to controller)
func on_punch(source_id: int, force: float) -> void:
	if _current_controller:
		_current_controller.on_punch(source_id, force)

# Debug flag helper
func debug_enabled() -> bool:
	return OS.is_debug_build()
