extends Resource
class_name AttackSpec

@export_category("Identity")
# Must be the move name, e.g., "LeadJabOneShot", "JabCrossOneShot"
@export var id: StringName = &""
# light | medium | heavy | special
@export var category: StringName = &"light"
@export var display_name: String = ""

@export_category("Range")
# Approach until distance_to_target() <= enter_distance
@export var enter_distance: float = 1.5
# Optional lower bound to launch; if <= 0, no lower bound is enforced
@export var launch_min_distance: float = 0.0

@export_category("Timing")
# Duration of the one-shot (used to hold swing phase)
@export var swing_time_sec: float = 0.8
# Cooldown before this attack can be used again
@export var cooldown_sec: float = 1.0
# Movement lock duration starting when the swing starts
@export var move_lock_sec: float = 0.8

@export_category("Animator OneShots")
# Full AnimationTree request param paths for A/B lanes
# Example: parameters/Fighting/LeadJabOneShot_A/request
@export var request_param_a: StringName = &""
@export var request_param_b: StringName = &""
