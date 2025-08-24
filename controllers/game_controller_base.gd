extends Node
class_name GameControllerBase

# Base interface for all game mode controllers (host-only for now)

@export var requires_map_ready: bool = true
var game: Game

func attach_to_game(g: Game) -> void:
	game = g

func on_enter(params: Dictionary) -> void:
	pass

func on_exit() -> void:
	pass

func on_map_ready(map_instance: Node3D) -> void:
	pass

func tick(_delta: float) -> void:
	pass

func on_punch(_source_id: int, _force: float) -> void:
	pass
