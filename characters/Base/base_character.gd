extends CharacterBody3D
class_name BaseCharacter

# --- Attack Queue System ---
# All attack requests are queued with timestamps.
# - Attacks are queued even if out of range.
# - If you get hit, the queue is cleared.
# - When close enough, attacks are executed in order.
# - Old attacks (>1s) are dropped except for the last one.
# - If in range and the queue is not empty, the next attack is launched.
# - All attack requests must use queue_attack(attack_id).
# - The queue is robust to spam and integrates with the FSM.

signal attacked_id(id: StringName)
signal attack_landed(amount: float)
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

@export_category("Round Flow")
@export var round_active: bool = false

@export_category("Combat (Data-Driven)")
@export var keep_eyes_on_target: bool = true
@export var approach_speed_scale: float = 1.0

@export var attack_library: AttackLibrary
@export_file("*.tres") var attack_library_path: String = "res://data/AttackLibrary.tres"

@export var attack_set_data: AttackSetData
@export_file("*.tres") var attack_set_data_path: String = "res://data/attack_sets/Default.tres"

@export var attack_debounce_after_fight_enter: float = 0.15
@export var launch_band_epsilon: float = 0.1

# Input buffers
@export var attack_press_retry_buffer_sec: float = 0.25
@export var attack_queue_buffer_sec: float = 0.25

@export_category("Scene References")
@export var navigation_agent_path: NodePath
@export var stats_node_path: NodePath
@export var animator_path: NodePath

@export_category("Navigation / Autopilot")
@export var use_agent_autopilot: bool = true
@export var move_arrival_tolerance: float = 0.25
@export var run_distance_threshold: float = 6.0
@export var nav_clamp_targets: bool = true
@export var nav_stuck_memory_frames: int = 6

@export_category("Debug")
@export var debug_enabled: bool = true
@export var debug_interval: float = 0.25
var _debug_accum: float = 0.0

@export_category("Input / Punch Mapping")
@export var input_source_id: int = 0
@export var accept_any_source_if_zero: bool = false

@export_category("Force -> Category Mapping")
@export var use_force_ranges: bool = true
@export var light_force_min: float = 0.1
@export var light_force_max: float = 999.99
@export var medium_force_min: float = 1000
@export var medium_force_max: float = 1999.99
@export var heavy_force_min: float = 2000
@export var heavy_force_max: float = 2999.99
@export var special_force_min: float = 3000
@export var special_force_max: float = 9999.99
@export var category_light: StringName = &"light"
@export var category_medium: StringName = &"medium"
@export var category_heavy: StringName = &"heavy"
@export var category_special: StringName = &"special"

@export_category("Damage Scaling (Optional)")
@export var scale_damage_by_force: bool = true
@export var min_damage_scale: float = 0.9
@export var max_damage_scale: float = 1.2
@export var default_light_damage: int = 5
@export var default_medium_damage: int = 8
@export var default_heavy_damage: int = 12
@export var default_special_damage: int = 16

@export_category("Auto Targeting")
@export var auto_target_enabled: bool = true
@export var auto_target_reacquire_interval: float = 0.5
@export var aggro_memory_sec: float = 3.0
@export var switch_to_aggressor_immediately: bool = true

@export_category("Auto Fight Movement")
@export var auto_fight_movement_enabled: bool = true
@export var arena_center: Vector3 = Vector3.ZERO
@export var arena_radius_hint: float = 15.0
@export var idle_strafe_interval_min: float = 0.8
@export var idle_strafe_interval_max: float = 1.6
@export var idle_strafe_magnitude: float = 0.6
@export var swing_forward_push: float = 0.25
@export var retreat_recent_hit_window: float = 1.5
@export var retreat_hit_threshold: int = 1
@export var retreat_push: float = -0.6
@export var center_return_bias: float = 0.5

@export_category("Spacing / Distance Control")
@export var hold_distance: float = 2.8
@export var hold_tolerance: float = 0.4
@export var post_swing_backstep_sec: float = 0.35
@export var post_swing_backstep_strength: float = 0.6

@export_category("Naturalization / Desync")
# Prefer rotation over strafing when we're already mostly facing the target.
@export var strafe_angle_min_deg: float = 12.0
# Desync strafing so both fighters don’t orbit in sync.
@export var strafe_activity_prob: float = 0.55
@export var strafe_on_time_min: float = 0.4
@export var strafe_on_time_max: float = 1.2
@export var strafe_off_time_min: float = 0.35
@export var strafe_off_time_max: float = 1.0
@export var strafe_magnitude_min: float = 0.25
@export var strafe_magnitude_max: float = 0.7
@export var strafe_speed_scale_min: float = 0.2     # 20% of strafe_speed
@export var strafe_speed_scale_max: float = 0.8     # 80% of strafe_speed

# If the target is circling us (high angular speed), rotate to face instead of circling with them.
@export var rotate_instead_on_target_strafe: bool = true
@export var target_strafe_omega_thresh_deg: float = 60.0   # deg/sec considered “they’re strafing”

@export_category("Hold Ground vs Retreat")
@export var approaching_speed_threshold: float = 0.8        # units/sec
@export var retreat_when_pressed_slowdown: float = 0.5      # scale backpedal
@export var hold_ground_chance_when_pressed: float = 0.35   # chance to stand ground

@export_category("Retreat Tuning")
# Global scale for backpedal speed (0.0..1.0). Lower = slower retreat.
@export var retreat_speed_scale: float = 0.55
# Maximum backpedal intent magnitude so we don't slam backwards (-1..0)
@export var retreat_max_mag: float = 0.45

@export_category("Center Seeking")
# Gentle drift toward ring center over time (even when not near edge)
@export var center_seek_enabled: bool = true
@export var center_seek_strength: float = 0.05     # small additive intent toward center

@export_category("Engage / Approach Tuning")
# Slow forward movement as we enter the range band: within (hold_distance + this), scale forward speed.
@export var engage_slowdown_band_m: float = 1.0
# Scale applied to forward speed when inside the slowdown band (0.1..1.0). 0.75 = 25% slower.
@export var engage_forward_speed_scale: float = 0.8
# When closing, maintain at least this much extra room inside hold_distance (a small standoff so we don't bump).
@export var engage_backoff_m: float = 1.0

@export_category("Stand-off / Rush")
# Half-width of the no-flip band around the stop distance.
@export var standoff_hysteresis_m: float = 0.15
# After a rush ends, pause this long before choosing a new intent.
@export var standoff_pause_sec: float = 0.25
# Safety timeout for a rush if we cannot reach the stop distance (blocked).
@export var rush_timeout_sec: float = 1.5

