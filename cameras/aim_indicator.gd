extends Node3D
class_name AimIndicator3D
"""
World-space aim marker that lies flush on the ground:
- Uses PlaneMesh (normal +Y) so it naturally aligns to surface normal.
- Orients parent +Y to the ground normal.
- Sits slightly above ground to avoid z-fighting.
- Smooth motion with configurable smoothing.
"""

@export var size: float = 0.6
@export var color: Color = Color(0.2, 1.0, 0.4, 0.5)
@export var hover_offset: float = 0.02
@export var smoothing: float = 12.0

var _mesh: MeshInstance3D
var _target_pos: Vector3 = Vector3.ZERO
var _target_nrm: Vector3 = Vector3.UP
var _has_target: bool = false

func _ready() -> void:
	_build_mesh()

func set_target(point: Vector3, normal: Vector3) -> void:
	_target_pos = point
	_target_nrm = normal.normalized()
	_has_target = true
	visible = true

func clear_target() -> void:
	_has_target = false
	visible = false

func _process(delta: float) -> void:
	if not _has_target:
		return
	# Smooth position
	var desired := _target_pos + _target_nrm * hover_offset
	global_position = global_position.lerp(desired, clampf(smoothing * delta, 0.0, 1.0))

	# Smooth orientation: align parent +Y to surface normal
	var current_up := global_transform.basis.y.normalized()
	var new_up := current_up.slerp(_target_nrm, clampf(smoothing * delta, 0.0, 1.0)).normalized()
	_set_basis_up(new_up)

func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new() # lies in XZ plane with +Y normal
	plane.size = Vector2.ONE
	_mesh.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	_mesh.material_override = mat

	add_child(_mesh)
	_mesh.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null

	# Scale the visual plane; no rotations needed
	_mesh.scale = Vector3(size, 1.0, size)
	visible = false

func _set_basis_up(up: Vector3) -> void:
	var y := up.normalized()
	# Pick a stable reference to avoid gimbal at near-parallel
	var ref := Vector3.FORWARD
	if abs(y.dot(ref)) > 0.95:
		ref = Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	global_transform.basis = Basis(x, y, z)
