extends CharacterBody3D
class_name BaseCharacter

signal attacked(strength: float)
signal attack_landed(strength: float)
signal took_hit(amount: int)
signal knocked_out

@export_category("Movement")
@export var walk_speed: float = 4.0
@export var strafe_speed: float = 3.5
@export var backpedal_speed: float = 3.0
@export var run_speed: float = 6.0
@export var turn_speed_deg: float = 720.0
@export var use_gravity: bool = true
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") if ProjectSettings.has_setting("physics/3d/default_gravity") else 9.81

@export_category("Combat")
@export var keep_eyes_on_target: bool = true
@export var min_attack_distance: float = 1.6
@export var max_attack_distance: float = 2.6
@export var attack_cooldown_sec: float = 0.8
@export var light_attack_threshold: float = 0.3
@export var medium_attack_threshold: float = 0.7

@export_category("Scene References")
@export var navigation_agent_path: NodePath
@export var stats_node_path: NodePath
@export var animator_path: NodePath # CharacterAnimator node

@export_category("Navigation / Autopilot")
@export var use_agent_autopilot: bool = true
@export var move_arrival_tolerance: float = 0.25
@export var desired_fight_distance: float = 2.1
@export var fight_distance_tolerance: float = 0.25
@export var run_distance_threshold: float = 6.0

@export_category("Debug")
@export var debug_enabled: bool = false
@export var debug_interval: float = 0.25
var _debug_accum: float = 0.0

var anim: AnimationPlayer
var agent: NavigationAgent3D
var stats: Node
var animator: CharacterAnimator

# Target can be a Node3D or a Vector3
var _target_node: Node3D
var _target_point: Vector3
var _has_target: bool = false

enum TargetMode { NONE, MOVE, FIGHT }
var _target_mode: int = TargetMode.NONE

# Intent interface set by PlayerController or AIController; autopilot writes to this too
var intents := {
	"move_local": Vector2.ZERO, # x = strafe right(+)/left(-), y = forward(+)/back(-) in local space
	"run": false,
	"retreat": false, # true = wants to get away
	"attack": false,
	"attack_strength": 0.0
}

enum State { IDLE, MOVING, ATTACKING, STAGGERED, KO }
var state: int = State.IDLE
var _last_attack_time: float = -1000.0
var _last_attack_strength: float = 1.0

func _ready() -> void:
	# Optional AnimationPlayer fallback if you still want animation_finished for state resets
	var model := $Model if has_node("Model") else null
	if model:
		anim = (model.find_child("AnimationPlayer") as AnimationPlayer)
	if anim:
		anim.connect("animation_finished", Callable(self, "_on_animation_finished"))

	# Get agent/stats/animator
	agent = (get_node_or_null(navigation_agent_path) as NavigationAgent3D) if navigation_agent_path != NodePath("") else ($NavigationAgent3D as NavigationAgent3D)
	stats = get_node_or_null(stats_node_path) if stats_node_path != NodePath("") else $Stats
	animator = (get_node_or_null(animator_path) as CharacterAnimator) if animator_path != NodePath("") else ($CharacterAnimator as CharacterAnimator)

	if stats:
		if stats.has_signal("died"):
			stats.connect("died", Callable(self, "_on_died"))
		if stats.has_signal("health_changed"):
			stats.connect("health_changed", Callable(self, "_on_health_changed"))

	if agent:
		# Relax tolerances to reduce oscillation near the goal
		agent.path_desired_distance = 0.5
		agent.target_desired_distance = 0.75
		# agent.avoidance_enabled = false # optional during debugging

# ----------------------------
# Targeting / Stance
# ----------------------------
func set_target(t: Variant) -> void:
	# Convenience: default to fight target
	set_fight_target(t)

func set_move_target(t: Variant) -> void:
	_set_target_internal(t, TargetMode.MOVE)
	if animator:
		animator.end_fight_stance()

func set_fight_target(t: Variant) -> void:
	_set_target_internal(t, TargetMode.FIGHT)
	if animator:
		animator.start_fight_stance()

func clear_target() -> void:
	if debug_enabled:
		print_debug("[BC] clear_target()")
	_target_node = null
	_target_point = global_position
	_has_target = false
	_target_mode = TargetMode.NONE
	if agent:
		agent.target_position = global_position
	if animator:
		animator.end_fight_stance()

func _set_target_internal(t: Variant, mode: int) -> void:
	_target_mode = mode
	if t is Node3D:
		_target_node = t
		_has_target = true
		if agent:
			agent.target_position = _target_node.global_position
		if debug_enabled:
			print_debug("[BC] set_target(mode=%s) -> Node3D: %s" % [_mode_name(mode), _target_node.name])
	elif t is Vector3:
		_target_node = null
		_target_point = t
		_has_target = true
		if agent:
			agent.target_position = _target_point
		if debug_enabled:
			print_debug("[BC] set_target(mode=%s) -> Point: %s" % [_mode_name(mode), str(_target_point)])
	else:
		clear_target()

func has_target() -> bool:
	return _has_target