@export_category("Reaction / Rush Strategy")
@export var reaction_lag_sec: float = 0.35                 # delay before we react to opponent’s retreat/approach
@export var retreat_memory_sec: float = 0.6                # how long we remember opponent retreating
@export var retreating_speed_threshold: float = 0.6        # units/sec considered a retreat
@export var rush_trigger_small_margin_m: float = 0.15      # small extra distance above band that can trigger a rush
@export var rush_trigger_min_time_sec: float = 0.6         # must stay above small margin for this long to rush
@export var random_bait_backstep_prob: float = 0.3         # chance to do a bait backstep when neutral
@export var bait_backstep_min_sec: float = 0.35
@export var bait_backstep_max_sec: float = 0.7
@export var bait_backstep_mag: float = 0.35                # capped by retreat_max_mag
@export var band_correction_gain: float = 0.12             # gentle distance correction size
@export var band_deadzone_m: float = 0.05                  # ignore corrections within this of target distance

# Optional step-in/back commit tuning
@export_category("Intent Commit")
@export var step_back_min_sec: float = 0.25
@export var step_back_max_sec: float = 0.45
@export var step_in_min_sec: float = 0.35
@export var step_in_max_sec: float = 0.7
@export var step_back_mag: float = 0.25
@export var step_in_mag: float = 0.25

@export_category("Combos / Attack Window")
@export var attack_window_sec: float = 5.0
@export var consume_window_on_combo: bool = true
@export var consume_window_on_basic: bool = true
@export var combo_finalize_gap_sec: float = 1.0   # inactivity gap before finalize


# --- Knockback tuning ---
@export_category("On Hit Tuning")
@export var knockback_duration_sec: float = 0.1     # how fast to apply the small knockback
@export var hitstun_immunity_while_ko: bool = true
@export var debug_combat: bool = true


# Layers used by Hurtbox/Hitbox (must match scripts)
const LAYER_HITBOX := 2
const LAYER_HURTBOX := 3


# Set by Scene
@onready var hurtbox: Hurtbox3D = $Hurtbox3D
@onready var hitbox: Hitbox3D = $Hitbox3D

# --- Attack Queue ---
var _attack_queue: Array = []

# Set by Scene
var _original_collision_layer: int
var _original_collision_mask: int

func _dbg(msg: String) -> void:
	if debug_enabled: print(msg)

func _combat_log(msg: String) -> void:
	if debug_combat:
		print("[Combat] ", get_path(), " | ", msg)

var agent: NavigationAgent3D
var stats: Node
var animator

var _target_node: Node3D
var _target_point: Vector3
var _has_target: bool = false
var _connected_target: BaseCharacter = null

enum TargetMode { NONE, MOVE, FIGHT }
var _target_mode: int = TargetMode.NONE

var intents := {
	"move_local": Vector2.ZERO,
	"run": false,
	"retreat": false,
}

enum State { IDLE, MOVING, ATTACKING, STAGGERED, KO }
var state: int = State.IDLE

var _last_attack_time_by_id := {}

enum AttackPhase { NONE, APPROACH, REPOSITION, SWING }
var _attack_phase: int = AttackPhase.NONE
var _attack_phase_until: float = 0.0
var _attack_spec_current
var _attack_id_current: StringName = &""

var _fight_entered_at: float = -1e9
var _move_locked_until: float = 0.0

var _last_move_local: Vector2 = Vector2.ZERO
var _stuck_frames: int = 0

var _attack_cat_current: StringName = &""
var _punch_force_current: float = 0.0

var _last_aggressor: BaseCharacter = null
var _last_aggressed_at: float = -1e9
var _autotarget_next_check_at: float = 0.0

var _last_hit_time: float = -1e9
var _recent_hits: int = 0
var _post_swing_until: float = 0.0
var _last_speed_applied: float = 0.001

var _rng := RandomNumberGenerator.new()
var _strafe_dir: int = 0
var _strafe_until: float = 0.0
var _strafe_active: bool = false
var _strafe_state_until: float = 0.0
var _my_strafe_speed_scale: float = 1.0
var _my_strafe_mag: float = 0.5

enum Intent { NONE, STRAFE_L, STRAFE_R, STEP_BACK, STEP_IN, HOLD }
var _intent: int = Intent.NONE
var _intent_until: float = 0.0
var _next_decision_at: float = 0.0

var _last_dist_to_target: float = 0.0
var _last_update_time: float = 0.0
var _last_target_vec: Vector3 = Vector3.ZERO
var _last_target_vec_time: float = 0.0

var _rush_active: bool = false
var _rush_stop_dist: float = 0.0
var _rush_giveup_at: float = 0.0

var _reaction_lag_until: float = 0.0
var _recent_backstep_until: float = 0.0
var _opponent_retreating_until: float = 0.0
var _distance_above_high_since: float = -1.0

var _intent_mag_y: float = 0.0

var _last_combo_debug: String = ""
var _last_force_select_debug: String = ""

var knockback_velocity: Vector3 = Vector3.ZERO
var knockback_timer: float = 0.0
var _stagger_until: float = -1.0

func _ready() -> void:
	_rng.randomize()
	_my_strafe_speed_scale = _rng.randf_range(strafe_speed_scale_min, strafe_speed_scale_max)
	_my_strafe_mag = _rng.randf_range(strafe_magnitude_min, strafe_magnitude_max)
	_strafe_dir = (1 if _rng.randf() < 0.5 else -1)
	_strafe_active = (_rng.randf() < strafe_activity_prob)
	_strafe_state_until = _now() + (_rng.randf_range(strafe_on_time_min, strafe_on_time_max) if _strafe_active else _rng.randf_range(strafe_off_time_min, strafe_off_time_max))
	_strafe_until = _now() + _rng.randf_range(idle_strafe_interval_min, idle_strafe_interval_max)

	if attack_library == null and attack_library_path != "":
		var r := load(attack_library_path)
		if r is AttackLibrary: attack_library = r
	if attack_set_data == null and attack_set_data_path != "":
		var r2 := load(attack_set_data_path)
		if r2 is AttackSetData: attack_set_data = r2

	agent = (get_node_or_null(navigation_agent_path) as NavigationAgent3D) if navigation_agent_path != NodePath("") else ($NavigationAgent3D as NavigationAgent3D)
	stats = get_node_or_null(stats_node_path) if stats_node_path != NodePath("") else $Stats
	animator = (get_node_or_null(animator_path)) if animator_path != NodePath("") else ($CharacterAnimator if has_node("CharacterAnimator") else null)

	if stats:
		if stats.has_signal("died"): stats.connect("died", Callable(self, "_on_died"))
		if stats.has_signal("health_changed"): stats.connect("health_changed", Callable(self, "_on_health_changed"))

	if agent:
		agent.path_desired_distance = 0.5
		agent.target_desired_distance = 0.75

	add_to_group("fighters")
	_connect_punch_input()

	_last_update_time = _now()
	_last_dist_to_target = distance_to_target()
	_last_target_vec = _vector_to_target()
	_last_target_vec_time = _last_update_time

	if hurtbox: hurtbox.owner_character = self
	if hitbox: hitbox.attacker = self

