extends Node3D
class_name FreeFlyTestingCamera
"""
Free-fly camera with click-to-ground raycasts + optional world-space aim marker.

Children:
- Camera3D at $Camera3D

Signals:
- left_click_ground(position)
- right_click_ground(position, shift_pressed)
- middle_click_ground(position)
"""

@export_category("Movement")
@export var move_speed: float = 10.0
@export var sprint_multiplier: float = 2.5

@export_category("Look")
@export var mouse_sensitivity: float = 0.2

@export_category("Raycast")
@export var ground_collision_mask: int = 1
@export var ray_length: float = 500.0

@export_category("Aim Marker")
@export var aim_enabled: bool = true
@export var aim_indicator_path: NodePath
@export var auto_create_indicator: bool = true
@export var indicator_size: float = 0.6
@export var indicator_color: Color = Color(0.2, 1.0, 0.4, 0.5)
@export var indicator_hover_offset: float = 0.02
@export var indicator_smoothing: float = 12.0

@onready var camera_node: Camera3D = $Camera3D
@onready var aim_indicator: AimIndicator3D = null

signal left_click_ground(position: Vector3)
signal right_click_ground(position: Vector3, shift_pressed: bool)
signal middle_click_ground(position: Vector3)

var _active: bool = false
var _velocity: Vector3 = Vector3.ZERO
var _pitch: float = 0.0
var _yaw: float = 0.0

func _ready() -> void:
	_yaw = self.rotation_degrees.y
	_pitch = camera_node.rotation_degrees.x
	_resolve_indicator()
	enable_camera()

func enable_camera() -> void:
	camera_node.make_current()
	_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func disable_camera() -> void:
	_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	# Toggle capture with Esc
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			disable_camera()
		else:
			enable_camera()
		return

	if not _active:
		if event is InputEventMouseButton and event.pressed:
			enable_camera()
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, -90.0, 90.0)
		self.rotation_degrees.y = _yaw
		camera_node.rotation_degrees.x = _pitch

	if event is InputEventMouseButton and event.pressed:
		var hit: Dictionary = _raycast_mouse()
		if hit.is_empty():
			return
		var pt: Vector3 = hit["position"]
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				left_click_ground.emit(pt)
			MOUSE_BUTTON_RIGHT:
				right_click_ground.emit(pt, Input.is_key_pressed(KEY_SHIFT))
			MOUSE_BUTTON_MIDDLE:
				middle_click_ground.emit(pt)

func _physics_process(delta: float) -> void:
	if not _active:
		return

	# Move
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (camera_node.global_transform.basis.z * input_dir.y) + (camera_node.global_transform.basis.x * input_dir.x)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	var current_speed := move_speed
	if Input.is_action_pressed("ui_accept"):
		current_speed *= sprint_multiplier
	_velocity = direction * current_speed
	global_position += _velocity * delta

	# Aim indicator
	if aim_enabled and aim_indicator:
		var hit: Dictionary = _raycast_mouse()
		if hit.is_empty():
			aim_indicator.clear_target()
		else:
			var pos: Vector3 = hit["position"]
			var nrm: Vector3 = hit["normal"] if hit.has("normal") else Vector3.UP
			aim_indicator.set_target(pos, nrm)

func get_mouse_ground_point() -> Vector3:
	var hit: Dictionary = _raycast_mouse()
	return hit["position"] if not hit.is_empty() else Vector3.INF

func _raycast_mouse() -> Dictionary:
	var vp := get_viewport()
	if not vp:
		return {}
	var mouse: Vector2 = vp.get_mouse_position()
	var from: Vector3 = camera_node.project_ray_origin(mouse)
	var to: Vector3 = from + camera_node.project_ray_normal(mouse) * ray_length
	var space: PhysicsDirectSpaceState3D = vp.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ground_collision_mask
	return space.intersect_ray(query)

func _resolve_indicator() -> void:
	if aim_indicator_path != NodePath(""):
		aim_indicator = get_node_or_null(aim_indicator_path) as AimIndicator3D
	if not aim_indicator and auto_create_indicator:
		aim_indicator = AimIndicator3D.new()
		aim_indicator.size = indicator_size
		aim_indicator.color = indicator_color
		aim_indicator.hover_offset = indicator_hover_offset
		aim_indicator.smoothing = indicator_smoothing
		if get_parent():
			get_parent().add_child(aim_indicator)
		else:
			add_child(aim_indicator)
		aim_indicator.global_transform = Transform3D.IDENTITY
