extends GameControllerBase
class_name ModeCommandStyleController

@export var light_threshold: float = 5.0
@export var heavy_threshold: float = 12.0

var _map: Node3D
var _queue_by_source: Dictionary = {} # source_id -> Array[StringName]

func on_enter(params: Dictionary) -> void:
	light_threshold = float(params.get("light_threshold", light_threshold))
	heavy_threshold = float(params.get("heavy_threshold", heavy_threshold))
	_queue_by_source.clear()
	if game.debug_enabled():
		print("[CommandStyle] enter lt=", light_threshold, " ht=", heavy_threshold)

func on_exit() -> void:
	if game.debug_enabled():
		print("[CommandStyle] exit. Queues=", _queue_by_source)

func on_map_ready(map_instance: Node3D) -> void:
	_map = map_instance
	if game.debug_enabled():
		print("[CommandStyle] map ready")

func on_punch(source_id: int, force: float) -> void:
	var cmd: StringName = &"light"
	if force >= heavy_threshold:
		cmd = &"heavy"
	elif force >= light_threshold:
		cmd = &"medium"
	if not _queue_by_source.has(source_id):
		_queue_by_source[source_id] = []
	var q: Array = _queue_by_source[source_id]
	q.append(cmd)
	_queue_by_source[source_id] = q
	if game.debug_enabled():
		print("[CommandStyle] src=", source_id, " -> cmd=", String(cmd))
