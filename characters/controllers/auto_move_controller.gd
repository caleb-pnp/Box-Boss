extends Node
class_name AutoMoveController

var character: BaseCharacter = null

# Internal state
var _rng := RandomNumberGenerator.new()
var _strafe_dir: int = 1
var _strafe_active: bool = false
var _strafe_state_until: float = 0.0
var _my_strafe_speed_scale: float = 1.0
var _my_strafe_mag: float = 0.5

# Modularized intent state (for debugging/UI only)
var move_local: Vector2 = Vector2.ZERO
var run: bool = false
var retreat: bool = false

func _ready():
	_rng.randomize()
	# Do NOT call _reset_strafe_state() here!

func setup(character_ref):
	character = character_ref
	_reset_strafe_state()

func process(delta: float) -> void:
	if not character or not character.round_active or character.state == character.State.KO:
		_reset_intents()
		character.stop_movement()
		return

	# Target reacquire
	if character.auto_target_enabled:
		var now_auto: float = _now()
		var need_reacquire: bool = (not character._has_target) or (not character._is_valid_target(character._target_node))
		if need_reacquire and now_auto >= character._autotarget_next_check_at:
			character._find_target_now()

	# Navigation update
	if character.agent and character._has_target and character._target_node:
		var dest: Vector3 = character._target_node.global_position
		if character.nav_clamp_targets and character._target_mode == character.TargetMode.MOVE:
			dest = character._nav_closest_on_map(dest)
		character.agent.target_position = dest

	# Update autopilot intent and apply movement
	_update_autopilot_intents()

func _update_autopilot_intents() -> void:
	if not character._has_target:
		_reset_intents()
		character.stop_movement()
		return

	var now: float = _now()
	var ml: Vector2 = Vector2.ZERO

	# Strafe logic
	if _strafe_active and now < _strafe_state_until:
		ml.x = _strafe_dir * clampf(_my_strafe_mag, 0.0, 1.0)
	else:
		ml = Vector2.ZERO

	# Center seeking
	if character.center_seek_enabled and character.arena_radius_hint > 0.001:
		var to_center: Vector3 = character.arena_center - character.global_position
		to_center.y = 0.0
		var dist_from_center: float = to_center.length()
		if dist_from_center > 0.001:
			var inward_local: Vector2 = _world_dir_to_local_move(to_center.normalized())
			var t_center: float = clamp(dist_from_center / max(character.arena_radius_hint, 0.001), 0.0, 1.0)
			ml += inward_local * (character.center_seek_strength * t_center)

	# Clamp retreat intent so we never blast backward
	if ml.y < 0.0:
		ml.y = max(ml.y, -clampf(character.retreat_max_mag, 0.0, 1.0))

	# Final clamp
	if ml.length() > 1.0:
		ml = ml.normalized()

	move_local = ml
	run = false
	retreat = (ml.y < -0.01)

	# Use new movement helper
	var speed_scale := 1.0
	if retreat:
		speed_scale = character.retreat_speed_scale
	elif absf(ml.x) > 0.01 and absf(ml.y) < 0.01:
		speed_scale = _my_strafe_speed_scale
	else:
		speed_scale = 1.0

	character.move_direction(ml, speed_scale, true)

	# Strafe state update
	if now >= _strafe_state_until:
		_reset_strafe_state()

func reset() -> void:
	_reset_intents()
	_reset_strafe_state()
	character.stop_movement()

func pause() -> void:
	_reset_intents()
	character.stop_movement()

func _reset_intents() -> void:
	move_local = Vector2.ZERO
	run = false
	retreat = false

func _reset_strafe_state() -> void:
	_my_strafe_speed_scale = _rng.randf_range(character.strafe_speed_scale_min, character.strafe_speed_scale_max)
	_my_strafe_mag = _rng.randf_range(character.strafe_magnitude_min, character.strafe_magnitude_max)
	_strafe_dir = (1 if _rng.randf() < 0.5 else -1)
	_strafe_active = (_rng.randf() < character.strafe_activity_prob)
	_strafe_state_until = _now() + (_rng.randf_range(character.strafe_on_time_min, character.strafe_on_time_max) if _strafe_active else _rng.randf_range(character.strafe_off_time_min, character.strafe_off_time_max))

func _world_dir_to_local_move(dir: Vector3) -> Vector2:
	var forward: Vector3 = -character.global_transform.basis.z
	var right: Vector3 = character.global_transform.basis.x
	var local_x = right.normalized().dot(dir)
	var local_y = forward.normalized().dot(dir)
	return Vector2(local_x, local_y)

# Returns the current time in seconds (float)
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
