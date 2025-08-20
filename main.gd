#Main.gd
class_name Main
extends Node3D

## We need a full game MAIN container that contains the MultiplayerSpawner. This is because
## the Spawner needs to live in the ROOT node forever; between Scene changes, otherwise
## it fails to catch up spawning objects to mid/late joining clients.

## enums
enum NetworkRole { ROLE_NONE, ROLE_SERVER, ROLE_CLIENT }

## signals
signal scene_command(command:String, args:Array) # propogates signals

## settings storage
const SETTINGS_FILE_PATH = "user://client_settings.tres"
var settings: ClientSettings # container for game settings
var game_network_role = NetworkRole.ROLE_NONE # queued up game mode between scenes

## singleton pattern
static var instance: Main

## scene loading
# Preload your loading screen scene
@export var loading_screen: PackedScene = preload("res://engine/loading_screen.tscn")
@onready var scene_container = $SceneContainer # container that will hold scene
var current_scene_instance: Node = null # active scene root node
var is_loading: bool = false

## main menu scene
@export var main_menu_screen: PackedScene = preload("res://menu.tscn")

## game scene
@export var game_scene_path: String = "res://game.tscn"

## alert dialog system
@onready var alert_dialog = $AlertLayer/AcceptDialog
var queued_alert_messages: Array = []

## connected device system
@onready var connected_device_reconnect_timer: Timer = $ConnectedDeviceReconnectTimer
var track_device_connection: bool = false
var connected_device_id: String = ""
var connected_device_retry_attempts: int = 0

## current user logged in
var current_user_data: Dictionary

# Final calculated results
var current_game_distance_m: float = 0.0
var average_game_speed_kph: float = 0.0
var total_game_time_s: float = 0.0
var moving_time_s: float = 0.0

# Internal tracking variables
var _is_game_active: bool = false
var _last_speed_update_time: float = 0.0 # For calculating time deltas
var _game_start_time_ms: int = 0 # For calculating total time
var _last_game_countdown: int = 0

# Variables to store the state of cumulative data
var _start_distance_m: float = 0.0
var _latest_distance_m: float = 0.0
var _has_received_distance_signal: bool = false

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	# Disconnect from Network Manager
	NetworkManager.disconnect("game_hosted", _on_game_hosted)
	NetworkManager.disconnect("connected_to_server", _on_connected_to_server)
	NetworkManager.disconnect("connection_failed", _on_connection_failed)

	# Disconnect from Serial Manager
	SerialManager.disconnect("serial_connection_opened", _on_serial_connection_opened)
	SerialManager.disconnect("device_connected", _on_device_connected)
	SerialManager.disconnect("device_connection_failed", _on_device_connection_failed)
	SerialManager.disconnect("device_disconnected", _on_device_disconnected)
	SerialManager.disconnect("data_update", _on_serial_data_for_stats)

## --- Initialization ---
func _ready() -> void:
	# Initializes the random number generator with a random seed
	randomize()

	# Load settings from Existing
	if ResourceLoader.exists(SETTINGS_FILE_PATH):
		settings = ResourceLoader.load(SETTINGS_FILE_PATH)
	else:
		settings = ClientSettings.new()

	# Connect to Network Manager
	NetworkManager.connect("game_hosted", _on_game_hosted)
	NetworkManager.connect("connected_to_server", _on_connected_to_server)
	NetworkManager.connect("connection_failed", _on_connection_failed)

	# Connect to Serial Manager (and start)
	SerialManager.connect("serial_connection_opened", _on_serial_connection_opened)
	SerialManager.connect("device_connected", _on_device_connected)
	SerialManager.connect("device_connection_failed", _on_device_connection_failed)
	SerialManager.connect("device_disconnected", _on_device_disconnected)
	SerialManager.connect("data_update", _on_serial_data_for_stats)
	SerialManager.start()

	# Start on Main Menu
	_change_scene_to_main_menu()

