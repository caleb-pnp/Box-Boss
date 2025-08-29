extends Node
class_name CombatController

signal attack_queued(display_name: String, force: float)

@export var max_attack_setup_time: float = 2.0
@export var retreat_distance: float = 1.0
@export var retreat_duration: float = 1.5

var character: BaseCharacter = null

# --- Attack Queue and Combo State ---
var attack_queue: Array = []
var current_attack: Dictionary = {}
var chase_window_attacks: Array = []

# --- Attack Phases ---
enum Phase { NONE, CHASE, SWING, POST_SWING, RETREAT }
var phase: int = Phase.NONE
var phase_until: float = 0.0

var debug_enabled: bool = false
var debug_combos: bool = true

func setup(character_ref):
	character = character_ref
	character.connect("chase_success", Callable(self, "_on_chase_success"))
	character.connect("chase_failed", Callable(self, "_on_chase_failed"))
	character.connect("retreat_success", Callable(self, "_on_retreat_success"))
	character.connect("retreat_failed", Callable(self, "_on_retreat_failed"))

func _ready() -> void:
	pass

func reset() -> void:
	attack_queue.clear()
	current_attack = {}
	chase_window_attacks.clear()
	phase = Phase.NONE
	phase_until = 0.0
	if character:
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
		Phase.CHASE:
			pass # do nothing hear, signal driven
		Phase.SWING:
			_process_swing_phase()
		Phase.POST_SWING:
			_process_post_swing_phase()
		Phase.RETREAT:
			_process_retreat_phase()

func handle_punch(source_id: int, force: float) -> void:
	if not character or not character.round_active or character.state == character.State.KO:
		return
	var attack_id: StringName = _select_attack_by_force_from_set(force)
	if String(attack_id) != "":
		_log("CombatController: Queued attack from punch input: %s (force=%.2f)" % [String(attack_id), force])
		var entry = { "id": attack_id, "queued_at": _now(), "force": force }
		if phase == Phase.CHASE:
			chase_window_attacks.append(entry)
		else:
			attack_queue.append(entry)
			if phase == Phase.NONE:
				_process_attack_queue()

		# --- Emit attack_queued signal for HUD ---
		if character and character.attack_library:
			var spec = character.attack_library.get_spec(attack_id)
			var display_name = spec.display_name if spec and "display_name" in spec else String(attack_id)
			emit_signal("attack_queued", display_name, force)

func _on_chase_success():
	print("Chase succeeded! Begin attack.")
	_finalize_combo_and_swing()

func _on_chase_failed():
	_log("Chase failed (timeout). Optionally attack and miss or abort.")
	_finalize_combo_and_swing()

func cancel_attack():
	# Cancel any attack in progress, including hitboxes and queued attacks
	phase = Phase.NONE
	attack_queue.clear()
	chase_window_attacks.clear()
	current_attack = {}
	if character and character.hitbox:
		character.hitbox.deactivate()
		_log("CombatController: Attack cancelled and hitbox deactivated.")
	else:
		_log("CombatController: Attack cancelled.")

func _process_attack_queue() -> void:
	if attack_queue.is_empty():
		return

	current_attack = attack_queue.pop_front()
	chase_window_attacks.clear()
	_log("CombatController: Started chase phase for attack: %s" % String(current_attack.get("id", "")))

	var attack_id = current_attack.get("id", "")
	var enter_distance = _get_attack_enter_distance(attack_id)
	var timeout = max_attack_setup_time
	character.start_chase(enter_distance, timeout)
	phase = Phase.CHASE


func _finalize_combo_and_swing() -> void:
	var all_attacks = [current_attack] + chase_window_attacks
	var combo = _calculate_combo(all_attacks)
	if combo.has("combo_id"):
		_log("CombatController: Combo detected: %s" % String(combo["combo_id"]))
		current_attack = combo
		_start_swing(combo)
	else:
		var best = _pick_biggest_force_attack(chase_window_attacks)
		_log("CombatController: No combo, using biggest force attack: %s" % String(best.get("id", "")))
		current_attack = best
		_start_swing(best)
	phase = Phase.SWING
	phase_until = _now() + _get_swing_duration(current_attack)
	chase_window_attacks.clear()
	current_attack = {}

	if debug_combos:
		print("[CombatController] SWING: attack_id=%s, swing_time_sec=%.2f" % [
			str(current_attack.get("id", "")),
			_get_swing_duration(current_attack)
		])

