extends CharacterBody3D
class_name BaseCharacter

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

var _window_start: float = -1e9
var _punch_window: Array = []            # of { t: float, force: float, src: int }
var _combo_finalize_at: float = -1e9     # next time we should finalize due to inactivity
var _window_dirty: bool = false          # new punches since last finalize
var _last_punch_force: float = 0.0

# Optional local debug helper (if you don't already have one)
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
	"attack": false,
	"attack_id": StringName(""),
	"attack_category": StringName("")
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
var _attack_intent_prev: bool = false
var _move_locked_until: float = 0.0

var _attack_wish_until: float = 0.0
var _queued_attack_cat: StringName = &""
var _queued_attack_id: StringName = &""
var _queued_until: float = 0.0

var _last_move_local: Vector2 = Vector2.ZERO
var _stuck_frames: int = 0

var _attack_cat_pending: StringName = &""
var _attack_cat_current: StringName = &""
var _punch_force_pending: float = 0.0
var _punch_force_current: float = 0.0

var _last_aggressor: BaseCharacter = null
var _last_aggressed_at: float = -1e9
var _autotarget_next_check_at: float = 0.0

var _last_hit_time: float = -1e9
var _recent_hits: int = 0
var _post_swing_until: float = 0.0
var _last_speed_applied: float = 0.001

# Desync/strafe state and intent commit
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

# Approach/target motion tracking
var _last_dist_to_target: float = 0.0
var _last_update_time: float = 0.0
var _last_target_vec: Vector3 = Vector3.ZERO
var _last_target_vec_time: float = 0.0

# Rush/stand-off and reaction state
var _rush_active: bool = false
var _rush_stop_dist: float = 0.0
var _rush_giveup_at: float = 0.0

var _reaction_lag_until: float = 0.0
var _recent_backstep_until: float = 0.0
var _opponent_retreating_until: float = 0.0
var _distance_above_high_since: float = -1.0

# Per-intent magnitude for step motions
var _intent_mag_y: float = 0.0

var _last_combo_debug: String = ""
var _last_force_select_debug: String = ""

# PATCH: Knockback variables
var knockback_velocity: Vector3 = Vector3.ZERO
var knockback_timer: float = 0.0
var _stagger_until: float = -1.0


func _ready() -> void:
	_rng.randomize()

	# Per-fighter strafe style
	_my_strafe_speed_scale = _rng.randf_range(strafe_speed_scale_min, strafe_speed_scale_max)
	_my_strafe_mag = _rng.randf_range(strafe_magnitude_min, strafe_magnitude_max)
	_strafe_dir = (1 if _rng.randf() < 0.5 else -1)
	_strafe_active = (_rng.randf() < strafe_activity_prob)
	_strafe_state_until = _now() + (_rng.randf_range(strafe_on_time_min, strafe_on_time_max) if _strafe_active else _rng.randf_range(strafe_off_time_min, strafe_off_time_max))
	_strafe_until = _now() + _rng.randf_range(idle_strafe_interval_min, idle_strafe_interval_max)

	# Lazy-load libraries
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

	# Initialize tracking
	_last_update_time = _now()
	_last_dist_to_target = distance_to_target()
	_last_target_vec = _vector_to_target()
	_last_target_vec_time = _last_update_time

	# Initiazlize hitbox and hurtbox
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
		_attack_wish_until = 0.0
		_post_swing_until = 0.0
		_clear_queue()
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
# Public helpers
# ----------------------------
# Log category or id requests so we can see what was queued.
func request_attack_category(cat: StringName) -> void:
	intents["attack_category"] = cat
	intents["attack_id"] = StringName("")
	intents["attack"] = true
	_attack_wish_until = _now() + attack_press_retry_buffer_sec
	if debug_enabled:
		print("[AttackReq] category=", String(cat), " (force=", str(_punch_force_pending), ") wish_until=", str(_attack_wish_until))