# ----------------------------
# Round gating
# ----------------------------
func set_round_active(active: bool) -> void:
	round_active = active
	if not active:
		intents["move_local"] = Vector2.ZERO
		intents["run"] = false
		intents["retreat"] = false
		_attack_phase = AttackPhase.NONE
		_attack_phase_until = 0.0
		_move_locked_until = 0.0
		_post_swing_until = 0.0
		_clear_attack_queue()
		_intent = Intent.NONE
		_intent_until = 0.0
		_next_decision_at = 0.0
		if state != State.KO:
			state = State.IDLE

# ----------------------------
# Optional setters
# ----------------------------
func set_attack_set_data(data: AttackSetData) -> void:
	attack_set_data = data

func set_input_source_id(id: int) -> void:
	input_source_id = id

# ----------------------------
# Attack Queue API
# ----------------------------
func queue_attack(attack_id: StringName) -> void:
	if String(attack_id) == "":
		return
	var now := _now()
	_attack_queue.append({ "id": attack_id, "queued_at": now })
	_cleanup_attack_queue(now)
	if debug_enabled:
		print("[AttackQueue] Queued attack id=", String(attack_id), " at ", str(now), " (queue size=", str(_attack_queue.size()), ")")

func request_attack_id(id: StringName) -> void:
	queue_attack(id)

func _cleanup_attack_queue(now: float) -> void:
	if _attack_queue.size() <= 1:
		return
	var keep: Array = []
	for i in range(_attack_queue.size()):
		var entry = _attack_queue[i]
		var age = now - float(entry["queued_at"])
		if age <= 1.0 or i == _attack_queue.size() - 1:
			keep.append(entry)
	_attack_queue = keep

func _clear_attack_queue() -> void:
	_attack_queue.clear()

# ----------------------------
# Targeting / Stance
# ----------------------------
func set_target(t: Variant) -> void:
	set_fight_target(t)

func set_move_target(t: Variant) -> void:
	_set_target_internal(t, TargetMode.MOVE)
	if animator and animator.has_method("end_fight_stance"):
		animator.end_fight_stance()

func set_fight_target(t: Variant) -> void:
	_set_target_internal(t, TargetMode.FIGHT)
	if animator and animator.has_method("start_fight_stance"):
		animator.start_fight_stance()
	_fight_entered_at = _now()

func clear_target() -> void:
	_disconnect_target_signals()
	_target_node = null
	_target_point = global_position
	_has_target = false
	_target_mode = TargetMode.NONE
	_attack_phase = AttackPhase.NONE
	_attack_phase_until = 0.0
	_move_locked_until = 0.0
	_attack_spec_current = null
	_attack_id_current = &""
	_attack_cat_current = &""
	_punch_force_current = 0.0
	_post_swing_until = 0.0
	_clear_attack_queue()
	if agent: agent.target_position = global_position
	if animator and animator.has_method("end_fight_stance"):
		animator.end_fight_stance()

func _set_target_internal(t: Variant, mode: int) -> void:
	_target_mode = mode
	if t is Node3D:
		_target_node = t
		_has_target = true
		_connect_target_signals(t)
		var dest: Vector3 = _target_node.global_position
		if nav_clamp_targets and agent and mode == TargetMode.MOVE:
			dest = _nav_closest_on_map(dest)
		if agent: agent.target_position = dest
	elif t is Vector3:
		_disconnect_target_signals()
		_target_node = null
		var dest_point: Vector3 = t
		if nav_clamp_targets and agent and mode == TargetMode.MOVE:
			dest_point = _nav_closest_on_map(dest_point)
		_target_point = dest_point
		_has_target = true
		if agent: agent.target_position = _target_point
	else:
		clear_target()

func has_target() -> bool: return _has_target

func get_target_position() -> Vector3:
	if not _has_target: return global_position
	return _target_node.global_position if _target_node else _target_point

func is_knocked_out() -> bool: return state == State.KO
func is_alive() -> bool: return not is_knocked_out()

# ----------------------------
# Core loop
# ----------------------------
func _physics_process(delta: float) -> void:
	# 1. Gravity
	if use_gravity:
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
	else:
		velocity.y = 0.0

	# 2. Knockback (highest priority; blocks all other movement/AI)
	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		move_and_slide()
		if knockback_timer <= 0.0:
			knockback_velocity = Vector3.ZERO
			collision_layer = _original_collision_layer
			collision_mask = _original_collision_mask
			_combat_log("DEBUG: Knockback collision restored: layer=%d, mask=%d" % [_original_collision_layer, _original_collision_mask])
		return

	# 3. Move lock second priority (blocks all input/AI, except gravity)
	if _move_locked_until > _now():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if animator and animator.has_method("update_locomotion"):
			animator.update_locomotion(Vector2.ZERO, 0.0)
		_track_target_motion()
		return

	# 4. KO or round end
	if not round_active or state == State.KO:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if state != State.KO:
			state = State.IDLE
		if animator and animator.has_method("update_locomotion"):
			animator.update_locomotion(Vector2.ZERO, 0.0)
		_track_target_motion()
		return

	# 6. AI/autopilot/steering section
	if agent and _has_target and _target_node:
		var dest: Vector3 = _target_node.global_position
		if nav_clamp_targets and _target_mode == TargetMode.MOVE:
			dest = _nav_closest_on_map(dest)
		agent.target_position = dest

	if auto_target_enabled:
		var now_auto: float = _now()
		var need_reacquire: bool = (not _has_target) or (not _is_valid_target(_target_node))
		if need_reacquire and now_auto >= _autotarget_next_check_at:
			_find_target_now()

	if use_agent_autopilot:
		_update_autopilot_intents()

	# 7. Compute desired movement and rotation
	var desired_move_dir_world: Vector3 = _compute_desired_world_direction()

	# Only rotate if not locked, knocked back, or staggered
	if not (_move_locked_until > _now() or knockback_timer > 0.0 or state == State.STAGGERED):
		_apply_rotation_towards_target_or_velocity(desired_move_dir_world, delta)

	_apply_horizontal_velocity(desired_move_dir_world)

	# 9. Move and update position
	var prev_position: Vector3 = global_position
	move_and_slide()
	var delta_pos: Vector3 = global_position - prev_position
	var moved_distance: float = delta_pos.length()
	if stats and moved_distance > 0.0 and stats.has_method("spend_movement"):
		stats.spend_movement(moved_distance)

	# 10. Update locomotion state
	var measured_h_speed: float = Vector2(delta_pos.x, delta_pos.z).length() / max(delta, 1e-6)
	state = State.MOVING if measured_h_speed > 0.1 else State.IDLE

	# 11. Combat and housekeeping
	_process_attack_queue()
	_tick_attack_phase()
	_track_target_motion()

	# Anim
	if animator and animator.has_method("update_locomotion"):
		var v: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		var right: Vector3 = global_transform.basis.x
		var forward: Vector3 = -global_transform.basis.z
		var lx: float = v.dot(right)
		var ly: float = v.dot(forward)
		var anim_move_local: Vector2 = Vector2(lx, ly) / _last_speed_applied
		anim_move_local.x = clamp(anim_move_local.x, -1.0, 1.0)
		anim_move_local.y = clamp(anim_move_local.y, -1.0, 1.0)
		animator.update_locomotion(anim_move_local, measured_h_speed)

