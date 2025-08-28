extends Node
class_name CombatController

@export var max_attack_setup_time: float = 5.0
@export var combo_close_window_time: float = 1.0
@export var combo_close_window_max_time: float = 7.0

var character: BaseCharacter = null

# --- Attack Queue and Combo State ---
var attack_queue: Array = []
var current_attack: Dictionary = {}
var setup_target_position: Vector3 = Vector3.ZERO
var setup_start_time: float = 0.0
var setup_window_attacks: Array = []
var setup_window_open: bool = false
var setup_window_close_time: float = 0.0
var setup_option: String = "fixed" # "fixed", "closing", "instant"

# --- Attack Phases ---
enum Phase { NONE, SETUP, SWING, POST_SWING }
var phase: int = Phase.NONE
var phase_until: float = 0.0

func reset() -> void:
	attack_queue.clear()
	current_attack = {}
	setup_window_attacks.clear()
	setup_window_open = false
	phase = Phase.NONE
	phase_until = 0.0
	if character:
		character.stop_movement()
		if character.hitbox:
			character.hitbox.deactivate()
		_log("CombatController: Reset and deactivated hitbox.")

func process(delta: float) -> void:
	if not character or not character.round_active or character.state == character.State.KO:
		reset()
		return

	match phase:
		Phase.NONE:
			_process_attack_queue()
		Phase.SETUP:
			_process_setup_phase()
		Phase.SWING:
			_process_swing_phase()
		Phase.POST_SWING:
			_process_post_swing_phase()

# --- Handle Punch Input (from BaseCharacter) ---
func handle_punch(source_id: int, force: float) -> void:
	if not character or not character.round_active or character.state == character.State.KO:
		return
	var attack_id: StringName = _select_attack_by_force_from_set(force)
	if String(attack_id) != "":
		_log("CombatController: Queued attack from punch input: %s (force=%.2f)" % [String(attack_id), force])
		queue_attack(attack_id)

func queue_attack(attack_id: StringName) -> void:
	if String(attack_id) == "":
		return
	var now := _now()
	attack_queue.append({ "id": attack_id, "queued_at": now })
	if setup_window_open:
		setup_window_attacks.append({ "id": attack_id, "queued_at": now })
	_log("CombatController: Attack queued: %s" % String(attack_id))

# --- Main Attack Queue Processing ---
func _process_attack_queue() -> void:
	if attack_queue.is_empty():
		return

	# Pop the oldest attack and start setup
	current_attack = attack_queue.pop_front()
	if character.target_node:
		setup_target_position = character.target_node.global_position
	else:
		setup_target_position = character.global_position
	setup_start_time = _now()
	setup_window_attacks = [current_attack]
	setup_window_open = true
	setup_window_close_time = setup_start_time + max_attack_setup_time
	phase = Phase.SETUP
	_log("CombatController: Started setup phase for attack: %s" % String(current_attack.get("id", "")))

# --- Setup Phase ---
func _process_setup_phase() -> void:
	var now := _now()
	var dist: float = (setup_target_position - character.global_position).length()
	var arrived: bool = dist < 0.2 # Tweak as needed

	# Use shared movement helper
	if not arrived:
		character.move_towards_point(setup_target_position, 1.0, true)
	else:
		character.stop_movement()

	# Combo window logic
	if setup_option == "fixed":
		if now - setup_start_time >= max_attack_setup_time:
			_finalize_combo_and_swing()
	elif setup_option == "closing":
		if arrived:
			if not setup_window_open:
				setup_window_open = true
				setup_window_close_time = now + combo_close_window_time
			elif now >= setup_window_close_time or (now - setup_start_time) >= combo_close_window_max_time:
				_finalize_combo_and_swing()
		else:
			setup_window_close_time = now + combo_close_window_time
	elif setup_option == "instant":
		if arrived:
			_finalize_combo_and_swing()

func _finalize_combo_and_swing() -> void:
	setup_window_open = false
	var combo = _calculate_combo(setup_window_attacks)
	if combo.has("combo_id"):
		_log("CombatController: Combo detected: %s" % String(combo["combo_id"]))
		_start_swing(combo)
	else:
		var best = _pick_biggest_force_attack(setup_window_attacks)
		_log("CombatController: No combo, using biggest force attack: %s" % String(best.get("id", "")))
		_start_swing(best)
	setup_window_attacks.clear()
	phase = Phase.SWING
	phase_until = _now() + _get_swing_duration(current_attack)

# --- Combo Calculation ---
func _calculate_combo(attacks: Array) -> Dictionary:
	if not character or not character.attack_set_data or not character.attack_library:
		return {}

	var ids: Array = []
	for entry in attacks:
		if entry.has("id"):
			ids.append(entry["id"])

	if character.attack_set_data.has_method("get_combo_ids"):
		var combos: Array = character.attack_set_data.get_combo_ids()
		for combo_id in combos:
			var combo_spec = character.attack_library.get_spec(combo_id)
			var has_seq = combo_spec and combo_spec.sequence != null
			if has_seq:
				var seq: Array = combo_spec.sequence
				if ids.size() >= seq.size():
					var window_seq = ids.slice(ids.size() - seq.size(), ids.size())
					if window_seq == seq:
						return {
							"combo_id": combo_id,
							"sequence": seq,
							"attacks": attacks.slice(ids.size() - seq.size(), ids.size())
						}
	return {}

