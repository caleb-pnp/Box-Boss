extends Control
class_name VersusStats

# Minimal, assumes a structure:
# VersusStats (Control)
#  ├─ TimerLabel (Label)                # optional
#  ├─ Left (Control)
#  │   ├─ Name (Label)
#  │   └─ Health (TextureProgressBar or ProgressBar)
#  └─ Right (Control)
#      ├─ Name (Label)
#      └─ Health (TextureProgressBar or ProgressBar)

@export var left_path: NodePath = ^"Left"
@export var right_path: NodePath = ^"Right"
@export var timer_path: NodePath = ^"TimerLabel"

var _left: Control
var _right: Control
var _timer: Label

var _players: Array = []

func _ready() -> void:
	_left = get_node_or_null(left_path)
	_right = get_node_or_null(right_path)
	_timer = get_node_or_null(timer_path)

func set_players(players: Array) -> void:
	_players = players.duplicate()
	# Names (fallback to node name)
	if _left:
		var name_l := _left.get_node_or_null(^"Name") as Label
		if name_l:
			name_l.text = _get_player_name(0)
	if _right:
		var name_r := _right.get_node_or_null(^"Name") as Label
		if name_r:
			name_r.text = _get_player_name(1)
	# Connect health updates if characters expose signals
	_connect_health_signal(0, _left)
	_connect_health_signal(1, _right)
	# Initialize bars if we can read current values now
	_refresh_health(0, _left)
	_refresh_health(1, _right)

func set_timer(seconds_left: int) -> void:
	if _timer:
		_timer.text = str(seconds_left)

func _get_player_name(i: int) -> String:
	if i >= _players.size():
		return "?"
	var p = _players[i]
	if p and p.has_method("get_display_name"):
		return p.get_display_name()
	return String(p.name)

func _connect_health_signal(i: int, panel: Control) -> void:
	if i >= _players.size() or panel == null:
		return
	var actor = _players[i]
	# Common naming: "health_changed(current, max)"
	if actor.has_signal("health_changed"):
		if not actor.is_connected("health_changed", Callable(self, "_on_health_changed").bind(i, panel)):
			actor.connect("health_changed", Callable(self, "_on_health_changed").bind(i, panel))
	# If no signal, we'll just sample when set_players is called.

func _on_health_changed(current: float, max_value: float, i: int, panel: Control) -> void:
	_update_health_bar(panel, current, max_value)

func _refresh_health(i: int, panel: Control) -> void:
	if i >= _players.size() or panel == null:
		return
	var actor = _players[i]
	var current := 100.0
	var max_value := 100.0
	if actor.has_method("get_health"):
		current = float(actor.get_health())
	if actor.has_method("get_health_max"):
		max_value = float(actor.get_health_max())
	_update_health_bar(panel, current, max_value)

func _update_health_bar(panel: Control, current: float, max_value: float) -> void:
	var bar := panel.get_node_or_null(^"Health")
	if bar == null:
		return
	# Support ProgressBar or TextureProgressBar
	if "max_value" in bar:
		bar.max_value = max_value
	if "value" in bar:
		bar.value = clamp(current, 0.0, max_value)
