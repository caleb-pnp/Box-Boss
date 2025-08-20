# SerialManager.gd - SINGLETON
extends Control

# Enum and Signals
enum Type{
	SPEED, DISTANCE, RPM, ENERGY, POWER, PULSE, TIME
}

var DeviceConfigs: Dictionary = {
	"TREADMILL_1": { "name": "FS-50D164", "mac": "27112feff940", "type": "TREADMILL" },
	"CROSSTRAINER_1": { "name": "XT-39", "mac": "42a834e1d188", "type": "CROSSTRAINER" },
	"BIKE_1": { "name": "FS-50D164", "mac": "299a08049226", "type": "BIKE" },
}

signal serial_connection_opened()
signal device_connected(device_id:String)
signal device_connection_failed(device_id:String)
signal device_disconnected(device_id:String)
signal data_update(device_id:String, data:float, type:Type)
signal scan_update(dev_name:String, dev_address: String)

# Class variables
var serial := GdSerial.new()
var baudrate := 115200
var bad_ports:Dictionary = {}
var timer_countdown:float = 0.0
var try_reconnect:bool = false
var current_port: String = ""
var buffer: String = ""


func _get_device_id_from_mac(mac_address: String) -> String:
	for device_id in DeviceConfigs.keys():
		var device_info = DeviceConfigs[device_id]
		if device_info.mac.to_lower() == mac_address.to_lower():
			return device_id
	return ""

func get_config_from_device_id(device_id: String) -> Variant:
	if DeviceConfigs.has(device_id):
		return DeviceConfigs[device_id]
	return null

func _exit_tree() -> void:
	if OmnistatApiClient.equipment_list_received.is_connected(_on_equipment_list_received):
		OmnistatApiClient.equipment_list_received.disconnect(_on_equipment_list_received)

func _ready() -> void:
	OmnistatApiClient.equipment_list_received.connect(_on_equipment_list_received)


func start() -> void:
	print("SerialManager: Requesting device list from API...")
	OmnistatApiClient.get_equipment()


func _on_equipment_list_received(api_response: Variant) -> void:
	if api_response and api_response.has("equipment"):
		var fetched_devices: Array = api_response["equipment"]
		if not fetched_devices.is_empty():
			var new_device_configs: Dictionary = {}
			for device in fetched_devices:
				if device.has_all(["id", "mac", "type"]):
					new_device_configs[device.id] = {
						"name": device.get("name", "N/A"),
						"mac": device.mac,
						"type": device.type,
					}
			DeviceConfigs = new_device_configs
			print("SerialManager: Successfully updated device list from API. Found %d devices." % DeviceConfigs.size())
		else:
			print("SerialManager: API returned no devices. Using hardcoded list.")
	else:
		print("SerialManager: Failed to fetch device list from API. Using hardcoded list.")

	print("Port List")
	print("---------")

	var port_list := serial.list_ports()
	var port = null
	for port_name_key in port_list.keys():
		var port_obj = port_list[port_name_key]
		var port_name_string = port_obj["port_name"]

		if port_obj.has("port_type") and "USB" in port_obj["port_type"]:
			if bad_ports.has(port_name_string) and bad_ports[port_name_string] >= 3:
				print(port_name_string + " (ignored, failed connection 3 times)")
			else:
				print(port_name_string)
				port = port_name_string
		else:
			print(port_name_string + "(ignored, not USB)")

	if port != null:
		start_connection(port, baudrate)
	else:
		print("No viable ports to connect to.")
		check_for_connection()


func start_connection(connection_port: String, connection_baudrate: int):
	if connection_port != null:
		print("Connecting to port: " + connection_port)
		serial.set_port(connection_port)
		serial.set_baud_rate(connection_baudrate)

		if serial.open():
			print("Port opened successfully!")
			try_reconnect = false
			current_port = connection_port
			serial_connection_opened.emit()
		else:
			_on_error("open", "Failed to open port: " + connection_port)


func connect_to_device(device_id: String) -> void:
	var device_config = get_config_from_device_id(device_id)
	if device_config:
		var device_mac = device_config.mac
		var device_type = device_config.type
		send_remove_all()
		send_connect(device_mac, device_type)
	else:
		print("Could not get device configuration")

func start_device(device_id: String) -> void:
	var device_config = get_config_from_device_id(device_id)
	if device_config:
		var device_mac = device_config.mac
		send_start(device_mac)
		send_speed(device_mac, 0)
		await get_tree().create_timer(2.0).timeout
		send_start(device_mac)
		send_speed(device_mac, 1)
	else:
		print("Could not get device configuration")

func stop_device(device_id: String) -> void:
	var device_config = get_config_from_device_id(device_id)
	if device_config:
		var device_mac = device_config.mac
		send_stop(device_mac)
	else:
		print("Could not get device configuration")


func _process(delta: float) -> void:
	if timer_countdown > 0:
		timer_countdown -= delta

	if timer_countdown <= 0 and try_reconnect:
		try_reconnect = false
		start()
		return

	if serial.is_open():
		# First, store the result of the function call in a variable.
		var available_bytes = serial.bytes_available()
		if available_bytes > 0:
			# Success, and there's data to read.
			_on_data_received()
	else:
		# If the port is not open, and we are not already in a retry loop,
		# trigger the check. This handles unexpected disconnections.
		if not try_reconnect and current_port != "":
			check_for_connection()


