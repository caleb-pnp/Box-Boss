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

@export_category("Attack OneShot Request Params (under FIGHTING)")
@export var attack_light_request_param: StringName = &"parameters/Fighting/LeadJabOneShot/request"
@export var attack_medium_request_param: StringName = &"parameters/Fighting/JabCrossOneShot/request"
@export var attack_heavy_request_param: StringName = &"parameters/Fighting/HookOneShot/request"
@export var attack_combo_request_param: StringName = &"parameters/Fighting/PunchComboOneShot/request"
@export var attack_uppercut_jab_request_param: StringName = &"parameters/Fighting/UppercutJabOneShot/request"
@export var attack_backflip_uppercut_request_param: StringName = &"parameters/Fighting/BackFlipToUppercutOneShot/request"

@export_category("Optional Reacts")
@export var hit_request_param: StringName = &""
@export var ko_request_param: StringName = &""

@export_category("Locomotion Mapping")
# If your BlendSpace2D axes differ from local_move (x=strife right, y=forward), adjust here.
@export var swap_xy: bool = false
@export var invert_x: bool = false
@export var invert_y: bool = false
@export var input_deadzone: float = 0.05

@export_category("Speed/Radius")
# If true, use direction from local_move and radius from horizontal_speed.
# If false, feed raw local_move directly to your BlendSpace2D.
@export var use_speed_scale_for_radius: bool = false
@export var speed_for_full_blend: float = 6.0  # typically your run_speed
@export var locomotion_smoothing: float = 12.0 # smoothing of the blend vector (higher = snappier)

@export_category("Optional Time Scale")
# Optionally scale an AnimationTree float parameter with speed (e.g., parameters/TimeScale/scale)
@export var time_scale_param: StringName = &""
@export var min_time_scale: float = 0.1
@export var max_time_scale: float = 1.5

@export_category("Debug")
@export var debug_enabled: bool = false
@export var debug_interval: float = 0.5
@export var log_param_discovery: bool = false
@export var debug_verbose: bool = false # Extra per-call logs for params/requests

@export_category("Tuning")
@export var light_threshold: float = 0.3
@export var heavy_threshold: float = 0.7

const DEFAULT_MODEL_NAME := "Model"

var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var anim_player: AnimationPlayer
var _fight_mode: bool = false

# Cached/smoothed blend
var _blend_vec: Vector2 = Vector2.ZERO
var _dbg_accum := 0.0
var _param_names: PackedStringArray = []

func _ready() -> void:
	# Skip resolving in the editor; do at runtime
	if Engine.is_editor_hint():
		return
	if debug_enabled:
		print_debug("[Animator] _ready() - deferring _resolve_anim_nodes. model_root_path=", model_root_path)
	call_deferred("_resolve_anim_nodes")

# ------------ Stance control ------------
func start_fight_stance() -> void:
	if debug_enabled:
		print_debug("[Animator] start_fight_stance()")
	_fight_mode = true
	_travel_to_current_stance()

func end_fight_stance() -> void:
	if debug_enabled:
		print_debug("[Animator] end_fight_stance()")
	_fight_mode = false
	_travel_to_current_stance()

func set_fight_stance(active: bool) -> void:
	if debug_enabled:
		print_debug("[Animator] set_fight_stance(", active, ")")
	_fight_mode = active
	_travel_to_current_stance()

func is_in_fight_stance() -> bool:
	return _fight_mode

