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

@export_category("Combat (Data-Driven)")
@export var keep_eyes_on_target: bool = true
@export var approach_speed_scale: float = 0.8
@export var attack_library: AttackLibrary = preload("res://characters/Attacks/AttackLibrary.tres")
@export var attack_set: AttackSet = preload("res://characters/Attacks/DefaultAttackSet.tres")
@export var attack_debounce_after_fight_enter: float = 0.15
@export var launch_band_epsilon: float = 0.1   # tolerance to avoid oscillation when distances are tight

# Input buffers to make spamming feel responsive
@export var attack_press_retry_buffer_sec: float = 0.25  # while held, auto-retry within this window
@export var attack_queue_buffer_sec: float = 0.25        # window to buffer a follow-up during SWING

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

# Intents: attack by category or id
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

# Per-attack cooldowns keyed by id
var _last_attack_time_by_id := {}

# Attack phases
enum AttackPhase { NONE, APPROACH, REPOSITION, SWING }
var _attack_phase: int = AttackPhase.NONE
var _attack_phase_until: float = 0.0
var _attack_spec_current: AttackSpec
var _attack_id_current: StringName = &""

# Debounce and movement lock
var _fight_entered_at: float = -1e9
var _attack_intent_prev: bool = false
var _move_locked_until: float = 0.0

# Input buffering
var _attack_wish_until: float = 0.0
var _queued_attack_cat: StringName = &""
var _queued_attack_id: StringName = &""
var _queued_until: float = 0.0

# Hysteresis memory
var _last_move_local: Vector2 = Vector2.ZERO
var _stuck_frames: int = 0

func _ready() -> void:
	var model := $Model if has_node("Model") else null
	if model:
		anim = (model.find_child("AnimationPlayer") as AnimationPlayer)
	if anim:
		anim.connect("animation_finished", Callable(self, "_on_animation_finished"))

	agent = (get_node_or_null(navigation_agent_path) as NavigationAgent3D) if navigation_agent_path != NodePath("") else ($NavigationAgent3D as NavigationAgent3D)
	stats = get_node_or_null(stats_node_path) if stats_node_path != NodePath("") else $Stats
	animator = (get_node_or_null(animator_path) as CharacterAnimator) if animator_path != NodePath("") else ($CharacterAnimator as CharacterAnimator)

	if stats:
		if stats.has_signal("died"): stats.connect("died", Callable(self, "_on_died"))
		if stats.has_signal("health_changed"): stats.connect("health_changed", Callable(self, "_on_health_changed"))

	if agent:
		agent.path_desired_distance = 0.5
		agent.target_desired_distance = 0.75

# ----------------------------
# Public helpers for controllers
# ----------------------------
func request_attack_category(cat: StringName) -> void:
	intents["attack_category"] = cat
	intents["attack_id"] = StringName("")
	intents["attack"] = true
	_attack_wish_until = _now() + attack_press_retry_buffer_sec

func request_attack_id(id: StringName) -> void:
	intents["attack_id"] = id
	intents["attack_category"] = StringName("")
	intents["attack"] = true
	_attack_wish_until = _now() + attack_press_retry_buffer_sec

# ----------------------------
# Targeting / Stance
# ----------------------------
func set_target(t: Variant) -> void:
	set_fight_target(t)

func set_move_target(t: Variant) -> void:
	_set_target_internal(t, TargetMode.MOVE)
	if animator: animator.end_fight_stance()

func set_fight_target(t: Variant) -> void:
	_set_target_internal(t, TargetMode.FIGHT)
	if animator: animator.start_fight_stance()
	_fight_entered_at = _now()
	intents["attack"] = false
	_attack_intent_prev = false

func clear_target() -> void:
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
	_clear_queue()
	if agent: agent.target_position = global_position
	if animator: animator.end_fight_stance()

func _set_target_internal(t: Variant, mode: int) -> void:
	_target_mode = mode
	if t is Node3D:
		_target_node = t
		_has_target = true
		var dest: Vector3 = _target_node.global_position
		if nav_clamp_targets and agent and mode == TargetMode.MOVE:
			dest = _nav_closest_on_map(dest)
		if agent: agent.target_position = dest
	elif t is Vector3:
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