func save_settings():
	var err = ResourceSaver.save(settings, SETTINGS_FILE_PATH)
	if err != OK:
		print("[MAIN] Error saving client settings: %s" % err)
	else:
		print("[MAIN] Saved client settings")

## --- Scene Changer Functions ---
func _change_scene(scene_path: String):
	# If we are already loading a scene, ignore this new request.
	if is_loading:
		return
	is_loading = true

	# Remove the old scene (e.g., the main menu or previous game level)
	if is_instance_valid(current_scene_instance):
		current_scene_instance.queue_free()

	# CRITICAL: Wait until the next idle frame to start the new process.
	# This ensures the old scene's signals can't interfere.
	call_deferred("_start_loading_process", scene_path)

# This new helper function contains the rest of the logic.
func _start_loading_process(scene_path: String):
	# Now that we're on a clean frame, create the loading screen.
	var loading_screen_instance = loading_screen.instantiate()

	# Connect the signal. There's no old instance to conflict with.
	loading_screen_instance.load_complete.connect(_on_load_complete)
	loading_screen_instance.load_failed.connect(_on_load_failed)

	# Add it to the tree and set it as the current instance.
	scene_container.add_child(loading_screen_instance)
	current_scene_instance = loading_screen_instance

	# Start the load.
	loading_screen_instance.start_load(scene_path)

# instant switch without loading screen
func _change_scene_to_main_menu():
	# If we are already loading a scene, ignore this new request.
	if is_loading:
		return
	is_loading = true

	# if multiplayer peer is set, destroy it
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

	# remove the current scene instance
	if is_instance_valid(current_scene_instance):
		current_scene_instance.queue_free()

	# clear scene container
	for child in scene_container.get_children():
		child.queue_free()

	# Instantiate the the preloaded main menu, and add to container
	var new_scene_instance = main_menu_screen.instantiate()
	scene_container.add_child(new_scene_instance)
	current_scene_instance = new_scene_instance

	# Set Network Role back to NONE
	game_network_role = NetworkRole.ROLE_NONE

	# Clear connect device
	connected_device_id = ""
	connected_device_retry_attempts = 0

	# display queued messages on load
	display_queued_messages()

	# set loading to false
	is_loading = false

func _on_load_complete(loaded_scene_resource: PackedScene):
	# Remove the loading screen
	if is_instance_valid(current_scene_instance):
		current_scene_instance.queue_free()

	# Instantiate the new, fully-loaded scene
	var new_scene_instance = loaded_scene_resource.instantiate()

	# Add it to the container
	scene_container.add_child(new_scene_instance)
	current_scene_instance = new_scene_instance

	# Reset the flag so we can change scenes again.
	is_loading = false

func _on_load_failed(target_scene_path: String):
	# Reset the flag so we can change scenes again.
	is_loading = false

	# return back to main menu
	_change_scene_to_main_menu()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

## -- Functions for Alert Message Queu System ---
func add_alert_message(message: String) -> void:
	queued_alert_messages.append(message)

func display_queued_messages() -> void:
	# Use a 'while' loop to safely process and remove items from the queue
	while not queued_alert_messages.is_empty():
		# Get the first message from the front of the queue
		var message = queued_alert_messages.front()

		alert_dialog.dialog_text = message
		alert_dialog.popup_centered()

		# Pause here until the user clicks "OK"
		await alert_dialog.confirmed

		# NEW: Once confirmed, remove the message we just showed
		queued_alert_messages.pop_front()