# ----------------------------
# Attack Queue Processing
# ----------------------------
func _process_attack_queue() -> void:
	if state == State.KO or not round_active:
		return
	if _attack_phase != AttackPhase.NONE:
		return # Already attacking or busy

	if _attack_queue.is_empty():
		return

	var now := _now()
	_cleanup_attack_queue(now)
	if _attack_queue.is_empty():
		return

	var next = _attack_queue[0]
	var id: StringName = next["id"]
	var spec = attack_library.get_spec(id)
	if spec == null:
		_attack_queue.pop_front()
		return

	var last_time: float = float(_last_attack_time_by_id.get(id, -1000.0))
	if now - last_time < max(0.0, spec.cooldown_sec):
		_attack_queue.pop_front()
		return

	if not _has_target:
		return

	var d2t: float = distance_to_target()
	var lower: float = float(max(0.0, spec.launch_min_distance))
	var upper: float = spec.enter_distance
	var eps: float = float(max(0.0, launch_band_epsilon))

	if lower > 0.0:
		if d2t < (lower - eps):
			_attack_phase = AttackPhase.REPOSITION
			_attack_spec_current = spec
			_attack_id_current = id
			return
		elif d2t > (upper + eps):
			_attack_phase = AttackPhase.APPROACH
			_attack_spec_current = spec
			_attack_id_current = id
			return
		else:
			_attack_cat_current = &""
			_start_swing(spec, id, now)
			_attack_queue.pop_front()
			return
	else:
		if d2t > (upper + eps):
			_attack_phase = AttackPhase.APPROACH
			_attack_spec_current = spec
			_attack_id_current = id
			return
		else:
			_attack_cat_current = &""
			_start_swing(spec, id, now)
			_attack_queue.pop_front()
			return

func _tick_attack_phase() -> void:
	if _attack_phase == AttackPhase.NONE: return
	var now: float = _now()
	match _attack_phase:
		AttackPhase.APPROACH:
			if _attack_spec_current:
				var d: float = distance_to_target()
				var lower: float = float(max(0.0, _attack_spec_current.launch_min_distance))
				var upper: float = _attack_spec_current.enter_distance
				var eps: float = float(max(0.0, launch_band_epsilon))
				var reposition_thresh: float = lower - eps
				var swing_upper: float = upper + eps
				if d < reposition_thresh and lower > 0.0:
					_attack_phase = AttackPhase.REPOSITION
				elif d <= swing_upper:
					_start_swing(_attack_spec_current, _attack_id_current, now)
		AttackPhase.REPOSITION:
			if _attack_spec_current:
				var d2: float = distance_to_target()
				var lower2: float = float(max(0.0, _attack_spec_current.launch_min_distance))
				var upper2: float = _attack_spec_current.enter_distance
				var eps2: float = float(max(0.0, launch_band_epsilon))
				var approach_thresh: float = upper2 + eps2
				var swing_lower: float = lower2 - eps2
				if d2 > approach_thresh:
					_attack_phase = AttackPhase.APPROACH
				elif d2 >= swing_lower:
					_start_swing(_attack_spec_current, _attack_id_current, now)
		AttackPhase.SWING:
			if now >= _attack_phase_until:
				_attack_phase = AttackPhase.NONE
				_attack_spec_current = null
				_attack_id_current = &""
				_attack_cat_current = &""
				_punch_force_current = 0.0
				_post_swing_until = now + max(0.0, post_swing_backstep_sec)

func _start_swing(spec, id: StringName, now: float) -> void:
	_attack_spec_current = spec
	_attack_id_current = id
	_last_attack_time_by_id[id] = now
	state = State.ATTACKING
	emit_signal("attacked_id", id)

	_attack_cat_current = &""
	_punch_force_current = 0.0

	if debug_enabled:
		print("[Swing] START id=", String(id), " cat=", String(_attack_cat_current), " force=", str(_punch_force_current))

	if animator and animator.has_method("play_attack_id"):
		if not (animator.has_method("is_in_fight_stance") and animator.is_in_fight_stance()):
			if animator.has_method("start_fight_stance"): animator.start_fight_stance()
		animator.play_attack_id(id)

	_move_locked_until = now + max(0.0, spec.move_lock_sec)
	_attack_phase = AttackPhase.SWING
	_attack_phase_until = now + max(0.0, spec.swing_time_sec)

	if hitbox:
		activate_hitbox_for_attack(_attack_id_current, _attack_spec_current, _punch_force_current)

func anim_event_hit() -> void:
	if debug_enabled:
		_combat_log("anim_event_hit triggered (damage handled by Hitbox3D)")

func take_hit(amount: int, source: Node = null, stagger_duration: float = 0.2) -> void:
	if state == State.KO: return
	if source and source is BaseCharacter and source != self:
		_last_aggressor = source as BaseCharacter
		_last_aggressed_at = _now()
		if switch_to_aggressor_immediately and _is_valid_target(_last_aggressor) and round_active:
			set_fight_target(_last_aggressor)

	var now: float = _now()
	if now - _last_hit_time > retreat_recent_hit_window:
		_recent_hits = 0
	_last_hit_time = now
	_recent_hits += 1

	if stats and stats.has_method("take_damage"): stats.take_damage(amount)
	emit_signal("took_hit", amount)
	if animator and animator.has_method("play_hit"): animator.play_hit(amount)
	state = State.STAGGERED
	_stagger_until = now + stagger_duration

	_attack_phase = AttackPhase.NONE
	_attack_phase_until = 0.0
	_move_locked_until = 0.0
	_attack_spec_current = null
	_attack_id_current = &""
	_attack_cat_current = &""
	_punch_force_current = 0.0
	_post_swing_until = 0.0
	_clear_attack_queue()

