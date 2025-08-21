extends Resource
class_name ActionStateBinding

@export var key: StringName = &"PUNCH"   # logical action key (e.g., PUNCH, COMBO_A, POSE)
@export var state: StringName = &"Punch"  # AnimationTree state name to travel to
