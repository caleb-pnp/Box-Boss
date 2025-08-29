extends Node
class_name PunchInputRouter

# Unified punched events: punched(source_id, force)
signal punched(source_id: int, force: float)

@export_category("Dev Keyboard")
@export var enable_keyboard_dev: bool = true
@export var key_to_source: Dictionary = { "KEY_1": 1, "KEY_2": 2, "KEY_3": 3, "KEY_4": 4 }

@export_category("Simulation Randomization")
@export var random_force_min: float = 2.0     # keep wide to cover future device ranges (e.g., up to ~2000)
@export var random_force_max: float = 4000.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	SerialManager.connect("force_update", _on_force_update)


# Production path: forward the exact force you received (e.g., from serial).
func forward_punch(source_id: int, force: float) -> void:
	emit_signal("punched", source_id, max(0.0, force))

# Convenience: simulate punch with randomized force, ignoring any provided value.
func simulate_punch_random(source_id: int) -> void:
	emit_signal("punched", source_id, _rand_force())

func _unhandled_input(event: InputEvent) -> void:
	if not enable_keyboard_dev:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code: int = key.physical_keycode
	var src: int = 0
	if code == KEY_1: src = int(key_to_source.get("KEY_1", 1))
	elif code == KEY_2: src = int(key_to_source.get("KEY_2", 2))
	elif code == KEY_3: src = int(key_to_source.get("KEY_3", 3))
	elif code == KEY_4: src = int(key_to_source.get("KEY_4", 4))
	if src != 0:
		# Always use wide random range for keyboard to mimic real device variability
		simulate_punch_random(src)

func _on_force_update(player_id: int, force: float) -> void:
	forward_punch(player_id, force)

func _rand_force() -> float:
	return _rng.randf_range(random_force_min, max(random_force_min, random_force_max))
