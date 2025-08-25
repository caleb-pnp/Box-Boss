extends Marker3D
class_name SpawnPoint

@export var index: int = 0        # order for VersusModeController
@export var team: int = -1        # optional team tag (unused in simple Versus)
@export var tag: String = ""      # optional label

# Global facing direction. If non-zero, spawns will face this direction.
# If zero, spawns will face toward world origin (0,0,0) by default.
@export var facing_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Ensure discoverable via group
	if not is_in_group("spawn"):
		add_to_group("spawn")
