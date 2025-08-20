# LoginInputVideoReceiver is a standalone TextureRect which receives the login video stream.
extends TextureRect

# MODIFIED: Port now matches the omnistat_login.py sender's default
const VIDEO_PORT = 5006

var server := UDPServer.new()
var peer: PacketPeerUDP

var current_frame_buffer: PackedByteArray = PackedByteArray()
var current_frame_id: int = -1

# Header size is 8 bytes (32-bit frame_id + 32-bit chunk_index)
const HEADER_SIZE = 8

func _ready() -> void:
	if server.listen(VIDEO_PORT) != OK:
		printerr("LoginReceiver: Error listening on video port: ", VIDEO_PORT)
	else:
		print("LoginReceiver: Listening for video stream on port ", VIDEO_PORT)

	set_expand_mode(EXPAND_IGNORE_SIZE)
	set_stretch_mode(STRETCH_KEEP_ASPECT_COVERED)

func _process(_delta: float) -> void:
	server.poll()

	if server.is_connection_available():
		peer = server.take_connection()
		print("LoginReceiver: Login video connection accepted.")

	if peer != null:
		while peer.get_available_packet_count() > 0:
			var packet_data: PackedByteArray = peer.get_packet()

			if packet_data.size() < HEADER_SIZE:
				continue

			var stream = StreamPeerBuffer.new()
			stream.data_array = packet_data
			stream.set_big_endian(true)

			var frame_id: int = stream.get_u32()
			var chunk_index: int = stream.get_u32()
			var chunk_data: PackedByteArray = packet_data.slice(HEADER_SIZE)

			if frame_id != current_frame_id:
				current_frame_buffer.clear()
				current_frame_id = frame_id

			if chunk_index == 0xFFFFFFFF: # End-of-frame signal
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
