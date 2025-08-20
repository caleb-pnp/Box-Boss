# Attach this script to the root Node3D of your FreeFlyCamera scene.
extends Node3D

@export_category("Movement")
@export var move_speed: float = 10.0
@export var sprint_multiplier: float = 2.5

@export_category("Look")
@export var mouse_sensitivity: float = 0.2

@onready var camera_node: Camera3D = $Camera3D

# --- Private Variables ---
var _active: bool = false
var _velocity: Vector3 = Vector3.ZERO
var _pitch: float = 0.0
var _yaw: float = 0.0


func _ready() -> void:
	# Initialize rotation from the current orientation set in the editor.
	_yaw = self.rotation_degrees.y
	_pitch = camera_node.rotation_degrees.x
	enable_camera()


# This method is called by the SpectatorManager to activate this camera
func enable_camera() -> void:
	camera_node.make_current()
	_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("FreeFlyCamera enabled.")


# This method is called by the SpectatorManager to deactivate this camera
func disable_camera() -> void:
	_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_velocity = Vector3.ZERO # Reset velocity when disabled
	print("FreeFlyCamera disabled.")


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventMouseMotion:
		# Horizontal rotation (Yaw) rotates the entire parent node.
		_yaw -= event.relative.x * mouse_sensitivity

		# Vertical rotation (Pitch) only rotates the child camera node.
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, -90.0, 90.0)

		# Apply rotations. Yaw is on the Y-axis of the parent (self).
		self.rotation_degrees.y = _yaw
		# Pitch is on the X-axis of the child camera.
		camera_node.rotation_degrees.x = _pitch


func _physics_process(delta: float) -> void:
	if not _active:
		return

	# Get a 2D vector from your specific input actions.
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# Calculate movement direction based on the camera's full 3D orientation.
	var direction := (camera_node.global_transform.basis.z * input_dir.y) + (camera_node.global_transform.basis.x * input_dir.x)

	# Normalize to prevent faster diagonal movement.
	if direction.length_squared() > 0:
		direction = direction.normalized()

	# Check for sprinting.
	var current_speed = move_speed
	if Input.is_action_pressed("ui_accept"):
		current_speed *= sprint_multiplier

	# Apply movement velocity to the parent node.
	_velocity = direction * current_speed
	global_position += _velocity * delta