## -- Command Executor Functions ---
func execute_command(command: String, args: Array = []):
	print("[MAIN] Executing command: ", command, " with args: ", args)

	match command.to_lower():
		## --- Main Specific Commands ---
		# Join or Host
		"join_or_host":
			# join or host with default args
			NetworkManager.start_discovery()
		# Host a Game
		"host":
			# update args
			if int(args[0]) > 0:
				settings.host_port = int(args[0])
			if int(args[1]) > 0:
				settings.host_max_players = clampi(args[1], 1, 32)

			# Manually Host a game
			initiate_equipment_connection()
			NetworkManager.host_game(settings.host_port, settings.host_max_players)

		# Join a Game (Requires initial Network Connection First)
		"join":
			# update args
			if str(args[0]) != "":
				settings.join_ip = str(args[0])
			if int(args[1]) > 0:
				settings.join_port = int(args[1])

			# Try Join Game
			initiate_equipment_connection()
			NetworkManager.join_game(settings.join_ip, settings.join_port)

		# Restart the Game
		"restart":
			# Call the new comprehensive shutdown function on the NetworkManager
			# (Assuming your NetworkManager is an autoload/singleton named "NetworkManager")
			NetworkManager.stop_hosting()

			# Now, proceed with changing the scene
			_change_scene_to_main_menu()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

		## --- Scene Commands ---
		# Used to start a game in game
		"start":
			scene_command.emit("start", args)
		# Unknown commands
		_:
			print("Unknown command: ", command)


## --- Network Manager Functions and Connection Callbacks ---
func _on_game_hosted():
	game_network_role = NetworkRole.ROLE_SERVER
	_change_scene(game_scene_path) # USE NEW METHOD

func _on_connected_to_server():
	# Now that we're connected, load the game scene
	game_network_role = NetworkRole.ROLE_CLIENT
	_change_scene(game_scene_path)

func _on_connection_failed():
	# Go back to the menu. The loading screen won't be shown.
	add_alert_message("Connection to the server timed out.")
	_change_scene_to_main_menu()

func force_spawned_nodes_catchup():
	for child in scene_container.get_children():
		# each child should have a force catchup state
		pass

# --- Input functions ---
func _on_serial_connection_opened():
	pass

func _on_device_connected(device_id: String) -> void:
	# Store the ID of this device as the one we want to keep alive.
	connected_device_id = device_id
	track_device_connection = true
	print("Main is now tracking connected device. Reconnect attempts set to 20.")
	connected_device_retry_attempts = 20

	# If the reconnect timer was running, we've succeeded, so stop it.
	if not connected_device_reconnect_timer.is_stopped():
		connected_device_reconnect_timer.stop()

func _on_device_connection_failed(device_id: String) -> void:
	if connected_device_id != device_id:
		connected_device_id = device_id
		track_device_connection = true
		print("Main is now tracking unconnected device. Reconnect attempts set to 5.")
		connected_device_retry_attempts = 5

	# try reconnect
	if connected_device_retry_attempts > 0 and connected_device_reconnect_timer.is_stopped():
		print("Attempting reconnect in 5 seconds...")
		connected_device_reconnect_timer.start()


func _on_device_disconnected(device_id: String) -> void:
	if connected_device_id == device_id:
		print("Tracked device disconnected. " + str(connected_device_retry_attempts) + " reconnection attempts remaining...")

		if connected_device_retry_attempts > 0 and connected_device_reconnect_timer.is_stopped():
			print("Attempting reconnect in 5 seconds...")
			connected_device_reconnect_timer.start()


func _on_connected_device_reconnect_timer_timeout() -> void:
	print("Attempting to reconnect to device...")
	if track_device_connection:
		if connected_device_retry_attempts > 0:
			SerialManager.connect_to_device(connected_device_id)
			connected_device_retry_attempts -= 1
		else:
			print("Exhausted reconnection attempts. Stopping until game restart.")

func _on_game_started() -> void:
	"""Resets stats and captures start time."""
	print("Main: Game started, resetting stats.")
	# Reset final results
	current_game_distance_m = 0.0
	average_game_speed_kph = 0.0
	total_game_time_s = 0.0
	moving_time_s = 0.0

	# Reset internal trackers
	_start_distance_m = 0.0
	_latest_distance_m = 0.0
	_has_received_distance_signal = false

	# Set the game to active and record start times
	var current_time_ms = Time.get_ticks_msec()
	_game_start_time_ms = current_time_ms
	_last_speed_update_time = current_time_ms / 1000.0
	_is_game_active = true

