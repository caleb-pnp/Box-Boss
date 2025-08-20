extends Node

signal game_hosted() # server side
signal player_connected(player_id:int) # server side
signal player_disconnected(player_id:int) # server side
signal connected_to_server # client side
signal connection_failed # client side

const DEFAULT_IP = "127.0.0.1"
const DEFAULT_PORT = 7777
const DEFAULT_MAX_PLAYERS = 32
const JOIN_TIMEOUT_S = 5.0

const DISCOVERY_PORT = 42420
const DISCOVERY_TIMEOUT_S = 3.0
const DISCOVERY_MESSAGE = "OMNISTAT_GAME_HOST"

var peer: ENetMultiplayerPeer
var _join_timeout_timer: Timer
var _broadcast_timer: Timer
var _discovery_timer: Timer

var _discovery_socket: PacketPeerUDP
var _is_discovering := false


func _init() -> void:
	# Timer for when a client attempts to join a server
	_join_timeout_timer = Timer.new()
	_join_timeout_timer.one_shot = true
	_join_timeout_timer.timeout.connect(_on_join_timeout)
	add_child(_join_timeout_timer)

	# Timer for the host to periodically broadcast its presence
	_broadcast_timer = Timer.new()
	_broadcast_timer.wait_time = 1.0
	_broadcast_timer.timeout.connect(_on_broadcast_timeout)
	add_child(_broadcast_timer)

	# Timer to limit how long we listen for hosts
	_discovery_timer = Timer.new()
	_discovery_timer.one_shot = true
	_discovery_timer.timeout.connect(_on_discovery_timeout)
	add_child(_discovery_timer)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


# --- NEW: Main entry point for starting or finding a game ---
func start_discovery():
	if multiplayer.get_multiplayer_peer():
		print("[NetworkManager] Already connected or hosting.")
		return

	print("[NetworkManager] Starting LAN discovery...")
	_discovery_socket = PacketPeerUDP.new()

	# Use bind() to listen for broadcasts on the discovery port
	if _discovery_socket.bind(DISCOVERY_PORT, "*") != OK:
		printerr("[NetworkManager] Failed to bind discovery socket. Cannot discover games.")
		_discovery_socket = null # Clear the socket object
		return

	_is_discovering = true
	_discovery_timer.start(DISCOVERY_TIMEOUT_S)
	print("[NetworkManager] Listening for hosts for %s seconds..." % DISCOVERY_TIMEOUT_S)


func _process(_delta: float) -> void:
	if not _is_discovering:
		return

	while _discovery_socket.get_available_packet_count() > 0:
		var sender_ip: String = _discovery_socket.get_packet_ip()
		var packet := _discovery_socket.get_packet()

		# --- MODIFIED: Parse JSON and check timestamp ---

		# 1. Attempt to parse the incoming packet as JSON.
		var json = JSON.new()
		if json.parse(packet.get_string_from_utf8()) != OK:
			continue # Not valid JSON, ignore packet.

		var broadcast_data: Dictionary = json.data

		# 2. Check if it's a valid discovery message.
		if broadcast_data.get("msg") == DISCOVERY_MESSAGE:
			# 3. Check for staleness.
			var host_timestamp = broadcast_data.get("timestamp", 0)
			var current_timestamp = Time.get_unix_time_from_system()
			var age_seconds = current_timestamp - host_timestamp

			if age_seconds > 30:
				print("[NetworkManager] Ignored stale broadcast (age: %d seconds)." % age_seconds)
				continue # Packet is too old, ignore it.

			# 4. Check for self-broadcast (same as before).
			var my_local_ips = IP.get_local_addresses()
			if sender_ip.is_empty() or sender_ip in my_local_ips:
				print("[NetworkManager] Ignored own broadcast.")
				continue

			# 5. If all checks pass, it's a valid, live host.
			print("[NetworkManager] Found valid game host at: %s" % sender_ip)
			_cleanup_discovery()
			join_game(sender_ip, DEFAULT_PORT)
			break