# --- Force-based Selection ---
func _pick_biggest_force_attack(attacks: Array) -> Dictionary:
	if not character or not character.attack_library:
		return attacks[0] if attacks.size() > 0 else current_attack

	var best: Dictionary = {}
	var best_force: float = -INF
	for entry in attacks:
		if entry.has("id"):
			var spec = character.attack_library.get_spec(entry["id"])
			var force = spec.force_max if spec and spec.force_max != null else null
			if force != null:
				force = float(force)
				if force > best_force:
					best_force = force
					best = entry
	return best if best else (attacks[0] if attacks.size() > 0 else current_attack)

func _get_swing_duration(attack: Dictionary) -> float:
	if not character or not character.attack_library or not attack.has("id"):
		return 0.5
	var spec = character.attack_library.get_spec(attack["id"])
	var swing_time = spec.swing_time_sec if spec and spec.swing_time_sec != null else null
	if swing_time != null:
		return float(swing_time)
	return 0.5

# --- Attack Selection by Force ---
func _select_attack_by_force_from_set(force: float) -> StringName:
	if not character or not character.attack_set_data or not character.attack_library:
		return StringName("")
	if not character.attack_set_data.has_method("get_basic_ids"):
		return StringName("")
	var candidates: Array[StringName] = character.attack_set_data.get_basic_ids()
	if candidates.is_empty():
		return StringName("")

	var in_range: Array = []
	for id in candidates:
		var spec = character.attack_library.get_spec(id)
		var fmin = spec.force_min if spec and spec.force_min != null else null
		var fmax = spec.force_max if spec and spec.force_max != null else null
		if fmin == null or fmax == null:
			continue
		fmin = float(fmin)
		fmax = float(fmax)
		if fmax < fmin:
			var tmp = fmin; fmin = fmax; fmax = tmp
		if force >= fmin and force <= fmax:
			var width = max(0.0001, fmax - fmin)
			var center = 0.5 * (fmin + fmax)
			var center_dist = absf(force - center)
			var selection_weight = spec.selection_weight if spec and spec.selection_weight != null else 1.0
			var weight = float(selection_weight)
			in_range.append({
				"id": id,
				"width": width,
				"center_dist": center_dist,
				"weight": weight
			})
	if in_range.size() > 0:
		in_range.sort_custom(func(a, b):
			if a["width"] < b["width"]: return true
			if a["width"] > b["width"]: return false
			if a["center_dist"] < b["center_dist"]: return true
			if a["center_dist"] > b["center_dist"]: return false
			if a["weight"] > b["weight"]: return true
			if a["weight"] < b["weight"]: return false
			return randi() % 2 == 0
		)
		_log("CombatController: Selected attack by force: %s" % String(in_range[0]["id"]))
		return in_range[0]["id"]

	var below: Array = []
	for id2 in candidates:
		var spec2 = character.attack_library.get_spec(id2)
		var fmin2 = spec2.force_min if spec2 and spec2.force_min != null else null
		var fmax2 = spec2.force_max if spec2 and spec2.force_max != null else null
		if fmin2 == null or fmax2 == null: continue
		fmin2 = float(fmin2)
		fmax2 = float(fmax2)
		if fmax2 < fmin2:
			var tmp2 = fmin2; fmin2 = fmax2; fmax2 = tmp2
		if fmax2 <= force:
			var gap = force - fmax2
			var width2 = max(0.0001, fmax2 - fmin2)
			below.append({ "id": id2, "gap": gap, "width": width2 })
	if below.size() == 0:
		return StringName("")
	below.sort_custom(func(a, b):
		if a["gap"] < b["gap"]: return true
		if a["gap"] > b["gap"]: return false
		if a["width"] < b["width"]: return true
		if a["width"] > b["width"]: return false
		return randi() % 2 == 0
	)
	_log("CombatController: Selected attack by force (below): %s" % String(below[0]["id"]))
	return below[0]["id"]

# --- Swing Phase ---
func _process_swing_phase() -> void:
	var now := _now()
	character.stop_movement()
	if now >= phase_until:
		phase = Phase.POST_SWING
		phase_until = now + 0.3 # Post-swing freeze
		# Deactivate hitbox at end of swing
		if character.hitbox:
			character.hitbox.deactivate()
			_log("CombatController: Hitbox deactivated at end of swing.")

# --- Post-Swing Phase ---
func _process_post_swing_phase() -> void:
	var now := _now()
	character.stop_movement()
	if now >= phase_until:
		phase = Phase.NONE

# --- Utility ---
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _log(msg: String) -> void:
	if character and character.debug_enabled:
		print("[CombatController] " + msg)

# --- Swing Logic ---
func _start_swing(attack: Dictionary) -> void:
	var attack_id = attack.get("id", "")
	if character.animator and character.animator.has_method("play_attack_id") and attack_id != "":
		character.animator.play_attack_id(attack_id)
		_log("CombatController: Playing attack animation: %s" % String(attack_id))
	# Activate hitbox for this attack
	if character.hitbox and character.attack_library:
		var spec = character.attack_library.get_spec(attack_id)
		if spec:
			var impact_force = float(spec.force_max) if spec and spec.force_max != null else 1.0
			character.hitbox.attacker = character
			character.hitbox.activate_for_attack(attack_id, spec, impact_force)
			_log("CombatController: Hitbox activated for attack: %s (force=%.2f)" % [String(attack_id), impact_force])
