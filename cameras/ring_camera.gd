extends Node3D
class_name VersusRingCamera

@export_group("Targets")
@export var use_group_targets: bool = true
@export var target_group: StringName = &"base_character"
@export var extra_targets: Array[NodePath] = []

@export_group("Center")
@export var ring_center_node: NodePath
@export var fallback_center: Vector3 = Vector3.ZERO

@export_group("Orbit")
@export var start_angle_degrees: float = 0.0
@export var orbit_speed_deg_per_sec: float = 2.0
@export var base_height: float = 4.0
@export var dip_amplitude: float = 1.2
@export var dip_period_sec: float = 24.0
@export var min_distance: float = 4.0
@export var max_distance: float = 12.0

@export var sep_close: float = 2.0
@export var sep_far: float = 12.0

@export_group("Smoothing")
@export_range(0.0, 1.0, 0.01) var position_smooth: float = 0.15
@export_range(0.0, 1.0, 0.01) var center_smooth: float = 0.2
@export_range(0.0, 1.0, 0.01) var distance_smooth: float = 0.2

@export_group("FOV (optional)")
@export var use_fov_zoom: bool = false
@export var fov_min: float = 55.0
@export var fov_max: float = 75.0

@export_group("Collision (optional)")
@export var avoid_clipping: bool = true
@export var collision_mask: int = 1
@export var collision_margin: float = 0.3
# New: never place the camera closer than this due to collisions
@export var min_distance_soft: float = 7.0
# New: raise the ray origin above the ring center to avoid hitting low geometry
@export var collision_origin_y_offset: float = 1.0

var _cam: Camera3D
var _angle_rad: float
var _time: float = 0.0

var _cur_center: Vector3
var _cur_pos: Vector3
var _cur_dist: float
var _cur_fov: float

func _ready() -> void:
	_cam = _find_or_create_camera()
	_cam.current = true

	_angle_rad = deg_to_rad(start_angle_degrees)
	var center := _compute_center()
	_cur_center = center
	_cur_dist = (min_distance + max_distance) * 0.5
	_cur_pos = center + Vector3(cos(_angle_rad) * _cur_dist, base_height, sin(_angle_rad) * _cur_dist)
	_cur_fov = _cam.fov

func _process(delta: float) -> void:
	_time += delta

	var targets := _collect_targets()
	var center_target = _get_ring_center()
	if center_target == null:
		center_target = _average_targets(targets)
	if center_target == null:
		center_target = fallback_center

	_cur_center = _exp_smooth_vec3(_cur_center, center_target, center_smooth, delta)

	var sep := _compute_separation(targets)
	var desired_dist := _remap_clamped(sep, sep_close, sep_far, min_distance, max_distance)
	_cur_dist = _exp_smooth_float(_cur_dist, desired_dist, distance_smooth, delta)

	_angle_rad = wrapf(_angle_rad + deg_to_rad(orbit_speed_deg_per_sec) * delta, -PI, PI)
	var dip := 0.0
	if dip_period_sec > 0.001 and dip_amplitude != 0.0:
		var phase := TAU * (_time / dip_period_sec)
		dip = sin(phase) * dip_amplitude

	var desired_pos := _cur_center + Vector3(cos(_angle_rad) * _cur_dist, base_height + dip, sin(_angle_rad) * _cur_dist)

	if avoid_clipping and is_instance_valid(get_world_3d()):
		var safe_pos := _resolve_collision(_cur_center, desired_pos)
		desired_pos = safe_pos

	_cur_pos = _exp_smooth_vec3(_cur_pos, desired_pos, position_smooth, delta)

	global_position = _cur_pos
	look_at(_cur_center, Vector3.UP)

	if use_fov_zoom:
		var fov_desired := _remap_clamped(sep, sep_close, sep_far, fov_min, fov_max)
		_cur_fov = _exp_smooth_float(_cur_fov, fov_desired, 0.25, delta)
		_cam.fov = _cur_fov

func set_targets(nodes: Array[Node]) -> void:
	use_group_targets = false
	extra_targets.clear()
	for n in nodes:
		if n is Node3D:
			extra_targets.append(n.get_path())

# -----------------------
# Internals
# -----------------------
func _find_or_create_camera() -> Camera3D:
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam:
		return cam
	for child in get_children():
		if child is Camera3D:
			return child as Camera3D
	cam = Camera3D.new()
	add_child(cam)
	cam.name = "Camera3D"
	return cam

func _collect_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if use_group_targets and is_instance_valid(get_tree()):
		for n in get_tree().get_nodes_in_group(target_group):
			if n is Node3D:
				out.append(n as Node3D)
	for p in extra_targets:
		var n := get_node_or_null(p)
		if n and n is Node3D:
			out.append(n as Node3D)
	return out

func _get_ring_center():
	if ring_center_node != NodePath():
		var n := get_node_or_null(ring_center_node)
		if n and n is Node3D:
			return (n as Node3D).global_transform.origin
	return null

func _average_targets(targets: Array[Node3D]):
	if targets.is_empty():
		return null
	var sum := Vector3.ZERO
	for t in targets:
		sum += t.global_transform.origin
	return sum / float(targets.size())

func _compute_separation(targets: Array[Node3D]) -> float:
	var n := targets.size()
	if n <= 1:
		return 0.0
	var max_d := 0.0
	for i in range(n):
		for j in range(i + 1, n):
			var a := targets[i].global_transform.origin
			var b := targets[j].global_transform.origin
			var d := a.distance_to(b)
			if d > max_d:
				max_d = d
	return max_d

func _resolve_collision(center: Vector3, desired_pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state

	# Raise the ray origin to avoid low obstacles near center
	var origin := center + Vector3(0.0, collision_origin_y_offset, 0.0)
	var dir := desired_pos - origin
	var dist := dir.length()
	if dist < 0.001:
		return desired_pos
	dir = dir / dist

	# Do not allow camera closer than min_distance_soft
	var target_dist = max(dist, min_distance_soft)
	var target_pos = origin + dir * target_dist

	var query := PhysicsRayQueryParameters3D.create(origin, target_pos)
	query.collision_mask = collision_mask
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return target_pos

	var hit_pos: Vector3 = hit["position"]
	var safe_dist = max(min_distance_soft, (hit_pos - origin).length() - collision_margin)
	return origin + dir * safe_dist

func _remap_clamped(x: float, a: float, b: float, c: float, d: float) -> float:
	if absf(b - a) < 0.0001:
		return (c + d) * 0.5
	var t = clamp((x - a) / (b - a), 0.0, 1.0)
	return lerp(c, d, t)

func _exp_smooth_float(current: float, target: float, smooth: float, delta: float) -> float:
	if smooth <= 0.0:
		return target
	if smooth >= 1.0:
		return current
	var alpha := 1.0 - pow(1.0 - smooth, delta * 60.0)
	return lerp(current, target, alpha)

func _exp_smooth_vec3(current: Vector3, target: Vector3, smooth: float, delta: float) -> Vector3:
	if smooth <= 0.0:
		return target
	if smooth >= 1.0:
		return current
	var alpha := 1.0 - pow(1.0 - smooth, delta * 60.0)
	return current.lerp(target, alpha)

func _compute_center() -> Vector3:
	# Initial center used at _ready() to place the camera before smoothing kicks in
	var targets := _collect_targets()
	var c = _average_targets(targets)
	if c == null:
		return fallback_center
	return c
