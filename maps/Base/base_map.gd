class_name BaseMap
extends Node3D

signal map_ready()

@export var id: StringName

# As MAPS are loaded incrementally, do not rely on _ready
# we need to manually call post_load() once all children have been added back to the scene
func _ready() -> void:
	# emit ready signal
	map_ready.emit()

	# Tell map manager it's been added to scene
	MapManager.map_added_to_scene()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