func _on_data_received():
	var data_string = serial.read_string(serial.bytes_available())
	buffer += data_string
	while true:
		var semicolon_index = buffer.find(";")
		var newline_index = buffer.find("\n")
		if semicolon_index == -1 and newline_index == -1:
			break
		var delimiter_index = -1
		if semicolon_index != -1 and (newline_index == -1 or semicolon_index < newline_index):
			delimiter_index = semicolon_index
		elif newline_index != -1:
			delimiter_index = newline_index
		if delimiter_index == -1:
			break
		var message = buffer.substr(0, delimiter_index)
		buffer = buffer.substr(delimiter_index + 1)

		if semicolon_index != -1 and (newline_index == -1 or semicolon_index < newline_index):
			print(Time.get_time_string_from_system() + "   [REPLY]" + message + "[/REPLY]")
			var clean_message = message.strip_edges()
			if clean_message.is_empty():
				continue
			var sections = clean_message.split(",", false)
			var devName = ""
			var devAdr = "" # MAC address from Arduino
			var device_id = "" # Logical ID from DeviceConfigs

			for section in sections:
				var parts = section.strip_edges().split(":", false)
				if parts.size() >= 2 and parts[0].strip_edges() == "ADDRESS":
					devAdr = parts[1].strip_edges()
					device_id = _get_device_id_from_mac(devAdr)
					break

			for section in sections:
				var clean_section = section.strip_edges()
				if clean_section.is_empty(): continue
				var parts = clean_section.split(":", false)
				if parts.size() < 2: continue

				var prefix = parts[0].strip_edges()
				var value_string = parts[1].strip_edges()

				match prefix:
					"CONNECTED":
						var connected_mac = str(value_string)
						var connected_id = _get_device_id_from_mac(connected_mac)
						if not connected_id.is_empty():
							print("Device connected: %s (ID: %s)" % [connected_mac, connected_id])
							device_connected.emit(connected_id)
						else:
							print("Warning: An unknown device connected with MAC: %s" % connected_mac)
					"CONNECT_FAILED":
						var connected_mac = str(value_string)
						var connected_id = _get_device_id_from_mac(connected_mac)
						if not connected_id.is_empty():
							print("Device connection failed: %s (ID: %s)" % [connected_mac, connected_id])
							device_connection_failed.emit(connected_id)
						else:
							print("Warning: An unknown device connected with MAC: %s" % connected_mac)
					"DISCONNECTED":
						var disconnected_mac = str(value_string)
						var disconnected_id = _get_device_id_from_mac(disconnected_mac)
						if not disconnected_id.is_empty():
							print("Device disconnected: %s (ID: %s)" % [disconnected_mac, disconnected_id])
							device_disconnected.emit(disconnected_id)
						else:
							print("Warning: An unknown device disconnected with MAC: %s" % disconnected_mac)
					"SPEED", "RPM", "DISTANCE", "ENERGY", "POWER", "PULSE", "TIME":
						if not device_id.is_empty():
							var value = value_string.to_float()
							data_update.emit(device_id, value, Type[prefix])
					"NAME":
						devName = str(value_string)
						scan_update.emit(devName, devAdr)
					"ADDRESS":
						pass
					_:
						print("Unknown prefix received: " + prefix)
		else:
			pass


func _on_error(where, what):
	if current_port and not bad_ports.has(current_port):
		bad_ports[current_port] = 1
	elif current_port:
		bad_ports[current_port] += 1

	print("Got error when %s: %s" % [where, what])
	check_for_connection()


func check_for_connection():
	if not serial.is_open():
		if current_port != "":
			print("Serial connection lost. Retrying in 10 seconds...")
		else:
			print("Failed to find or open a serial port. Retrying in 10 seconds...")

		timer_countdown = 10.0
		try_reconnect = true
	else:
		print("Serial %s is (still) connected" % [current_port])


func send_data(data_string:String):
	if serial.is_open():
		print(Time.get_time_string_from_system() + "; Sending data: " + data_string)
		if not serial.write_string(data_string):
			_on_error("write", "Failed to write data to port")
	else:
		print(Time.get_time_string_from_system() + "; Cannot send data (no port open): " + data_string)


func send_connect(mac_address:String, device_type:String = ""):
	var data = "CONNECT:" + str(mac_address) + ":" + str(device_type) + ";"
	send_data(data)

func send_scan_devices():
	var data = "SCAN;"
	send_data(data)

func send_list_connected():
	var data = "LIST;"
	send_data(data)

func send_remove(mac_address: String):
	var data = "REMOVE:" + mac_address + ";"
	send_data(data)

func send_remove_all():
	var data = "REMOVE:ALL;"
	send_data(data)

func send_start(mac_address: String):
	var data = "SEND:START:" + mac_address + ";"
	send_data(data)

func send_stop(mac_address: String):
	var data = "SEND:STOP:" + mac_address + ";"
	send_data(data)

func send_speed(mac_address: String, speed:int):
	var data = "SEND:SPEED:" + mac_address + ":" + str(speed) + ";"
	send_data(data)

# resistance
func send_res(mac_address: String, res:int):
	var data = "SEND:RES:" + mac_address + ":" + str(res) + ";"
	send_data(data)
