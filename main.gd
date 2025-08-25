class_name Main
extends Node3D

# Keep a permanent Main singleton
static var instance: Main

# Scene command bus (Game listens)
signal scene_command(command: String, args: Array)

# Settings
const SETTINGS_FILE_PATH = "user://client_settings.tres"
var settings: ClientSettings

# Network role
enum NetworkRole { ROLE_NONE, ROLE_SERVER, ROLE_CLIENT }
var game_network_role := NetworkRole.ROLE_NONE

# Scene management
@onready var scene_container: Node3D = $SceneContainer # the active scene
@onready var net_root: Node3D = $NetRoot # multiplayer spawner monitors this node
@onready var loading_screen_node: Node = $GUILayer/LoadingScreen # permanent loading screen instance

var current_scene_instance: Node = null
var is_loading: bool = false

# Main menu and game scene paths
@export var main_menu_screen: PackedScene = preload("res://menu.tscn")
@export var game_scene_path: String = "res://game.tscn"

# Alerts
@onready var alert_dialog: AcceptDialog = $AlertLayer/AcceptDialog
var queued_alert_messages: Array = []

# Device connection tracking (kept; not race-stat specific)
@onready var connected_device_reconnect_timer: Timer = $ConnectedDeviceReconnectTimer
var track_device_connection: bool = false
var connected_device_id: String = ""
var connected_device_retry_attempts: int = 0

# Current user context (kept for menu/auth/UI)
var current_user_data: Dictionary

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	# Disconnect from Network Manager
	if NetworkManager.is_connected("game_hosted", _on_game_hosted):
		NetworkManager.disconnect("game_hosted", _on_game_hosted)
	if NetworkManager.is_connected("connected_to_server", _on_connected_to_server):
		NetworkManager.disconnect("connected_to_server", _on_connected_to_server)
	if NetworkManager.is_connected("connection_failed", _on_connection_failed):
		NetworkManager.disconnect("connection_failed", _on_connection_failed)

	# Disconnect from Serial Manager
	if SerialManager.is_connected("serial_connection_opened", _on_serial_connection_opened):
		SerialManager.disconnect("serial_connection_opened", _on_serial_connection_opened)
	if SerialManager.is_connected("device_connected", _on_device_connected):
		SerialManager.disconnect("device_connected", _on_device_connected)
	if SerialManager.is_connected("device_connection_failed", _on_device_connection_failed):
		SerialManager.disconnect("device_connection_failed", _on_device_connection_failed)
	if SerialManager.is_connected("device_disconnected", _on_device_disconnected):
		SerialManager.disconnect("device_disconnected", _on_device_disconnected)
	# Note: no data_update connection here (race/stat logic removed)

func _ready() -> void:
	randomize()

	# Load or create settings
	if ResourceLoader.exists(SETTINGS_FILE_PATH):
		settings = ResourceLoader.load(SETTINGS_FILE_PATH)
	else:
		settings = ClientSettings.new()

	# Connect managers
	NetworkManager.connect("game_hosted", _on_game_hosted)
	NetworkManager.connect("connected_to_server", _on_connected_to_server)
	NetworkManager.connect("connection_failed", _on_connection_failed)

	SerialManager.connect("serial_connection_opened", _on_serial_connection_opened)
	SerialManager.connect("device_connected", _on_device_connected)
	SerialManager.connect("device_connection_failed", _on_device_connection_failed)
	SerialManager.connect("device_disconnected", _on_device_disconnected)
	SerialManager.start()

	# Wire permanent loading screen once
	if loading_screen_node:
		if not loading_screen_node.is_connected("load_complete", _on_load_complete):
			loading_screen_node.connect("load_complete", _on_load_complete)
		if not loading_screen_node.is_connected("load_failed", _on_load_failed):
			loading_screen_node.connect("load_failed", _on_load_failed)

	# Start at main menu
	_change_scene_to_main_menu()

func save_settings() -> void:
	var err := ResourceSaver.save(settings, SETTINGS_FILE_PATH)
	if err != OK:
		print("[MAIN] Error saving client settings: %s" % err)
	else:
		print("[MAIN] Saved client settings")

# -------------------------
# Scene change helpers
# -------------------------
func _change_scene(scene_path: String) -> void:
	if is_loading:
		return
	is_loading = true

	# Remove previous scene instance
	if is_instance_valid(current_scene_instance):
		current_scene_instance.queue_free()
		current_scene_instance = null

	# Clear the container to keep it clean (do not touch GUILayer)
	for child in scene_container.get_children():
		child.queue_free()

	# Kick off threaded load via the permanent overlay
	if loading_screen_node and loading_screen_node.has_method("start_load"):
		loading_screen_node.call("start_load", scene_path)
	else:
		# Fallback: synchronous load if overlay missing
		var res := load(scene_path)
		if res and res is PackedScene:
			_on_load_complete(res)
		else:
			_on_load_failed(scene_path)