func request_attack_id(id: StringName) -> void:
	intents["attack_id"] = id
	intents["attack_category"] = StringName("")
	intents["attack"] = true
	_attack_wish_until = _now() + attack_press_retry_buffer_sec
	if debug_enabled:
		print("[AttackReq] id=", String(id), " wish_until=", str(_attack_wish_until))

func request_auto_target() -> void:
	auto_target_enabled = true
	_autotarget_next_check_at = 0.0
	_find_target_now()

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
	intents["attack"] = false
	_attack_intent_prev = false

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
	_attack_wish_until = 0.0
	_attack_cat_pending = &""
	_attack_cat_current = &""
	_punch_force_pending = 0.0
	_punch_force_current = 0.0
	_post_swing_until = 0.0
	_clear_queue()
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
	# Gravity
	if use_gravity:
		if not is_on_floor(): velocity.y -= gravity * delta
		else: velocity.y = 0.0
	else:
		velocity.y = 0.0

	# PATCH: Apply knockback blending
	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		if knockback_timer <= 0.0:
			knockback_velocity = Vector3.ZERO

	# Handle stagger recovery
	if state == State.STAGGERED:
		if _now() >= _stagger_until:
			state = State.IDLE
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			if animator and animator.has_method("update_locomotion"):
				animator.update_locomotion(Vector2.ZERO, 0.0)
			_track_target_motion()
			return

	# Gate by round state
	if not round_active or state == State.KO:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if state != State.KO: state = State.IDLE
		if animator and animator.has_method("update_locomotion"):
			animator.update_locomotion(Vector2.ZERO, 0.0)
		# Track target motion while idle too
		_track_target_motion()
		return

	# Follow moving target
	if agent and _has_target and _target_node:
		var dest: Vector3 = _target_node.global_position
		if nav_clamp_targets and _target_mode == TargetMode.MOVE:
			dest = _nav_closest_on_map(dest)
		agent.target_position = dest

	# Auto-target
	if auto_target_enabled:
		var now_auto: float = _now()
		var need_reacquire: bool = (not _has_target) or (not _is_valid_target(_target_node))
		if need_reacquire and now_auto >= _autotarget_next_check_at:
			_find_target_now()

	# Autopilot intents
	if use_agent_autopilot:
		_update_autopilot_intents()

	# Steering and velocity
	var desired_move_dir_world: Vector3 = _compute_desired_world_direction()
	_apply_rotation_towards_target_or_velocity(desired_move_dir_world, delta)
	_apply_horizontal_velocity(desired_move_dir_world)

	# Move
	var prev_position: Vector3 = global_position
	move_and_slide()
	var delta_pos: Vector3 = global_position - prev_position
	var moved_distance: float = delta_pos.length()
	if stats and moved_distance > 0.0 and stats.has_method("spend_movement"):
		stats.spend_movement(moved_distance)

	# Locomotion state
	var measured_h_speed: float = Vector2(delta_pos.x, delta_pos.z).length() / max(delta, 1e-6)
	state = State.MOVING if measured_h_speed > 0.1 else State.IDLE

	# Combat
	_handle_attack_intent()
	_tick_attack_phase()

	# Track approach/target angular speed for next tick decisions
	_track_target_motion()

	# Finalize any pending window if its gap elapsed
	_finalize_attack_window_if_due()


	# Anim
	if animator and animator.has_method("update_locomotion"):
		var v: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		var right: Vector3 = global_transform.basis.x
		var forward: Vector3 = -global_transform.basis.z
		var lx: float = v.dot(right)
		var ly: float = v.dot(forward)
		# Normalize by the actual speed we applied so values map to [-1..1]
		var anim_move_local: Vector2 = Vector2(lx, ly) / _last_speed_applied
		# Clamp to avoid small overshoots
		anim_move_local.x = clamp(anim_move_local.x, -1.0, 1.0)
		anim_move_local.y = clamp(anim_move_local.y, -1.0, 1.0)
		animator.update_locomotion(anim_move_local, measured_h_speed)

