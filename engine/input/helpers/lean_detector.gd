# LeanDetector.gd
class_name LeanDetector
extends Node

enum ThrowHand {
	LEFT,
	RIGHT
}

signal throw_detected(hand: ThrowHand)

var lean_axis: float = 0.0

const COMMAND_PORT = 4245
const LEAN_DATA_PORT = 4242
const THROW_DATA_PORT = 4243
const IP_ADDRESS = "127.0.0.1"

var _lean_server := UDPServer.new()
var _throw_server := UDPServer.new()
var _lean_peer: PacketPeerUDP
var _throw_peer: PacketPeerUDP
var _command_peer := PacketPeerUDP.new()

func _ready() -> void:
	if _lean_server.listen(LEAN_DATA_PORT) != OK:
		printerr("LeanDetector: Error listening for lean data on port: ", LEAN_DATA_PORT)
	else:
		print("LeanDetector: Listening successfully for lean data on port ", LEAN_DATA_PORT)

	if _throw_server.listen(THROW_DATA_PORT) != OK:
		printerr("LeanDetector: Error listening for throw data on port: ", THROW_DATA_PORT)
	else:
		print("LeanDetector: Listening successfully for throw data on port ", THROW_DATA_PORT)

	# DO NOT connect the command peer here. We will set the destination before sending.

func _process(_delta: float) -> void:
	_lean_server.poll()
	_throw_server.poll()

	if _lean_server.is_connection_available():
		_lean_peer = _lean_server.take_connection()
	if _lean_peer != null and _lean_peer.get_available_packet_count() > 0:
		var lean_str = _lean_peer.get_packet().get_string_from_utf8()
		if lean_str.is_valid_float():
			lean_axis = lean_str.to_float()

	if _throw_server.is_connection_available():
		_throw_peer = _throw_server.take_connection()
	if _throw_peer != null and _throw_peer.get_available_packet_count() > 0:
		var throw_str = _throw_peer.get_packet().get_string_from_utf8()
		var parts = throw_str.split(",")
		if parts.size() == 2:
			if parts[0] == "1":
				emit_signal("throw_detected", ThrowHand.LEFT)
			if parts[1] == "1":
				emit_signal("throw_detected", ThrowHand.RIGHT)

func get_lean_axis() -> float:
	return lean_axis

# --- MODIFIED: Use set_dest_address for reliable sending ---
func activate():
	print("Activating Lean Detector...")
	_command_peer.set_dest_address(IP_ADDRESS, COMMAND_PORT)
	_command_peer.put_packet("ACQUIRE".to_utf8_buffer())

func deactivate():
	print("Deactivating Lean Detector...")
	_command_peer.set_dest_address(IP_ADDRESS, COMMAND_PORT)
	_command_peer.put_packet("RELEASE".to_utf8_buffer())

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_lean_server.stop()
		_throw_server.stop()