func _change_scene_to_main_menu() -> void:
	if is_loading:
		return
	is_loading = true

	# Reset multiplayer peer on menu entry
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

	# Remove current scene instance
	if is_instance_valid(current_scene_instance):
		current_scene_instance.queue_free()
		current_scene_instance = null

	# Clear scene container
	for child in scene_container.get_children():
		child.queue_free()

	# Instantiate menu
	var new_scene_instance := main_menu_screen.instantiate()
	scene_container.add_child(new_scene_instance)
	current_scene_instance = new_scene_instance

	# Reset network role and connection tracking
	game_network_role = NetworkRole.ROLE_NONE
	connected_device_id = ""
	connected_device_retry_attempts = 0

	# Show any queued alerts
	display_queued_messages()

	is_loading = false

func _on_load_complete(loaded_scene_resource: PackedScene) -> void:
	# Instantiate and add new scene
	var new_scene_instance := loaded_scene_resource.instantiate()
	scene_container.add_child(new_scene_instance)
	current_scene_instance = new_scene_instance

	# Explicitly hide the overlay if it doesn't auto-hide
	if loading_screen_node and loading_screen_node.has_method("hide_screen"):
		loading_screen_node.call("hide_screen")

	is_loading = false

func _on_load_failed(target_scene_path: String) -> void:
	# Hide overlay on failure
	if loading_screen_node and loading_screen_node.has_method("hide_screen"):
		loading_screen_node.call("hide_screen")
	is_loading = false
	_change_scene_to_main_menu()

# -------------------------
# Alerts
# -------------------------
func add_alert_message(message: String) -> void:
	queued_alert_messages.append(message)

func display_queued_messages() -> void:
	while not queued_alert_messages.is_empty():
		var message = queued_alert_messages.front()
		alert_dialog.dialog_text = message
		alert_dialog.popup_centered()
		await alert_dialog.confirmed
		queued_alert_messages.pop_front()

# -------------------------
# Command executor
# -------------------------
func execute_command(command: String, args: Array = []) -> void:
	print("[MAIN] Executing command: ", command, " with args: ", args)

	match command.to_lower():
		"join_or_host":
			NetworkManager.start_discovery()
		"host":
			initiate_equipment_connection()
			NetworkManager.host_game(settings.host_port, settings.host_max_players)
		"join":
			initiate_equipment_connection()
			NetworkManager.join_game(settings.join_ip, settings.join_port)
		"restart":
			NetworkManager.stop_hosting()
			_change_scene_to_main_menu()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		"start":
			scene_command.emit("start", args)
		_:
			print("Unknown command: ", command)

# -------------------------
# Network callbacks
# -------------------------
func _on_game_hosted() -> void:
	game_network_role = NetworkRole.ROLE_SERVER
	_change_scene(game_scene_path)

func _on_connected_to_server() -> void:
	game_network_role = NetworkRole.ROLE_CLIENT
	_change_scene(game_scene_path)

func _on_connection_failed() -> void:
	add_alert_message("Connection to the server timed out.")
	_change_scene_to_main_menu()

# -------------------------
# Serial/device callbacks
# -------------------------
func _on_serial_connection_opened() -> void:
	pass

func _on_device_connected(device_id: String) -> void:
	connected_device_id = device_id
	track_device_connection = true
	print("Main is now tracking connected device. Reconnect attempts set to 20.")
	connected_device_retry_attempts = 20
	if not connected_device_reconnect_timer.is_stopped():
		connected_device_reconnect_timer.stop()

func _on_device_connection_failed(device_id: String) -> void:
	if connected_device_id != device_id:
		connected_device_id = device_id
		track_device_connection = true
		print("Main is now tracking unconnected device. Reconnect attempts set to 5.")
		connected_device_retry_attempts = 5
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

# -------------------------
# Equipment helpers
# -------------------------
func initiate_equipment_connection() -> void:
	var equipment_id := Main.instance.settings.equipment_id
	if equipment_id.is_empty():
		print("No equipment selected in Settings menu to connect to. Ignoring connection.")
		return
	var device_to_connect = SerialManager.get_config_from_device_id(equipment_id)
	if device_to_connect:
		print("Attempting to connect to device: ", device_to_connect.name)
		SerialManager.connect_to_device(equipment_id)