# ----------------------------
# Core loop
# ----------------------------
func _physics_process(delta: float) -> void:
	if state == State.KO: return

	# Gravity
	if use_gravity:
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
	else:
		velocity.y = 0.0

	# Follow moving target
	if agent and _has_target and _target_node:
		var dest: Vector3 = _target_node.global_position
		if nav_clamp_targets and _target_mode == TargetMode.MOVE:
			dest = _nav_closest_on_map(dest)
		agent.target_position = dest

	# Autopilot
	if use_agent_autopilot:
		_update_autopilot_intents()

	# Steering and velocity
	var desired_move_dir_world: Vector3 = _compute_desired_world_direction()
	_apply_rotation_towards_target_or_velocity(desired_move_dir_world, delta)
	_apply_horizontal_velocity(desired_move_dir_world)

	# Move
	var prev_position: Vector3 = global_position
	move_and_slide()

	# Stamina drain (optional)
	var delta_pos: Vector3 = global_position - prev_position
	var moved_distance: float = delta_pos.length()
	if stats and moved_distance > 0.0 and stats.has_method("spend_movement"):
		stats.spend_movement(moved_distance)

	# Speed and locomotion state
	var measured_h_speed: float = Vector2(delta_pos.x, delta_pos.z).length() / max(delta, 1e-6)
	state = State.MOVING if measured_h_speed > 0.1 else State.IDLE

	# Combat
	_handle_attack_intent()
	_tick_attack_phase()

	# Anim
	if animator:
		animator.update_locomotion(intents["move_local"], measured_h_speed)

# ----------------------------
# Autopilot
# ----------------------------
func _update_autopilot_intents() -> void:
	if not _has_target:
		return

	var now: float = _now()
	# Movement lock
	if now < _move_locked_until:
		if animator and not animator.is_in_fight_stance():
			animator.start_fight_stance()
		intents["move_local"] = Vector2.ZERO
		intents["run"] = false
		intents["retreat"] = false
		return

	match _attack_phase:
		AttackPhase.APPROACH:
			if animator and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			_set_autopilot_move_towards(get_target_position())
			intents["run"] = false
			intents["retreat"] = false
			return
		AttackPhase.REPOSITION:
			if animator and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			_set_autopilot_move_away_from(get_target_position())
			intents["run"] = false
			intents["retreat"] = true
			return
		AttackPhase.SWING:
			if animator and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			intents["move_local"] = Vector2.ZERO
			intents["run"] = false
			intents["retreat"] = false
			return
		_:
			pass

	# Idle: hold or travel to move target
	if _target_mode == TargetMode.MOVE:
		var to_target: Vector3 = get_target_position() - global_position
		to_target.y = 0.0
		if to_target.length() <= move_arrival_tolerance or (agent and agent.is_navigation_finished()):
			intents["move_local"] = Vector2.ZERO
			intents["run"] = false
			intents["retreat"] = false
			clear_target()
			return
		_set_autopilot_move_towards(get_target_position())
		intents["run"] = to_target.length() > run_distance_threshold
		intents["retreat"] = false
	else:
		intents["move_local"] = Vector2.ZERO
		intents["run"] = false
		intents["retreat"] = false

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

# Move directly away from target (backpedal)
func _set_autopilot_move_away_from(world_target: Vector3) -> void:
	var to_target: Vector3 = world_target - global_position
	to_target.y = 0.0
	var dir_world: Vector3 = Vector3.ZERO
	if to_target.length() > 0.001:
		dir_world = -to_target.normalized() # away from target

	var right: Vector3 = global_transform.basis.x
	var forward: Vector3 = -global_transform.basis.z
	var x: float = dir_world.dot(right)
	var y: float = dir_world.dot(forward)
	var move_local: Vector2 = Vector2(x, y)
	if move_local.length() > 0.001:
		move_local = move_local.normalized()
	# Ensure a small backpedal even if almost aligned
	if move_local.y > -0.2:
		move_local.y = -0.2
	intents["move_local"] = move_local
	_last_move_local = intents["move_local"]

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