func _on_health_changed(current: int, _max: int) -> void:
	if current <= 0: _on_died()

func _on_died() -> void:
	state = State.KO
	emit_signal("knocked_out")
	_attack_phase = AttackPhase.NONE
	_attack_phase_until = 0.0
	_move_locked_until = 0.0
	_attack_spec_current = null
	_attack_id_current = &""
	_attack_cat_current = &""
	_punch_force_current = 0.0
	_post_swing_until = 0.0
	_clear_attack_queue()
	if animator and animator.has_method("play_ko"): animator.play_ko()

# ----------------------------
# PunchInput integration
# ----------------------------
func _connect_punch_input() -> void:
	var router := get_node_or_null("/root/PunchInput")
	if router:
		if not router.is_connected("punched", Callable(self, "_on_punched")):
			router.connect("punched", Callable(self, "_on_punched"))
	else:
		if debug_enabled:
			push_warning("[BC] PunchInput autoload not found at /root/PunchInput")

func _on_punched(source_id: int, force: float) -> void:
	_dbg("[Punch] src=" + str(source_id) + " force=" + str(force))
	if not round_active: return
	if input_source_id == 0 and not accept_any_source_if_zero: return
	if input_source_id != 0 and source_id != input_source_id: return
	if state == State.KO: return

	var attack_id: StringName = _select_attack_by_force_from_set(force)
	if String(attack_id) != "":
		queue_attack(attack_id)

# ----------------------------
# Movement helpers
# ----------------------------
func _compute_desired_world_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var local_move: Vector2 = intents["move_local"]
	var world_dir: Vector3 = (forward * local_move.y) + (right * local_move.x)
	var len: float = world_dir.length()
	if len > 1.0 and len > 0.0:
		world_dir /= len
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
	var d: Vector3 = dir
	d.y = 0.0
	if d.length() < 1e-6:
		return rotation.y
	return atan2(-d.x, -d.z)

func _rotate_yaw_towards(desired_yaw: float, max_step: float) -> void:
	var current_yaw: float = rotation.y
	var diff: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	if absf(diff) <= max_step:
		rotation.y = desired_yaw
	else:
		rotation.y = current_yaw + clampf(diff, -max_step, max_step)

func _apply_horizontal_velocity(desired_dir_world: Vector3) -> void:
	var local_move: Vector2 = intents["move_local"]
	var speed: float = walk_speed

	# Base speed by intent direction
	if bool(intents["run"]) and bool(intents["retreat"]):
		speed = run_speed
	elif local_move.y < -0.01:
		speed = backpedal_speed * clampf(retreat_speed_scale, 0.0, 1.0)
	elif local_move.y > 0.01:
		speed = walk_speed
	elif absf(local_move.x) > 0.01 and absf(local_move.y) < 0.01:
		speed = strafe_speed * _my_strafe_speed_scale
	elif bool(intents["run"]):
		speed = run_speed

	# Phase slowdown
	if _attack_phase == AttackPhase.APPROACH or _attack_phase == AttackPhase.REPOSITION:
		speed *= clampf(approach_speed_scale, 0.05, 1.0)

	# Engage slowdown near range
	if local_move.y > 0.01 and _has_target:
		var d_to: float = distance_to_target()
		if d_to < (hold_distance + engage_slowdown_band_m):
			speed *= clampf(engage_forward_speed_scale, 0.1, 1.0)

	# Apply velocity. desired_dir_world length is <= 1 (clamped), so magnitude scales speed.
	var horizontal_vel: Vector3 = desired_dir_world * speed
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z

	_last_speed_applied = max(0.001, speed)

# ADD: Activate our permanent Hitbox3D using spec timing.
func activate_hitbox_for_attack(attack_id: StringName, spec: Resource, impact_force: float, reach_override_m: float = -1.0) -> void:
	if hitbox == null:
		_combat_log("No Hitbox3D node under this character.")
		return
	hitbox.attacker = self
	hitbox.activate_for_attack(attack_id, spec, impact_force)
	_combat_log("activate_hitbox: %s force=%.2f" % [String(attack_id), impact_force])


# REPLACE: thin adapter used by Hitbox3D; computes damage and forwards to take_hit.
func apply_hit(attacker: Node, spec: Resource, impact_force: float) -> void:
	# Safety: never hit self (Hitbox3D also guards)
	if attacker == self:
		return

	var from_s: String = "<none>"
	if attacker != null and attacker is Node:
		from_s = str((attacker as Node).get_path())
	_combat_log("apply_hit: from=" + from_s)

	if spec == null:
		_combat_log("apply_hit: spec=null (skipping)")
		return

	var base_damage: float = float(_spec_val(spec, &"damage", 10.0))
	var dmg: float = base_damage

	if bool(_spec_val(spec, &"scale_damage_by_force", false)):
		var fmin: float = float(_spec_val(spec, &"force_min", 0.0))
		var fmax: float = float(_spec_val(spec, &"force_max", 1.0))
		if fmax < fmin:
			var tmp := fmin; fmin = fmax; fmax = tmp
		var t: float = 0.0
		if fmax > fmin:
			t = clamp((impact_force - fmin) / max(0.0001, (fmax - fmin)), 0.0, 1.0)
		var dmin: float = float(_spec_val(spec, &"min_damage", base_damage))
		var dmax: float = float(_spec_val(spec, &"max_damage", base_damage))
		dmg = lerp(dmin, dmax, t)
		_combat_log("apply_hit: scaled dmg " + str(dmg) + " (force=" + str(impact_force) + " fmin=" + str(fmin) + " fmax=" + str(fmax) + " dmin=" + str(dmin) + " dmax=" + str(dmax) + ")")
	else:
		_combat_log("apply_hit: base dmg " + str(dmg))

	var stagger_sec: float = float(_spec_val(spec, &"stagger_sec", 0.2)) # fallback if not present
	take_hit(int(round(dmg)), attacker, stagger_sec)

	if animator and animator.has_method("cancel_attack_oneshot"):
		animator.cancel_attack_oneshot()

	var kb_m: float = float(_spec_val(spec, &"knockback_meters", 0.0))
	var kb_dur: float = float(_spec_val(spec, &"knockback_duration_sec", knockback_duration_sec))
	if kb_m > 0.0 and attacker is Node3D and self is Node3D:
		var dir: Vector3 = ((self as Node3D).global_transform.origin - (attacker as Node3D).global_transform.origin)
		dir.y = 0.0
		dir = dir.normalized()
		var velocity = kb_m / max(kb_dur, 0.01)
		_combat_log("DEBUG: knockback: kb_m=%.3f kb_dur=%.3f velocity=%.3f direction=%s" % [kb_m, kb_dur, velocity, str(dir)])
		_apply_knockback(dir, velocity, kb_dur)
		_combat_log("apply_hit: knockback " + str(kb_m) + "m over " + str(kb_dur) + "s")


