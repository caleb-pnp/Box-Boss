extends Node
class_name CharacterAnimator

# Hook up to your existing nodes (on your Model) via the inspector.
@export var animation_tree_path: NodePath
@export var animation_player_path: NodePath # optional fallback, e.g., for notifies or direct clips

# State machine playback path (if your root is a StateMachine)
@export var state_machine_playback_path: String = "parameters/StateMachine/playback"

# Locomotion parameter paths (set whichever your tree uses; leave unused ones blank)
# Common patterns:
#  - BlendSpace2D: parameters/Locomotion/blend_position
#  - Separate axes: parameters/Locomotion/x and /y
#  - Speed/moving flags: parameters/Locomotion/speed, parameters/Locomotion/is_moving
@export var locomotion_blend2d_path: String = ""
@export var move_x_param_path: String = ""
@export var move_y_param_path: String = ""
@export var speed_param_path: String = ""
@export var moving_param_path: String = ""
@export var run_param_path: String = ""      # optional if your tree blends run/walk
@export var retreat_param_path: String = ""  # optional if your tree needs it

# Optional: auto-travel between Idle/Move if you keep those as explicit states
@export var auto_travel_idle_move: bool = false
@export var idle_state: StringName = &"Idle"
@export var move_state: StringName = &"Move"

# Optional bindings in case your state names differ from logical keys
@export var action_state_bindings: Array[ActionStateBinding] = []

# Hit/KO convenience (rename to match your states or set bindings instead)
@export var hit_small_state: StringName = &"TakeHitSmall"
@export var hit_medium_state: StringName = &"TakeHitMedium"
@export var hit_big_state: StringName = &"TakeHitBig"
@export var ko_state: StringName = &"KO"
@export var hit_medium_threshold: int = 12
@export var hit_big_threshold: int = 25

var _tree: AnimationTree
var _player: AnimationPlayer
var _playback: AnimationNodeStateMachinePlayback
var _action_to_state: Dictionary[StringName, StringName] = {}

func _ready() -> void:
	_tree = get_node_or_null(animation_tree_path)
	_player = get_node_or_null(animation_player_path)
	if _tree:
		_tree.active = true
		_playback = _tree.get(state_machine_playback_path) as AnimationNodeStateMachinePlayback

	# Build optional remap for keys -> state names
	_action_to_state.clear()
	for binding in action_state_bindings:
		if binding and String(binding.state) != "":
			_action_to_state[binding.key] = binding.state

# Locomotion: set whatever params your tree listens to
func update_locomotion(local_move: Vector2, horizontal_speed: float, run: bool = false, retreat: bool = false) -> void:
	if not _tree:
		return
	if locomotion_blend2d_path != "":
		_tree.set(locomotion_blend2d_path, Vector2(local_move.x, local_move.y))
	if move_x_param_path != "":
		_tree.set(move_x_param_path, local_move.x)
	if move_y_param_path != "":
		_tree.set(move_y_param_path, local_move.y)
	if speed_param_path != "":
		_tree.set(speed_param_path, horizontal_speed)
	if moving_param_path != "":
		_tree.set(moving_param_path, horizontal_speed > 0.1)
	if run_param_path != "":
		_tree.set(run_param_path, run)
	if retreat_param_path != "":
		_tree.set(retreat_param_path, retreat)

	if auto_travel_idle_move and _playback:
		_playback.travel(move_state if horizontal_speed > 0.1 else idle_state)

# Actions: travel to named states (or use optional remap)
func play_key(key: StringName) -> bool:
	var state_name: StringName = _action_to_state.get(key, key)
	return _travel(state_name) or _play_player_if_present(state_name)

func play_attack_by_strength(strength: float, light_key: StringName = &"PUNCH", medium_key: StringName = &"COMBO_A", heavy_key: StringName = &"COMBO_B") -> void:
	if strength < 0.3:
		play_key(light_key)
	elif strength < 0.7:
		play_key(medium_key)
	else:
		play_key(heavy_key)

func play_hit(amount: int) -> void:
	if amount >= hit_big_threshold:
		_travel_or_player(hit_big_state)
	elif amount >= hit_medium_threshold:
		_travel_or_player(hit_medium_state)
	else:
		_travel_or_player(hit_small_state)

func play_ko() -> void:
	_travel_or_player(ko_state)

# Generic helpers for direct parameter control (flags/one-shots/etc.)
func set_param(param_path: String, value: Variant) -> void:
	if _tree and param_path != "":
		_tree.set(param_path, value)

# For OneShot nodes used outside the StateMachine: set their "request" param to true.
# Example: trigger("parameters/PunchOneShot/request")
func trigger(param_path: String) -> void:
	if _tree and param_path != "":
		_tree.set(param_path, true)

# Internals
func _travel(state_name: StringName) -> bool:
	if not _playback:
		return false
	_playback.travel(state_name)
	return true

func _play_player_if_present(name: StringName) -> bool:
	if _player and _player.has_animation(name):
		_player.play(name)
		return true
	return false

func _travel_or_player(name: StringName) -> void:
	if not _travel(name):
		_play_player_if_present(name)