# ------------ Driving ------------
# local_move: Vector2(x=strife right/left, y=forward/back) from BaseCharacter
# horizontal_speed: m/s on the ground (used for optional speed radius and time scaling)
func update_locomotion(local_move: Vector2, horizontal_speed: float) -> void:
	if not _ensure_tree():
		push_warning("CharacterAnimator.update_locomotion: AnimationTree not resolved. Ensure a Model -> AnimationTree exists under model_root.")
		if debug_enabled:
			print_debug("[Animator] update_locomotion(): NO TREE. local_move=", local_move, " speed=", horizontal_speed)
		return

	if debug_enabled and debug_verbose:
		print_debug("[Animator] update_locomotion(): IN local_move=", local_move, " h_speed=", horizontal_speed, " fight_mode=", _fight_mode)

	# Deadzone
	var v := local_move
	if v.length() < input_deadzone:
		if debug_enabled and debug_verbose:
			print_debug("[Animator] Deadzone applied. len=", v.length(), " dz=", input_deadzone)
		v = Vector2.ZERO

	# Axis mapping
	if swap_xy:
		v = Vector2(v.y, v.x)
	if invert_x:
		v.x = -v.x
	if invert_y:
		v.y = -v.y

	# Construct target blend
	var target := v
	if use_speed_scale_for_radius:
		var dir := v.normalized() if v.length() > 0.0001 else Vector2.ZERO
		var radius := clampf(horizontal_speed / max(0.001, speed_for_full_blend), 0.0, 1.0)
		target = dir * radius
		if debug_enabled and debug_verbose:
			print_debug("[Animator] Speed->radius. dir=", dir, " radius=", radius, " target=", target)

	# Smooth the blend
	var alpha := clampf(locomotion_smoothing * get_physics_process_delta_time(), 0.0, 1.0)
	var prev_blend := _blend_vec
	_blend_vec = _blend_vec.lerp(target, alpha)
	if debug_enabled and debug_verbose:
		print_debug("[Animator] Smooth blend: prev=", prev_blend, " target=", target, " alpha=", alpha, " out=", _blend_vec)

	# Ensure parameter names exist; if not, try to auto-map based on your tree
	_ensure_blend_params()

	# Drive both MOVING and FIGHTING blend positions (so switching is seamless)
	var ok_move := _set_vec2(moving_blend_param, _blend_vec)
	var ok_fight := _set_vec2(fighting_blend_param, _blend_vec)
	if debug_enabled and debug_verbose:
		print_debug("[Animator] Set blends -> moving(", moving_blend_param, ") ok=", ok_move, " | fighting(", fighting_blend_param, ") ok=", ok_fight)

	# Optional time scaling with speed
	if time_scale_param != &"":
		var tscale := clampf(lerp(min_time_scale, max_time_scale, clampf(horizontal_speed / max(0.001, speed_for_full_blend), 0.0, 1.0)), min_time_scale, max_time_scale)
		var ok_ts := _set_float(time_scale_param, tscale)
		if debug_enabled and debug_verbose:
			print_debug("[Animator] TimeScale(", time_scale_param, ")=", tscale, " ok=", ok_ts)

	_travel_to_current_stance()

	# Periodic debug snapshot
	if debug_enabled:
		_dbg_accum += get_physics_process_delta_time()
		if _dbg_accum >= debug_interval:
			_dbg_accum = 0.0
			var stance := "FIGHT" if _fight_mode else "MOVE"
			print_debug("[Animator] tick stance=", stance, " blend=", _blend_vec, " local_move=", local_move)

func play_attack_by_strength(strength: float) -> void:
	if not _ensure_tree():
		push_warning("CharacterAnimator.play_attack_by_strength: AnimationTree not resolved.")
		return
	if not _fight_mode:
		start_fight_stance()
	var s := clampf(strength, 0.0, 1.0)
	var req_param := attack_medium_request_param
	if s < light_threshold and attack_light_request_param != &"":
		req_param = attack_light_request_param
	elif s >= heavy_threshold and attack_heavy_request_param != &"":
		req_param = attack_heavy_request_param
	var ok := _request(req_param)
	if debug_enabled:
		print_debug("[Animator] play_attack_by_strength s=", s, " req=", req_param, " ok=", ok)

func play_hit(_amount: int) -> void:
	if not _ensure_tree() or hit_request_param == &"":
		return
	if not _fight_mode:
		start_fight_stance()
	var ok := _request(hit_request_param)
	if debug_enabled:
		print_debug("[Animator] play_hit req=", hit_request_param, " ok=", ok)

func play_ko() -> void:
	if not _ensure_tree() or ko_request_param == &"":
		return
	var ok := _request(ko_request_param)
	if debug_enabled:
		print_debug("[Animator] play_ko req=", ko_request_param, " ok=", ok)

