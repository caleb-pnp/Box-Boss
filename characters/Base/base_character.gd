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

var anim: AnimationPlayer
var agent: NavigationAgent3D
var stats: Node
var animator: CharacterAnimator

# Target can be a Node3D or a Vector3
var _target_node: Node3D
var _target_point: Vector3
var _has_target: bool = false

# Intent interface set by either PlayerController or AIController
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
	anim = $Model.find_child("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.connect("animation_finished", Callable(self, "_on_animation_finished"))

	# Get agent/stats/animator
	agent = (get_node_or_null(navigation_agent_path) as NavigationAgent3D) if navigation_agent_path != NodePath("") else ($NavigationAgent3D as NavigationAgent3D)
	stats = get_node_or_null(stats_node_path) if stats_node_path != NodePath("") else $Stats
	animator = (get_node_or_null(animator_path) as CharacterAnimator) if animator_path != NodePath("") else ($CharacterAnimator as CharacterAnimator)

	if stats:
		stats.connect("died", Callable(self, "_on_died"))
		stats.connect("health_changed", Callable(self, "_on_health_changed"))

	if agent:
		agent.path_desired_distance = 0.1
		agent.target_desired_distance = 0.1

func set_target(t: Variant) -> void:
	if t is Node3D:
		_target_node = t
		_has_target = true
		if agent:
			agent.target_position = _target_node.global_position
	elif t is Vector3:
		_target_node = null
		_target_point = t
		_has_target = true
		if agent:
			agent.target_position = _target_point
	else:
		_has_target = false
		if agent:
			agent.target_position = global_position

func has_target() -> bool:
	return _has_target

func get_target_position() -> Vector3:
	if not _has_target:
		return global_position
	if _target_node:
		return _target_node.global_position
	return _target_point

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

	# Steering and horizontal velocity
	var desired_move_dir_world := _compute_desired_world_direction(delta)
	_apply_rotation_towards_target_or_velocity(desired_move_dir_world, delta)
	var horizontal_speed := _apply_horizontal_velocity(desired_move_dir_world)

	# Move once per frame
	var prev_position := global_position
	move_and_slide()

	# Movement stamina drain
	var moved_distance: float = (global_position - prev_position).length()
	if stats and moved_distance > 0.0 and stats.has_method("spend_movement"):
		stats.spend_movement(moved_distance)

	# Update locomotion state
	state = State.MOVING if horizontal_speed > 0.1 else State.IDLE

	# Combat + Animations
	_handle_attack_intent()
	if animator:
		animator.update_locomotion(intents["move_local"], horizontal_speed)

func _compute_desired_world_direction(_delta: float) -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var local_move: Vector2 = intents["move_local"]
	var world_dir: Vector3 = (forward * local_move.y) + (right * local_move.x)
	if world_dir.length() > 1e-3:
		world_dir = world_dir.normalized()
	return world_dir

func _apply_rotation_towards_target_or_velocity(desired_dir_world: Vector3, delta: float) -> void:
	var turning_speed: float = deg_to_rad(turn_speed_deg) * delta
	var should_face_target: bool = keep_eyes_on_target and _has_target and not (bool(intents["run"]) and bool(intents["retreat"]))
	if should_face_target:
		var to_target: Vector3 = get_target_position() - global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			_rotate_yaw_towards(atan2(to_target.x, to_target.z), turning_speed)
	elif desired_dir_world.length() > 0.01:
		_rotate_yaw_towards(atan2(desired_dir_world.x, desired_dir_world.z), turning_speed)

func _rotate_yaw_towards(desired_yaw: float, max_step: float) -> void:
	var current_yaw: float = rotation.y
	var diff: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	if abs(diff) <= max_step:
		rotation.y = desired_yaw
	else:
		rotation.y = current_yaw + clamp(diff, -max_step, max_step)

# Only sets horizontal velocity; returns the resulting horizontal speed (m/s)
func _apply_horizontal_velocity(desired_dir_world: Vector3) -> float:
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
	return horizontal_vel.length()

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
	# If relying only on AnimationTree transitions, you can remove animation_finished usage below.

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

# Utility helpers for controllers
func in_attack_range() -> bool:
	var d := (get_target_position() - global_position).length()
	return d >= min_attack_distance and d <= max_attack_distance

func distance_to_target() -> float:
	return (get_target_position() - global_position).length()
