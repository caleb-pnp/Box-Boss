extends Node
# Level test controller for two BaseCharacter instances with CharacterAnimator integration.
#
# Inspector:
# - char_a_path: NodePath to first BaseCharacter
# - char_b_path: NodePath to second BaseCharacter
# - free_cam_path: NodePath to the FreeFlyTestingCamera node (Node3D with Camera3D child)
#
# Mouse (via FreeFlyTestingCamera signals):
# - Left Click: Selected character MOVE to clicked ground point.
# - Right Click: Selected character FIGHT the other character (Shift+Right Click = fight the clicked point instead).
# - Middle Click: Teleport selected character to clicked point (debug).
#
# Keyboard (handled via _unhandled_input, no InputMap needed):
# - 1 / 2 (or Numpad 1 / 2): Select Character A / B.
# - P: Toggle agent autopilot on selected (if property exists).
# - C: Clear selected character target (back to moving stance).
# - F: Toggle fighting stance on selected (does not change target).
# - R: Make both characters target each other and enter fight stance.
# - J/K/L/I: Trigger light/medium/heavy/special attack (category-based via AttackSetData) on selected.
# - U: Fire the currently equipped LIGHT attack directly on the Animator (bypasses BaseCharacter gates) to isolate Animator/AnimationTree issues.
# - V: Validate selected character's AttackSetData and AttackLibrary (IDs and OneShot param paths vs AnimationTree).
# - H: Make selected take a small hit.
# - O: Knock out selected (via stats.take_damage if available, else force KO).

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
		if free_cam.left_click_ground.is_connected(_on_cam_left_click) == false:
			free_cam.left_click_ground.connect(_on_cam_left_click)
		if free_cam.right_click_ground.is_connected(_on_cam_right_click) == false:
			free_cam.right_click_ground.connect(_on_cam_right_click)
		if free_cam.middle_click_ground.is_connected(_on_cam_middle_click) == false:
			free_cam.middle_click_ground.connect(_on_cam_middle_click)

	print("TestHarness ready. Selected = A. 1/2 to switch. Click ground to move/fight. Hotkeys: P/C/F/R, J/K/L/I, U (animator direct), V (validate), H, O")

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard-only; mouse is handled by FreeFlyTestingCamera
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	match key.physical_keycode:
		KEY_1, KEY_KP_1:
			_selected = Selected.A
			print("Selected: A")
		KEY_2, KEY_KP_2:
			_selected = Selected.B
			print("Selected: B")
		KEY_P:
			var c := _selected_char()
			if c and _has_prop(c, "use_agent_autopilot"):
				var new_val := not bool(c.get("use_agent_autopilot"))
				c.set("use_agent_autopilot", new_val)
				print("Autopilot (selected): ", new_val)
			else:
				print("Selected character has no 'use_agent_autopilot' property.")
		KEY_C:
			_bc_clear_target(_selected_char())
		KEY_F:
			var c2 := _selected_char()
			if c2 and c2.animator:
				if c2.animator.is_in_fight_stance():
					c2.animator.end_fight_stance()
					print("Stance: moving")
				else:
					c2.animator.start_fight_stance()
					print("Stance: fighting")
		KEY_R:
			if char_a and char_b:
				_bc_set_fight_target(char_a, char_b)
				_bc_set_fight_target(char_b, char_a)
				print("Both characters set to fight each other.")
		# Category-based attacks (via AttackSetData on BaseCharacter)
		KEY_J:
			_trigger_attack_category(_selected_char(), &"light")
		KEY_K:
			_trigger_attack_category(_selected_char(), &"medium")
		KEY_L:
			_trigger_attack_category(_selected_char(), &"heavy")
		KEY_I:
			_trigger_attack_category(_selected_char(), &"special")
		# Direct animator fire for the equipped LIGHT id, bypassing BaseCharacter gates
		KEY_U:
			_animator_direct_light(_selected_char())
		# Validate library/set/params for selected
		KEY_V:
			_validate_selected()
		KEY_H:
			var c3 := _selected_char()
			if c3:
				c3.take_hit(10)
		KEY_O:
			var c4 := _selected_char()
			if c4:
				if c4.stats and c4.stats.has_method("take_damage"):
					c4.stats.take_damage(99999)
				else:
					c4._on_died()
		_:
			pass

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