# Optional specific attacks
func play_lead_jab() -> void: start_fight_stance(); var ok := _request(attack_light_request_param); if debug_enabled: print_debug("[Animator] play_lead_jab ok=", ok)
func play_jab_cross() -> void: start_fight_stance(); var ok := _request(attack_medium_request_param); if debug_enabled: print_debug("[Animator] play_jab_cross ok=", ok)
func play_hook() -> void: start_fight_stance(); var ok := _request(attack_heavy_request_param); if debug_enabled: print_debug("[Animator] play_hook ok=", ok)
func play_punch_combo() -> void: start_fight_stance(); var ok := _request(attack_combo_request_param); if debug_enabled: print_debug("[Animator] play_punch_combo ok=", ok)
func play_uppercut_jab() -> void: start_fight_stance(); var ok := _request(attack_uppercut_jab_request_param); if debug_enabled: print_debug("[Animator] play_uppercut_jab ok=", ok)
func play_backflip_uppercut() -> void: start_fight_stance(); var ok := _request(attack_backflip_uppercut_request_param); if debug_enabled: print_debug("[Animator] play_backflip_uppercut ok=", ok)

# ------------ Internals ------------
func _ensure_tree() -> bool:
	if _tree:
		return true
	if debug_enabled:
		print_debug("[Animator] _ensure_tree(): resolving...")
	_resolve_anim_nodes()
	var ok := _tree != null
	if debug_enabled:
		print_debug("[Animator] _ensure_tree(): resolved=", ok)
	return ok

func _travel_to_current_stance() -> void:
	if not _playback:
		if debug_enabled:
			print_debug("[Animator] _travel_to_current_stance(): no playback yet")
		return
	var target := state_fighting if _fight_mode else state_moving
	var current := _playback.get_current_node()
	if current != target:
		if debug_enabled:
			print_debug("[Animator] State travel: ", current, " -> ", target)
		_playback.travel(target)
	else:
		if debug_enabled and debug_verbose:
			print_debug("[Animator] State already at: ", current)

func _set_vec2(path: StringName, v: Vector2) -> bool:
	if path == &"" or not _tree:
		return false
	var spath := String(path)
	if _param_exists(spath):
		_tree.set(spath, v)
		if debug_enabled and debug_verbose:
			print_debug("[Animator] set Vec2 ", spath, " = ", v)
		return true
	if debug_enabled or log_param_discovery:
		push_warning("CharacterAnimator: Vec2 param not found: " + spath)
	return false

func _set_float(path: StringName, f: float) -> bool:
	if path == &"" or not _tree:
		return false
	var spath := String(path)
	if _param_exists(spath):
		_tree.set(spath, f)
		if debug_enabled and debug_verbose:
			print_debug("[Animator] set Float ", spath, " = ", f)
		return true
	if debug_enabled or log_param_discovery:
		push_warning("CharacterAnimator: Float param not found: " + spath)
	return false

func _request(path: StringName) -> bool:
	if path == &"" or not _tree:
		return false
	var spath := String(path)
	if _param_exists(spath):
		_tree.set(spath, 1) # AnimationNodeOneShot 'request'
		if debug_enabled and debug_verbose:
			print_debug("[Animator] request OneShot ", spath)
		return true
	if debug_enabled or log_param_discovery:
		push_warning("CharacterAnimator: OneShot request param not found: " + spath)
	return false

func _resolve_anim_nodes() -> void:
	var model_root := _resolve_model_root()
	if not model_root:
		push_warning("CharacterAnimator: Could not resolve model root (looked for '%s' or model_root_path)." % [DEFAULT_MODEL_NAME])
		return
	if debug_enabled:
		print_debug("[Animator] Resolved model_root: ", model_root.name, " path=", model_root.get_path())

	_tree = _find_animation_tree_best(model_root)
	anim_player = _find_animation_player(model_root)

	if _tree:
		_tree.active = true
		_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if debug_enabled:
			print_debug("[Animator] Found AnimationTree at ", _tree.get_path(), " active=", _tree.active, " playback=", _playback != null)
		_cache_param_names()
		if debug_enabled:
			print_debug("[Animator] Tree param count: ", _param_names.size())
		_ensure_blend_params()
	else:
		push_warning("CharacterAnimator: No AnimationTree found under model root '%s'." % [model_root.name])

	if not anim_player and debug_enabled and debug_verbose:
		print_debug("[Animator] No AnimationPlayer found (optional)")

