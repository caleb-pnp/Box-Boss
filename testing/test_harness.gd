extends Node
"""
Level test controller for two BaseCharacter instances with CharacterAnimator integration.

Inspector:
- char_a_path: NodePath to first BaseCharacter
- char_b_path: NodePath to second BaseCharacter
- free_cam_path: NodePath to the FreeFlyTestingCamera node (Node3D with Camera3D child)

Mouse (via FreeFlyTestingCamera signals):
- Left Click: Selected character MOVE to clicked ground point.
- Right Click: Selected character FIGHT the other character (Shift+Right Click = fight the clicked point instead).
- Middle Click: Teleport selected character to clicked point (debug).

Keyboard:
- 1 / 2: Select Character A / B.
- P: Toggle agent autopilot on selected (if property exists).
- C: Clear selected character target (back to moving stance).
- F: Toggle fighting stance on selected (does not change target).
- R: Make both characters target each other and enter fight stance.
- J/K/L: Trigger light/medium/heavy attack on selected.
- H: Make selected take a small hit.
- O: Knock out selected (via stats.take_damage if available, else force KO).
"""

@export_category("Scene References")
@export var char_a_path: NodePath
@export var char_b_path: NodePath
@export var free_cam_path: NodePath

var char_a: BaseCharacter
var char_b: BaseCharacter
var free_cam: FreeFlyTestingCamera

enum Selected { A, B }
var _selected: int = Selected.A

func _ready() -> void:
	char_a = get_node_or_null(char_a_path) as BaseCharacter
	char_b = get_node_or_null(char_b_path) as BaseCharacter
	free_cam = get_node_or_null(free_cam_path) as FreeFlyTestingCamera

	if not char_a or not char_b:
		push_warning("TestHarness: Assign both 'char_a_path' and 'char_b_path' to BaseCharacter nodes.")
	if not free_cam:
		push_warning("TestHarness: Assign 'free_cam_path' to a FreeFlyTestingCamera node.")

	# Connect camera click signals
	if free_cam:
		free_cam.left_click_ground.connect(_on_cam_left_click)
		free_cam.right_click_ground.connect(_on_cam_right_click)
		free_cam.middle_click_ground.connect(_on_cam_middle_click)

	_ensure_input_actions()
	print("TestHarness ready. Selected = A. Use keys 1/2 to switch. Click ground to drive movement/fight.")

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard-only; mouse is handled by FreeFlyTestingCamera
	if event.is_action_pressed("th_select_a"):
		_selected = Selected.A
		print("Selected: A")
	elif event.is_action_pressed("th_select_b"):
		_selected = Selected.B
		print("Selected: B")
	elif event.is_action_pressed("th_toggle_autopilot"):
		var c := _selected_char()
		if c and _has_prop(c, "use_agent_autopilot"):
			var new_val := not bool(c.get("use_agent_autopilot"))
			c.set("use_agent_autopilot", new_val)
			print("Autopilot (selected): ", new_val)
		else:
			print("Selected character has no 'use_agent_autopilot' property.")
	elif event.is_action_pressed("th_clear_target"):
		_bc_clear_target(_selected_char())
	elif event.is_action_pressed("th_toggle_fight_stance"):
		var c2 := _selected_char()
		if c2 and c2.animator:
			if c2.animator.is_in_fight_stance():
				c2.animator.end_fight_stance()
				print("Stance: moving")
			else:
				c2.animator.start_fight_stance()
				print("Stance: fighting")
	elif event.is_action_pressed("th_fight_each_other"):
		if char_a and char_b:
			_bc_set_fight_target(char_a, char_b)
			_bc_set_fight_target(char_b, char_a)
			print("Both characters set to fight each other.")
	elif event.is_action_pressed("th_attack_light"):
		_trigger_attack(_selected_char(), 0.15)
	elif event.is_action_pressed("th_attack_medium"):
		_trigger_attack(_selected_char(), 0.5)
	elif event.is_action_pressed("th_attack_heavy"):
		_trigger_attack(_selected_char(), 0.9)
	elif event.is_action_pressed("th_hit_small"):
		var c3 := _selected_char()
		if c3:
			c3.take_hit(10)
	elif event.is_action_pressed("th_force_ko"):
		var c4 := _selected_char()
		if c4:
			if c4.stats and c4.stats.has_method("take_damage"):
				c4.stats.take_damage(99999)
			else:
				c4._on_died()

# ------------------
# Camera signal handlers
# ------------------
func _on_cam_left_click(point: Vector3) -> void:
	_bc_set_move_target(_selected_char(), point)

func _on_cam_right_click(point: Vector3, shift_pressed: bool) -> void:
	if shift_pressed:
		_bc_set_fight_target(_selected_char(), point)
	else:
		var other := _other_char()
		if other:
			_bc_set_fight_target(_selected_char(), other)

func _on_cam_middle_click(point: Vector3) -> void:
	var c := _selected_char()
	if c:
		c.global_position = point
		c.velocity = Vector3.ZERO

# ------------------
# Helpers
# ------------------
func _selected_char() -> BaseCharacter:
	return char_a if _selected == Selected.A else char_b

func _other_char() -> BaseCharacter:
	return char_b if _selected == Selected.A else char_a

func _trigger_attack(c: BaseCharacter, strength: float) -> void:
	if not c:
		return
	c.intents["attack_strength"] = strength
	c.intents["attack"] = true

func _bc_set_move_target(c: BaseCharacter, t: Variant) -> void:
	if not c:
		return
	if c.has_method("set_move_target"):
		c.set_move_target(t)
	else:
		c.set_target(t)
		if c.animator:
			c.animator.end_fight_stance()
	print("MOVE target set for ", c.name)

func _bc_set_fight_target(c: BaseCharacter, t: Variant) -> void:
	if not c:
		return
	if c.has_method("set_fight_target"):
		c.set_fight_target(t)
	else:
		c.set_target(t)
		if c.animator:
			c.animator.start_fight_stance()
	print("FIGHT target set for ", c.name)

func _bc_clear_target(c: BaseCharacter) -> void:
	if not c:
		return
	if c.has_method("clear_target"):
		c.clear_target()
	else:
		c.set_target(null)
		if c.animator:
			c.animator.end_fight_stance()
	print("Cleared target for ", c.name)

# Ensure we have default input actions without needing to edit Project Settings
func _ensure_input_actions() -> void:
	_add_action_if_missing("th_select_a", [KEY_1])
	_add_action_if_missing("th_select_b", [KEY_2])
	_add_action_if_missing("th_toggle_autopilot", [KEY_P])
	_add_action_if_missing("th_clear_target", [KEY_C])
	_add_action_if_missing("th_toggle_fight_stance", [KEY_F])
	_add_action_if_missing("th_fight_each_other", [KEY_R])
	_add_action_if_missing("th_attack_light", [KEY_J])
	_add_action_if_missing("th_attack_medium", [KEY_K])
	_add_action_if_missing("th_attack_heavy", [KEY_L])
	_add_action_if_missing("th_hit_small", [KEY_H])
	_add_action_if_missing("th_force_ko", [KEY_O])

func _add_action_if_missing(name: String, keys: Array) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name)
	for sc in keys:
		var ev := InputEventKey.new()
		ev.keycode = sc
		InputMap.action_add_event(name, ev)

func _has_prop(obj: Object, prop_name: String) -> bool:
	for p in obj.get_property_list():
		if p.has("name") and String(p["name"]) == prop_name:
			return true
	return false
