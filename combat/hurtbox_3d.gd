extends Area3D
class_name Hurtbox3D

@export var owner_character: Node = null
@export var debug_hurtbox: bool = true

# Layers: must match Hitbox3D
const LAYER_HITBOX := 2
const LAYER_HURTBOX := 3

func _log(msg: String) -> void:
	if debug_hurtbox:
		var who_path: String = "<none>"
		if owner_character != null and owner_character is Node:
			who_path = str((owner_character as Node).get_path())
		print("[Hurtbox] ", msg, " | owner=", who_path)

func _ready() -> void:
	monitoring = true
	monitorable = true
	set_collision_layer_value(LAYER_HURTBOX, true)
	set_collision_mask_value(LAYER_HITBOX, true)

	# Warn if no shape
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D:
			has_shape = true
			break
	if not has_shape:
		_log("WARNING: No CollisionShape3D. Add one so this can be hit.")
	_log("ready() layer(HURTBOX)=" + str(get_collision_layer_value(LAYER_HURTBOX)) + " mask(HITBOX)=" + str(get_collision_mask_value(LAYER_HITBOX)) + " monitoring=" + str(monitoring))