func _Finalize_consume_window(clear_all: bool) -> void:
	if clear_all:
		_punch_window.clear()
	_window_start = _now()

# Call this each frame (you likely already call _finalize_attack_window_if_due from _physics_process)
func _finalize_attack_window_if_due() -> void:
	if not _window_dirty: return
	if _punch_window.is_empty(): return
	var now := _now()
	if now < _combo_finalize_at: return
	_force_finalize_current_window(now, _last_punch_force, "gap")

# Core finalizer: evaluates combos first, then basic force selection, then nothing.
# eval_time is used for sliding-window combo checks; basic_force is the force for single-move selection.
func _force_finalize_current_window(eval_time: float, basic_force: float, reason: String = "gap") -> void:
	_dbg("[Finalize] reason=" + reason + " window_size=" + str(_punch_window.size()))

	# 1) Combos take priority
	var combo_id := _try_eval_combos_from_set(eval_time)
	if String(combo_id) != "":
		_dbg("[Finalize] COMBO -> " + String(combo_id))
		_attack_cat_pending = &""
		_punch_force_pending = basic_force
		request_attack_id(combo_id)
		_consume_window(consume_window_on_combo)
		return

	# 2) Basic force-based selection
	var pick_id := _select_attack_by_force_from_set(basic_force)
	if String(pick_id) != "":
		_dbg("[Finalize] BASIC -> " + String(pick_id) + " (force=" + str(basic_force) + ")")
		_attack_cat_pending = &""
		_punch_force_pending = basic_force
		request_attack_id(pick_id)
		_consume_window(consume_window_on_basic)
		return

	# 3) Nothing matched
	_dbg("[Finalize] no combo and no basic match; no attack")
	_consume_window(consume_window_on_basic)

# Consume/clear the current window; after consuming there is no active window until next punch
func _consume_window(clear_all: bool) -> void:
	_window_dirty = false
	_combo_finalize_at = -1e9
	if clear_all:
		_punch_window.clear()
	# Mark "no active window" so next punch starts a fresh one
	_window_start = -1e9

# SLIDING WINDOW combo evaluation (uses eval_time instead of now)
# Keep your debug strings (_last_combo_debug) if you already added them.
func _try_eval_combos_from_set(eval_time: float) -> StringName:
	_last_combo_debug = ""
	if attack_set_data == null or attack_library == null: return StringName("")
	if not attack_set_data.has_method("get_combo_ids"): return StringName("")
	var ids: Array[StringName] = attack_set_data.get_combo_ids()
	if ids.is_empty():
		_last_combo_debug = "[Combo] no combo ids in set"
		return StringName("")

	var best_id: StringName = &""
	var best_pri := -1
	var best_req := -1
	var best_force := -1.0

	var lines: Array[String] = []
	lines.append("[Combo] evaluating " + str(ids.size()) + " candidates; window_len=" + str(_punch_window.size()))

	for id in ids:
		var spec = attack_library.get_spec(id)
		if spec == null or not spec.has_method("get"):
			lines.append("  - " + String(id) + " skip (no spec)")
			continue

		var req := int(spec.get("combo_required_count"))
		var each_min := float(spec.get("combo_each_min_force"))
		var win_override := float(spec.get("combo_window_sec"))
		var priority := int(spec.get("combo_priority"))
		if req <= 0:
			lines.append("  - " + String(id) + " skip (no combo trigger)")
			continue

		var use_window := (win_override if win_override > 0.0 else attack_window_sec)

		var considered := 0
		var count := 0
		for e in _punch_window:
			var age := eval_time - float(e["t"])
			if age <= use_window and age >= 0.0:
				considered += 1
				if float(e["force"]) >= each_min:
					count += 1

		var match := (count >= req)
		lines.append("  - " + String(id) + " req=" + str(req) + " each_min=" + str(each_min) + " win=" + str(use_window) + "s considered=" + str(considered) + " count=" + str(count) + " match=" + str(match) + " pri=" + str(priority))

		if match:
			var better := false
			if priority > best_pri: better = true
			elif priority == best_pri and req > best_req: better = true
			elif priority == best_pri and req == best_req and each_min > best_force: better = true
			if better:
				best_id = id
				best_pri = priority
				best_req = req
				best_force = each_min

	if String(best_id) != "":
		lines.append("[Combo] picked=" + String(best_id) + " pri=" + str(best_pri) + " req=" + str(best_req) + " each_min=" + str(best_force))
	else:
		lines.append("[Combo] none matched")

	_last_combo_debug = "\n".join(lines)
	if debug_enabled and _last_combo_debug != "":
		print(_last_combo_debug)
	return best_id

