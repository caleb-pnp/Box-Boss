# LeanInputVideoReceiver is a standalone TextureRect which receives video input
extends TextureRect

# MODIFIED: Port now matches the Python sender's default
const VIDEO_PORT = 4244

var server := UDPServer.new()
var peer: PacketPeerUDP

var current_frame_buffer: PackedByteArray = PackedByteArray()
var current_frame_id: int = -1

# MODIFIED: Header size is now 8 bytes (32-bit frame_id + 32-bit chunk_index)
const HEADER_SIZE = 8

func _ready() -> void:
	if server.listen(VIDEO_PORT) != OK:
		print("VideoReceiver: Error listening on video port: ", VIDEO_PORT)
	else:
		print("VideoReceiver: Listening for video stream on port ", VIDEO_PORT)

	# These settings are good, no changes needed here
	set_expand_mode(EXPAND_IGNORE_SIZE)
	set_stretch_mode(STRETCH_KEEP_ASPECT_COVERED)

func _process(_delta: float) -> void:
	server.poll()

	if server.is_connection_available():
		peer = server.take_connection()
		print("VideoReceiver: LeanDetector video connection accepted.")

	if peer != null:
		while peer.get_available_packet_count() > 0:
			var packet_data: PackedByteArray = peer.get_packet()

			if packet_data.size() < HEADER_SIZE:
				continue

			var stream = StreamPeerBuffer.new()
			stream.data_array = packet_data
			# Python's '!' format specifier is big-endian
			stream.set_big_endian(true)

			# MODIFIED: Read both frame_id and chunk_index as 32-bit unsigned integers
			var frame_id: int = stream.get_u32()
			var chunk_index: int = stream.get_u32()
			var chunk_data: PackedByteArray = packet_data.slice(HEADER_SIZE)

			if frame_id != current_frame_id:
				current_frame_buffer.clear()
				current_frame_id = frame_id

			# MODIFIED: Check for the correct 32-bit end-of-frame signal
			if chunk_index == 0xFFFFFFFF:
				var image := Image.new()
				if image.load_jpg_from_buffer(current_frame_buffer) == OK:
					var img_tex := ImageTexture.create_from_image(image)
					self.texture = img_tex
				current_frame_buffer.clear()
			else:
				current_frame_buffer.append_array(chunk_data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		server.stop()
