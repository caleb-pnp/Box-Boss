extends Marker3D
class_name SpawnPoint

@export var index: int = 0        # order for VersusModeController
@export var team: int = -1        # optional team tag (unused in simple Versus)
@export var tag: String = ""      # optional label

func _ready() -> void:
	# Ensure discoverable via group
	if not is_in_group("spawn"):
		add_to_group("spawn")