func _on_game_finished() -> void:
	"""Finalizes calculations and posts session data at the end of a game."""
	print("Main: Game finished, finalizing stats.")
	_is_game_active = false

	# --- Final Calculations ---

	# 1. Calculate Total Game Time from start to finish.
	total_game_time_s = (Time.get_ticks_msec() - _game_start_time_ms) / 1000.0

	# 2. Calculate final distance.
	if _has_received_distance_signal:
		current_game_distance_m = _latest_distance_m - _start_distance_m

	# 3. Calculate Average Speed based on MOVING time.
	if moving_time_s > 0:
		# Average speed in meters/second
		var avg_speed_mps = current_game_distance_m / moving_time_s
		# Convert to kilometers/hour for the final result
		average_game_speed_kph = avg_speed_mps * 3.6
	else:
		average_game_speed_kph = 0.0

	print("Game stats: Total Time = %ss, Moving Time = %ss, Distance = %sm, Avg Speed = %s km/h" % [total_game_time_s, moving_time_s, current_game_distance_m, average_game_speed_kph])

	# --- Post Data to API ---

	# 1. Get the current user's ID.
	var my_player_id = -1
	var current_user_data_details = current_user_data.get("details")
	if current_user_data_details:
		my_player_id = current_user_data_details.get("id", -1)
	if my_player_id == -1:
		print("Not posting stats: User not logged in.")
		return

	# 2. Get the equipment's STRING ID.
	# This is the correct VARCHAR(50) ID that the database expects.
	var equipment_id = connected_device_id

	# Safety check if no device is connected
	if equipment_id.is_empty():
		print("Not posting stats: Equipment ID is empty.")
		return

	# 3. Get the coins collected by the player.
	var collected_coins = get_local_player_coins()
	print("Coins calculated by get_coins_for_player: ", collected_coins)

	# 4. Call the API client with all the calculated data.
	OmnistatApiClient.post_pedal_faster_session(
		my_player_id,
		equipment_id, # Sending the correct string ID
		collected_coins,
		current_game_distance_m,
		total_game_time_s,
		moving_time_s,
		average_game_speed_kph
	)

	# 5. Stop equipment
	SerialManager.stop_device(equipment_id)

func _on_game_countdown(time_left: int) -> void:
	# if new countdown
	if time_left > _last_game_countdown:
		_last_game_countdown = time_left

		# if we have a connected equipment
		var equipment_id = connected_device_id
		if not equipment_id.is_empty():
			SerialManager.start_device(equipment_id)
	else:
		# same countdown, which is counting down... just update
		_last_game_countdown = time_left

func _on_serial_data_for_stats(device_id: String, value: float, type: SerialManager.Type) -> void:
	"""Listens for all data updates during the game to track stats."""
	if not _is_game_active:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var time_delta = current_time - _last_speed_update_time

	match type:
		SerialManager.Type.SPEED:
			# If speed is > 0, add the time since the last update to our moving timer.
			if value > 0.0:
				moving_time_s += time_delta

			# FALLBACK: If this device doesn't send DISTANCE, we calculate it from speed.
			if not _has_received_distance_signal:
				var speed_mps = value * 1000.0 / 3600.0
				current_game_distance_m += speed_mps * time_delta

		SerialManager.Type.DISTANCE:
			if not _has_received_distance_signal:
				_start_distance_m = value
				_has_received_distance_signal = true
			_latest_distance_m = value

	_last_speed_update_time = current_time


func initiate_equipment_connection() -> void:
	var equipment_id = Main.instance.settings.equipment_id
	if equipment_id.is_empty():
		print("No equipment selected in Settings menu to connect to. Ignoring connection.")
		return

	var device_to_connect = SerialManager.get_config_from_device_id(equipment_id)
	if device_to_connect:
		print("Attempting to connect to device: ", device_to_connect.name)
		SerialManager.connect_to_device(equipment_id)

# The function is now specifically for getting the LOCAL player's coin count.
func get_local_player_coins() -> int:
	# Get the unique peer ID of the local player running this code.
	var my_peer_id: int = multiplayer.get_unique_id()
	return 0