func _notification(what):
	# This is called when the user clicks the 'X' on the window
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_hosting() # Use the new, complete function

func _exit_tree():
	# This is called when the scene is about to be removed
	stop_hosting() # Use the new, complete function


func host_game(port:int, max_players:int):
	if port <= 0: port = DEFAULT_PORT
	if max_players <= 0: max_players = DEFAULT_MAX_PLAYERS

	print("[NetworkManager SERVER] Starting server...")
	peer = ENetMultiplayerPeer.new()
	if peer.create_server(port, max_players) != OK:
		print("[NetworkManager SERVER] Failed to create server.")
		return

	multiplayer.multiplayer_peer = peer
	print("[NetworkManager SERVER] Server started successfully on port %d." % port)

	game_hosted.emit()
	_broadcast_timer.start()


func join_game(ip_address: String, port:int):
	if ip_address == "": ip_address = DEFAULT_IP
	if port <= 0: port = DEFAULT_PORT

	print("[NetworkManager CLIENT] Joining server at %s:%s..." % [ip_address, port])
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip_address, port) != OK:
		print("[NetworkManager CLIENT] Failed to create client.")
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	_join_timeout_timer.start(JOIN_TIMEOUT_S)


# --- Discovery Callbacks and Helpers ---
func _on_discovery_timeout():
	# This runs if the discovery timer finishes without finding any hosts
	print("[NetworkManager] Discovery timeout. No hosts found.")
	_cleanup_discovery()
	print("[NetworkManager] Becoming the host.")
	host_game(DEFAULT_PORT, DEFAULT_MAX_PLAYERS)


func _cleanup_discovery():
	_is_discovering = false
	if _discovery_timer.time_left > 0:
		_discovery_timer.stop()
	if _discovery_socket:
		_discovery_socket.close()
		_discovery_socket = null


# --- Server Side Callbacks (Unchanged) ---
func _on_player_connected(player_id: int):
	print("[NetworkManager SERVER] Player connected: %d" % player_id)
	player_connected.emit(player_id)

func _on_player_disconnected(player_id: int):
	print("[NetworkManager SERVER] Player disconnected: %d" % player_id)
	player_disconnected.emit(player_id)


# --- Client Side Callbacks (Unchanged) ---
func _on_connected_to_server() -> void:
	_join_timeout_timer.stop()
	print("[NetworkManager CLIENT] Successfully connected to server!")
	connected_to_server.emit()

func _on_connection_failed() -> void:
	_join_timeout_timer.stop()
	multiplayer.multiplayer_peer = null
	print("[NetworkManager CLIENT] Connection failed.")
	connection_failed.emit()

func _on_join_timeout() -> void:
	multiplayer.multiplayer_peer = null
	print("[NetworkManager CLIENT] Connection timed out.")
	connection_failed.emit()


func _on_broadcast_timeout():
	var broadcast_socket := PacketPeerUDP.new()
	broadcast_socket.set_broadcast_enabled(true)

	if broadcast_socket.connect_to_host("255.255.255.255", DISCOVERY_PORT) == OK:
		# --- MODIFIED: Create a JSON payload ---

		# 1. Create a dictionary for the broadcast message.
		var broadcast_data = {
			"msg": DISCOVERY_MESSAGE,
			"timestamp": Time.get_unix_time_from_system()
		}

		# 2. Convert the dictionary to a JSON string, then to a data buffer.
		var packet = JSON.stringify(broadcast_data).to_utf8_buffer()

		# 3. Send the packet.
		broadcast_socket.put_packet(packet)
		broadcast_socket.close()

func stop_hosting():
	# Stop sending "I'm a host" broadcast packets
	if _broadcast_timer.time_left > 0:
		_broadcast_timer.stop()

	# Close the server and disconnect clients
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	print("[NetworkManager] Hosting has been stopped.")
