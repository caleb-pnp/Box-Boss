# LoginDetector.gd
extends Node

## Emitted when a user successfully logs in.
signal login_successful(user_id)

const COMMAND_PORT = 4246
const DATA_PORT = 5005
const IP_ADDRESS = "127.0.0.1"

var _data_server := UDPServer.new()
var _peer: PacketPeerUDP

# MODIFIED: The correct class for sending UDP packets in Godot 4 is PacketPeerUDP.
var _command_peer := PacketPeerUDP.new()

func _ready() -> void:
	if _data_server.listen(DATA_PORT) != OK:
		printerr("LoginDetector: Error listening on port: ", DATA_PORT)
	else:
		print("LoginDetector: Listening successfully for login data on port ", DATA_PORT)

	# MODIFIED: Set the destination for the command peer.
	_command_peer.connect_to_host(IP_ADDRESS, COMMAND_PORT)

func _process(_delta: float) -> void:
	_data_server.poll()

	if _data_server.is_connection_available():
		_peer = _data_server.take_connection()
		print("LoginDetector: Connection from Python script accepted.")

	if _peer != null and _peer.get_available_packet_count() > 0:
		var data: PackedByteArray = _peer.get_packet()
		var user_id_str: String = data.get_string_from_utf8()

		if user_id_str.is_valid_int():
			var user_id = user_id_str.to_int()
			print("Login Detector received User ID: ", user_id)
			emit_signal("login_successful", user_id)

func activate():
	print("Activating Login Detector...")
	# MODIFIED: The correct method to send a packet is put_packet().
	_command_peer.put_packet("ACQUIRE".to_ascii_buffer())

func deactivate():
	print("Deactivating Login Detector...")
	_command_peer.put_packet("RELEASE".to_ascii_buffer())

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_data_server.stop()
