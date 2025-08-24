extends Node
class_name PunchInputRouter

# Host-only punch router. Emits unified punched(source_id, force).
signal punched(source_id: int, force: float)

@export var enable_keyboard_dev: bool = true
# Map physical keys to source ids; two local sources by default
@export var key_to_source: Dictionary = { "KEY_1": 1, "KEY_2": 2, "KEY_3": 3, "KEY_4": 4 }
@export var light_force: float = 5.0
@export var heavy_force: float = 15.0

func simulate_punch(source_id: int, force: float) -> void:
	emit_signal("punched", source_id, max(0.0, force))

func forward_punch(source_id: int, force: float) -> void:
	emit_signal("punched", source_id, max(0.0, force))

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
		var f: float = (heavy_force if key.shift_pressed else light_force)
		emit_signal("punched", src, f)