func _resolve_model_root() -> Node:
	# Prefer explicit NodePath (supports '../Model' for a sibling)
	if model_root_path != NodePath(""):
		var node := get_node_or_null(model_root_path)
		if node:
			return node
		if debug_enabled:
			print_debug("[Animator] model_root_path not found: ", model_root_path)
	# Fallback: try sibling named "Model"
	var parent := get_parent()
	if parent:
		var sib := parent.get_node_or_null(DEFAULT_MODEL_NAME)
		if sib:
			return sib
		# Broad fallback: search under parent subtree
		var found := _find_first_named(parent, DEFAULT_MODEL_NAME)
		if found:
			return found
	return null

func _find_first_named(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for c in root.get_children():
		var found := _find_first_named(c, target_name)
		if found:
			return found
	return null

# Prefer a tree literally named "AnimationTree"; otherwise first typed AnimationTree,
# preferring one that exposes a StateMachine playback.
func _find_animation_tree_best(root: Node) -> AnimationTree:
	# Fast path: exact name match
	var by_name := root.find_child("AnimationTree", true, false)
	if by_name is AnimationTree:
		if debug_enabled and debug_verbose:
			print_debug("[Animator] _find_animation_tree_best(): by_name -> ", by_name.get_path())
		return by_name

	# Fallback: typed DFS, prefer one with StateMachine playback
	var first: AnimationTree = null
	var best: AnimationTree = null
	var stack: Array = [root]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is AnimationTree:
			if first == null:
				first = n
			var playback = n.get("parameters/playback")
			var has_playback := playback is AnimationNodeStateMachinePlayback
			if debug_enabled and debug_verbose:
				print_debug("[Animator] Candidate AnimationTree: ", n.get_path(), " has_playback=", has_playback)
			if has_playback and best == null:
				best = n
		for c in n.get_children():
			stack.push_back(c)
	return best if best != null else first

func _find_animation_player(root: Node) -> AnimationPlayer:
	# Prefer a node literally named "AnimationPlayer"
	var by_name := root.find_child("AnimationPlayer", true, false)
	if by_name is AnimationPlayer:
		return by_name
	# Fallback: typed DFS
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null

# -------- Parameter discovery and safety --------
func _cache_param_names() -> void:
	_param_names.clear()
	if not _tree:
		return
	var props := _tree.get_property_list()
	for p in props:
		if p is Dictionary and p.has("name"):
			_param_names.push_back(String(p["name"]))

func _param_exists(path: String) -> bool:
	if _param_names.is_empty():
		_cache_param_names()
	return _param_names.has(path)

func _ensure_blend_params() -> void:
	if not _tree:
		return
	if _param_names.is_empty():
		_cache_param_names()

	var lower_contains := func(s: String, needle: String) -> bool:
		return s.to_lower().find(needle) >= 0

	# If configured params exist, keep them. Otherwise try to auto-find.
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
				if lower_contains.call(lname, "/moving/"):
					moving_candidates.append(name)
				elif lower_contains.call(lname, "/fighting/"):
					fighting_candidates.append(name)

		# Fallback: if not found by state name, grab any with that suffix
		if not moving_ok and moving_candidates.size() > 0:
			found_moving = moving_candidates[0]
		elif not moving_ok:
			for name in _param_names:
				if name.ends_with("/Move2D/blend_position"):
					found_moving = name
					break

		if not fighting_ok and fighting_candidates.size() > 0:
			found_fighting = fighting_candidates[0]
		elif not fighting_ok:
			for name in _param_names:
				if name.ends_with("/Move2D/blend_position"):
					found_fighting = name
					break

		# Assign back so inspector shows the resolved paths at runtime
		moving_blend_param = StringName(found_moving)
		fighting_blend_param = StringName(found_fighting)

		if log_param_discovery:
			print_debug("[Animator] Resolved blend params -> MOVING: ", moving_blend_param, " | FIGHTING: ", fighting_blend_param, " (moving_ok=", moving_ok, " fighting_ok=", fighting_ok, ")")
	else:
		if log_param_discovery and debug_verbose:
			print_debug("[Animator] Blend params already valid: MOVING=", moving_blend_param, " FIGHTING=", fighting_blend_param)