# -------------------------
# Loading overlay helpers for Game or others
# -------------------------
func show_loading(progress: float = 0.0, message: String = "") -> void:
	if not loading_screen_node:
		return
	# Use external-progress mode
	if loading_screen_node.has_method("begin_external"):
		loading_screen_node.call("begin_external", message)
	if loading_screen_node.has_method("update_progress"):
		loading_screen_node.call("update_progress", progress)

func update_loading(progress: float) -> void:
	if loading_screen_node and loading_screen_node.has_method("update_progress"):
		loading_screen_node.call("update_progress", progress)

func hide_loading() -> void:
	if not loading_screen_node:
		return
	# Ensure bar shows complete, then hide immediately (don’t rely on auto_hide_on_complete)
	if loading_screen_node.has_method("update_progress"):
		loading_screen_node.call("update_progress", 1.0)
	if loading_screen_node.has_method("hide_screen"):
		loading_screen_node.call("hide_screen")

# -------------------------
# UI host helpers (GUILayer/UIContainer)
# -------------------------
func get_ui_host() -> Control:
	var layer := get_node_or_null("GUILayer") as CanvasLayer
	if not layer:
		return null
	return layer.get_node_or_null("UIContainer") as Control

# Add an already-instantiated UI control
func add_ui(node: Control) -> void:
	var host := get_ui_host()
	if not host or not node:
		return
	host.add_child(node)

# Instantiate and mount a UI scene; returns the control so controller can keep a ref
func mount_ui(scene: PackedScene) -> Control:
	var host := get_ui_host()
	if not host or not scene:
		return null
	var node := scene.instantiate() as Control
	if node:
		host.add_child(node)
	return node

# Remove a specific UI node
func remove_ui(node: Node) -> void:
	if node and is_instance_valid(node):
		node.queue_free()

# Clear all UI under UIContainer (e.g., when switching controllers)
func clear_ui() -> void:
	var host := get_ui_host()
	if not host:
		return
	for child in host.get_children():
		child.queue_free()

# -------------------------
# Networked spawn helpers (NetRoot)
# -------------------------
# Get or create the NetRoot (permanent parent for networked entities)
func get_net_root() -> Node3D:
	var n: Node3D = null
	if is_instance_valid(net_root):
		n = net_root
	else:
		n = get_node_or_null("NetRoot") as Node3D
	if n == null:
		n = Node3D.new()
		n.name = "NetRoot"
		add_child(n)
	net_root = n
	return n

# Try to locate a MultiplayerSpawner under NetRoot.
# - Returns the first child that is a MultiplayerSpawner.
# - Falls back to a node named "Spawner" if types can’t be checked.
func get_net_spawner() -> Node:
	var root := get_net_root()
	# Preferred: find by type
	for child in root.get_children():
		# Avoid strict typing to keep this flexible if MultiplayerSpawner isn’t compiled here
		if child.get_class() == "MultiplayerSpawner":
			return child
	# Fallback by common names
	var by_name := root.get_node_or_null("Spawner")
	if by_name:
		return by_name
	var by_alt := root.get_node_or_null("MultiplayerSpawner")
	return by_alt

# Spawn a networked scene under NetRoot directly (basic pattern).
# Note: for late joiners and deterministic spawning, prefer using a MultiplayerSpawner.
func spawn_networked_scene(scene: PackedScene, parent: Node = null) -> Node:
	if scene == null:
		push_error("[Main] spawn_networked_scene: scene is null.")
		return null
	var node := scene.instantiate()
	var p := parent if parent != null else get_net_root()
	p.add_child(node)
	return node

# Preferred: spawn via MultiplayerSpawner so late joiners reconstruct the same objects.
# The exact API of your spawner may differ; this calls a generic "spawn" method if present.
func spawn_networked_with_spawner(scene_id: StringName, data:Variant = null) -> Node:
	var spawner := get_net_spawner()
	if spawner == null:
		push_error("[Main] No MultiplayerSpawner found under NetRoot. Cannot spawn networked with spawner.")
		return null
	if not spawner.has_method("spawn"):
		push_error("[Main] MultiplayerSpawner has no 'spawn' method; wire up your spawn callback.")
		return null
	# Typically call from the server/authority
	return spawner.call("spawn", scene_id, data)

# Optional: clear all networked entities (keeps the spawner node if present)
func clear_net_root(keep_spawner: bool = true) -> void:
	var root := get_net_root()
	for child in root.get_children():
		var is_spawner := child.get_class() == "MultiplayerSpawner" or child.name == "Spawner" or child.name == "MultiplayerSpawner"
		if keep_spawner and is_spawner:
			continue
		child.queue_free()
