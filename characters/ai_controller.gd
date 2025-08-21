extends Node

@export var character_path: NodePath
@export var enabled: bool = true

# Ranges and pacing
@export var preferred_range: Vector2 = Vector2(1.8, 2.4) # x=min, y=max
@export var approach_run_distance: float = 4.5
@export var attack_cooldown_range: Vector2 = Vector2(0.9, 1.6) # seconds
@export var decision_interval_range: Vector2 = Vector2(0.6, 1.2) # seconds
@export var stamina_threshold_attack: float = 30.0
@export var retreat_health_ratio: float = 0.2
@export var retreat_stamina_ratio: float = 0.2

# Circling
@export var circle_bias: float = 0.9 # how much we favor strafing over forward when in range (0..1)
@export var circle_switch_interval_range: Vector2 = Vector2(2.0, 4.0)

var character: BaseCharacter
var next_decision_time: float = 0.0
var next_attack_time: float = 0.0
var circle_dir: int = 1
var next_circle_switch_time: float = 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	character = get_node_or_null(character_path)
	if not character:
		push_warning("AIController: character_path is not set.")
		return
	_reset_timers(true)

func _physics_process(_delta: float) -> void:
	if not enabled or not character:
		return
	if not character.has_target():
		_idle()
		return

	var now := Time.get_unix_time_from_system()
	if now >= next_circle_switch_time:
		# GDScript doesn't use ?:, use if/else expression instead
		circle_dir = 1 if (rng.randi() % 2 == 0) else -1
		next_circle_switch_time = now + rng.randf_range(circle_switch_interval_range.x, circle_switch_interval_range.y)

	var dist := character.distance_to_target()

	var health_ratio := 1.0
	var stamina := 100.0
	var max_stamina := 100.0
	if character.stats:
		# If Stats.gd has class_name Stats, this is typed and safe
		health_ratio = float(character.stats.health) / max(1.0, float(character.stats.max_health))
		stamina = float(character.stats.stamina)
		max_stamina = float(character.stats.max_stamina)

	# Retreat logic
	if health_ratio <= retreat_health_ratio or (stamina / max_stamina) <= retreat_stamina_ratio:
		_retreat(dist)
		return

	# In-range circle/attack
	if dist >= preferred_range.x and dist <= preferred_range.y:
		_circle_and_fight(now, stamina)
		return

	# Approach
	_approach(dist)

func _idle() -> void:
	character.intents["move_local"] = Vector2.ZERO
	character.intents["run"] = false
	character.intents["retreat"] = false

func _retreat(_dist: float) -> void:
	# If very close, run away and allow turning away from target
	character.intents["move_local"] = Vector2(0.0, -1.0)
	character.intents["run"] = true
	character.intents["retreat"] = true

func _approach(dist: float) -> void:
	# Move forward toward target. Run if far.
	character.intents["move_local"] = Vector2(0.0, 1.0)
	character.intents["run"] = dist > approach_run_distance
	character.intents["retreat"] = false

func _circle_and_fight(now: float, stamina: float) -> void:
	# Strafe around the target, with slight forward bias to maintain contact
	var forward_bias := 1.0 - circle_bias # small forward component
	character.intents["move_local"] = Vector2(circle_dir, forward_bias).normalized()
	character.intents["run"] = false
	character.intents["retreat"] = false

	if now >= next_attack_time and stamina >= stamina_threshold_attack and character.in_attack_range():
		# Choose an attack strength with some variability
		var strength := rng.randf_range(0.3, 1.0)
		character.intents["attack"] = true
		character.intents["attack_strength"] = strength
		next_attack_time = now + rng.randf_range(attack_cooldown_range.x, attack_cooldown_range.y)

	# Occasionally flip circling direction
	if now >= next_decision_time:
		_reset_timers(false)

func _reset_timers(initial: bool) -> void:
	var now := Time.get_unix_time_from_system()
	next_decision_time = now + rng.randf_range(decision_interval_range.x, decision_interval_range.y)
	if initial:
		next_attack_time = now + rng.randf_range(attack_cooldown_range.x, attack_cooldown_range.y)
	next_circle_switch_time = now + rng.randf_range(circle_switch_interval_range.x, circle_switch_interval_range.y)