# --- Combo Calculation ---
func _calculate_combo(attacks: Array) -> Dictionary:
	if not character or not character.attack_set_data or not character.attack_library:
		return {}

	var combos = []
	if "combo_attack_ids" in character.attack_set_data:
		combos = []
		for combo_id in character.attack_set_data.combo_attack_ids:
			var found = false
			for attack_spec in character.attack_library.attacks:
				if "id" in attack_spec and attack_spec.id == combo_id:
					combos.append(attack_spec)
					found = true
					break
			if debug_combos and not found:
				print("[ComboDebug] Combo ID not found in attack_library.attacks array: ", combo_id)
	else:
		var fallback_combo = {
			"id": "force_combo",
			"required_count": character.attack_set_data["combo_required_count"] if "combo_required_count" in character.attack_set_data else 0,
			"each_min_force": character.attack_set_data["combo_each_min_force"] if "combo_each_min_force" in character.attack_set_data else 0.0,
			"window_sec": character.attack_set_data["combo_window_sec"] if "combo_window_sec" in character.attack_set_data else -1.0,
			"priority": 0
		}
		combos = [fallback_combo]

	var now = _now()
	var best_combo = {}
	var best_priority = -INF

	for combo in combos:
		var required_count = int(combo["combo_required_count"]) if "combo_required_count" in combo else 0
		var each_min_force = float(combo["combo_each_min_force"]) if "combo_each_min_force" in combo else 0.0
		var window_sec = float(combo["combo_window_sec"]) if "combo_window_sec" in combo else -1.0
		var priority = int(combo["combo_priority"]) if "combo_priority" in combo else 0
		if debug_combos:
			print("[ComboDebug] Checking combo: id=%s, required_count=%d, each_min_force=%.2f, window_sec=%.2f, priority=%d" % [
				combo["id"] if "id" in combo else "force_combo", required_count, each_min_force, window_sec, priority
			])
		if required_count <= 0 or each_min_force <= 0.0:
			if debug_combos:
				print("[ComboDebug] Skipping combo due to invalid requirements.")
			continue

		var valid_attacks = []
		for entry in attacks:
			if entry.has("queued_at") and entry.has("force"):
				var t = float(entry["queued_at"])
				var f = float(entry["force"])
				if (window_sec < 0.0 or now - t <= window_sec) and f >= each_min_force:
					valid_attacks.append(entry)
					if debug_combos:
						print("[ComboDebug]   Valid attack: id=%s, force=%.2f, t=%.2f (age=%.2f)" % [
							entry["id"], f, t, now-t
						])
		if debug_combos:
			print("[ComboDebug]   Found %d valid attacks for this combo." % valid_attacks.size())

		if valid_attacks.size() >= required_count:
			if debug_combos:
				print("[ComboDebug]   Combo matched! Priority=%d" % priority)
			if priority > best_priority:
				best_priority = priority
				best_combo = {
					"combo_id": combo["id"] if "id" in combo else "force_combo",
					"id": combo["id"] if "id" in combo else "force_combo",
					"attacks": valid_attacks.slice(valid_attacks.size() - required_count, valid_attacks.size())
				}
				if debug_combos:
					print("[ComboDebug]   >>> This combo will be used!")

	return best_combo if best_combo.size() > 0 else {}

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

func _process_swing_phase() -> void:
	var now := _now()
	if now >= phase_until:
		phase = Phase.POST_SWING
		phase_until = now + 0.3
		if character.hitbox:
			character.hitbox.deactivate()
			_log("CombatController: Hitbox deactivated at end of swing.")

func _process_post_swing_phase() -> void:
	var now := _now()
	if now >= phase_until:
		phase = Phase.RETREAT
		phase_until = now + retreat_duration
		if character.hitbox:
			character.hitbox.deactivate()
			_log("CombatController: Hitbox deactivated at end of swing.")

func _process_retreat_phase() -> void:
	if not character or not character.target_node:
		phase = Phase.NONE
		if character:
			character.on_attack_finished()
		return

	# Only start retreat if not already retreating
	if not character.retreating:
		var desired_space = retreat_distance # meters
		var timeout = retreat_duration # seconds, adjust as needed
		character.start_retreat(desired_space, timeout)
		_log("RETREAT PHASE: Started retreat to %.2f meters for %.2f seconds" % [desired_space, timeout])
	# Do nothing else; wait for retreat_success or retreat_failed signals

func _on_retreat_success():
	_log("RETREAT: Success, reached desired distance.")
	character.stop_retreat()
	phase = Phase.NONE
	if character:
		character.on_attack_finished()

func _on_retreat_failed():
	_log("RETREAT: Failed (timeout).")
	character.stop_retreat()
	phase = Phase.NONE
	if character:
		character.on_attack_finished()

# --- Utility ---
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _log(msg: String) -> void:
	if debug_enabled:
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


func _get_attack_enter_distance(attack_id: StringName) -> float:
	if not character or not character.attack_library:
		return 1.0 # Default
	var spec = character.attack_library.get_spec(attack_id)
	if spec and "enter_distance" in spec:
		return float(spec.enter_distance)
	if spec and "range" in spec:
		return float(spec.range)
	return 1.0 # Fallback

func _get_attack_min_distance(attack_id: StringName) -> float:
	if not character or not character.attack_library:
		return 0.0 # Default: no min
	var spec = character.attack_library.get_spec(attack_id)
	if spec and "min_distance" in spec:
		return float(spec.min_distance)
	if spec and "launch_min_distance" in spec:
		return float(spec.launch_min_distance)
	return 0.5 # Fallback
