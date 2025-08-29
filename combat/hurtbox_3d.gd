extends Area3D
class_name Hurtbox3D

@export var debug_hurtbox: bool = true
var character: BaseCharacter = null

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
func receive_hit(attacker, spec, impact_force) -> void:
	_log("receive_hit: emitting hit_received")
	emit_signal("hit_received", attacker, spec, impact_force)