# Only sets horizontal velocity
func _apply_horizontal_velocity(desired_dir_world: Vector3) -> void:
	var local_move: Vector2 = intents["move_local"]
	var speed: float = walk_speed
	if bool(intents["run"]) and bool(intents["retreat"]):
		speed = run_speed
	elif local_move.y < -0.01:
		speed = backpedal_speed
	elif absf(local_move.x) > 0.01 and absf(local_move.y) < 0.01:
		speed = strafe_speed
	elif bool(intents["run"]):
		speed = run_speed

	# Slow down while closing or creating space
	if _attack_phase == AttackPhase.APPROACH or _attack_phase == AttackPhase.REPOSITION:
		speed *= clampf(approach_speed_scale, 0.05, 1.0)

	var horizontal_vel: Vector3 = desired_dir_world * speed
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z

# ----------------------------
# Combat (ID/category-driven) with epsilon-tolerant "launch band"
# ----------------------------
func _handle_attack_intent() -> void:
	var now: float = _now()

	# Check current press and buffered "wish"
	var pressed: bool = bool(intents["attack"])
	var rising: bool = pressed and not _attack_intent_prev
	var wish_active: bool = now <= _attack_wish_until

	# Update edge detector and clear one-shot flag
	_attack_intent_prev = pressed
	intents["attack"] = false

	# On rising edge, extend the wish window to auto-retry briefly
	if rising:
		_attack_wish_until = now + attack_press_retry_buffer_sec
		wish_active = true

	# If we're currently swinging, allow queuing the next move while within buffer
	if _attack_phase == AttackPhase.SWING and wish_active:
		_queue_next_from_intents()
		return

	# If there's no active wish and no rising edge, do nothing
	if not wish_active and not rising:
		return

	# Debounce after entering stance
	if now - _fight_entered_at < attack_debounce_after_fight_enter:
		return

	# Already in an attack flow?
	if _attack_phase != AttackPhase.NONE:
		return

	# Need a library
	if not attack_library:
		if debug_enabled: push_warning("BaseCharacter: attack_library not assigned.")
		return

	# Resolve ID from intents
	var id: StringName = intents["attack_id"]
	if String(id) == "":
		var cat: StringName = intents["attack_category"]
		if String(cat) != "" and attack_set:
			id = attack_set.get_id_for_category(cat)
	if String(id) == "":
		if debug_enabled: push_warning("BaseCharacter: no attack_id and no attack_set/category provided.")
		return

	var spec: AttackSpec = attack_library.get_spec(id)
	if spec == null:
		if debug_enabled: push_warning("BaseCharacter: unknown attack id=" + String(id))
		return

	# Per-id cooldown gate
	var last_time: float = float(_last_attack_time_by_id.get(id, -1000.0))
	if now - last_time < max(0.0, spec.cooldown_sec):
		# Keep wish active; it'll retrigger when cooldown ends (within buffer window)
		return

	# Must have target
	if not _has_target:
		return

	# Decide phase based on distance band with tolerance
	var d: float = distance_to_target()
	var lower: float = float(max(0.0, spec.launch_min_distance))
	var upper: float = spec.enter_distance
	var eps: float = float(max(0.0, launch_band_epsilon))

	var reposition_thresh: float = lower - eps
	var approach_thresh: float = upper + eps

	if lower > 0.0:
		if d < reposition_thresh:
			# too close -> back up first
			if animator and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			_attack_phase = AttackPhase.REPOSITION
			_attack_spec_current = spec
			_attack_id_current = id
			if debug_enabled:
				print_debug("[BC] REPOSITION id=", String(id), " d=", d, " < ", reposition_thresh, " (min=", lower, " eps=", eps, ")")
			return
		elif d > approach_thresh:
			# too far -> approach
			if animator and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			_attack_phase = AttackPhase.APPROACH
			_attack_spec_current = spec
			_attack_id_current = id
			if debug_enabled:
				print_debug("[BC] APPROACH id=", String(id), " d=", d, " > ", approach_thresh, " (enter=", upper, " eps=", eps, ")")
			return
		else:
			# within tolerant band -> swing
			_start_swing(spec, id, now)
			_attack_wish_until = 0.0
			return
	else:
		# No lower bound: original behavior, with approach hysteresis
		if d > approach_thresh:
			if animator and not animator.is_in_fight_stance():
				animator.start_fight_stance()
			_attack_phase = AttackPhase.APPROACH
			_attack_spec_current = spec
			_attack_id_current = id
			if debug_enabled:
				print_debug("[BC] APPROACH id=", String(id), " d=", d, " > ", approach_thresh)
		else:
			_start_swing(spec, id, now)
			_attack_wish_until = 0.0

