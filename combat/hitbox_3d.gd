extends Area3D
class_name Hitbox3D

# Layers: must match Hurtbox3D
const LAYER_HITBOX := 2
const LAYER_HURTBOX := 3

@export var attacker: Node = null                 # BaseCharacter
@export var debug_hitbox: bool = true
@export var rehit_interval_sec: float = 0.25
@export var max_rehits_per_target: int = 4
@export var disable_shape_when_inactive: bool = true  # set false to always see the shape in Debug -> Visible Collision Shapes

# Active window control
var _active: bool = false
var _active_until: float = 0.0
var _activation_delay_sec: float = 0.0
var _activation_duration_sec: float = 0.0

# Re-hit tracking
var _rehit_next_time: Dictionary = {}
var _rehit_count: Dictionary = {}

# Current attack info
var _attack_id: StringName = &""
var _spec: Resource = null
var _impact_force: float = 0.0

# Timer
var _timer_activate: Timer = null

# Predefined shape references (do NOT create/replace; we only read/modify)
var _shape_cs: CollisionShape3D = null
var _box: BoxShape3D = null

func _log(msg: String) -> void:
	if debug_hitbox:
		var atk_path: String = "<none>"
		if attacker != null and attacker is Node:
			atk_path = str((attacker as Node).get_path())
		print("[Hitbox] ", msg, " | atk=", atk_path)

func _ready() -> void:
	monitoring = false
	monitorable = true
	set_collision_layer_value(LAYER_HITBOX, true)
	set_collision_mask_value(LAYER_HURTBOX, true)

	_find_predefined_shape()

	# Signals
	connect("area_entered", Callable(self, "_on_area_entered"))

	# Activation timer
	_timer_activate = Timer.new()
	_timer_activate.one_shot = true
	add_child(_timer_activate)
	_timer_activate.connect("timeout", Callable(self, "_on_activation_timer_timeout"))

	set_physics_process(true)
	_log("ready()")

# Locate the existing CollisionShape3D and BoxShape3D set in the editor
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
	# We do NOT replace the shape; we only adjust if it's a box
	if _shape_cs.shape is BoxShape3D:
		_box = _shape_cs.shape
	else:
		_log("Note: CollisionShape3D is not a BoxShape3D; reach resizing will be skipped.")

# Public API

# Set reach in meters by adjusting only the Z size and Z offset.
# Model faces -Z, so we push origin.z = -reach/2.
func set_reach_meters(reach_m: float) -> void:
	if _shape_cs == null:
		_find_predefined_shape()
	if _shape_cs == null:
		return
	if _box == null:
		# Shape is not a BoxShape3D; cannot adjust size.z cleanly
		_log("set_reach_meters skipped (shape is not BoxShape3D)")
		return
	reach_m = max(0.0, reach_m)
	# Adjust Z size, preserve X/Y
	var s: Vector3 = _box.size
	s.z = reach_m
	_box.size = s
	# Center in front of the character along -Z by half the reach
	var xf := _shape_cs.transform
	xf.origin.z = -reach_m * 0.5
	_shape_cs.transform = xf
	_log("reach set -> size.z=" + str(reach_m) + " offset.z=" + str(xf.origin.z))

# Configure from a spec WITHOUT replacing your shape.
# Optional property: reach_meters (float)
# Optional: rehit_interval_sec, max_rehits_per_target, active_start_sec, active_end_sec
func configure_from_spec(spec: Resource) -> void:
	_spec = spec
	if spec == null:
		return
	# If spec provides reach, apply it
	var has_reach = spec.has_method("get") and spec.has_property("reach_meters")
	if has_reach:
		var r = spec.get("reach_meters")
		if typeof(r) == TYPE_FLOAT or typeof(r) == TYPE_INT:
			set_reach_meters(float(r))
	# Re-hit cadence
	if spec.has_property("rehit_interval_sec"):
		rehit_interval_sec = float(spec.get("rehit_interval_sec"))
	if spec.has_property("max_rehits_per_target"):
		max_rehits_per_target = int(spec.get("max_rehits_per_target"))

# Activate using spec timing (if present), else immediately for duration if you call activate() directly.
func activate_for_attack(attack_id: StringName, spec: Resource, impact_force: float) -> void:
	_attack_id = attack_id
	_impact_force = impact_force
	configure_from_spec(spec)

	var start_off: float = 0.05
	var end_off: float = 0.20
	if spec != null:
		if spec.has_property("active_start_sec"):
			start_off = float(spec.get("active_start_sec"))
		if spec.has_property("active_end_sec"):
			end_off = float(spec.get("active_end_sec"))
	var duration: float = max(0.0, end_off - start_off)
	_activation_delay_sec = max(0.0, start_off)
	_activation_duration_sec = duration

	_log("schedule activate: start_off=" + str(_activation_delay_sec) + " duration=" + str(_activation_duration_sec))
	_timer_activate.start(_activation_delay_sec)

# Immediate activation for a given duration (seconds)
func activate(duration_sec: float) -> void:
	var now_time: float = Time.get_ticks_msec() / 1000.0
	_active = true
	_active_until = now_time + max(0.0, duration_sec)
	monitoring = true
	_set_shape_disabled(false)
	_rehit_next_time.clear()
	_rehit_count.clear()
	_log("ACTIVATE for " + str(duration_sec) + "s (until " + str(_active_until) + ")")

func deactivate() -> void:
	_active = false
	monitoring = false
	_set_shape_disabled(true)
	_log("DEACTIVATE")

# Internals

func _physics_process(delta: float) -> void:
	if not _active:
		return
	var now_time: float = Time.get_ticks_msec() / 1000.0
	if now_time >= _active_until:
		deactivate()
		return

	# Poll overlaps to allow periodic re-hits
	var areas := get_overlapping_areas()
	for area in areas:
		var hb := area as Hurtbox3D
		if hb == null or hb.owner_character == null:
			continue
		# Prevent self-hits
		if attacker != null and hb.owner_character == attacker:
			continue
		_try_apply_hit(hb.owner_character, now_time)

func _on_area_entered(area: Area3D) -> void:
	if not _active:
		return
	var hb := area as Hurtbox3D
	if hb == null or hb.owner_character == null:
		return
	# Prevent self-hits
	if attacker != null and hb.owner_character == attacker:
		return
	_try_apply_hit(hb.owner_character, Time.get_ticks_msec() / 1000.0)

func _try_apply_hit(target: Node, now_time: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var key := target.get_instance_id()
	var next_ok: float = float(_rehit_next_time.get(key, -1.0))
	var count: int = int(_rehit_count.get(key, 0))

	if count >= max_rehits_per_target:
		return
	if next_ok >= 0.0 and now_time < next_ok:
		return

	_rehit_next_time[key] = now_time + rehit_interval_sec
	_rehit_count[key] = count + 1

	if target.has_method("apply_hit"):
		_log("HIT -> " + str(target.get_path()) + " #" + str(_rehit_count[key]) + " force=" + str(_impact_force))
		target.apply_hit(attacker, _spec, _impact_force)
	else:
		_log("target missing apply_hit(attacker, spec, force)")

func _set_shape_disabled(disabled: bool) -> void:
	if not disable_shape_when_inactive:
		return
	if _shape_cs != null:
		_shape_cs.disabled = disabled

func _on_activation_timer_timeout() -> void:
	activate(_activation_duration_sec)
