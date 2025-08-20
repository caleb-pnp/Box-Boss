# client_settings.gd
class_name ClientSettings
extends Resource

@export var host_port: int = 7777
@export var host_max_players: int = 32

@export var join_ip: String = "127.0.0.1"
@export var join_port: int = 7777

@export var player_name: String = "Player"

@export var equipment_id: String = ""
@export var equipment_settings: Dictionary = {
	"BIKE": {
		"max_speed": 50.0,
		"lean_multiplier": 1.0
	},
	"TREADMILL": {
		"max_speed": 15.0,
		"lean_multiplier": 1.0
	},
	"CROSSTRAINER": {
		"max_speed": 15.0,
		"lean_multiplier": 1.0
	},
	"ROWER": {
		"max_speed": 15.0,
		"lean_multiplier": 1.0
	}
}


func reset_to_defaults():
	host_port = 7777
	host_max_players = 32
	join_ip = "127.0.0.1"
	join_port = 7777
	player_name = "Player"
	equipment_id = ""
	equipment_settings = {
		"BIKE": {
			"max_speed": 50.0,
			"lean_multiplier": 1.0
		},
		"TREADMILL": {
			"max_speed": 15.0,
			"lean_multiplier": 1.0
		},
		"CROSSTRAINER": {
			"max_speed": 15.0,
			"lean_multiplier": 1.0
		},
		"ROWER": {
			"max_speed": 15.0,
			"lean_multiplier": 1.0
		}
	}
