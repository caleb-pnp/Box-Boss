extends Node3D
class_name Game

static var instance: Game

signal state_changed(state)
signal game_ready(game: Game)

# The number of nodes to add per frame.
# Adjust this number based on performance. Higher is faster but can cause stutter.
const BATCH_SIZE = 50

@onready var main = Main.instance
@onready var gui_manager:Control = $GUILayer/GUI_Manager
@onready var level_container:Node3D = $LevelContainer


# -- Variables tracking current game state ---
var _current_map: Node3D

func _enter_tree() -> void:
	# in enter tree, as will be run before children node's ready function
	Game.instance = self


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Connect to Command Manager
	main.connect("scene_command", _on_scene_command)

	# Connect to Map Manager
	MapManager.connect("map_loaded", _on_map_manager_map_loaded)
	MapManager.connect("loading_progress", _on_map_manager_loading_progress)

	# Check for Game ROLE
	if main.game_network_role == Main.NetworkRole.ROLE_SERVER:
		# Join Game as SERVER
		_join_game_as_server()
	elif main.game_network_role == Main.NetworkRole.ROLE_CLIENT:
		# Join Game as CLIENT
		_join_game_as_client()

	# Emit Game Ready Signal
	game_ready.emit(self)

func _exit_tree() -> void:
	# Disconnect from Command Manager
	if main.is_connected("scene_command", _on_scene_command):
		main.disconnect("scene_command", _on_scene_command)

	# Disconnect from Map Manager
	if MapManager.map_loaded.is_connected(_on_map_manager_map_loaded):
		MapManager.map_loaded.disconnect(_on_map_manager_map_loaded)

	if MapManager.loading_progress.is_connected(_on_map_manager_loading_progress):
		MapManager.loading_progress.disconnect(_on_map_manager_loading_progress)

	if Game.instance == self:
		Game.instance = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		main.execute_command("restart")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_scene_command(command: String, args: Array) -> void:
	## ALL CLIENTS
	if command == "leave":
		# restart
		main.execute_command("restart", [])
	## SERVER ONLY
	if multiplayer.is_server():
		match(command):
			"start":
				# when server clicks 'start' for the first time
				pass

# When we are the SERVER
func _join_game_as_server() -> void:
	# double check we are server
	if not multiplayer.is_server():
		return

	# get player name
	var player_name = main.settings.player_name + " (ID: 1)"


# When we are the CLIENT
func _join_game_as_client() -> void:
	# double check we are NOT server
	if multiplayer.is_server():
		return

	# get player name
	var player_name = main.settings.player_name + " (ID: " + str(multiplayer.get_unique_id()) + ")"


# Connected to the MapManager loading in progress function
func _on_map_manager_loading_progress(progress: float) -> void:
	# pass loading progress to GUI manager
	gui_manager.show_loading(progress)

# Connected to the MapManager finished loading function
func _on_map_manager_map_loaded(packed_scene: PackedScene) -> void:
	# First, clear out any old map that might be in the container.
	clear_old_map()

	print("[GAME] Map instance loaded, adding into level container.")

	await get_tree().process_frame

	# instance the packed scene
	var instance = packed_scene.instantiate()

	# Update our tracking variable.
	_current_map = instance

	# connect to signals
	if not instance.is_connected("map_ready", _on_map_instance_map_ready):
		instance.connect("map_ready", _on_map_instance_map_ready)

	# add to container
	$LevelContainer.add_child(instance)
#

# Dynamically called by map instance when finished added to scene
func _on_map_instance_map_ready() -> void:
	pass

func clear_old_map() -> void:
	# First, clear out any old map that might be in the container.
	for child in level_container.get_children():
		child.queue_free()

	if _current_map != null:
		_current_map = null
