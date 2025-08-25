extends SelectableData
class_name ModeData

@export var description: String = ""

# What to start when this mode is chosen. Prefer lazy-loaded paths to avoid preload chains.
# One of these should be set:
@export var controller_key: StringName = &""           # Key for game.begin_local_controller(key, ...)
@export_file("*.tscn") var controller_scene_path: String = "" # res://.../MyModeController.tscn (optional)
@export_file("*.gd") var controller_script_path: String = "" # res://.../MyModeController.gd  (optional)

# Optional mode-specific defaults merged into the params sent to the game when starting the mode.
@export var default_params: Dictionary = {}
