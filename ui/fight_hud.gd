extends CanvasLayer
class_name FightHUD

# Layer 0: stats; Layer 1: overlay (countdown, banners)
@export var stats_layer_path: NodePath = ^"StatsLayer"
@export var overlay_layer_path: NodePath = ^"OverlayLayer"
@export var countdown_node_path: NodePath = ^"OverlayLayer/CountdownOverlay"
@export var stats_node_path: NodePath = ^"StatsLayer/VersusStats"
@export var canvas_layer_order: int = 10  # keep on top of other UI

var _countdown: Node
var _stats: Node
var _stats_layer: Control
var _overlay_layer: Control

func _ready() -> void:
	print("[FightHUD] _ready")
	layer = canvas_layer_order

	_stats_layer = get_node_or_null(stats_layer_path)
	_overlay_layer = get_node_or_null(overlay_layer_path)
	_countdown = get_node_or_null(countdown_node_path)
	_stats = get_node_or_null(stats_node_path)

	# Force full-rect layout for layers (handy if the scene wasn’t laid out in editor)
	if _stats_layer:
		_stats_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		_stats_layer.visible = true
	if _overlay_layer:
		_overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay_layer.visible = true

	print("[FightHUD] countdown node: ", str(_countdown))
	print("[FightHUD] stats node: ", str(_stats))
	print("[FightHUD] layer: ", str(layer))

	# One frame later, print sizes
	call_deferred("_debug_print_rects")

func _debug_print_rects() -> void:
	await get_tree().process_frame
	var vp_rect: Rect2i = get_viewport().get_visible_rect()
	var vp_size: Vector2i = vp_rect.size
	var stats_size: Vector2 = _stats_layer.size if _stats_layer else Vector2.ZERO
	var overlay_size: Vector2 = _overlay_layer.size if _overlay_layer else Vector2.ZERO
	print("[FightHUD] viewport size: ", str(vp_size))
	print("[FightHUD] stats_layer size: ", str(stats_size))
	print("[FightHUD] overlay_layer size: ", str(overlay_size))

func bind_players(players: Array) -> void:
	print("[FightHUD] bind_players: ", str(players.size()))
	if _stats and _stats.has_method("set_players"):
		_stats.set_players(players)
	else:
		print("[FightHUD][WARN] Stats node missing or set_players() not found")

func show_countdown(seconds: int = 5) -> void:
	print("[FightHUD] show_countdown(", str(seconds), ")")
	if _countdown and _countdown.has_method("play"):
		await _countdown.play(seconds)
		print("[FightHUD] show_countdown finished")
	else:
		print("[FightHUD][ERROR] Countdown node missing or no play() method")

func set_timer_seconds_left(seconds_left: int) -> void:
	if _stats and _stats.has_method("set_timer"):
		_stats.set_timer(seconds_left)
