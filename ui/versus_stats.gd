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
	_ensure_player_panels()
	_left = get_node_or_null(left_path)
	_right = get_node_or_null(right_path)
	_timer = get_node_or_null(timer_path)

func _ensure_player_panels():
	if _left == null:
		_left = Control.new()
		_left.name = "Left"
		add_child(_left)
		_left.anchor_left = 0.0
		_left.anchor_right = 0.5
		_left.anchor_top = 0.0
		_left.anchor_bottom = 0.0
		_left.offset_left = 10
		_left.offset_right = -10
		_left.offset_top = 10
		_left.offset_bottom = 60
		_ensure_attack_queue(_left)

	if _right == null:
		_right = Control.new()
		_right.name = "Right"
		add_child(_right)
		_right.anchor_left = 0.5
		_right.anchor_right = 1.0
		_right.anchor_top = 0.0
		_right.anchor_bottom = 0.0
		_right.offset_left = 10
		_right.offset_right = -10
		_right.offset_top = 10
		_right.offset_bottom = 60
		_ensure_attack_queue(_right)

	# Add Name and Health for Left
	if _left.get_node_or_null("Name") == null:
		var name_label = Label.new()
		name_label.name = "Name"
		name_label.anchor_left = 0.0
		name_label.anchor_right = 1.0
		name_label.offset_left = 0
		name_label.offset_right = 0
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_left.add_child(name_label)
	if _left.get_node_or_null("Health") == null:
		var health_bar = ProgressBar.new()
		health_bar.name = "Health"
		health_bar.anchor_left = 0.0
		health_bar.anchor_right = 1.0
		health_bar.offset_left = 0
		health_bar.offset_right = 0
		health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		health_bar.position.y = 24
		_left.add_child(health_bar)

	# Add Name and Health for Right
	if _right.get_node_or_null("Name") == null:
		var name_label = Label.new()
		name_label.name = "Name"
		name_label.anchor_left = 0.0
		name_label.anchor_right = 1.0
		name_label.offset_left = 0
		name_label.offset_right = 0
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_right.add_child(name_label)
	if _right.get_node_or_null("Health") == null:
		var health_bar = ProgressBar.new()
		health_bar.name = "Health"
		health_bar.anchor_left = 0.0
		health_bar.anchor_right = 1.0
		health_bar.offset_left = 0
		health_bar.offset_right = 0
		health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		health_bar.position.y = 24
		_right.add_child(health_bar)

func _ensure_attack_queue(panel: Control) -> VBoxContainer:
	var queue = panel.get_node_or_null("AttackQueue") as VBoxContainer
	if queue == null:
		queue = VBoxContainer.new()
		queue.name = "AttackQueue"
		queue.anchor_left = 0.0
		queue.anchor_right = 1.0
		queue.anchor_top = 0.0
		queue.anchor_bottom = 0.0
		queue.offset_left = 0
		queue.offset_right = 0
		queue.offset_top = 48  # below health bar (adjust as needed)
		queue.offset_bottom = 120  # gives it height (adjust as needed)
		panel.add_child(queue)
	return queue

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
	_refresh_health(0)
	_refresh_health(1)

	# --- Attack queue integration ---
	for i in range(_players.size()):
		var actor = _players[i]
		var panel = _left if i == 0 else _right
		_ensure_attack_queue(panel) # Make sure the queue container exists
		# Connect to attack_queued signal if not already connected
		if actor and actor.combat:
			var cc = actor.combat
			if cc and not cc.is_connected("attack_queued", Callable(self, "_on_attack_queued").bind(i)):
				cc.connect("attack_queued", Callable(self, "_on_attack_queued").bind(i))

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
	if actor and actor.stats:
		# Avoid duplicate connections
		if not actor.stats.is_connected("health_changed", Callable(self, "_on_health_changed").bind(i)):
			actor.stats.connect("health_changed", Callable(self, "_on_health_changed").bind(i))
	# Optionally, update immediately
	_refresh_health(i)

func _on_health_changed(current: int, max: int, i: int) -> void:
	var panel = _left if i == 0 else _right
	_update_health_bar(panel, current, max)

func _refresh_health(i: int) -> void:
	var actor = _players[i]
	var panel = _left if i == 0 else _right
	var current = actor.stats.health if actor and actor.stats else 0
	var max_value = actor.stats.max_health if actor and actor.stats else 100
	_update_health_bar(panel, current, max_value)

func _update_health_bar(panel: Control, current: float, max_value: float) -> void:
	var bar = panel.get_node_or_null("Health")
	if bar == null:
		return
	bar.max_value = max_value
	bar.value = clamp(current, 0.0, max_value)

# Handler for attack_queued signal
func _on_attack_queued(punch_type: String, force: float, i: int) -> void:
	var panel = _left if i == 0 else _right
	add_attack_entry(panel, punch_type, force)

func add_attack_entry(panel: Control, punch_type: String, force: float):
	var queue = _ensure_attack_queue(panel)
	var label = Label.new()
	label.text = "%s (%.0f)" % [punch_type, force]
	label.modulate = Color(1, 1, 1, 1)
	queue.add_child(label)
	# Animate fade out and removal
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(1.5)
	tween.tween_callback(Callable(label, "queue_free"))
	# Limit queue length (e.g., last 5 attacks)
	if queue.get_child_count() > 5:
		queue.get_child(0).queue_free()
