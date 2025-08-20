# OmnistatApiClient.gd - SINGLETON
extends Node

# --- NEW SIGNALS ---
signal user_details_received(details: Dictionary)
signal user_game_data_received(data: Dictionary)

# --- EXISTING SIGNALS ---
signal user_settings_received(settings: Dictionary)
signal equipment_list_received(equipment_data: Variant)
signal request_succeeded(response_data: Dictionary)
signal request_failed(status_code: int, error_message: String)
signal request_timed_out

@export var api_base_url = "http://192.168.0.127:5000/api"
@export var timeout: float = 10.0

var http_request: HTTPRequest

func _exit_tree() -> void:
	if http_request:
		if http_request.request_completed.is_connected(_on_request_completed):
			http_request.request_completed.disconnect(_on_request_completed)


func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	http_request.timeout = timeout

# --- NEW: Get User Details Function ---
# Fetches basic user info (id, name, coins).
func get_user_details(user_id: int) -> void:
	var temp_http_request = HTTPRequest.new()
	add_child(temp_http_request)
	temp_http_request.timeout = timeout

	temp_http_request.request_completed.connect(
		_on_get_user_details_completed.bind(temp_http_request),
		CONNECT_ONE_SHOT
	)

	var url = "%s/users/%s" % [api_base_url, user_id]
	var error = temp_http_request.request(url, [], HTTPClient.METHOD_GET)

	if error != OK:
		print_rich("[color=red]API Error: Could not start GET user details request.[/color]")
		user_details_received.emit(null)
		temp_http_request.queue_free()

func _on_get_user_details_completed(result, response_code, headers, body, temp_http_request):
	var details_data = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json_parser = JSON.new()
		if json_parser.parse(body.get_string_from_utf8()) == OK:
			details_data = json_parser.get_data()

	user_details_received.emit(details_data)
	temp_http_request.queue_free()

# --- NEW: Get User Game Data Stack Function ---
# Fetches the complete data package for a user (details, settings, etc.).
func get_user_game_data(user_id: int) -> void:
	var temp_http_request = HTTPRequest.new()
	add_child(temp_http_request)
	temp_http_request.timeout = timeout

	temp_http_request.request_completed.connect(
		_on_get_user_game_data_completed.bind(temp_http_request),
		CONNECT_ONE_SHOT
	)

	var url = "%s/users/%s/gamedata" % [api_base_url, user_id]
	var error = temp_http_request.request(url, [], HTTPClient.METHOD_GET)

	if error != OK:
		print_rich("[color=red]API Error: Could not start GET user gamedata request.[/color]")
		user_game_data_received.emit(null)
		temp_http_request.queue_free()

func _on_get_user_game_data_completed(result, response_code, headers, body, temp_http_request):
	var game_data = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json_parser = JSON.new()
		if json_parser.parse(body.get_string_from_utf8()) == OK:
			game_data = json_parser.get_data()

	user_game_data_received.emit(game_data)
	temp_http_request.queue_free()


# --- Existing GET Functions (Unchanged) ---
func get_user_settings(user_id: int) -> void:
	var temp_http_request = HTTPRequest.new()
	add_child(temp_http_request)
	temp_http_request.timeout = timeout
	temp_http_request.request_completed.connect(
		_on_get_user_settings_completed.bind(temp_http_request),
		CONNECT_ONE_SHOT
	)
	var url = "%s/users/%s/settings" % [api_base_url, user_id]
	var error = temp_http_request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		print_rich("[color=red]API Error: Could not start GET user settings request.[/color]")
		user_settings_received.emit(null)
		temp_http_request.queue_free()

func _on_get_user_settings_completed(result, response_code, headers, body, temp_http_request):
	var settings_data = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var json_parser = JSON.new()
		if json_parser.parse(body.get_string_from_utf8()) == OK:
			settings_data = json_parser.get_data()
	user_settings_received.emit(settings_data)
	temp_http_request.queue_free()

func get_equipment() -> void:
	var temp_http_request = HTTPRequest.new()
	add_child(temp_http_request)
	temp_http_request.timeout = timeout
	temp_http_request.request_completed.connect(
		_on_get_equipment_completed.bind(temp_http_request),
		CONNECT_ONE_SHOT
	)
	var url = api_base_url + "/equipment"
	var error = temp_http_request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		print_rich("[color=red]API Error: Could not start GET equipment request.[/color]")
		equipment_list_received.emit(null)
		temp_http_request.queue_free()

func _on_get_equipment_completed(result, response_code, headers, body, temp_http_request):
	var response_data = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var json_parser = JSON.new()
		if json_parser.parse(body.get_string_from_utf8()) == OK:
			response_data = json_parser.get_data()
	equipment_list_received.emit(response_data)
	temp_http_request.queue_free()


# --- Session Posting Functions and Handlers (Unchanged) ---
func post_boxing_session(user_id: int, punches: int, force: float):
	var url = api_base_url + "/sessions/boxing"
	var body = { "user_id": user_id, "punches": punches, "force": force }
	_make_post_request(url, body)

func post_containment_session(user_id: int, gates_closed: int, distance: float):
	var url = api_base_url + "/sessions/containment"
	var body = { "user_id": user_id, "gates_closed": gates_closed, "distance": distance }
	_make_post_request(url, body)

func post_pedal_faster_session(
	user_id: int,
	equipment_id: String,
	coins_earned: int,
	distance_m: float,
	total_time_s: float,
	moving_time_s: float,
	average_speed_kph: float
):
	var url = api_base_url + "/sessions/pedalfaster"

	var body = {
		"user_id": user_id,
		"equipment_id": equipment_id,
		"coins_earned": coins_earned,
		"distance_m": distance_m,
		"total_time_s": total_time_s,
		"moving_time_s": moving_time_s,
		"average_speed_kph": average_speed_kph
	}

	print("Posting Pedal Faster session data to %s" % url)
	_make_post_request(url, body)

func _make_post_request(url: String, body: Dictionary):
	var json_body = JSON.stringify(body)
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		print_rich("[color=red]API Error: Could not start the HTTP request.[/color]")
		request_failed.emit(-1, "Could not start request.")

func _on_request_completed(result, response_code, headers, body):
	match result:
		HTTPRequest.RESULT_SUCCESS:
			var response_data = JSON.parse_string(body.get_string_from_utf8())
			if response_code >= 200 and response_code < 300:
				print_rich("[color=green]API Success (Code: %s)[/color]" % response_code)
				request_succeeded.emit(response_data)
			else:
				print_rich("[color=red]API Failure (Code: %s)[/color]" % response_code)
				var error_msg = "Unknown error"
				if response_data and response_data.has("error"):
					error_msg = response_data.error
				request_failed.emit(response_code, error_msg)
		HTTPRequest.RESULT_TIMEOUT:
			print_rich("[color=orange]API Error: Request timed out.[/color]")
			request_timed_out.emit()
		_:
			print_rich("[color=red]API Error: Network or connection error.[/color]")
			request_failed.emit(result, "Network or connection error.")