func _tick_attack_phase() -> void:
	if _attack_phase == AttackPhase.NONE:
		return
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
					if debug_enabled:
						print_debug("[BC] APPROACH->REPOSITION d=", d, " < ", reposition_thresh)
				elif d <= swing_upper:
					_start_swing(_attack_spec_current, _attack_id_current, now)
					_attack_wish_until = 0.0
		AttackPhase.REPOSITION:
			if _attack_spec_current:
				var d: float = distance_to_target()
				var lower: float = float(max(0.0, _attack_spec_current.launch_min_distance))
				var upper: float = _attack_spec_current.enter_distance
				var eps: float = float(max(0.0, launch_band_epsilon))
				var approach_thresh: float = upper + eps
				var swing_lower: float = lower - eps
				if d > approach_thresh:
					_attack_phase = AttackPhase.APPROACH
					if debug_enabled:
						print_debug("[BC] REPOSITION->APPROACH d=", d, " > ", approach_thresh)
				elif d >= swing_lower:
					_start_swing(_attack_spec_current, _attack_id_current, now)
					_attack_wish_until = 0.0
		AttackPhase.SWING:
			if now >= _attack_phase_until:
				_attack_phase = AttackPhase.NONE
				_attack_spec_current = null
				_attack_id_current = &""
				# Pop queued attack if still valid
				if now <= _queued_until and (String(_queued_attack_id) != "" or String(_queued_attack_cat) != ""):
					if String(_queued_attack_id) != "":
						intents["attack_id"] = _queued_attack_id
						intents["attack_category"] = StringName("")
					else:
						intents["attack_id"] = StringName("")
						intents["attack_category"] = _queued_attack_cat
					intents["attack"] = true
					_attack_wish_until = now + attack_press_retry_buffer_sec
				_clear_queue()
		_:
			pass

func _queue_next_from_intents() -> void:
	var id: StringName = intents["attack_id"]
	var cat: StringName = intents["attack_category"]
	if String(id) == "" and String(cat) == "":
		return
	_queued_attack_id = id
	_queued_attack_cat = cat
	_queued_until = _now() + attack_queue_buffer_sec
	# Clear one-shot intent flag so it won’t continuously spam
	intents["attack"] = false
	if debug_enabled:
		print_debug("[BC] Queued next attack: id=", String(id), " cat=", String(cat))

func _clear_queue() -> void:
	_queued_attack_id = &""
	_queued_attack_cat = &""
	_queued_until = 0.0

func _start_swing(spec: AttackSpec, id: StringName, now: float) -> void:
	_last_attack_time_by_id[id] = now
	state = State.ATTACKING
	emit_signal("attacked_id", id)

	if animator:
		if not animator.is_in_fight_stance():
			animator.start_fight_stance()
		animator.play_attack_id(id)

	# Lock movement and set swing window
	_move_locked_until = now + max(0.0, spec.move_lock_sec)
	_attack_phase = AttackPhase.SWING
	_attack_phase_until = now + max(0.0, spec.swing_time_sec)

func anim_event_hit() -> void:
	emit_signal("attack_landed", 1.0)

func take_hit(amount: int) -> void:
	if state == State.KO: return
	if stats and stats.has_method("take_damage"):
		stats.take_damage(amount)
	emit_signal("took_hit", amount)
	if animator: animator.play_hit(amount)
	state = State.STAGGERED
	_attack_phase = AttackPhase.NONE
	_attack_phase_until = 0.0
	_move_locked_until = 0.0
	_attack_spec_current = null
	_attack_id_current = &""
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
	_clear_queue()
	_attack_wish_until = 0.0
	if animator: animator.play_ko()

func _on_animation_finished(_name: StringName) -> void:
	if state in [State.ATTACKING, State.STAGGERED]:
		state = State.IDLE

# ----------------------------
# Utilities
# ----------------------------
func distance_to_target() -> float:
	return (get_target_position() - global_position).length()

func _nav_closest_on_map(world_point: Vector3) -> Vector3:
	if not agent: return world_point
	var map_rid: RID = agent.get_navigation_map()
	return NavigationServer3D.map_get_closest_point(map_rid, world_point)

func _now() -> float:
	# Monotonic, high-resolution time in seconds
	return float(Time.get_ticks_msec()) / 1000.0