# ----------------------------
# Auto-targeting helpers
# ----------------------------
func _find_target_now() -> void:
	_autotarget_next_check_at = _now() + max(0.05, auto_target_reacquire_interval)

	# Prefer last aggressor
	if _is_valid_target(_last_aggressor) and (_now() - _last_aggressed_at) <= aggro_memory_sec:
		set_fight_target(_last_aggressor)
		return

	# Closest alive fighter
	var best: BaseCharacter = null
	var best_d2 := 1e30
	for n in get_tree().get_nodes_in_group("fighters"):
		if n == self: continue
		if not _is_valid_target(n): continue
		var bc := n as BaseCharacter
		var d2 := (bc.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = bc
	if best: set_fight_target(best)

func _is_valid_target(n: Node) -> bool:
	if n == null or not is_instance_valid(n): return false
	if not (n is BaseCharacter): return false
	var bc := n as BaseCharacter
	if bc == self: return false
	if not bc.is_inside_tree(): return false
	if bc.is_knocked_out(): return false
	return true

func _connect_target_signals(t: Node):
	_disconnect_target_signals()
	if t is BaseCharacter:
		var bc := t as BaseCharacter
		if bc.has_signal("knocked_out") and not bc.is_connected("knocked_out", Callable(self, "_on_target_knocked_out")):
			bc.connect("knocked_out", Callable(self, "_on_target_knocked_out"))
		_connected_target = bc

func _disconnect_target_signals():
	if _connected_target and is_instance_valid(_connected_target):
		if _connected_target.is_connected("knocked_out", Callable(self, "_on_target_knocked_out")):
			_connected_target.disconnect("knocked_out", Callable(self, "_on_target_knocked_out"))
	_connected_target = null

func _on_target_knocked_out() -> void:
	clear_target()
	if auto_target_enabled and round_active:
		_find_target_now()

# ----------------------------
# Intent selection and autopilot
# ----------------------------
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
			# If you added _intent_mag_y, use it here; otherwise keep step_back_mag.
			# var back_mag: float = clampf(_intent_mag_y, 0.0, 1.0)
			var back_mag: float = min(step_back_mag, retreat_max_mag)
			ml.y = -back_mag
		Intent.STEP_IN:
			if _rush_active:
				# Distance-limited rush toward stop with hysteresis
				if d > (_rush_stop_dist + standoff_hysteresis_m):
					ml.y = 1.0
				elif now > _rush_giveup_at:
					_end_rush(now)  # blocked too long
				else:
					_end_rush(now)  # reached stop band
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
	# - not frozen, not rushing, not already committed, and out of reaction lag
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

# ----------------------------
# Movement helpers
# ----------------------------
# Replace this function to keep input magnitude (no normalization, just clamp length <= 1)
func _compute_desired_world_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var local_move: Vector2 = intents["move_local"]
	var world_dir: Vector3 = (forward * local_move.y) + (right * local_move.x)
	# Preserve magnitude so |local_move| scales speed; clamp so diagonals don't exceed 1
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

# ----------------------------
# Combat
# ----------------------------
# Replace this function so applied speed is recorded; forward slowdown etc. stays intact
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

# Add verbose prints explaining how an attack is chosen and which phase we enter.
func _handle_attack_intent() -> void:
	var now: float = _now()

	var pressed: bool = bool(intents["attack"])
	var rising: bool = pressed and not _attack_intent_prev
	var wish_active: bool = now <= _attack_wish_until

	_attack_intent_prev = pressed
	intents["attack"] = false

	if rising:
		_attack_wish_until = now + attack_press_retry_buffer_sec
		wish_active = true
		if debug_enabled:
			print("[AttackIntent] rising edge; wish_active set; _attack_wish_until=", str(_attack_wish_until))

	# If swinging, queue the next request only
	if _attack_phase == AttackPhase.SWING and wish_active:
		if debug_enabled:
			print("[AttackIntent] currently SWING; queue next from intents (id=", String(intents["attack_id"]), " cat=", String(intents["attack_category"]), ")")
		_queue_next_from_intents()
		return

	if not wish_active and not rising:
		return
	if now - _fight_entered_at < attack_debounce_after_fight_enter:
		if debug_enabled: print("[AttackIntent] debounced right after fight enter")
		return
	if _attack_phase != AttackPhase.NONE:
		if debug_enabled: print("[AttackIntent] ignored: _attack_phase=", str(_attack_phase))
		return
	if not attack_library:
		if debug_enabled: push_warning("BaseCharacter: attack_library not assigned.")
		return

	# Choose attack id to try
	var requested_id: StringName = intents["attack_id"]
	var requested_cat: StringName = intents["attack_category"]
	var id: StringName = requested_id
	var pending_cat: StringName = &""
	var chosen_via_cat: bool = false

	if String(id) == "":
		if String(requested_cat) != "" and attack_set_data:
			id = attack_set_data.get_id_for_category(requested_cat)
			pending_cat = requested_cat
			chosen_via_cat = true

	if debug_enabled:
		print("[AttackSelect] requested_id='", String(requested_id), "' requested_cat='", String(requested_cat), "' => chosen_id='", String(id), "' via_cat=", str(chosen_via_cat))

	if String(id) == "":
		if debug_enabled: print("[AttackSelect] no id resolved; abort")
		return

	var spec = attack_library.get_spec(id)
	if spec == null:
		if debug_enabled: push_warning("BaseCharacter: unknown attack id=" + String(id))
		return

	var last_time: float = float(_last_attack_time_by_id.get(id, -1000.0))
	if now - last_time < max(0.0, spec.cooldown_sec):
		if debug_enabled: print("[AttackSelect] on cooldown; skip id=", String(id))
		return
	if not _has_target:
		if debug_enabled: print("[AttackSelect] no target")
		return

	var d2t: float = distance_to_target()
	var lower: float = float(max(0.0, spec.launch_min_distance))
	var upper: float = spec.enter_distance  # FIX: use spec, not _attack_spec_current
	var eps: float = float(max(0.0, launch_band_epsilon))

	var reposition_thresh: float = lower - eps
	var approach_thresh: float = upper + eps

	if debug_enabled:
		print("[AttackRange] d=", str(d2t), " lower=", str(lower), " upper=", str(upper), " eps=", str(eps), " -> reposition_thresh=", str(reposition_thresh), " approach_thresh=", str(approach_thresh))

	if lower > 0.0:
		if d2t < reposition_thresh:
			if animator and animator.has_method("start_fight_stance") and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			if debug_enabled: print("[AttackPhase] REPOSITION: too close (d<", str(reposition_thresh), ") for id=", String(id))
			_attack_phase = AttackPhase.REPOSITION
			_attack_spec_current = spec
			_attack_id_current = id
			_attack_cat_pending = pending_cat
			return
		elif d2t > approach_thresh:
			if animator and animator.has_method("start_fight_stance") and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			if debug_enabled: print("[AttackPhase] APPROACH: too far (d>", str(approach_thresh), ") for id=", String(id))
			_attack_phase = AttackPhase.APPROACH
			_attack_spec_current = spec
			_attack_id_current = id
			_attack_cat_pending = pending_cat
			return
		else:
			if debug_enabled: print("[AttackPhase] SWING: in band for id=", String(id))
			_attack_cat_pending = pending_cat
			_start_swing(spec, id, now)
			_attack_wish_until = 0.0
			return
	else:
		# No min distance: only check upper bound
		if d2t > approach_thresh:
			if animator and animator.has_method("start_fight_stance") and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			if debug_enabled: print("[AttackPhase] APPROACH (no lower bound) for id=", String(id))
			_attack_phase = AttackPhase.APPROACH
			_attack_spec_current = spec
			_attack_id_current = id
			_attack_cat_pending = pending_cat
		else:
			if debug_enabled: print("[AttackPhase] SWING (no lower bound) for id=", String(id))
			_attack_cat_pending = pending_cat
			_start_swing(spec, id, now)
			_attack_wish_until = 0.0

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
					_attack_wish_until = 0.0
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
					_attack_wish_until = 0.0
		AttackPhase.SWING:
			if now >= _attack_phase_until:
				_attack_phase = AttackPhase.NONE
				_attack_spec_current = null
				_attack_id_current = &""
				_attack_cat_current = &""
				_punch_force_current = 0.0
				_post_swing_until = now + max(0.0, post_swing_backstep_sec)
				if now <= _queued_until and (String(_queued_attack_id) != "" or String(_queued_attack_cat) != ""):
					if String(_queued_attack_id) != "":
						intents["attack_id"] = _queued_attack_id
						intents["attack_category"] = StringName("")
					else:
						intents["attack_id"] = StringName("")
						intents["attack_category"] = _queued_attack_cat
					intents["attack"] = true
					_attack_wish_until = now + attack_press_retry_buffer_sec

func _queue_next_from_intents() -> void:
	var id: StringName = intents["attack_id"]
	var cat: StringName = intents["attack_category"]
	if String(id) == "" and String(cat) == "": return
	_queued_attack_id = id
	_queued_attack_cat = cat
	_queued_until = _now() + attack_queue_buffer_sec
	intents["attack"] = false

func _clear_queue() -> void:
	_queued_attack_id = &""
	_queued_attack_cat = &""
	_queued_until = 0.0

# REPLACE: _start_swing to trigger Hitbox3D
func _start_swing(spec, id: StringName, now: float) -> void:
	_attack_spec_current = spec
	_attack_id_current = id
	_last_attack_time_by_id[id] = now
	state = State.ATTACKING
	emit_signal("attacked_id", id)

	_attack_cat_current = _attack_cat_pending
	_punch_force_current = _punch_force_pending
	_attack_cat_pending = &""
	_punch_force_pending = 0.0

	if debug_enabled:
		print("[Swing] START id=", String(id), " cat=", String(_attack_cat_current), " force=", str(_punch_force_current))

	if animator and animator.has_method("play_attack_id"):
		if not (animator.has_method("is_in_fight_stance") and animator.is_in_fight_stance()):
			if animator.has_method("start_fight_stance"): animator.start_fight_stance()
		animator.play_attack_id(id)

	# Lock movement during swing
	_move_locked_until = now + max(0.0, spec.move_lock_sec)
	_attack_phase = AttackPhase.SWING
	_attack_phase_until = now + max(0.0, spec.swing_time_sec)

	# Activate permanent Hitbox3D using spec timing (active_start_sec/end_sec)
	if hitbox:
		activate_hitbox_for_attack(_attack_id_current, _attack_spec_current, _punch_force_current)

# REPLACE: anim_event_hit to avoid direct damage (Hitbox3D handles collisions)
func anim_event_hit() -> void:
	# Keep for VFX/SFX timing only. Do not apply damage here.
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
	_attack_cat_pending = &""
	_attack_cat_current = &""
	_punch_force_pending = 0.0
	_punch_force_current = 0.0
	_post_swing_until = 0.0
	_clear_queue()
	_attack_wish_until = 0.0

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
	_attack_cat_pending = &""
	_attack_cat_current = &""
	_punch_force_pending = 0.0
	_punch_force_current = 0.0
	_post_swing_until = 0.0
	_clear_queue()
	_attack_wish_until = 0.0
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

# UPDATED: buffer punch, but cut-and-finalize if this punch would exceed attack_window_sec
func _on_punched(source_id: int, force: float) -> void:
	_dbg("[Punch] src=" + str(source_id) + " force=" + str(force))

	if not round_active: return
	if input_source_id == 0 and not accept_any_source_if_zero: return
	if input_source_id != 0 and source_id != input_source_id: return
	if state == State.KO: return

	var now := _now()

	# If there is an active window and it's too old, finalize it immediately
	if not _punch_window.is_empty():
		var span := now - _window_start
		if span > attack_window_sec:
			# Force-finalize the previous window using the last punch in that window
			var last_force := float(_punch_window.back().get("force", 0.0))
			_dbg("[Window] span " + str(span) + "s > " + str(attack_window_sec) + "s; force-finalize previous window")
			_force_finalize_current_window(now, last_force, "max_window")

			# Start a fresh window anchored at this punch
			_punch_window.clear()
			_window_start = now
			_dbg("[Window] new window start at " + str(_window_start))

	# If no active window, start one now
	if _punch_window.is_empty():
		_window_start = now
		_dbg("[Window] start at " + str(_window_start))

	# Record this punch into the (possibly new) window
	_punch_window.append({ "t": now, "force": force, "src": source_id })
	_last_punch_force = force

	# Schedule finalize after inactivity gap
	_combo_finalize_at = now + max(0.0, combo_finalize_gap_sec)
	_window_dirty = true
	_dbg("[Window] size=" + str(_punch_window.size()) + " finalize_at=" + str(_combo_finalize_at))


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

# ----------------------------
# Damage resolution
# ----------------------------
func _get_current_attack_damage() -> int:
	var base_dmg: float = 0.0

	if _attack_spec_current and _attack_spec_current.has_method("get"):
		var v: Variant = _attack_spec_current.get("damage")
		if typeof(v) != TYPE_NIL:
			base_dmg = float(v)
		if base_dmg <= 0.0:
			var v2: Variant = _attack_spec_current.get("damage_amount")
			if typeof(v2) != TYPE_NIL:
				base_dmg = float(v2)
		if base_dmg <= 0.0:
			var v3: Variant = _attack_spec_current.get("power")
			if typeof(v3) != TYPE_NIL:
				base_dmg = float(v3)

	if base_dmg <= 0.0:
		if _attack_cat_current == category_special:
			base_dmg = float(default_special_damage)
		elif _attack_cat_current == category_heavy:
			base_dmg = float(default_heavy_damage)
		elif _attack_cat_current == category_medium:
			base_dmg = float(default_medium_damage)
		else:
			base_dmg = float(default_light_damage)

	if scale_damage_by_force and _punch_force_current > 0.0:
		var lo: float = light_force_min
		var hi: float = light_force_max
		if _attack_cat_current == category_special:
			lo = special_force_min; hi = special_force_max
		elif _attack_cat_current == category_heavy:
			lo = heavy_force_min; hi = heavy_force_max
		elif _attack_cat_current == category_medium:
			lo = medium_force_min; hi = medium_force_max
		if hi > lo:
			var f: float = clamp(_punch_force_current, lo, hi)
			var t: float = (f - lo) / (hi - lo)
			var scale: float = lerp(min_damage_scale, max_damage_scale, t)
			base_dmg *= scale

	return int(round(max(0.0, base_dmg)))

# ----------------------------
# Utilities
# ----------------------------
func distance_to_target() -> float:
	return (get_target_position() - global_position).length()

func _vector_to_target() -> Vector3:
	var v: Vector3 = get_target_position() - global_position
	v.y = 0.0
	return v

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

func _track_target_motion() -> void:
	var now: float = _now()
	_last_dist_to_target = distance_to_target()
	_last_update_time = now
	_last_target_vec = _vector_to_target()
	_last_target_vec_time = now

func _world_dir_to_local_move(world_dir: Vector3) -> Vector2:
	var right: Vector3 = global_transform.basis.x
	var forward: Vector3 = -global_transform.basis.z
	var x: float = world_dir.dot(right)
	var y: float = world_dir.dot(forward)
	return Vector2(x, y)

func _nav_closest_on_map(world_point: Vector3) -> Vector3:
	if not agent: return world_point
	var map_rid: RID = agent.get_navigation_map()
	return NavigationServer3D.map_get_closest_point(map_rid, world_point)

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _category_from_force(force: float) -> StringName:
	if not use_force_ranges:
		return category_heavy if force >= medium_force_min else category_light
	if force >= special_force_min and force <= special_force_max:
		return category_special
	if force >= heavy_force_min and force <= heavy_force_max:
		return category_heavy
	if force >= medium_force_min and force <= medium_force_max:
		return category_medium
	return category_light

func _set_autopilot_move_towards(world_target: Vector3) -> void:
	var dir_world: Vector3 = Vector3.ZERO
	if agent:
		var next_pos: Vector3 = agent.get_next_path_position()
		var to_next: Vector3 = next_pos - global_position
		to_next.y = 0.0
		dir_world = to_next if to_next.length() > 0.001 else (world_target - global_position)
	else:
		dir_world = world_target - global_position
	dir_world.y = 0.0

	var eps: float = 0.001
	var dist_to_target: float = (world_target - global_position).length()

	if dir_world.length() <= eps and dist_to_target > move_arrival_tolerance:
		_stuck_frames += 1
		if _stuck_frames <= nav_stuck_memory_frames:
			intents["move_local"] = _last_move_local
		else:
			intents["move_local"] = Vector2.ZERO
	else:
		_stuck_frames = 0
		if dir_world.length() > eps:
			dir_world = dir_world.normalized()
		var right: Vector3 = global_transform.basis.x
		var forward: Vector3 = -global_transform.basis.z
		var x: float = dir_world.dot(right)
		var y: float = dir_world.dot(forward)
		var move_local: Vector2 = Vector2(x, y)
		intents["move_local"] = move_local.normalized() if move_local.length() > 0.001 else Vector2.ZERO
		_last_move_local = intents["move_local"]

func _set_autopilot_move_away_from(world_target: Vector3) -> void:
	var to_target: Vector3 = world_target - global_position
	to_target.y = 0.0
	var dir_world: Vector3 = Vector3.ZERO
	if to_target.length() > 0.001:
		dir_world = -to_target.normalized()

	var right: Vector3 = global_transform.basis.x
	var forward: Vector3 = -global_transform.basis.z
	var x: float = dir_world.dot(right)
	var y: float = dir_world.dot(forward)
	var move_local: Vector2 = Vector2(x, y)
	if move_local.length() > 0.001:
		move_local = move_local.normalized()
	if move_local.y > -0.2:
		move_local.y = -0.2
	intents["move_local"] = move_local
	_last_move_local = intents["move_local"]

func _end_rush(now: float) -> void:
	_rush_active = false
	_intent = Intent.HOLD
	_intent_until = now + standoff_pause_sec
	_next_decision_at = _intent_until + _rng.randf_range(0.1, 0.3)

# ADD: Activate our permanent Hitbox3D using spec timing.
func activate_hitbox_for_attack(attack_id: StringName, spec: Resource, impact_force: float, reach_override_m: float = -1.0) -> void:
	if hitbox == null:
		_combat_log("No Hitbox3D node under this character.")
		return
	# Optional per-attack reach override:
	# if reach_override_m >= 0.0:
	# 	hitbox.set_reach_meters(reach_override_m)

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
		_apply_knockback(dir, velocity, kb_dur)
		_combat_log("apply_hit: knockback " + str(kb_m) + "m over " + str(kb_dur) + "s")


func _apply_knockback(direction: Vector3, velocity: float, duration: float):
	knockback_velocity = direction.normalized() * velocity
	knockback_timer = duration

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
