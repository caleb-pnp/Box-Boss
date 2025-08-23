extends Node
class_name CharacterAnimator

@export_category("Model Root (Preferred)")
@export var model_root_path: NodePath

@export_category("State Machine States")
@export var state_moving: StringName = &"Moving"
@export var state_fighting: StringName = &"Fighting"

@export_category("Locomotion Blend Params")
@export var moving_blend_param: StringName = &"parameters/Moving/Move2D/blend_position"
@export var fighting_blend_param: StringName = &"parameters/Fighting/Move2D/blend_position"

@export_category("Optional Reacts")
@export var hit_request_param: StringName = &""
@export var ko_request_param: StringName = &""

@export_category("Locomotion Mapping")
@export var swap_xy: bool = false
@export var invert_x: bool = false
@export var invert_y: bool = false
@export var input_deadzone: float = 0.05

@export_category("Speed/Radius")
@export var use_speed_scale_for_radius: bool = false
@export var speed_for_full_blend: float = 6.0
@export var smooth_input: bool = false
@export var locomotion_smoothing: float = 12.0

@export_category("Optional Time Scale")
@export var time_scale_param: StringName = &"parameters/Fighting/Move2DTimeScale/scale"
@export var min_time_scale: float = 0.1
@export var max_time_scale: float = 1.5
@export var move2d_timescale_threshold: float = 0.1
@export var move2d_timescale_idle: float = 1.0
@export var move2d_timescale_active: float = 1.5

@export_category("Attacks (Data-Driven)")
@export var attack_library: AttackLibrary = preload("res://characters/Attacks/AttackLibrary.tres")

@export_category("Attacks: Restart Behavior")
@export var attack_smooth_restart: bool = true
@export var attack_fadein_time: float = 0.10
@export var attack_fadeout_time: float = 0.10
@export var attack_restart_wait: float = 0.06

@export_category("Debug")
@export var debug_enabled: bool = false
@export var debug_interval: float = 0.25
@export var log_param_discovery: bool = true
@export var debug_verbose: bool = false

const DEFAULT_MODEL_NAME := "Model"

var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var anim_player: AnimationPlayer
var _fight_mode: bool = false

var _blend_vec: Vector2 = Vector2.ZERO
var _dbg_accum: float = 0.0
var _param_names: PackedStringArray = []

