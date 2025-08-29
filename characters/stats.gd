extends Node
class_name Stats

signal health_changed(current: int, max: int)
signal stamina_changed(current: float, max: float)
signal died

@export var max_health: int = 100
@export var max_stamina: float = 100.0
@export var stamina_regen_per_sec: float = 15.0
@export var stamina_attack_cost: float = 20.0
@export var stamina_move_drain_per_meter: float = 0.0 # optional light drain while moving

var health: int
var stamina: float

func _ready() -> void:
	health = max_health
	stamina = max_stamina
	emit_signal("health_changed", health, max_health)
	emit_signal("stamina_changed", stamina, max_stamina)

func _process(delta: float) -> void:
	regenerate_stamina(delta)

func regenerate_stamina(delta: float) -> void:
	if stamina < max_stamina:
		stamina = min(max_stamina, stamina + stamina_regen_per_sec * delta)
		emit_signal("stamina_changed", stamina, max_stamina)

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	print("Taking damage:", amount, "Current health:", health)
	health = max(0, health - amount)
	print("Health after:", health)
	emit_signal("health_changed", health, max_health)
	if health == 0:
		emit_signal("died")

func try_spend_stamina(cost: float) -> bool:
	if stamina >= cost:
		stamina -= cost
		emit_signal("stamina_changed", stamina, max_stamina)
		return true
	return false

func spend_movement(distance_m: float) -> void:
	if stamina_move_drain_per_meter <= 0.0:
		return
	if distance_m <= 0.0:
		return
	stamina = max(0.0, stamina - stamina_move_drain_per_meter * distance_m)
	emit_signal("stamina_changed", stamina, max_stamina)