# Trigger by category via AttackSetData
func _trigger_attack_category(c: BaseCharacter, cat: StringName) -> void:
	if not c:
		return
	if c.has_method("request_attack_category"):
		c.request_attack_category(cat)
	else:
		# Fallback: write intents directly
		c.intents["attack_category"] = cat
		c.intents["attack_id"] = StringName("")
		c.intents["attack"] = true
	print("Attack request (category): ", String(cat), " for ", c.name)

# Optional: trigger an explicit move by ID
func _trigger_attack_id(c: BaseCharacter, id: StringName) -> void:
	if not c:
		return
	if c.has_method("request_attack_id"):
		c.request_attack_id(id)
	else:
		# Fallback: write intents directly
		c.intents["attack_id"] = id
		c.intents["attack_category"] = StringName("")
		c.intents["attack"] = true
	print("Attack request (id): ", String(id), " for ", c.name)

# Direct animator test: fire the currently equipped LIGHT id immediately
func _animator_direct_light(c: BaseCharacter) -> void:
	if not c or not c.animator:
		print("Animator direct test: No character or animator.")
		return
	var id := StringName("")
	if c.attack_set_data:
		id = c.attack_set_data.get_id_for_category(&"light")
	if String(id) == "":
		print("Animator direct test: No light_id in attack_set_data.")
		return
	print("Animator direct test: play_attack_id(", String(id), ") on ", c.name)
	# Ensure fight stance for the animator
	if not c.animator.is_in_fight_stance():
		c.animator.start_fight_stance()
	# Try to play immediately (async)
	c.animator.play_attack_id(id)

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

func _has_prop(obj: Object, prop_name: String) -> bool:
	for p in obj.get_property_list():
		if p.has("name") and String(p["name"]) == prop_name:
			return true
	return false

# ------------------
# Validation helpers
# ------------------
func _validate_selected() -> void:
	var c := _selected_char()
	if not c:
		print("[Validate] No selected character.")
		return
	print("[Validate] Selected: ", c.name)
	if not c.attack_library:
		print("[Validate] attack_library NOT set on BaseCharacter")
	else:
		var count_text := "OK"
		if _has_prop(c.attack_library, "attacks"):
			var arr = c.attack_library.get("attacks")
			if typeof(arr) == TYPE_ARRAY:
				count_text = "OK (" + str(arr.size()) + " specs)"
		print("[Validate] attack_library ", count_text)
	if not c.attack_set_data:
		print("[Validate] attack_set_data NOT set on BaseCharacter")
	else:
		print("[Validate] attack_set_data equipped: light=", String(c.attack_set_data.light_id), " medium=", String(c.attack_set_data.medium_id), " heavy=", String(c.attack_set_data.heavy_id), " special=", String(c.attack_set_data.special_id))

	# Check mapping for the four categories
	var cats := [StringName("light"), StringName("medium"), StringName("heavy"), StringName("special")]
	for cat in cats:
		var id := (c.attack_set_data.get_id_for_category(cat) if c.attack_set_data else StringName(""))
		if String(id) == "":
			print("  - ", String(cat), ": NO ID configured")
			continue
		var spec := (c.attack_library.get_spec(id) if c.attack_library else null)
		if spec == null:
			print("  - ", String(cat), ": id=", String(id), " NOT FOUND in library")
			continue
		print("  - ", String(cat), ": id=", String(id), " enter=", spec.enter_distance, " swing=", spec.swing_time_sec, " lock=", spec.move_lock_sec, " cd=", spec.cooldown_sec)
		# Validate animator param paths if we can reach the tree
		var anim = c.animator
		if anim and _animator_has_param(anim, String(spec.request_param_a)):
			print("      request A OK: ", String(spec.request_param_a))
		else:
			print("      request A MISSING: ", String(spec.request_param_a))
		if spec.request_param_b != StringName(""):
			if anim and _animator_has_param(anim, String(spec.request_param_b)):
				print("      request B OK: ", String(spec.request_param_b))
			else:
				print("      request B MISSING: ", String(spec.request_param_b))

func _animator_has_param(anim, path: String) -> bool:
	if anim == null or path == "" or not anim.has_method("_tree") and not anim.has_method("get_tree"):
		# Best-effort: if animator doesn't expose internals, we can't validate
		return false
	# The animator may cache param names; use that if available
	if anim.has_method("_param_names"):
		var names = anim._param_names
		if names and names.has(path):
			return true
	# Otherwise, scan the tree properties if available
	if anim._tree:
		var props = anim._tree.get_property_list()
		for p in props:
			if p is Dictionary and p.has("name") and String(p["name"]) == path:
				return true
	return false