# Toggle map for A/B lanes per AttackSpec.id
var _toggle_by_attack_id := {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	call_deferred("_resolve_anim_nodes")

# ------------ Stance control ------------
func start_fight_stance() -> void:
	_fight_mode = true
	_travel_to_current_stance()

func end_fight_stance() -> void:
	_fight_mode = false
	_travel_to_current_stance()

func set_fight_stance(active: bool) -> void:
	_fight_mode = active
	_travel_to_current_stance()

func is_in_fight_stance() -> bool:
	return _fight_mode

# ------------ Driving ------------
func update_locomotion(local_move: Vector2, horizontal_speed: float) -> void:
	if not _ensure_tree():
		return

	var v := local_move
	if v.length() < input_deadzone:
		v = Vector2.ZERO

	if swap_xy: v = Vector2(v.y, v.x)
	if invert_x: v.x = -v.x
	if invert_y: v.y = -v.y

	var target := v
	if use_speed_scale_for_radius:
		var dir := v.normalized() if v.length() > 0.0001 else Vector2.ZERO
		var radius := clampf(horizontal_speed / max(0.001, speed_for_full_blend), 0.0, 1.0)
		target = dir * radius

	if smooth_input and locomotion_smoothing > 0.0:
		var alpha := clampf(locomotion_smoothing * get_physics_process_delta_time(), 0.0, 1.0)
		_blend_vec = _blend_vec.lerp(target, alpha)
	else:
		_blend_vec = target

	_ensure_blend_params()
	_set_vec2(moving_blend_param, _blend_vec)
	_set_vec2(fighting_blend_param, _blend_vec)

	if time_scale_param != &"":
		var ax := absf(_blend_vec.x)
		var ay := absf(_blend_vec.y)
		var active := (ax >= move2d_timescale_threshold) or (ay >= move2d_timescale_threshold)
		_set_float(time_scale_param, move2d_timescale_active if active else move2d_timescale_idle)

	_travel_to_current_stance()

# ------------ Attacks / Reacts ------------
# Play by attack ID (Animator loads spec, uses its A/B params)
func play_attack_id(id: StringName) -> void:
	if not _ensure_tree():
		return
	if not _fight_mode:
		start_fight_stance()
	if not attack_library:
		push_warning("CharacterAnimator: no attack_library set; cannot play id=" + String(id))
		return
	var spec: AttackSpec = attack_library.get_spec(id)
	if spec == null:
		push_warning("CharacterAnimator: unknown attack id=" + String(id))
		return

	var req_a := spec.request_param_a
	var req_b := spec.request_param_b
	if req_a == &"" and req_b == &"":
		push_warning("CharacterAnimator: spec has no OneShot params for id=" + String(id))
		return

	var use_b := bool(_toggle_by_attack_id.get(spec.id, false))
	var chosen: StringName = req_b if (use_b and req_b != &"") else req_a
	await _fire_oneshot(chosen)
	_toggle_by_attack_id[spec.id] = not use_b

func play_hit(_amount: int) -> void:
	if not _ensure_tree() or hit_request_param == &"":
		return
	if not _fight_mode:
		start_fight_stance()
	await _fire_oneshot(hit_request_param)

func play_ko() -> void:
	if not _ensure_tree() or ko_request_param == &"":
		return
	await _fire_oneshot(ko_request_param)

# ------------ Internals ------------
func _ensure_blend_params() -> void:
	if not _tree:
		return
	if _param_names.is_empty():
		_cache_param_names()

	var moving_ok := _param_exists(String(moving_blend_param))
	var fighting_ok := _param_exists(String(fighting_blend_param))

	var found_moving := String(moving_blend_param)
	var found_fighting := String(fighting_blend_param)

	if not (moving_ok and fighting_ok):
		var moving_candidates: Array[String] = []
		var fighting_candidates: Array[String] = []
		for name in _param_names:
			if name.ends_with("/Move2D/blend_position"):
				var lname := name.to_lower()
				if lname.find("/moving/") >= 0:
					moving_candidates.append(name)
				elif lname.find("/fighting/") >= 0:
					fighting_candidates.append(name)

		if not moving_ok:
			if moving_candidates.size() > 0:
				found_moving = moving_candidates[0]
			else:
				for name in _param_names:
					if name.ends_with("/Move2D/blend_position"):
						found_moving = name
						break

		if not fighting_ok:
			if fighting_candidates.size() > 0:
				found_fighting = fighting_candidates[0]
			else:
				for name in _param_names:
					if name.ends_with("/Move2D/blend_position"):
						found_fighting = name
						break

		moving_blend_param = StringName(found_moving)
		fighting_blend_param = StringName(found_fighting)

		if log_param_discovery:
			print_debug("[Animator] Resolved blend params -> MOVING: ", moving_blend_param, " | FIGHTING: ", fighting_blend_param, " (moving_ok=", moving_ok, " fighting_ok=", fighting_ok, ")")
	elif log_param_discovery and debug_verbose:
		print_debug("[Animator] Blend params already valid: MOVING=", moving_blend_param, " FIGHTING=", fighting_blend_param)


func _ensure_tree() -> bool:
	if _tree:
		return true
	_resolve_anim_nodes()
	return _tree != null

func _travel_to_current_stance() -> void:
	if not _playback:
		return
	var target := state_fighting if _fight_mode else state_moving
	if _playback.get_current_node() != target:
		_playback.travel(target)

func _set_vec2(path: StringName, v: Vector2) -> bool:
	if path == &"" or not _tree: return false
	var spath := String(path)
	if _param_exists(spath):
		_tree.set(spath, v)
		return true
	return false

func _set_float(path: StringName, f: float) -> bool:
	if path == &"" or not _tree: return false
	var spath := String(path)
	if _param_exists(spath):
		_tree.set(spath, f)
		return true
	return false

func _resolve_anim_nodes() -> void:
	var model_root: Node = _resolve_model_root()
	if not model_root:
		push_warning("CharacterAnimator: Could not resolve model root (looked for '%s' or model_root_path)." % [DEFAULT_MODEL_NAME])
		return
	_tree = _find_animation_tree_best(model_root)
	anim_player = _find_animation_player(model_root)
	if _tree:
		_tree.active = true
		_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		_cache_param_names()

func _resolve_model_root() -> Node:
	if model_root_path != NodePath(""):
		return get_node_or_null(model_root_path)
	var parent := get_parent()
	if not parent: return null
	var sib := parent.get_node_or_null(DEFAULT_MODEL_NAME)
	return sib if sib else _find_first_named(parent, DEFAULT_MODEL_NAME)

func _find_first_named(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for c in root.get_children():
		var found := _find_first_named(c, target_name)
		if found: return found
	return null

func _find_animation_tree_best(root: Node) -> AnimationTree:
	var by_name_node: Node = root.find_child("AnimationTree", true, false)
	var by_name_tree: AnimationTree = by_name_node as AnimationTree
	if by_name_tree:
		return by_name_tree
	var first: AnimationTree = null
	var best: AnimationTree = null
	var stack: Array = [root]
	while stack.size() > 0:
		var n_node: Node = stack.pop_back()
		var n_tree: AnimationTree = n_node as AnimationTree
		if n_tree:
			if first == null: first = n_tree
			var playback: AnimationNodeStateMachinePlayback = n_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
			if playback and best == null:
				best = n_tree
		for c in n_node.get_children():
			stack.push_back(c)
	return best if best != null else first

func _find_animation_player(root: Node) -> AnimationPlayer:
	var by_name_node: Node = root.find_child("AnimationPlayer", true, false)
	var by_name_player: AnimationPlayer = by_name_node as AnimationPlayer
	if by_name_player: return by_name_player
	var as_player: AnimationPlayer = root as AnimationPlayer
	if as_player: return as_player
	for c in root.get_children():
		var found := _find_animation_player(c)
		if found: return found
	return null

func _cache_param_names() -> void:
	_param_names.clear()
	if not _tree: return
	var props := _tree.get_property_list()
	for p in props:
		if p is Dictionary and p.has("name"):
			_param_names.push_back(String(p["name"]))

func _param_exists(path: String) -> bool:
	if _param_names.is_empty():
		_cache_param_names()
	return _param_names.has(path)

# OneShot helper
func _fire_oneshot(req_param: StringName) -> void:
	if req_param == &"" or not _tree: return
	var req := String(req_param)
	if not _param_exists(req):
		push_warning("CharacterAnimator: OneShot param not found: " + req)
		return
	var active_path := req.replace("/request", "/active")
	var fadein_path := req.replace("/request", "/fadein_time")
	var fadeout_path := req.replace("/request", "/fadeout_time")
	if attack_fadein_time > 0.0 and _param_exists(fadein_path):
		_tree.set(fadein_path, attack_fadein_time)
	if attack_fadeout_time > 0.0 and _param_exists(fadeout_path):
		_tree.set(fadeout_path, attack_fadeout_time)
	var already_active := _param_exists(active_path) and bool(_tree.get(active_path))
	if attack_smooth_restart and already_active:
		_tree.set(active_path, false)
		var wait_s := (attack_restart_wait if attack_restart_wait > 0.0 else 0.06)
		await get_tree().create_timer(wait_s).timeout
	_tree.set(req, 1)
