extends GameControllerBase
class_name ModeStrongestWinsController

@export var turns_total: int = 10
@export var turn_window_sec: float = 5.0

var _turn_index: int = 0
var _time_left: float = 0.0
var _peaks_by_turn_and_source: Dictionary = {} # key: "turn:source" -> float
var _map: Node3D

func on_enter(params: Dictionary) -> void:
	turns_total = int(params.get("turns_total", turns_total))
	turn_window_sec = float(params.get("turn_window_sec", turn_window_sec))
	_turn_index = 0
	_time_left = turn_window_sec
	_peaks_by_turn_and_source.clear()
	if game.debug_enabled():
		print("[StrongestWins] enter turns=", turns_total, " window=", turn_window_sec)

func on_exit() -> void:
	if game.debug_enabled():
		print("[StrongestWins] exit")

func on_map_ready(map_instance: Node3D) -> void:
	_map = map_instance
	if game.debug_enabled():
		print("[StrongestWins] map ready: ", _map)

func tick(delta: float) -> void:
	if _turn_index >= turns_total:
		_finish()
		return
	_time_left = max(0.0, _time_left - delta)
	if _time_left <= 0.0:
		_turn_index += 1
		_time_left = turn_window_sec
		if game.debug_enabled():
			print("[StrongestWins] advance turn ", _turn_index, "/", turns_total)

func on_punch(source_id: int, force: float) -> void:
	if _turn_index >= turns_total:
		return
	var key: String = str(_turn_index) + ":" + str(source_id)
	var current_peak: float = float(_peaks_by_turn_and_source.get(key, 0.0))
	if force > current_peak:
		_peaks_by_turn_and_source[key] = force
		if game.debug_enabled():
			print("[StrongestWins] turn=", _turn_index, " src=", source_id, " peak=", force)

func _finish() -> void:
	if game.debug_enabled():
		print("[StrongestWins] finished. Peaks=", _peaks_by_turn_and_source)
