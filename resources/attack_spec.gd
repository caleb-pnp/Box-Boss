extends Resource
class_name AttackSpec

@export_category("Identity")
@export var id: StringName = &""
@export var category: StringName = &"light" # light | medium | heavy | special
@export var display_name: String = ""

@export_category("Range")
@export var enter_distance: float = 1.5
@export var launch_min_distance: float = 0.0

@export_category("Hitbox/Reach")
@export var reach_meters: float = 1.5

@export_category("Timing")
@export var swing_time_sec: float = 0.8
@export var cooldown_sec: float = 1.0
@export var move_lock_sec: float = 0.8

@export_category("Animator OneShots")
@export var request_param_a: StringName = &""
@export var request_param_b: StringName = &""

@export_category("Selection / Force Mapping")
@export var force_min: float = 0.0
@export var force_max: float = 999999.0
@export var selection_weight: float = 1.0   # optional small bias when ties remain

@export_category("Combo Trigger (optional; only if this id is in AttackSetData.combo_attack_ids)")
@export var combo_required_count: int = 0      # e.g., 2 for "two hard punches"
@export var combo_each_min_force: float = 0.0  # each punch must be >= this
@export var combo_window_sec: float = -1.0     # <= 0 => use character's attack_window_sec
@export var combo_priority: int = 100          # higher wins when multiple combos match

@export_category("On Hit")
@export var damage: float = 10.0
@export var scale_damage_by_force: bool = false
@export var min_damage: float = 5.0
@export var max_damage: float = 25.0
@export var stagger_sec: float = 0.2
@export var knockback_meters: float = 0.5
@export var knockback_duration_sec: float = 0.5

@export_category("Hitbox Timing")
@export var active_start_sec: float = 0.25 # when the hitbox becomes active in the attack
@export var active_end_sec: float = 1.25    # when it stops being active
@export var rehit_interval_sec: float = 0.50  # if overlapping, how often to re-apply a hit
@export var max_rehits_per_target: int = 1    # safety limit for multi-hit attacks

# Optional: add _to_string for debugging
func _to_string() -> String:
	return "[AttackSpec %s: %s, reach=%.2f]" % [id, display_name, reach_meters]
