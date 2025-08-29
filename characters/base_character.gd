extends CharacterBody3D
class_name BaseCharacter

signal chase_success
signal chase_failed
signal retreat_success
signal retreat_failed

enum State { IDLE, AUTO_MOVE, ATTACKING, HIT_RESPONSE, KO }
enum TargetMode { NONE, MOVE, FIGHT }

# --- Shared Character Movement Settings ---
@export var walk_speed: float = 5.0
@export var turn_speed_deg: float = 180.0 # Degrees per second for facing target

# --- Chase/Retreat Variables ---
var chasing: bool = false
var retreating: bool = false
var _chase_enter_distance := 1.0
var _chase_timeout := 1.0
var _chase_timer := 0.0
var _retreat_timeout: float = 1.0
var _retreat_timer: float = 0.0
var _retreat_target_position: Vector3 = Vector3.ZERO

# --- Shared Character State, Target and Movement Variables ---
var state: int = State.IDLE
var prev_state: int = State.IDLE
var auto_target_enabled: bool = false
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
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# --- Internal Variables ---
var debug_enabled: bool = false


var _attack_enter_distance := 1.0
var _attack_setup_timeout := 1.0
var _attack_setup_timer := 0.0
var _attack_setup_active := false

func _ready():
	_dbg("_ready: Assigning self to controllers")
	auto_move.setup(self)
	combat.setup(self)
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
	_dbg("_physics_process: state=%s" % str(state))
	match state:
		State.HIT_RESPONSE:
			pass
			#_dbg("_physics_process: HIT_RESPONSE, calling hit_response.process")
			#hit_response.process(delta)
		State.ATTACKING:
			_dbg("_physics_process: ATTACKING, calling combat.process")
			combat.process(delta)
		State.AUTO_MOVE:
			_dbg("_physics_process: AUTO_MOVE, calling auto_move.process")
			auto_move.process(delta)
			move_and_slide()
			return
		State.IDLE:
			_dbg("_physics_process: IDLE")
			pass
		State.KO:
			_dbg("_physics_process: KO")
			pass

	if chasing and target_node:
		_chase_timer += delta
		var to_target = target_node.global_position - global_position
		to_target.y = 0.0
		var dist = to_target.length()
		if dist > _chase_enter_distance:
			nav_agent.set_target_position(target_node.global_position)
			var next_path_pos = nav_agent.get_next_path_position()
			var direction = (next_path_pos - global_position).normalized()
			#nav_agent.velocity = direction * walk_speed
			velocity = direction * walk_speed
			_face_target(to_target, delta)
		else:
			stop_chase()
			emit_signal("chase_success")
		if _chase_timer >= _chase_timeout:
			stop_chase()
			emit_signal("chase_failed")

	if retreating:
		_retreat_timer += delta
		var to_retreat = _retreat_target_position - global_position
		to_retreat.y = 0.0
		var dist = to_retreat.length()
		if dist > 0.1:
			var direction = to_retreat.normalized()
			velocity = direction * walk_speed / 2
			_face_target(target_node.global_position - global_position, delta)
		else:
			stop_retreat()
			emit_signal("retreat_success")
		if _retreat_timer >= _retreat_timeout:
			stop_retreat()
			emit_signal("retreat_failed")

	if not chasing and not retreating:
		#nav_agent.velocity = Vector3.ZERO
		velocity = Vector3.ZERO

	# move and slide
	move_and_slide()
	update_locomotion_animation()


func update_locomotion_animation() -> void:
	# --- CORRECTED ANIMATION UPDATE ---
	if animator and animator.has_method("update_locomotion"):
		# Only calculate if the character is actually moving
		if velocity.length_squared() > 0.01:
			var move_direction = velocity.normalized()

			# Get the character's forward and right directions in the world
			var forward_dir = -global_transform.basis.z # Your local -Z forward vector
			var right_dir = global_transform.basis.x   # Your local +X right vector

			# Calculate forward/backward amount (-1 to +1) using the dot product
			var forward_amount = move_direction.dot(forward_dir)

			# Calculate strafe left/right amount (-1 to +1)
			var strafe_amount = move_direction.dot(right_dir)

			# Pass these clean -1 to +1 values to the animator
			# This gives you exactly what you wanted:
			# X: Strafe value (-1 for left, +1 for right)
			# Y: Locomotion value (-1 for backward, +1 for forward)
			animator.update_locomotion(Vector2(strafe_amount, forward_amount), velocity.length())
		else:
			# Not moving, send zero values
			animator.update_locomotion(Vector2.ZERO, 0.0)

func start_chase(enter_distance: float, timeout: float):
	_chase_enter_distance = enter_distance
	_chase_timeout = timeout
	_chase_timer = 0.0
	chasing = true

func stop_chase():
	chasing = false
	nav_agent.set_velocity(Vector3.ZERO)

func start_retreat(distance: float, timeout: float):
	_retreat_timeout = timeout
	_retreat_timer = 0.0
	retreating = true
	# Calculate retreat point ONCE
	var to_target = target_node.global_position - global_position
	to_target.y = 0.0
	var away_direction = -to_target.normalized()
	_retreat_target_position = global_position + away_direction * distance