func _apply_knockback(direction: Vector3, velocity: float, duration: float):
	knockback_velocity = direction.normalized() * velocity
	knockback_timer = duration
	_combat_log("DEBUG: _apply_knockback: velocity=%s, duration=%.3f" % [str(knockback_velocity), duration])

	# Store original collision layers/masks
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask

	# Move to a non-fighter layer (e.g., layer 2) to avoid pushing attacker
	collision_layer = 2
	collision_mask = 2
	_combat_log("DEBUG: Knockback collision swap: layer=2, mask=2")

# Simple knockback; replace with your controller’s impulse if needed
#func _apply_knockback(dir: Vector3, meters: float) -> void:
	#if meters <= 0.0: return
	#if not (self is Node3D): return
	#var start_pos: Vector3 = (self as Node3D).global_transform.origin
	#var end_pos: Vector3 = start_pos + dir * meters
	#var tw := create_tween()
	#tw.tween_property(self, "global_position", end_pos, knockback_duration_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Safe getter for Resource properties (Object.get has no default param)
func _spec_val(s: Resource, prop: StringName, fallback):
	if s == null:
		return fallback
	var v = s.get(prop)
	return fallback if v == null else v


# Force-first selection across all "basic" ids in the set.
# Rule:
# - If one or more ranges contain the force: prefer narrower width; if equal width, prefer smaller distance to center; if still equal, random.
# - Else: pick closest rounded down (range with max <= force and minimal (force - max)); tie -> narrower; else random.
# - If none below, return "" (no move).
# Replace your force-based selector with this version that shows scoring and ties
func _select_attack_by_force_from_set(force: float) -> StringName:
	_last_force_select_debug = ""
	if attack_set_data == null or attack_library == null: return StringName("")
	if not attack_set_data.has_method("get_basic_ids"): return StringName("")
	var candidates: Array[StringName] = attack_set_data.get_basic_ids()
	if candidates.is_empty():
		_last_force_select_debug = "[ForcePick] no basic candidate ids in set"
		return StringName("")

	var lines: Array[String] = []
	lines.append("[ForcePick] force=" + str(force) + " candidates=" + str(candidates.size()))

	var in_range: Array = []
	for id in candidates:
		var spec = attack_library.get_spec(id)
		if spec == null or not spec.has_method("get"):
			lines.append("  - " + String(id) + " skip (no spec)")
			continue
		var vm = spec.get("force_min")
		var vx = spec.get("force_max")
		if typeof(vm) == TYPE_NIL or typeof(vx) == TYPE_NIL:
			lines.append("  - " + String(id) + " skip (no force_min/max)")
			continue
		var fmin := float(vm)
		var fmax := float(vx)
		if fmax < fmin:
			var tmp = fmin; fmin = fmax; fmax = tmp

		if force >= fmin and force <= fmax:
			var width = max(0.0001, fmax - fmin)
			var center := 0.5 * (fmin + fmax)
			var center_dist := absf(force - center)
			var weight := 1.0
			var vw = spec.get("selection_weight")
			if typeof(vw) != TYPE_NIL:
				weight = max(0.01, float(vw))
			in_range.append({
				"id": id,
				"fmin": fmin,
				"fmax": fmax,
				"width": width,
				"center": center,
				"center_dist": center_dist,
				"weight": weight
			})
			lines.append("  - " + String(id) + " IN  [" + str(fmin) + ", " + str(fmax) + "] width=" + str(width) + " center=" + str(center) + " dist=" + str(center_dist) + " w=" + str(weight))
		else:
			lines.append("  - " + String(id) + " OUT [" + str(fmin) + ", " + str(fmax) + "]")

	if in_range.size() > 0:
		in_range.sort_custom(func(a, b):
			if a["width"] < b["width"]: return true
			if a["width"] > b["width"]: return false
			if a["center_dist"] < b["center_dist"]: return true
			if a["center_dist"] > b["center_dist"]: return false
			if a["weight"] > b["weight"]: return true
			if a["weight"] < b["weight"]: return false
			return _rng.randf() < 0.5
		)
		var chosen = in_range[0]
		lines.append("[ForcePick] chose IN " + String(chosen["id"]) + " width=" + str(chosen["width"]) + " dist=" + str(chosen["center_dist"]) + " w=" + str(chosen["weight"]))
		_last_force_select_debug = "\n".join(lines)
		return chosen["id"]

	# No inside hits: closest rounded-down (fmax <= force)
	var below: Array = []
	for id2 in candidates:
		var spec2 = attack_library.get_spec(id2)
		if spec2 == null or not spec2.has_method("get"): continue
		var vm2 = spec2.get("force_min")
		var vx2 = spec2.get("force_max")
		if typeof(vm2) == TYPE_NIL or typeof(vx2) == TYPE_NIL: continue
		var fmin2 := float(vm2)
		var fmax2 := float(vx2)
		if fmax2 < fmin2:
			var tmp2 = fmin2; fmin2 = fmax2; fmax2 = tmp2

		if fmax2 <= force:
			var gap := force - fmax2
			var width2 = max(0.0001, fmax2 - fmin2)
			below.append({ "id": id2, "gap": gap, "width": width2, "fmin": fmin2, "fmax": fmax2 })
			lines.append("  - " + String(id2) + " BELOW gap=" + str(gap) + " width=" + str(width2) + " [" + str(fmin2) + ", " + str(fmax2) + "]")

	if below.size() == 0:
		lines.append("[ForcePick] no IN and no BELOW; returning none")
		_last_force_select_debug = "\n".join(lines)
		return StringName("")

	below.sort_custom(func(a, b):
		if a["gap"] < b["gap"]: return true
		if a["gap"] > b["gap"]: return false
		if a["width"] < b["width"]: return true
		if a["width"] > b["width"]: return false
		return _rng.randf() < 0.5
	)
	var chosen2 = below[0]
	lines.append("[ForcePick] chose BELOW " + String(chosen2["id"]) + " gap=" + str(chosen2["gap"]) + " width=" + str(chosen2["width"]))
	_last_force_select_debug = "\n".join(lines)
	return chosen2["id"]

# --- Utility and required helper functions ---

# Returns the current time in seconds (float)
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# Returns the distance to the current target, or 0 if none
func distance_to_target() -> float:
	if not _has_target:
		return 0.0
	return global_position.distance_to(get_target_position())

