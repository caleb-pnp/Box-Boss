extends Area3D
class_name Hitbox3D

@export var attacker: Node = null
@export var debug_hitbox: bool = true
@export var rehit_interval_sec: float = 0.25
@export var max_rehits_per_target: int = 4
@export var disable_shape_when_inactive: bool = true

var character: BaseCharacter = null

# --- Internal/Private (unchanged from your version) ---

var _active: bool = false
var _active_until: float = 0.0
var _activation_delay_sec: float = 0.0
var _activation_duration_sec: float = 0.0
var _rehit_next_time: Dictionary = {}
var _rehit_count: Dictionary = {}
var _attack_id: StringName = &""
var _spec: Resource = null # the current hit spec
var _impact_force: float = 0.0 # the current hit impact force
var _timer_activate: Timer = null
var _shape_cs: CollisionShape3D = null
var _box: BoxShape3D = null

# --- Public API ---
func activate_for_attack(attack_id: StringName, spec: Resource, impact_force: float) -> void:
	_active = true
	monitoring = true
	_attack_id = attack_id
	_impact_force = impact_force
	configure_from_spec(spec)
	var start_off: float = 0.05
	var end_off: float = 0.20
	if spec != null:
		if "active_start_sec" in spec:
			start_off = float(spec.active_start_sec)
		if "active_end_sec" in spec:
			end_off = float(spec.active_end_sec)
	var duration: float = max(0.0, end_off - start_off)
	_activation_delay_sec = max(0.0, start_off)
	_activation_duration_sec = duration
	_log("schedule activate: start_off=" + str(_activation_delay_sec) + " duration=" + str(_activation_duration_sec))
	_timer_activate.start(_activation_delay_sec)

func deactivate() -> void:
	_active = false
	monitoring = false
	_set_shape_disabled(true)
	_log("DEACTIVATE")

func configure_from_spec(spec: Resource) -> void:
	_spec = spec
	if spec == null:
		return
	if "reach_meters" in spec:
		set_reach_meters(float(spec.reach_meters))
	if "rehit_interval_sec" in spec:
		rehit_interval_sec = float(spec.rehit_interval_sec)
	if "max_rehits_per_target" in spec:
		max_rehits_per_target = int(spec.max_rehits_per_target)

func set_reach_meters(reach_m: float) -> void:
	if _shape_cs == null:
		_find_predefined_shape()
	if _shape_cs == null:
		return
	if _box == null:
		_log("set_reach_meters skipped (shape is not BoxShape3D)")
		return
	reach_m = max(0.0, reach_m)
	var s: Vector3 = _box.size
	s.z = reach_m
	_box.size = s
	var xf := _shape_cs.transform
	xf.origin.z = -reach_m * 0.5
	_shape_cs.transform = xf
	_log("reach set -> size.z=" + str(reach_m) + " offset.z=" + str(xf.origin.z))



func _log(msg: String) -> void:
	if debug_hitbox:
		var atk_path: String = "<none>"
		if attacker != null and attacker is Node:
			atk_path = str((attacker as Node).get_path())
		print("[Hitbox] ", msg, " | atk=", atk_path)

func _ready() -> void:
	_find_predefined_shape()
	_timer_activate = Timer.new()
	_timer_activate.one_shot = true
	add_child(_timer_activate)
	_timer_activate.connect("timeout", Callable(self, "_on_activation_timer_timeout"))

func _find_predefined_shape() -> void:
	_shape_cs = null
	_box = null
	for c in get_children():
		if c is CollisionShape3D:
			_shape_cs = c
			break
	if _shape_cs == null:
		_log("WARNING: No CollisionShape3D child found; cannot collide.")
		return
	if _shape_cs.shape is BoxShape3D:
		_box = _shape_cs.shape
	else:
		_log("Note: CollisionShape3D is not a BoxShape3D; reach resizing will be skipped.")

func activate(duration_sec: float) -> void:
	var now_time: float = Time.get_ticks_msec() / 1000.0
	_active = true
	_active_until = now_time + max(0.0, duration_sec)
	monitoring = true
	_set_shape_disabled(false)
	_rehit_next_time.clear()
	_rehit_count.clear()
	_log("ACTIVATE for " + str(duration_sec) + "s (until " + str(_active_until) + ")")

func _physics_process(delta: float) -> void:
	if not _active:
		return
	var now_time: float = Time.get_ticks_msec() / 1000.0
	if now_time >= _active_until:
		deactivate()
		return
	var areas := get_overlapping_areas()
	for area in areas:
		var hb := area as Hurtbox3D
		if hb == null or hb.character == null:
			continue
		if attacker != null and hb.character == attacker:
			continue
		_try_apply_hit(hb, now_time)

func _try_apply_hit(target_hurtbox: Hurtbox3D, now_time: float) -> void:
	if target_hurtbox == null or not is_instance_valid(target_hurtbox):
		return
	if target_hurtbox.has_method("receive_hit"):
		target_hurtbox.receive_hit(character, _spec, _impact_force)
	else:
		_log("target missing apply_hit(attacker, spec, force)")

func _set_shape_disabled(disabled: bool) -> void:
	if not disable_shape_when_inactive:
		return
	if _shape_cs != null:
		_shape_cs.disabled = disabled

func _on_activation_timer_timeout() -> void:
	activate(_activation_duration_sec)