func stop_retreat():
	retreating = false
	nav_agent.set_velocity(Vector3.ZERO)

func _face_target(to_target: Vector3, delta: float):
	if to_target.length() < 0.01:
		return
	var desired_yaw = atan2(-to_target.x, -to_target.z)
	var current_yaw = rotation.y
	var max_step = deg_to_rad(turn_speed_deg) * delta
	var diff = wrapf(desired_yaw - current_yaw, -PI, PI)
	if absf(diff) <= max_step:
		rotation.y = desired_yaw
	else:
		rotation.y = current_yaw + clampf(diff, -max_step, max_step)

# When Punch Received, Forward to Controller
func _on_punched(source_id: int, force: float) -> void:
	_dbg("[Punch] src=" + str(source_id) + " force=" + str(force))
	if not round_active:
		_dbg("_on_punched: round not active, ignoring punch")
		return
	if input_source_id != 0 and source_id != input_source_id:
		_dbg("_on_punched: input_source_id mismatch, ignoring punch")
		return
	if state == State.KO:
		_dbg("_on_punched: state is KO, ignoring punch")
		return
	if state == State.HIT_RESPONSE:
		_dbg("_on_punched: in HIT_RESPONSE, forwarding to hit_response.handle_punch")
		hit_response.handle_punch(source_id, force)
	else:
		if combat:
			_dbg("_on_punched: forwarding to combat.handle_punch")
			combat.handle_punch(source_id, force)
			# Only save prev_state if not already attacking
			if state != State.ATTACKING:
				prev_state = state
			state = State.ATTACKING
			_dbg("_on_punched: state set to ATTACKING")

func on_attack_finished():
	state = prev_state

## ---- MOVEMENT PUBLIC FUNCTIONS -----
# Move in a direction (local or world), with a speed scale (0..1), and pose/stance
func move_direction(local_dir: Vector2, speed_scale: float = 1.0, fighting_pose: bool = true) -> void:
	_dbg("move_direction: local_dir=%s, speed_scale=%.2f, fighting_pose=%s" % [str(local_dir), speed_scale, str(fighting_pose)])
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
	_dbg("move_towards_point: target=%s, speed_scale=%.2f, fighting_pose=%s" % [str(target), speed_scale, str(fighting_pose)])
	var to_target = target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		var dir = to_target.normalized()
		var local_dir = _world_dir_to_local_move(dir)
		move_direction(local_dir, speed_scale, fighting_pose)
	else:
		_dbg("move_towards_point: Already at target, stopping movement")
		stop_movement()

# Strafe around a point (positive x = right, negative x = left), with speed scale and pose
func strafe_around_point(target: Vector3, strafe_dir: float, speed_scale: float = 1.0, fighting_pose: bool = true) -> void:
	_dbg("strafe_around_point: target=%s, strafe_dir=%.2f, speed_scale=%.2f, fighting_pose=%s" % [str(target), strafe_dir, speed_scale, str(fighting_pose)])
	var to_target = target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		var forward = to_target.normalized()
		var right = Vector3.UP.cross(forward).normalized()
		var strafe_vec = right * strafe_dir
		var local_dir = _world_dir_to_local_move(strafe_vec)
		move_direction(local_dir, speed_scale, fighting_pose)
	else:
		_dbg("strafe_around_point: Already at target, stopping movement")
		stop_movement()

# Stop all movement
func stop_movement() -> void:
	print("Stop Movement")
	_dbg("stop_movement: velocity set to zero")
	velocity.x = 0.0
	velocity.z = 0.0
	if animator and animator.has_method("update_locomotion"):
		animator.update_locomotion(Vector2.ZERO, 0.0)


## --- Nav Agent Functions
func move_to_point(target_pos: Vector3):
	nav_agent.set_target_position(target_pos)

func stop_nav_agent():
	if nav_agent:
		nav_agent.set_target_position(global_transform.origin)
		nav_agent.velocity = Vector3.ZERO

## --- Targeting Functions
func set_target(t: Variant, mode: int = TargetMode.FIGHT) -> void:
	_dbg("set_target: t=%s, mode=%s" % [str(t), str(mode)])
	target_node = t if t is Node3D else null
	has_target = target_node != null
	target_mode = mode

func set_move_target(t: Variant) -> void:
	_dbg("set_move_target: t=%s" % str(t))
	set_target(t, TargetMode.MOVE)
	state = State.AUTO_MOVE
	_dbg("set_move_target: state set to AUTO_MOVE")

func set_fight_target(t: Variant) -> void:
	_dbg("set_fight_target: t=%s" % str(t))
	set_target(t, TargetMode.FIGHT)
	state = State.AUTO_MOVE
	_dbg("set_fight_target: state set to AUTO_MOVE")

func clear_target() -> void:
	_dbg("clear_target: clearing target_node and has_target")
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


func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()


func _on_navigation_agent_3d_navigation_finished() -> void:
	pass
	#print("Finished")
