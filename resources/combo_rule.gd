extends Resource
class_name ComboRule

@export var attack_id: StringName = &""         # The move to trigger when the rule matches
@export var required_count: int = 2             # e.g., 2 punches
@export var each_min_force: float = 1000.0      # each punch must be >= this
@export var window_sec: float = -1.0            # <= 0 uses fighter's default attack_window_sec
@export var priority: int = 100                 # Higher beats lower when multiple rules match
