extends Resource
class_name AttackSpec

@export_category("Identity")
@export var id: StringName = &""
@export var category: StringName = &"light" # light | medium | heavy | special
@export var display_name: String = ""

@export_category("Range")
@export var enter_distance: float = 1.5
@export var launch_min_distance: float = 0.0

@export_category("Timing")
@export var swing_time_sec: float = 0.8
@export var cooldown_sec: float = 1.0
@export var move_lock_sec: float = 0.8

@export_category("Animator OneShots")
@export var request_param_a: StringName = &""
@export var request_param_b: StringName = &""

@export_category("Impact")
@export var damage: float = 8.0
@export var guard_damage: float = 2.0
@export var stagger_time_sec: float = 0.2