func get_target_position() -> Vector3:
	if not _has_target:
		return global_position
	if _target_node:
		return _target_node.global_position
	return _target_point

# ----------------------------
# Core loop
# ----------------------------
func _physics_process(delta: float) -> void:
	if state == State.KO:
		return

	# Gravity
	if use_gravity:
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
	else:
		velocity.y = 0.0

	# Keep agent target updated if following a moving node
	if agent and _has_target and _target_node:
		agent.target_position = _target_node.global_position

	# If autopilot is enabled, refresh intents to head toward targets
	if use_agent_autopilot:
		_update_autopilot_intents()

	# Steering and horizontal velocity
	var desired_move_dir_world := _compute_desired_world_direction()
	_apply_rotation_towards_target_or_velocity(desired_move_dir_world, delta)
	_apply_horizontal_velocity(desired_move_dir_world)

	# Move once per frame
	var prev_position := global_position
	move_and_slide()

	# Movement stamina drain
	var delta_pos := global_position - prev_position
	var moved_distance: float = delta_pos.length()
	if stats and moved_distance > 0.0 and stats.has_method("spend_movement"):
		stats.spend_movement(moved_distance)

	# Measured horizontal speed (what actually happened)
	var measured_h_speed = Vector2(delta_pos.x, delta_pos.z).length() / max(delta, 1e-6)

	# Update locomotion state from measured speed
	var prev_state := state
	state = State.MOVING if measured_h_speed > 0.1 else State.IDLE
	if debug_enabled and prev_state != state:
		print_debug("[BC] state -> %s" % _state_name(state))

	# Debug tick
	if debug_enabled:
		_debug_accum += delta
		if _debug_accum >= debug_interval:
			_debug_accum = 0.0
			_debug_snapshot(desired_move_dir_world, measured_h_speed)

	# Combat + Animations
	_handle_attack_intent()
	if animator:
		animator.update_locomotion(intents["move_local"], measured_h_speed)

# ----------------------------
# Autopilot (NavigationAgent3D)
# ----------------------------
func _update_autopilot_intents() -> void:
	if not _has_target:
		return
	var to_target := get_target_position() - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if _target_mode == TargetMode.MOVE:
		if dist <= move_arrival_tolerance:
			intents["move_local"] = Vector2.ZERO
			intents["run"] = false
			intents["retreat"] = false
			clear_target()
			return
		_set_autopilot_move_towards(get_target_position())
		intents["run"] = dist > run_distance_threshold
		intents["retreat"] = false
	elif _target_mode == TargetMode.FIGHT:
		var lower = max(min_attack_distance, desired_fight_distance - fight_distance_tolerance)
		var upper = min(max_attack_distance, desired_fight_distance + fight_distance_tolerance)
		if dist > upper:
			_set_autopilot_move_towards(get_target_position())
			intents["run"] = dist > run_distance_threshold
			intents["retreat"] = false
		elif dist < lower:
			# Step back to open space
			_set_autopilot_step_back()
			intents["run"] = false
			intents["retreat"] = true
		else:
			# In good range: stop driving locomotion; stance/aiming handles facing
			intents["move_local"] = Vector2.ZERO
			intents["run"] = false
			intents["retreat"] = false

func _set_autopilot_move_towards(world_target: Vector3) -> void:
	var dir_world := Vector3.ZERO
	if agent:
		# Prefer next path corner; fallback directly to target
		var next_pos := agent.get_next_path_position()
		var to_next := next_pos - global_position
		to_next.y = 0.0
		dir_world = to_next if to_next.length() > 0.001 else (world_target - global_position)
	else:
		dir_world = world_target - global_position
	dir_world.y = 0.0
	if dir_world.length() > 0.001:
		dir_world = dir_world.normalized()
	# Convert to local move x/y (x = right, y = forward)
	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	var x := dir_world.dot(right)
	var y := dir_world.dot(forward)
	var move_local := Vector2(x, y)
	intents["move_local"] = move_local.normalized() if move_local.length() > 0.001 else Vector2.ZERO

func _set_autopilot_step_back() -> void:
	# Move straight back in local space
	intents["move_local"] = Vector2(0.0, -1.0)

# ----------------------------
# Movement helpers
# ----------------------------
func _compute_desired_world_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var local_move: Vector2 = intents["move_local"]
	var world_dir: Vector3 = (forward * local_move.y) + (right * local_move.x)
	if world_dir.length() > 1e-3:
		world_dir = world_dir.normalized()
	return world_dir

func _apply_rotation_towards_target_or_velocity(desired_dir_world: Vector3, delta: float) -> void:
	var max_yaw_step: float = deg_to_rad(turn_speed_deg) * delta
	var should_face_target: bool = keep_eyes_on_target and _has_target and not (bool(intents["run"]) and bool(intents["retreat"]))
	if should_face_target:
		var to_target: Vector3 = get_target_position() - global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			_rotate_yaw_towards(_yaw_from_direction(to_target), max_yaw_step)
	elif desired_dir_world.length() > 0.01:
		_rotate_yaw_towards(_yaw_from_direction(desired_dir_world), max_yaw_step)