# Returns the vector from self to the current target, or Vector3.ZERO if none
func _vector_to_target() -> Vector3:
	if not _has_target:
		return Vector3.ZERO
	return get_target_position() - global_position

# Dummy: disconnects signals from the current target (implement as needed)
func _disconnect_target_signals() -> void:
	# Implement if you connect signals to the target node
	pass

# Dummy: connects signals to the current target (implement as needed)
func _connect_target_signals(target: Node) -> void:
	# Implement if you want to react to target events
	pass

# Dummy: returns the closest navigable point to the given position (implement as needed)
func _nav_closest_on_map(pos: Vector3) -> Vector3:
	# Implement using your navigation system if needed
	return pos

# Dummy: tracks target motion (implement as needed)
func _track_target_motion() -> void:
	# Implement if you want to track target movement for AI
	pass

# Dummy: checks if a target is valid (implement as needed)
func _is_valid_target(target: Node) -> bool:
	return target != null

# Dummy: finds a new target (implement as needed)
func _find_target_now() -> void:
	# Implement auto-targeting logic here
	pass

# Dummy: updates autopilot movement intents (implement as needed)
func _update_autopilot_intents() -> void:
	if not _has_target:
		return

	var now: float = _now()
	var d: float = distance_to_target()

	# Movement lock
	if now < _move_locked_until:
		if animator and animator.has_method("is_in_fight_stance") and not animator.is_in_fight_stance():
			animator.start_fight_stance()
		intents["move_local"] = Vector2.ZERO
		intents["run"] = false
		intents["retreat"] = false
		return

	match _attack_phase:
		AttackPhase.APPROACH:
			if animator and animator.has_method("is_in_fight_stance") and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			_set_autopilot_move_towards(get_target_position())
			intents["run"] = true
			intents["retreat"] = false
			return
		AttackPhase.REPOSITION:
			if animator and animator.has_method("is_in_fight_stance") and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			_set_autopilot_move_away_from(get_target_position())
			intents["run"] = false
			intents["retreat"] = true
			return
		AttackPhase.SWING:
			if animator and animator.has_method("is_in_fight_stance") and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			var push: float = swing_forward_push
			if d < (hold_distance - hold_tolerance * 0.25):
				push = -0.1
			var ml_swing: Vector2 = Vector2(0.0, clampf(push, -1.0, 1.0))
			intents["move_local"] = ml_swing
			intents["run"] = false
			intents["retreat"] = (ml_swing.y < 0.0)
			return
		_:
			pass

	# Approach/press info for intent chooser
	var dt: float = max(0.0001, now - _last_update_time)
	var closing_speed: float = (_last_dist_to_target - d) / dt
	var to_target: Vector3 = _vector_to_target()
	var desired_yaw: float = _yaw_from_direction(to_target)
	var diff_yaw: float = absf(wrapf(desired_yaw - rotation.y, -PI, PI))
	var angle_deg: float = rad_to_deg(diff_yaw)
	var omega_deg: float = _target_angular_speed_deg_per_sec()

	# Track “above-high” duration to allow rush after a slight gap persists
	var low_band: float = hold_distance - hold_tolerance
	var high_band: float = hold_distance + hold_tolerance
	if d > (high_band + rush_trigger_small_margin_m):
		if _distance_above_high_since < 0.0:
			_distance_above_high_since = now
	else:
		_distance_above_high_since = -1.0

	# Opponent retreat detection (distance increasing fast)
	if (-closing_speed) > retreating_speed_threshold:
		_opponent_retreating_until = now + retreat_memory_sec

	# Keep the stance fresh
	if animator and animator.has_method("is_in_fight_stance") and not animator.is_in_fight_stance():
		animator.start_fight_stance()

	# Update/choose intent only when needed (prevents per-frame flip-flop)
	_maybe_update_intent(now, d, closing_speed, omega_deg)

	# Build movement from committed intent
	var ml: Vector2 = Vector2.ZERO
	match _intent:
		Intent.STRAFE_L:
			ml.x = -clampf(_my_strafe_mag, 0.0, 1.0)
		Intent.STRAFE_R:
			ml.x = clampf(_my_strafe_mag, 0.0, 1.0)
		Intent.STEP_BACK:
			var back_mag: float = min(step_back_mag, retreat_max_mag)
			ml.y = -back_mag
		Intent.STEP_IN:
			if _rush_active:
				if d > (_rush_stop_dist + standoff_hysteresis_m):
					ml.y = 1.0
				elif now > _rush_giveup_at:
					_end_rush(now)
				else:
					_end_rush(now)
			else:
				ml = Vector2.ZERO
		Intent.HOLD, Intent.NONE:
			ml = Vector2.ZERO

	# Stand-off freeze: inside the stop band, do not change Y with other nudges
	var freeze_y: bool = false
	if _rush_stop_dist > 0.0:
		var low_stop: float = max(0.0, _rush_stop_dist - standoff_hysteresis_m)
		var high_stop: float = _rush_stop_dist + standoff_hysteresis_m
		freeze_y = (d >= low_stop and d <= high_stop)

	# Post-swing spacing (skip if frozen)
	if not freeze_y and now < _post_swing_until and d < (hold_distance + hold_tolerance * 0.5):
		ml.y = -clampf(post_swing_backstep_strength, 0.0, 1.0)

	# Gentle distance corrections ONLY if:
	if not freeze_y and not _rush_active and ml == Vector2.ZERO and now >= _intent_until and now >= _reaction_lag_until:
		var delta_from_hold: float = d - hold_distance
		if absf(delta_from_hold) > band_deadzone_m:
			if delta_from_hold < 0.0:
				ml.y += -band_correction_gain
			else:
				ml.y += band_correction_gain

	# Pressing logic (skip if frozen)
	if not freeze_y:
		var near_band: bool = absf(d - hold_distance) <= (hold_tolerance * 1.2)
		if closing_speed > approaching_speed_threshold and near_band:
			if _rng.randf() < clampf(hold_ground_chance_when_pressed, 0.0, 1.0):
				if ml.y < 0.0: ml.y = 0.0
			else:
				if ml.y < 0.0: ml.y *= clampf(retreat_when_pressed_slowdown, 0.05, 1.0)

	# Angle gating: if very square-on and not strafe intent, prefer rotation-only
	if (_intent == Intent.NONE or _intent == Intent.HOLD) and angle_deg < max(0.0, strafe_angle_min_deg):
		ml.x = 0.0

	# Gentle center seeking: suppress Y contribution if in stand-off freeze
	if center_seek_enabled and arena_radius_hint > 0.001:
		var to_center: Vector3 = arena_center - global_position
		to_center.y = 0.0
		var dist_from_center: float = to_center.length()
		if dist_from_center > 0.001:
			var inward_local: Vector2 = _world_dir_to_local_move(to_center.normalized())
			var t_center: float = clamp(dist_from_center / max(arena_radius_hint, 0.001), 0.0, 1.0)
			if freeze_y:
				inward_local.y = 0.0
			ml = ml + inward_local * (center_seek_strength * t_center)

	# Edge bias: also zero Y if we’re freezing
	if arena_radius_hint > 0.1:
		var to_center2: Vector3 = (arena_center - global_position)
		to_center2.y = 0.0
		var dist_from_center2: float = to_center2.length()
		if dist_from_center2 >= (arena_radius_hint * 0.85):
			var inward2: Vector2 = Vector2.ZERO
			if dist_from_center2 > 0.001:
				inward2 = _world_dir_to_local_move(to_center2.normalized())
			if freeze_y:
				inward2.y = 0.0
			ml = (ml * (1.0 - center_return_bias)) + (inward2 * center_return_bias)

	# Clamp retreat intent so we never blast backward
	if ml.y < 0.0:
		ml.y = max(ml.y, -clampf(retreat_max_mag, 0.0, 1.0))

	# Final clamp
	if ml.length() > 1.0:
		ml = ml.normalized()

	intents["move_local"] = ml
	intents["run"] = false
	intents["retreat"] = (ml.y < -0.01)

