extends Node
class_name PunchInputRouter

# Unified punched events: punched(source_id, force)
signal punched(source_id: int, force: float)

@export_category("Dev Keyboard")
@export var enable_keyboard_dev: bool = true
@export var key_to_source: Dictionary = { "KEY_1": 1, "KEY_2": 2, "KEY_3": 3, "KEY_4": 4 }
# Base forces for keyboard testing (Shift = heavy). We'll add jitter so it's different each time.
@export var light_force: float = 5.0
@export var heavy_force: float = 15.0
@export var keyboard_jitter_pct: float = 0.25  # +/- percentage randomness around the base force

@export_category("Simulation Randomization")
# When true, simulate_punch() will ignore/override the provided force and randomize it.
# Later, when you wire a real serial listener, call forward_punch() to pass the exact force through.
@export var randomize_on_simulate: bool = true
@export var random_force_min: float = 2.0     # keep wide to cover future device ranges (e.g., up to ~2000)
@export var random_force_max: float = 3000.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

# Developer helper: simulate a punch for a given source.
# If randomize_on_simulate is true (default) or force <= 0, a random force is generated.
func simulate_punch(source_id: int, force: float = -1.0) -> void:
	var f := force
	if randomize_on_simulate or f <= 0.0:
		f = _rand_force()
	emit_signal("punched", source_id, max(0.0, f))

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
		# Randomize around base light/heavy so each press differs
		var base := heavy_force if key.shift_pressed else light_force
		var jitter := clampf(keyboard_jitter_pct, 0.0, 1.0)
		var fmin = max(0.0, base * (1.0 - jitter))
		var fmax := base * (1.0 + jitter)
		var f := _rng.randf_range(fmin, fmax)
		emit_signal("punched", src, f)

func _rand_force() -> float:
	return _rng.randf_range(random_force_min, max(random_force_min, random_force_max))