func _yaw_from_direction(dir: Vector3) -> float:
	# Godot forward is -Z. This returns a yaw so that -Z faces 'dir'.
	var d := dir
	d.y = 0.0
	if d.length() < 1e-6:
		return rotation.y
	return atan2(-d.x, -d.z)

func _rotate_yaw_towards(desired_yaw: float, max_step: float) -> void:
	var current_yaw: float = rotation.y
	var diff: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	if abs(diff) <= max_step:
		rotation.y = desired_yaw
	else:
		rotation.y = current_yaw + clamp(diff, -max_step, max_step)

# Only sets horizontal velocity from desired direction
func _apply_horizontal_velocity(desired_dir_world: Vector3) -> void:
	var local_move: Vector2 = intents["move_local"]
	var speed: float = walk_speed
	if bool(intents["run"]) and bool(intents["retreat"]):
		speed = run_speed
	elif local_move.y < -0.01:
		speed = backpedal_speed
	elif abs(local_move.x) > 0.01 and abs(local_move.y) < 0.01:
		speed = strafe_speed
	elif bool(intents["run"]):
		speed = run_speed
	var horizontal_vel: Vector3 = desired_dir_world * speed
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z

# ----------------------------
# Combat
# ----------------------------
func _handle_attack_intent() -> void:
	if not bool(intents["attack"]):
		return
	intents["attack"] = false
	var now: float = Time.get_unix_time_from_system()
	if now - _last_attack_time < attack_cooldown_sec:
		return
	if not in_attack_range():
		return
	_last_attack_strength = clamp(float(intents["attack_strength"]), 0.0, 1.0)
	if stats and stats.has_method("try_spend_stamina"):
		if not stats.try_spend_stamina(stats.stamina_attack_cost * lerp(0.7, 1.3, _last_attack_strength)):
			return
	_last_attack_time = now
	state = State.ATTACKING
	emit_signal("attacked", _last_attack_strength)
	if animator:
		animator.play_attack_by_strength(_last_attack_strength)

func anim_event_hit() -> void:
	emit_signal("attack_landed", _last_attack_strength)

func take_hit(amount: int) -> void:
	if state == State.KO:
		return
	if stats and stats.has_method("take_damage"):
		stats.take_damage(amount)
	emit_signal("took_hit", amount)
	if animator:
		animator.play_hit(amount)
	state = State.STAGGERED

func _on_health_changed(current: int, _max: int) -> void:
	if current <= 0:
		_on_died()

func _on_died() -> void:
	state = State.KO
	emit_signal("knocked_out")
	if animator:
		animator.play_ko()

func _on_animation_finished(_name: StringName) -> void:
	# Only relevant if you're still using AnimationPlayer for some clips.
	if state in [State.ATTACKING, State.STAGGERED]:
		state = State.IDLE

# ----------------------------
# Utility helpers for controllers
# ----------------------------
func in_attack_range() -> bool:
	var d := (get_target_position() - global_position).length()
	return d >= min_attack_distance and d <= max_attack_distance

func distance_to_target() -> float:
	return (get_target_position() - global_position).length()

# ----------------------------
# Debug helpers
# ----------------------------
func _mode_name(m: int) -> String:
	match m:
		TargetMode.NONE: return "NONE"
		TargetMode.MOVE: return "MOVE"
		TargetMode.FIGHT: return "FIGHT"
		_: return str(m)

func _state_name(s: int) -> String:
	match s:
		State.IDLE: return "IDLE"
		State.MOVING: return "MOVING"
		State.ATTACKING: return "ATTACKING"
		State.STAGGERED: return "STAGGERED"
		State.KO: return "KO"
		_: return str(s)

func _debug_snapshot(desired_dir_world: Vector3, horizontal_speed: float) -> void:
	var tgt_pos := get_target_position()
	var to_tgt := tgt_pos - global_position
	to_tgt.y = 0.0
	var next_corner := agent.get_next_path_position() if agent else Vector3.ZERO
	var facing_yaw := rotation.y
	var desired_yaw_tgt := _yaw_from_direction(to_tgt)
	var desired_yaw_move := _yaw_from_direction(desired_dir_world)
	var forward := -global_transform.basis.z
	print_debug("[BC] pos=%s  tgt=%s  mode=%s  dist=%.2f" % [str(global_position), str(tgt_pos), _mode_name(_target_mode), to_tgt.length()])
	if agent:
		print_debug("     agent.next=%s  path_dist=%.2f  target_dist=%.2f" %
			[str(next_corner), agent.path_desired_distance, agent.target_desired_distance])
	print_debug("     local_move=%s run=%s retreat=%s speed=%.2f" %
		[ str(intents['move_local']), str(bool(intents['run'])), str(bool(intents['retreat'])), horizontal_speed ])
	print_debug("     facing_yaw=%.1f  yaw_tgt=%.1f  yaw_move=%.1f  fwd.dot(move)=%.2f" %
		[ rad_to_deg(facing_yaw), rad_to_deg(desired_yaw_tgt), rad_to_deg(desired_yaw_move), forward.dot(desired_dir_world) ])
