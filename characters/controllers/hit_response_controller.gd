extends Node
class_name HitResponseController

var character: BaseCharacter = null

var _stagger_until: float = 0.0
var _knockback_until: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _prev_state: int = BaseCharacter.State.IDLE

var debug: bool = false

# Mash-out logic
var _mash_count: int = 0
var mash_threshold: int = 5 # Number of punches to break out

func _ready() -> void:
	if character == null:
		push_warning("HitResponseController: No character assigned!")
		return
	if character.hurtbox and character.hurtbox.has_signal("hit_received"):
		character.hurtbox.connect("hit_received", Callable(self, "on_hit_received"))
		if debug:
			print("[HitResponseController] Connected to hit_received signal.")

func on_hit_received(attacker, spec, impact_force) -> void:
	if character == null:
		return
	if debug:
		print("[HitResponseController] on_hit_received: attacker=%s, force=%.2f, spec=%s" % [str(attacker), impact_force, str(spec)])

	# --- Determine stagger duration ---
	var stagger_sec: float = 0.2
	if spec and spec.stagger_sec != null:
		stagger_sec = float(spec.stagger_sec)
	_stagger_until = _now() + stagger_sec

	# --- Animation selection ---
	var anim_type: String = ""
	var knockback_v: float = 0.0
	var knockback_dur: float = 0.0
	if spec:
		knockback_v = float(spec.knockback_velocity) if spec.knockback_velocity != null else 0.0
		knockback_dur = float(spec.knockback_duration) if spec.knockback_duration != null else 0.0
	if (knockback_v * knockback_dur) > 1.25:
		anim_type = "uppercut"
	elif impact_force < 1000.0:
		anim_type = "head"
	elif impact_force < 2000.0:
		anim_type = "side"
	else:
		anim_type = "body"

	# --- Play hit animation ---
	if character.animator and character.animator.has_method("play_hit"):
		character.animator.play_hit(anim_type)
		if debug:
			print("[HitResponseController] Played hit animation: %s" % anim_type)

	# --- Store previous state and set HIT_RESPONSE ---
	_prev_state = character.state
	character.state = BaseCharacter.State.HIT_RESPONSE

	# --- Apply knockback if present ---
	if knockback_v > 0.0 and attacker is Node3D and character is Node3D:
		var dir: Vector3 = (character.global_transform.origin - attacker.global_transform.origin)
		dir.y = 0.0
		dir = dir.normalized()
		_knockback_velocity = dir * knockback_v
		_knockback_until = _now() + knockback_dur
		if debug:
			print("[HitResponseController] Applied knockback: velocity=%.2f, dur=%.2f, dir=%s" % [knockback_v, knockback_dur, str(dir)])
	else:
		_knockback_velocity = Vector3.ZERO
		_knockback_until = 0.0

	# Apply damage via stats
	if character.stats and spec and spec.damage:
		character.stats.take_damage(int(spec.damage))

	# Reset mash count on new hit
	_mash_count = 0

func handle_punch(source_id: int, force: float) -> void:
	# Called by BaseCharacter when a punch is received during HIT_RESPONSE
	_mash_count += 1
	if debug:
		print("[HitResponseController] handle_punch: mash_count=%d" % _mash_count)
	if _mash_count >= mash_threshold:
		# Allow break out: go to ATTACKING state
		character.state = BaseCharacter.State.ATTACKING
		if debug:
			print("[HitResponseController] Mash threshold reached! Breaking out to ATTACKING.")
		# Optionally reset hit response timers
		_knockback_velocity = Vector3.ZERO
		_knockback_until = 0.0
		_stagger_until = 0.0
		_mash_count = 0

func process(delta: float) -> void:
	# If broken out, do nothing
	if character.state != BaseCharacter.State.HIT_RESPONSE:
		return

	var now = _now()

	# Handle knockback if active
	if now < _knockback_until:
		# Apply knockback velocity
		character.velocity.x = _knockback_velocity.x
		character.velocity.z = _knockback_velocity.z
	elif now < _stagger_until:
		# Stop movement, still staggered
		character.stop_movement()
	else:
		# End of hit response, return to previous state
		_knockback_velocity = Vector3.ZERO
		_knockback_until = 0.0
		_stagger_until = 0.0
		if _prev_state and _prev_state != BaseCharacter.State.HIT_RESPONSE:
			character.state = _prev_state
		else:
			character.state = BaseCharacter.State.AUTO_MOVE

		_mash_count = 0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
