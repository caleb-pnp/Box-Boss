extends Node
class_name AutoMoveController

var character: BaseCharacter = null

# --- Character Movement Settings ---
@export var strafe_speed_scale_min: float = 0.2
@export var strafe_speed_scale_max: float = 0.8
@export var strafe_magnitude_min: float = 0.25
@export var strafe_magnitude_max: float = 0.7
@export var strafe_activity_prob: float = 0.55
@export var strafe_on_time_min: float = 0.4
@export var strafe_on_time_max: float = 1.2
@export var strafe_off_time_min: float = 0.35
@export var strafe_off_time_max: float = 1.0
@export var retreat_max_mag: float = 0.45
@export var retreat_speed_scale: float = 0.55

# --- Center Seeking Settings
@export var center_seek_enabled: bool = true
@export var center_seek_strength: float = 0.05

# --- Stance Distance Variables
@export var hold_distance: float = 2.8
@export var hold_tolerance: float = 0.4

# --- Step Back Variables
@export var step_in_min_sec: float = 0.35
@export var step_in_max_sec: float = 0.7
@export var step_back_min_sec: float = 0.25
@export var step_back_max_sec: float = 0.45
@export var step_in_mag: float = 0.25
@export var step_back_mag: float = 0.25

# --- Rush/Bait Variables
@export var standoff_hysteresis_m: float = 0.15
@export var rush_timeout_sec: float = 1.5
@export var engage_backoff_m: float = 1.0
@export var random_bait_backstep_prob: float = 0.3
@export var bait_backstep_min_sec: float = 0.35
@export var bait_backstep_max_sec: float = 0.7
@export var bait_backstep_mag: float = 0.35

# --- Hold Time
@export var idle_activity_prob: float = 0.15 # Try 0.35 or higher for more idling
@export var think_time_min: float = 0.25
@export var think_time_max: float = 2.5

# --- Debug
@export var debug_autopilot: bool = false

# Rush/bait state and tuning
var _rush_active: bool = false
var _rush_stop_dist: float = 0.0
var _rush_giveup_at: float = 0.0
var _recent_backstep_until: float = 0.0

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

enum Intent { NONE, STRAFE_L, STRAFE_R, STEP_BACK, STEP_IN, HOLD }
var _intent: int = Intent.NONE
var _intent_until: float = 0.0
var _next_decision_at: float = 0.0

func _ready():
	_rng.randomize()

func setup(character_ref):
	character = character_ref
	_reset_strafe_state()

func process(delta: float) -> void:
	if not character or not character.round_active or character.state == character.State.KO:
		_reset_intents()
		character.stop_movement()
		return

	# Target reacquire (if you want to implement auto-targeting, do it here)
	if character.auto_target_enabled:
		if not character.has_target or character.target_node == null:
			pass

	# Navigation update
	if character.agent and character.has_target and character.target_node:
		var dest: Vector3 = character.target_node.global_position
		character.agent.target_position = dest

	# Update autopilot intent and apply movement
	_update_autopilot_intents()
	_face_target(delta)

