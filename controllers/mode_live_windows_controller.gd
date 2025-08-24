extends GameControllerBase
class_name ModeLiveWindowsController

@export var duration_sec: float = 60.0
@export var window_every_sec: float = 5.0
@export var window_len_sec: float = 1.0

var _time_left: float = 0.0
var _window_time: float = 0.0
var _in_window: bool = false
var _map: Node3D
var _hits: Array[Dictionary] = [] # [{t:float, src:int, force:float}]

func on_enter(params: Dictionary) -> void:
	duration_sec = float(params.get("duration_sec", duration_sec))
	window_every_sec = float(params.get("window_every_sec", window_every_sec))
	window_len_sec = float(params.get("window_len_sec", window_len_sec))
	_time_left = duration_sec
	_window_time = window_every_sec
	_in_window = false
	_hits.clear()
	if game.debug_enabled():
		print("[LiveWindows] enter d=", duration_sec, " every=", window_every_sec, " len=", window_len_sec)

func on_exit() -> void:
	if game.debug_enabled():
		print("[LiveWindows] exit. Hits=", _hits)

func on_map_ready(map_instance: Node3D) -> void:
	_map = map_instance
	if game.debug_enabled():
		print("[LiveWindows] map ready")

func tick(delta: float) -> void:
	_time_left = max(0.0, _time_left - delta)
	_window_time = max(0.0, _window_time - delta)
	if not _in_window and _window_time <= 0.0:
		_in_window = true
		_window_time = window_len_sec
		if game.debug_enabled():
			print("[LiveWindows] WINDOW OPEN")
	elif _in_window and _window_time <= 0.0:
		_in_window = false
		_window_time = window_every_sec
		if game.debug_enabled():
			print("[LiveWindows] WINDOW CLOSE")
	if _time_left <= 0.0:
		if game.debug_enabled():
			print("[LiveWindows] finished. Hits=", _hits)

func on_punch(source_id: int, force: float) -> void:
	if not _in_window:
		return
	_hits.append({ "t": (duration_sec - _time_left), "src": source_id, "force": force })
	if game.debug_enabled():
		print("[LiveWindows] hit t=", (duration_sec - _time_left), " src=", source_id, " f=", force)