func _set_autopilot_move_towards(target_pos: Vector3) -> void:
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		intents["move_local"] = Vector2.ZERO
		return
	intents["move_local"] = _world_dir_to_local_move(to_target.normalized())

func _set_autopilot_move_away_from(target_pos: Vector3) -> void:
	var away: Vector3 = global_position - target_pos
	away.y = 0.0
	if away.length() < 0.01:
		intents["move_local"] = Vector2.ZERO
		return
	intents["move_local"] = _world_dir_to_local_move(away.normalized())

func _world_dir_to_local_move(dir: Vector3) -> Vector2:
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var local_x = right.normalized().dot(dir)
	var local_y = forward.normalized().dot(dir)
	return Vector2(local_x, local_y)

func _target_angular_speed_deg_per_sec() -> float:
	# Compute target angular speed around us based on change in bearing.
	var now: float = _now()
	var dt: float = max(0.0001, now - _last_target_vec_time)
	var cur: Vector3 = _vector_to_target()
	if cur.length_squared() < 1e-6 or _last_target_vec.length_squared() < 1e-6:
		_last_target_vec = cur
		_last_target_vec_time = now
		return 0.0
	var a1: float = atan2(-cur.x, -cur.z)
	var a0: float = atan2(-_last_target_vec.x, -_last_target_vec.z)
	var d_ang: float = wrapf(a1 - a0, -PI, PI)
	return rad_to_deg(d_ang) / dt

func _maybe_update_intent(now: float, d: float, closing_speed: float, omega_deg: float) -> void:
	# Decide only when commitment expired and the pause is over
	if now < _intent_until or now < _next_decision_at:
		return

	var low: float = hold_distance - hold_tolerance
	var high: float = hold_distance + hold_tolerance

	# Track whether we can rush off a small margin if it persists
	var can_rush_small: bool = false
	if _distance_above_high_since >= 0.0 and (now - _distance_above_high_since) >= rush_trigger_min_time_sec:
		can_rush_small = true

	# Large deviations: prefer decisive step in/out
	if d > high + 0.4 or (can_rush_small or (now < _opponent_retreating_until and now >= _reaction_lag_until)):
		# Start a distance-limited rush toward stop distance (hold_distance - engage_backoff_m)
		_intent = Intent.STEP_IN
		_intent_mag_y = 1.0
		_rush_active = true
		_rush_stop_dist = max(0.2, hold_distance - engage_backoff_m)
		_rush_giveup_at = now + rush_timeout_sec
		_intent_until = now + _rng.randf_range(step_in_min_sec, step_in_max_sec)
		_next_decision_at = _intent_until + _rng.randf_range(strafe_off_time_min, strafe_off_time_max)
		return
	elif d < low - 0.4:
		_intent = Intent.STEP_BACK
		_intent_mag_y = min(step_back_mag, retreat_max_mag)
		_rush_active = false
		_intent_until = now + _rng.randf_range(step_back_min_sec, step_back_max_sec)
		_next_decision_at = _intent_until + _rng.randf_range(strafe_off_time_min, strafe_off_time_max)
		_recent_backstep_until = _intent_until
		_reaction_lag_until = now + reaction_lag_sec
		return

	# Neutral: sometimes do a bait backstep to create an opening
	var neutral: bool = (_intent == Intent.NONE or _intent == Intent.HOLD or _intent == Intent.STRAFE_L or _intent == Intent.STRAFE_R)
	if neutral and now >= _recent_backstep_until:
		if _rng.randf() < clampf(random_bait_backstep_prob, 0.0, 1.0):
			_intent = Intent.STEP_BACK
			_intent_mag_y = min(bait_backstep_mag, retreat_max_mag)
			_rush_active = false
			_intent_until = now + _rng.randf_range(bait_backstep_min_sec, bait_backstep_max_sec)
			_next_decision_at = _intent_until + _rng.randf_range(strafe_off_time_min, strafe_off_time_max)
			_recent_backstep_until = _intent_until
			# After bait, delay our next forward reaction so the opponent can open the distance
			_reaction_lag_until = now + reaction_lag_sec
			return

	# Otherwise, maybe strafe; avoid mirroring if target is clearly circling
	var allow_strafe_now: bool = (_rng.randf() < clampf(strafe_activity_prob, 0.0, 1.0)) and not (rotate_instead_on_target_strafe and absf(omega_deg) >= target_strafe_omega_thresh_deg)
	_rush_active = false
	if allow_strafe_now:
		_intent = Intent.STRAFE_L if _rng.randf() < 0.5 else Intent.STRAFE_R
		_intent_mag_y = 0.0
		_intent_until = now + _rng.randf_range(strafe_on_time_min, strafe_on_time_max)
		_next_decision_at = _intent_until + _rng.randf_range(strafe_off_time_min, strafe_off_time_max)
	else:
		_intent = Intent.HOLD
		_intent_mag_y = 0.0
		_intent_until = now + _rng.randf_range(strafe_off_time_min, strafe_off_time_max)
		_next_decision_at = _intent_until + _rng.randf_range(0.1, 0.3)

func _end_rush(now: float) -> void:
	_rush_active = false
	_intent = Intent.HOLD
	_intent_until = now + standoff_pause_sec
	_next_decision_at = _intent_until + _rng.randf_range(0.1, 0.3)