func _update_autopilot_intents() -> void:
	if not character.has_target or character.target_node == null:
		_reset_intents()
		character.stop_movement()
		return

	var now: float = _now() / 1000.0 # ms to seconds
	var ml: Vector2 = Vector2.ZERO

	# --- Distance to target ---
	var to_target = character.target_node.global_position - character.global_position
	to_target.y = 0.0
	var dist = to_target.length()

	var high_band = self.hold_distance + self.hold_tolerance
	var low_band = self.hold_distance - self.hold_tolerance

	var is_strafing = _intent == Intent.STRAFE_L or _intent == Intent.STRAFE_R
	var is_stepping = _intent == Intent.STEP_IN or _intent == Intent.STEP_BACK

	# --- Only update intent if expired, or if continuing a rush ---
	if _rush_active:
		if dist > (_rush_stop_dist + self.standoff_hysteresis_m):
			_intent = Intent.STEP_IN
			ml.y = 1.0
			if now > _rush_giveup_at:
				_rush_active = false
		else:
			_rush_active = false
			_intent = Intent.HOLD
			_intent_until = now + _rng.randf_range(self.think_time_min, self.think_time_max)
			_dbg("[AutoMove] Intent: RUSH END -> HOLD for %.2fs" % (_intent_until - now))
	elif now >= _intent_until:
		# Only pick a new intent if the previous one expired!
		# Rush-in: Only sometimes, and only if not already strafing or stepping
		if not is_strafing and not is_stepping and dist > (high_band + 0.4) and _rng.randf() < 0.45:
			_rush_active = true
			_rush_stop_dist = max(0.2, self.hold_distance - self.engage_backoff_m)
			_rush_giveup_at = now + self.rush_timeout_sec
			_intent = Intent.STEP_IN
			_intent_until = now + _rng.randf_range(self.step_in_min_sec, self.step_in_max_sec)
			_dbg("[AutoMove] Intent: RUSH-IN (STEP_IN) for %.2fs" % (_intent_until - now))
		# Bait backstep: Only if not already strafing or stepping, and not recently done
		elif not is_strafing and not is_stepping and now >= _recent_backstep_until and _rng.randf() < self.random_bait_backstep_prob:
			_intent = Intent.STEP_BACK
			_intent_until = now + _rng.randf_range(self.bait_backstep_min_sec, self.bait_backstep_max_sec)
			_recent_backstep_until = _intent_until
			ml.y = -min(self.bait_backstep_mag, self.retreat_max_mag)
			_dbg("[AutoMove] Intent: BAIT BACKSTEP for %.2fs" % (_intent_until - now))
		else:
			var r = _rng.randf()
			if r < self.strafe_activity_prob:
				_intent = (Intent.STRAFE_L if _rng.randf() < 0.5 else Intent.STRAFE_R)
				_intent_until = now + _rng.randf_range(self.strafe_on_time_min, self.strafe_on_time_max)
				_dbg("[AutoMove] Intent: STRAFE %s for %.2fs" % (["LEFT" if _intent == Intent.STRAFE_L else "RIGHT", _intent_until - now]))
			elif r < self.strafe_activity_prob + self.idle_activity_prob:
				_intent = Intent.HOLD
				_intent_until = now + _rng.randf_range(self.think_time_min, self.think_time_max)
				_dbg("[AutoMove] Intent: HOLD for %.2fs" % (_intent_until - now))
			elif dist > (self.hold_distance + self.hold_tolerance):
				_intent = Intent.STEP_IN
				_intent_until = now + _rng.randf_range(self.step_in_min_sec, self.step_in_max_sec)
				_dbg("[AutoMove] Intent: STEP_IN for %.2fs" % (_intent_until - now))
			elif dist < (self.hold_distance - self.hold_tolerance):
				_intent = Intent.STEP_BACK
				_intent_until = now + _rng.randf_range(self.step_back_min_sec, self.step_back_max_sec)
				_dbg("[AutoMove] Intent: STEP_BACK for %.2fs" % (_intent_until - now))
			else:
				_intent = Intent.HOLD
				_intent_until = now + _rng.randf_range(self.think_time_min, self.think_time_max)
				_dbg("[AutoMove] Intent: HOLD for %.2fs" % (_intent_until - now))

	# --- Build movement vector from intent ---
	match _intent:
		Intent.STRAFE_L:
			ml.x = -clampf(_my_strafe_mag, 0.0, 1.0)
		Intent.STRAFE_R:
			ml.x = clampf(_my_strafe_mag, 0.0, 1.0)
		Intent.STEP_BACK:
			var dir = -to_target.normalized()
			var local_dir = _world_dir_to_local_move(dir)
			ml += local_dir * min(self.step_back_mag, self.retreat_max_mag)
		Intent.STEP_IN:
			var dir = to_target.normalized()
			var local_dir = _world_dir_to_local_move(dir)
			ml += local_dir * self.step_in_mag
		Intent.HOLD, Intent.NONE:
			ml = Vector2.ZERO

	# --- Center seeking: only if not idling ---
	if _intent != Intent.HOLD and _intent != Intent.NONE:
		if self.center_seek_enabled and character.arena_radius_hint > 0.001:
			var to_center: Vector3 = character.arena_center - character.global_position
			to_center.y = 0.0
			var dist_from_center: float = to_center.length()
			if dist_from_center > 0.001:
				var inward_local: Vector2 = _world_dir_to_local_move(to_center.normalized())
				var t_center: float = clamp(dist_from_center / max(character.arena_radius_hint, 0.001), 0.0, 1.0)
				ml += inward_local * (self.center_seek_strength * t_center)

	# --- Clamp tiny movement to zero ---
	if ml.length() < 0.01:
		ml = Vector2.ZERO

	move_local = ml
	run = false
	retreat = (ml.y < -0.01)

	# Use new movement helper
	var speed_scale := 1.0
	if retreat:
		speed_scale = self.retreat_speed_scale
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
	_my_strafe_speed_scale = _rng.randf_range(self.strafe_speed_scale_min, self.strafe_speed_scale_max)
	_my_strafe_mag = _rng.randf_range(self.strafe_magnitude_min, self.strafe_magnitude_max)
	_strafe_dir = (1 if _rng.randf() < 0.5 else -1)
	_strafe_active = (_rng.randf() < self.strafe_activity_prob)
	_strafe_state_until = _now() + (_rng.randf_range(self.strafe_on_time_min, self.strafe_on_time_max) if _strafe_active else _rng.randf_range(self.strafe_off_time_min, self.strafe_off_time_max))

func _face_target(delta: float) -> void:
	if not character or not character.has_target or character.target_node == null:
		return
	var to_target = character.target_node.global_position - character.global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return
	var desired_yaw = atan2(-to_target.x, -to_target.z)
	var current_yaw = character.rotation.y
	var max_step = deg_to_rad(character.turn_speed_deg) * delta
	var diff = wrapf(desired_yaw - current_yaw, -PI, PI)
	if absf(diff) <= max_step:
		character.rotation.y = desired_yaw
	else:
		character.rotation.y = current_yaw + clampf(diff, -max_step, max_step)

func _world_dir_to_local_move(dir: Vector3) -> Vector2:
	var forward: Vector3 = -character.global_transform.basis.z
	var right: Vector3 = character.global_transform.basis.x
	var local_x = right.normalized().dot(dir)
	var local_y = forward.normalized().dot(dir)
	return Vector2(local_x, local_y)

func _now() -> float:
	return Time.get_ticks_msec()

func _dbg(msg: String) -> void:
	if debug_autopilot:
		print(msg)
