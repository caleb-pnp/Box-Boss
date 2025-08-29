extends Area3D
class_name Hurtbox3D

@export var debug_hurtbox: bool = true
var character: BaseCharacter = null

var _processed_attack_ids := {}
var _attack_hit_times := {} # key: String, value: float (last hit time)
var _attack_hit_counts := {} # key: String, value: int (number of hits)

signal hit_received(attacker, spec, impact_force)

func _log(msg: String) -> void:
	if debug_hurtbox:
		var who_path: String = "<none>"
		if character != null and character is Node:
			who_path = str((character as Node).get_path())
		print("[Hurtbox] ", msg, " | owner=", who_path)

func _ready() -> void:
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D:
			has_shape = true
			break
	if not has_shape:
		_log("WARNING: No CollisionShape3D. Add one so this can be hit.")

# Called by Hitbox3D when a hit is detected
func receive_hit(attacker, spec, impact_force, attack_instance_id) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var interval := 0.5
	var max_rehits := 1
	if spec:
		if "rehit_interval_sec" in spec:
			interval = float(spec.rehit_interval_sec)
		if "max_rehits_per_target" in spec:
			max_rehits = int(spec.max_rehits_per_target)
	var key = str(attack_instance_id) + "_" + str(attacker.get_instance_id())
	var hit_count = _attack_hit_counts.get(key, 0)
	var last_time = _attack_hit_times.get(key, -1000.0)

	if max_rehits <= 1:
		if hit_count >= 1:
			return # Only allow one hit ever for this attack instance
	else:
		if hit_count >= max_rehits:
			return # Reached max hits for this attack instance
		if now - last_time < interval:
			return # Too soon for another hit

	# Allow hit
	_attack_hit_counts[key] = hit_count + 1
	_attack_hit_times[key] = now
	emit_signal("hit_received", attacker, spec, impact_force)
	if spec and "damage" in spec:
		show_damage_text(int(spec.damage))

func show_damage_text(amount: int):
	var text = Label3D.new()
	text.set_script(load("res://ui/labels/damage_text_3d.gd")) # Attach your script first!
	text.text = "-%d" % amount
	text.modulate = Color(1, 0.2, 0.2)
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.fade_time = 2.0 # Now this works, because the script is attached
	text.scale = Vector3(2, 2, 2) # Double the size in all dimensions
	get_tree().current_scene.add_child(text)
	text.global_position = character.global_position + Vector3(0, 1, 0)
