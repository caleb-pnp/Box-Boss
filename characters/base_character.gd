extends CharacterBody3D
class_name BaseCharacter

enum State { IDLE, AUTO_MOVE, ATTACKING, HIT_RESPONSE, KO }
enum TargetMode { NONE, MOVE, FIGHT }

# --- Character Movement Settings ---
@export var walk_speed: float = 5.0
@export var strafe_speed_scale_min: float = 0.2
@export var strafe_speed_scale_max: float = 0.8
@export var strafe_magnitude_min: float = 0.25
@export var strafe_magnitude_max: float = 0.7
@export var strafe_activity_prob: float = 0.55
@export var strafe_on_time_min: float = 0.4
@export var strafe_on_time_max: float = 1.2
@export var strafe_off_time_min: float = 0.35
@export var strafe_off_time_max: float = 1.0
@export var retreat_max_mag: float = 0.45
@export var retreat_speed_scale: float = 0.55

# --- Center Seeking Settings
@export var center_seek_enabled: bool = true
@export var center_seek_strength: float = 0.05

# --- Shared Character State, Target and Movement Variables ---
var state: int = State.IDLE
var target_node: Node3D = null
var target_point: Vector3 = Vector3.ZERO
var has_target: bool = false
var target_mode: int = TargetMode.NONE

var agent: NavigationAgent3D = null
var stats: Node = null

var round_active: bool = false
var arena_center: Vector3 = Vector3.ZERO
var arena_radius_hint: float = 0.0

# --- Shared Combat Variables ---
@export var attack_library: AttackLibrary
@export_file("*.tres") var attack_library_path: String = "res://data/AttackLibrary.tres"

@export var attack_set_data: AttackSetData
@export_file("*.tres") var attack_set_data_path: String = "res://data/attack_sets/Default.tres"

@export var input_source_id: int = 0

func set_attack_set_data(data: AttackSetData) -> void:
	attack_set_data = data

func set_input_source_id(id: int) -> void:
	input_source_id = id

# --- Shared Controllers and Helpers ---
@onready var animator: CharacterAnimator = $CharacterAnimator
@onready var auto_move: AutoMoveController = $AutoMoveController
@onready var combat: CombatController = $CombatController
@onready var hit_response: HitResponseController = $HitResponseController
@onready var hitbox: Hitbox3D = $Hitbox3D
@onready var hurtbox: Hurtbox3D = $Hurtbox3D

# --- Internal Variables ---
var debug_enabled: bool = true

func _ready():
	# assing self to controllers
	auto_move.setup(self)
	combat.character = self
	hit_response.character = self

	# connect punch input to self
	_connect_punch_input()

	# connect hurtbox to hit response controller
	if hurtbox and hurtbox.has_signal("hit_received") and hit_response:
		hurtbox.connect("hit_received", Callable(hit_response, "on_hit_received"))

func _connect_punch_input() -> void:
	var router := PunchInput
	if router:
		if not router.is_connected("punched", Callable(self, "_on_punched")):
			router.connect("punched", Callable(self, "_on_punched"))
	else:
		if debug_enabled:
			_dbg("[BC] PunchInput autoload not found at /root/PunchInput")

func _physics_process(delta):
	match state:
		State.HIT_RESPONSE:
			hit_response.process(delta)
		State.ATTACKING:
			combat.process(delta)
		State.AUTO_MOVE:
			auto_move.process(delta)
		State.IDLE:
			# Idle logic
			pass
		State.KO:
			# KO logic
			pass

	move_and_slide()



# When Punch Received, Forward to Controller
func _on_punched(source_id: int, force: float) -> void:
	_dbg("[Punch] src=" + str(source_id) + " force=" + str(force))
	if not round_active: return
	if input_source_id != 0 and source_id != input_source_id: return
	if state == State.KO: return
	if combat:
		combat.handle_punch(source_id, force)



## ---- MOVEMENT PUBLIC FUNCTIONS -----
# Move in a direction (local or world), with a speed scale (0..1), and pose/stance
func move_direction(local_dir: Vector2, speed_scale: float = 1.0, fighting_pose: bool = true) -> void:
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var move_vec: Vector3 = (forward * local_dir.y) + (right * local_dir.x)
	if move_vec.length() > 1.0:
		move_vec = move_vec.normalized()
	var speed = walk_speed * clamp(speed_scale, 0.0, 1.0)
	velocity.x = move_vec.x * speed
	velocity.z = move_vec.z * speed
	if animator and animator.has_method("update_locomotion"):
		animator.update_locomotion(local_dir, speed * move_vec.length())
	if fighting_pose and animator and animator.has_method("start_fight_stance"):
		animator.start_fight_stance()
	elif not fighting_pose and animator and animator.has_method("end_fight_stance"):
		animator.end_fight_stance()

# Move toward a world point, with speed scale and pose
func move_towards_point(target: Vector3, speed_scale: float = 1.0, fighting_pose: bool = true) -> void:
	var to_target = target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		var dir = to_target.normalized()
		var local_dir = _world_dir_to_local_move(dir)
		move_direction(local_dir, speed_scale, fighting_pose)
	else:
		stop_movement()

# Strafe around a point (positive x = right, negative x = left), with speed scale and pose
func strafe_around_point(target: Vector3, strafe_dir: float, speed_scale: float = 1.0, fighting_pose: bool = true) -> void:
	var to_target = target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		var forward = to_target.normalized()
		var right = Vector3.UP.cross(forward).normalized()
		var strafe_vec = right * strafe_dir
		var local_dir = _world_dir_to_local_move(strafe_vec)
		move_direction(local_dir, speed_scale, fighting_pose)
	else:
		stop_movement()

# Stop all movement
func stop_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if animator and animator.has_method("update_locomotion"):
		animator.update_locomotion(Vector2.ZERO, 0.0)


## --- Targeting Functions
func set_target(t: Variant, mode: int = TargetMode.FIGHT) -> void:
	target_node = t if t is Node3D else null
	has_target = target_node != null
	target_mode = mode

func set_move_target(t: Variant) -> void:
	set_target(t, TargetMode.MOVE)

func set_fight_target(t: Variant) -> void:
	set_target(t, TargetMode.FIGHT)

func clear_target() -> void:
	target_node = null
	has_target = false
	target_mode = TargetMode.NONE


# Helper: convert world direction to local move intent
func _world_dir_to_local_move(dir: Vector3) -> Vector2:
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var local_x = right.normalized().dot(dir)
	var local_y = forward.normalized().dot(dir)
	return Vector2(local_x, local_y)


func _dbg(msg: String) -> void:
	if debug_enabled: print("[base_character.gd] " + msg)
