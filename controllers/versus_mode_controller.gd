extends GameControllerBase
class_name VersusModeController

@export var boxer_library: BoxerLibrary = preload("res://data/BoxerLibrary.tres")
@export var attack_set_library: AttackSetLibrary = preload("res://data/AttackSetLibrary.tres")
@export var attack_library_default: AttackLibrary = preload("res://data/AttackLibrary.tres")

# Fallback spawn configuration when no spawn markers are found
@export var fallback_spawn_center: Vector3 = Vector3(0, 5, 0)
@export var fallback_spawn_radius: float = 2.5

# If your model's visual forward isn't -Z, add a yaw offset here (degrees).
@export var spawn_yaw_offset_degrees: float = 0.0

# Target pairing controls (legacy)
@export var auto_pair_targets_on_ready := false
@export var auto_pair_delay_sec := 0.0

# HUD integration
@export_group("HUD")
@export var fight_hud_scene: PackedScene = preload("res://gui/fight_hud.tscn")
@export var use_countdown: bool = true
@export_range(1, 10, 1) var countdown_seconds: int = 5
@export var winner_countdown: float = 8.0

var _players_param: Array[Dictionary] = []
var _map_id: StringName = &""
var _map_instance: Node3D = null
var _spawned: Array[BaseCharacter] = []

var _hud: Node = null     # FightHUD instance (CanvasLayer). We call by method-name to avoid hard type deps.


func _init() -> void:
	requires_map_ready = true

func on_enter(params: Dictionary) -> void:
	_players_param = params.get("players", []) as Array[Dictionary]
	_map_id = params.get("map_id", StringName(""))
	print("[VersusMode] on_enter: players=", str(_players_param.size()), " map_id=", String(_map_id))
	if String(_map_id) == "":
		push_warning("[VersusMode] No map_id provided in params. Ensure Game.begin_local_controller received a map ref.")

func on_exit() -> void:
	print("[VersusMode] on_exit: cleaning up ", str(_spawned.size()), " spawned actors.")
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	_map_instance = null

	# Clean up HUD if we created it
	if _hud and is_instance_valid(_hud):
		print("[VersusMode][HUD] Freeing HUD instance")
		_hud.queue_free()
	_hud = null

func on_map_ready(map_instance: Node3D) -> void:
	_map_instance = map_instance
	print("[VersusMode] on_map_ready: map_instance=", str(_map_instance))
	if not _map_instance:
		push_error("[VersusMode] on_map_ready called with null map instance.")
		return

	print("[VersusMode] Spawning players...")
	_spawn_players_from_boxer_data()
	_setup_cameras()

	# Freeze fighters until "FIGHT!" (prevents early movement/attacks)
	_set_round_active_for_all(false)

	# HUD + Countdown flow (preferred if a FightHUD scene is provided)
	var did_countdown := false
	if fight_hud_scene:
		print("[VersusMode][HUD] fight_hud_scene is assigned, ensuring HUD...")
		var hud := _ensure_hud()
		if hud:
			print("[VersusMode][HUD] HUD instance ready: ", hud.name, " (", hud.get_class(), ")")
			# Provide spawned players to HUD (for names/health bars)
			if hud.has_method("bind_players"):
				print("[VersusMode][HUD] Calling bind_players() with ", str(_spawned.size()), " players")
				hud.bind_players(_spawned)
			else:
				print("[VersusMode][HUD][WARN] HUD missing bind_players()")
			# Optional countdown gating start
			if use_countdown:
				if hud.has_method("show_countdown"):
					print("[VersusMode][HUD] Starting countdown for ", str(countdown_seconds), " seconds...")
					did_countdown = true
					await hud.show_countdown(countdown_seconds)
					print("[VersusMode][HUD] Countdown finished")
				else:
					print("[VersusMode][HUD][WARN] HUD missing show_countdown(), skipping countdown")
			else:
				print("[VersusMode][HUD] use_countdown=false, skipping countdown")
		else:
			print("[VersusMode][HUD][ERROR] _ensure_hud() returned null")
	else:
		print("[VersusMode][HUD] No fight_hud_scene assigned, skipping HUD")

	# Start targeting and then unfreeze so they only move after "FIGHT!"
	if did_countdown:
		print("[VersusMode] Requesting fighters to auto-target after countdown...")
		_request_fighters_find_targets() # mark targets first
		_set_round_active_for_all(true)   # then allow movement/combat
	else:
		if auto_pair_targets_on_ready:
			if auto_pair_delay_sec > 0.0:
				print("[VersusMode] Auto pair delay: ", str(auto_pair_delay_sec), "s")
				await get_tree().create_timer(auto_pair_delay_sec).timeout
			print("[VersusMode] Legacy auto pairing due to flags...")
			_pair_targets()                 # mark targets first
			_set_round_active_for_all(true) # then allow movement/combat
		else:
			print("[VersusMode] Requesting fighters to auto-target (no countdown)...")
			_request_fighters_find_targets()
			_set_round_active_for_all(true)

# Public entry if you want to trigger countdown + start from outside (e.g., after a custom intro)
func start_round() -> void:
	print("[VersusMode] start_round() invoked")
	_set_round_active_for_all(false) # freeze before new round gate
	if fight_hud_scene and _hud and is_instance_valid(_hud) and use_countdown and _hud.has_method("show_countdown"):
		print("[VersusMode][HUD] Starting countdown from start_round(): ", str(countdown_seconds))
		await _hud.show_countdown(countdown_seconds)
		print("[VersusMode][HUD] Countdown finished (start_round)")
	print("[VersusMode] Requesting fighters to auto-target (start_round)")
	_request_fighters_find_targets()
	_set_round_active_for_all(true)

# -------------------------------------------------------
# HUD helpers
# -------------------------------------------------------
func _ensure_hud() -> Node:
	if _hud and is_instance_valid(_hud):
		print("[VersusMode][HUD] Reusing existing HUD")
		return _hud
	if not fight_hud_scene:
		print("[VersusMode][HUD][ERROR] fight_hud_scene not set")
		return null
	_hud = fight_hud_scene.instantiate()
	if _hud == null:
		print("[VersusMode][HUD][ERROR] Instantiation failed")
		return null
	var parent: Node = _map_instance if _map_instance else self
	parent.add_child(_hud)
	print("[VersusMode][HUD] Added HUD to parent: ", parent.name)
	return _hud

# -------------------------------------------------------
# Fighter targeting
# -------------------------------------------------------
func _request_fighters_find_targets() -> void:
	var supported := 0
	for c in _spawned:
		if c and c.has_method("request_auto_target"):
			c.request_auto_target()
			supported += 1
		elif c:
			print("[VersusMode][WARN] ", c.name, " has no request_auto_target(), skipping.")
	if supported == 0:
		print("[VersusMode][WARN] No fighters support auto-targeting; falling back to pairing.")
		_pair_targets()
	else:
		print("[VersusMode] Auto-target requested for ", str(supported), " fighters.")

func _set_round_active_for_all(active: bool) -> void:
	for c in _spawned:
		if c == null:
			continue
		if c.has_method("set_round_active"):
			c.set_round_active(active)
		else:
			# Property fallback
			var plist := c.get_property_list()
			for prop in plist:
				if prop.has("name") and String(prop["name"]) == "round_active":
					c.set("round_active", active)
					break
	print("[VersusMode] round_active = ", str(active), " for ", str(_spawned.size()), " fighters")

# Keep this around for legacy fallback or debug
func _enable_auto_face_target(enabled: bool) -> void:
	for c in _spawned:
		if c == null:
			continue
		if c.has_method("set_auto_face_target_enabled"):
			c.set_auto_face_target_enabled(enabled)
			print("[VersusMode] auto_face_target via method for ", c.name, " = ", str(enabled))
		elif _has_property(c, &"auto_face_target"):
			c.set("auto_face_target", enabled)
			print("[VersusMode] auto_face_target via property for ", c.name, " = ", str(enabled))
		else:
			print("[VersusMode][WARN] ", c.name, " has no auto-face API (method or property). Skipping.")

# Helper: check if an object exposes a property by name
func _has_property(obj: Object, prop: StringName) -> bool:
	var plist := obj.get_property_list()
	for p in plist:
		if p.has("name") and StringName(p["name"]) == prop:
			return true
	return false

# Optional: add more debug to pairing so you can see assignments clearly
func _pair_targets() -> void:
	if _spawned.is_empty():
		print("[VersusMode] _pair_targets(): no actors to pair")
		return
	if _spawned.size() == 2:
		_spawned[0].set_fight_target(_spawned[1])
		_spawned[1].set_fight_target(_spawned[0])
		print("[VersusMode] Paired 2 players: ",
			_spawned[0].name, " <-> ", _spawned[1].name)
		return
	for i in _spawned.size():
		var me := _spawned[i]
		var other := _spawned[(i + 1) % _spawned.size()]
		me.set_fight_target(other)
		print("[VersusMode] Pair: ", me.name, " -> ", other.name)
	print("[VersusMode] Paired ", str(_spawned.size()), " players in a ring.")

# -------------------------------------------------------
# Spawning and setup
# -------------------------------------------------------
func _spawn_players_from_boxer_data() -> void:
	_spawned.clear()
	if not _map_instance:
		push_warning("[VersusMode] No map instance; cannot spawn players.")
		return
	if not boxer_library:
		push_warning("[VersusMode] boxer_library not assigned; cannot resolve boxer scenes.")
		return

	var spawns := _collect_spawn_points(_map_instance)
	if spawns.is_empty():
		print("[VersusMode] No spawn markers found; using fallback center ", str(fallback_spawn_center), " radius ", str(fallback_spawn_radius))
	else:
		print("[VersusMode] Found ", str(spawns.size()), " spawn markers. Spawning ", str(_players_param.size()), " players.")

	for i in _players_param.size():
		var p: Dictionary = _players_param[i]
		var char_id: StringName = p.get("character_id", StringName(""))
		var src_id = p.get("source_id", i)
		print("[VersusMode] Spawning player index=", str(i), " source_id=", str(src_id), " character_id=", String(char_id))

		if String(char_id) == "":
			push_warning("[VersusMode] Player " + str(i) + " missing character_id; skipping spawn.")
			continue

		var boxer := _lookup_boxer_data(char_id)
		if boxer == null or boxer.scene == null:
			push_warning("[VersusMode] Invalid BoxerData or scene for id=" + String(char_id))
			continue

		var boxer_instance := boxer.scene.instantiate()
		if boxer_instance == null:
			push_warning("[VersusMode] Failed to instance boxer scene for " + String(char_id))
			continue

		# Find the BaseCharacter node (prefer the actual actor so we don't fight a rotated parent)
		var actor: BaseCharacter = null
		if boxer_instance is BaseCharacter:
			actor = boxer_instance as BaseCharacter
		elif boxer_instance is CharacterBody3D:
			actor = boxer_instance as BaseCharacter
		else:
			actor = boxer_instance.get_tree().get_first_node_in_group("base_character") as BaseCharacter
			if actor == null:
				for n in boxer_instance.get_children():
					if n is CharacterBody3D:
						actor = n as BaseCharacter
						break

		_map_instance.add_child(boxer_instance)

		# Position first, then orient using look_at (Y flattened). Ignore marker rotation entirely.
		var pose := _get_spawn_pose(i, spawns, _players_param.size())
		if actor and actor is Node3D:
			_apply_spawn_pose(actor as Node3D, pose.origin, pose.facing)
		elif boxer_instance is Node3D:
			_apply_spawn_pose(boxer_instance as Node3D, pose.origin, pose.facing)
		else:
			push_warning("[VersusMode] Spawned node is not Node3D; cannot apply spawn pose.")

		# Configure actor
		if actor:
			_apply_attack_selection(actor, p)
			_apply_player_color(boxer_instance, p.get("color", Color.WHITE))
			actor.name = "Player_" + str(src_id)

			# Optional: set input source id on the character if it exposes it
			if actor.has_method("set_input_source_id"):
				actor.set_input_source_id(int(src_id))
			else:
				var plist := actor.get_property_list()
				for prop in plist:
					if prop.has("name") and String(prop["name"]) == "input_source_id":
						actor.set("input_source_id", int(src_id))
						break

			_spawned.append(actor)
			if actor.has_signal("knocked_out"):
				actor.connect("knocked_out", Callable(self, "_on_fighter_knocked_out").bind(actor))
			print("[VersusMode] Spawned OK: ", actor.name, " at ", str(pose.origin))
		else:
			push_warning("[VersusMode] Could not find BaseCharacter in boxer scene for " + String(char_id))

	if _spawned.is_empty():
		push_warning("[VersusMode] No players spawned. Check boxer data and parameters.")
	else:
		print("[VersusMode] Total spawned actors: ", str(_spawned.size()))

func _on_fighter_knocked_out(actor: BaseCharacter) -> void:
	print("[VersusMode] Fighter knocked out: ", actor.name)
	_check_for_winner()

func _check_for_winner() -> void:
	var alive := []
	for c in _spawned:
		if c.state != c.State.KO:
			alive.append(c)
	if alive.size() == 1:
		var winner = alive[0]
		print("[VersusMode] WINNER: ", winner.name)
		_announce_winner_and_restart(winner)
	elif alive.size() == 0:
		print("[VersusMode] No fighters left! Draw?")
		_announce_winner_and_restart(null)

func _announce_winner_and_restart(winner: BaseCharacter) -> void:
	var winner_name = winner.name if winner else "No one"
	var winner_num = ""
	if winner and winner.name.begins_with("Player_"):
		winner_num = winner.name.substr(7)
	else:
		winner_num = winner_name

	# Show winner message on HUD if available
	if _hud and _hud.has_method("show_winner_banner"):
		_hud.show_winner_banner("Player %s Wins!" % winner_num, winner_countdown)
		await get_tree().create_timer(winner_countdown).timeout
	else:
		print("Player %s Wins!" % winner_num)
		await get_tree().create_timer(winner_countdown).timeout

	# Restart the game
	if Main and Main.instance and Main.instance.has_method("execute_command"):
		Main.instance.execute_command("restart")
	else:
		print("[VersusMode] Could not restart game: Main.instance missing or invalid.")

func _apply_attack_selection(actor: BaseCharacter, player_params: Dictionary) -> void:
	if attack_library_default and actor.attack_library == null:
		actor.attack_library = attack_library_default
		print("[VersusMode] Applied default AttackLibrary to ", actor.name)

	var set_id: StringName = player_params.get("attack_set_id", StringName(""))
	if String(set_id) == "":
		return
	if not attack_set_library:
		push_warning("[VersusMode] attack_set_library not assigned; cannot resolve attack set " + String(set_id))
		return

	var set_data := _lookup_attack_set_data(set_id)
	if set_data:
		if actor.has_method("set_attack_set_data"):
			actor.set_attack_set_data(set_data)
		else:
			actor.attack_set_data = set_data
		print("[VersusMode] Applied AttackSet '", String(set_id), "' to ", actor.name)
	else:
		push_warning("[VersusMode] AttackSet not found: " + String(set_id))

func _apply_player_color(root: Node, color: Color) -> void:
	if not root:
		return
	var mesh := (root as Node).find_child("TeamColor", true, false)
	if mesh and mesh is MeshInstance3D:
		var mi := mesh as MeshInstance3D
		if mi.material_override:
			var mat := mi.material_override.duplicate() as StandardMaterial3D
			if mat:
				mat.albedo_color = color
				mi.material_override = mat
				print("[VersusMode] Tinted TeamColor via material_override.")
		elif mi.get_surface_override_material_count() > 0:
			var mat2 := mi.get_surface_override_material(0)
			if mat2 and mat2 is StandardMaterial3D:
				var dup := (mat2 as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.albedo_color = color
				mi.set_surface_override_material(0, dup)
				print("[VersusMode] Tinted TeamColor via surface override.")

func _setup_cameras() -> void:
	var vp := get_viewport()
	if vp and vp.get_camera_3d():
		print("[VersusMode] Active camera already present: ", vp.get_camera_3d().name)
		return
	var map_cam := _find_camera_in_map()
	if map_cam:
		map_cam.current = true
		print("[VersusMode] Activated camera found in map: ", map_cam.name)
		return
	if game and game.has_method("ensure_free_camera"):
		print("[VersusMode] No camera found; requesting Game.ensure_free_camera()")
		game.ensure_free_camera()

func _find_camera_in_map() -> Camera3D:
	if not _map_instance:
		return null
	var stack: Array[Node] = [_map_instance]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Camera3D:
			return n as Camera3D
		for c in n.get_children():
			stack.append(c)
	return null

# -------------------------------------------------------
# Spawn helpers
# -------------------------------------------------------
func _collect_spawn_points(map_root: Node3D) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for n in map_root.get_tree().get_nodes_in_group("spawn"):
		if n is Marker3D:
			out.append(n as Marker3D)
	if out.is_empty():
		for n in map_root.get_children():
			_collect_marker3d_rec(n, out)
	out.sort_custom(func(a: Marker3D, b: Marker3D) -> bool:
		var ai = a.get("index") if a.has_method("get") else null
		var bi = b.get("index") if b.has_method("get") else null
		if ai is int and bi is int:
			return int(ai) < int(bi)
		return String(a.name) < String(b.name)
	)
	if out.is_empty():
		print("[VersusMode] No spawn markers found; will use fallback center.")
	else:
		print("[VersusMode] Using ", str(out.size()), " spawn markers (sorted).")
	return out

func _collect_marker3d_rec(n: Node, into: Array[Marker3D]) -> void:
	if n is Marker3D and String(n.name).to_lower().begins_with("spawn"):
		into.append(n as Marker3D)
	for c in n.get_children():
		_collect_marker3d_rec(c, into)

# Position and facing, ignoring marker rotation entirely
func _get_spawn_pose(i: int, spawns: Array[Marker3D], total_players: int) -> Dictionary:
	var origin := Vector3.ZERO
	var facing := -Vector3.FORWARD

	if i < spawns.size():
		var m := spawns[i]
		origin = m.global_transform.origin
		# Face toward world center from the marker position (flattened)
		facing = Vector3(-origin.x, 0.0, -origin.z)
	else:
		var center := fallback_spawn_center
		var radius := fallback_spawn_radius
		if total_players == 2:
			var angle := 0.0 if i == 0 else PI
			var offset := Vector3(radius * cos(angle), 0.0, radius * sin(angle))
			origin = center + offset
			facing = Vector3(center.x - origin.x, 0.0, center.z - origin.z)
		else:
			var ang = TAU * float(i) / max(1.0, float(total_players))
			var offset2 := Vector3(radius * cos(ang), 0.0, radius * sin(ang))
			origin = center + offset2
			facing = Vector3(center.x - origin.x, 0.0, center.z - origin.z)

	if facing.length_squared() < 0.000001:
		facing = -Vector3.FORWARD

	return { "origin": origin, "facing": facing }

# Apply spawn pose: set position, then look_at with Y flattened to avoid pitch
func _apply_spawn_pose(target_node: Node3D, origin: Vector3, facing: Vector3) -> void:
	target_node.global_position = origin
	var flat_dir := facing
	flat_dir.y = 0.0
	if flat_dir.length_squared() < 0.000001:
		flat_dir = -Vector3.FORWARD
	else:
		flat_dir = flat_dir.normalized()
	target_node.look_at(origin + flat_dir, Vector3.UP)
	if absf(spawn_yaw_offset_degrees) > 0.001:
		target_node.rotate_y(deg_to_rad(spawn_yaw_offset_degrees))

# -------------------------------------------------------
# Lookups
# -------------------------------------------------------
func _lookup_boxer_data(id: StringName) -> BoxerData:
	if not boxer_library:
		return null
	if boxer_library.has_method("get_boxer"):
		var data := boxer_library.get_boxer(id)
		if data:
			print("[VersusMode] Resolved BoxerData for id=", String(id))
		return data
	if boxer_library.has_method("all"):
		for b in boxer_library.all():
			if b is BoxerData and (b as BoxerData).id == id:
				print("[VersusMode] Resolved BoxerData via scan for id=", String(id))
				return b as BoxerData
	return null

func _lookup_attack_set_data(id: StringName) -> AttackSetData:
	if not attack_set_library:
		return null
	if attack_set_library.has_method("get_set"):
		var data := attack_set_library.get_set(id)
		if data:
			print("[VersusMode] Resolved AttackSetData for id=", String(id))
		return data
	if attack_set_library.has_method("all"):
		for s in attack_set_library.all():
			if s is AttackSetData and (s as AttackSetData).id == id:
				print("[VersusMode] Resolved AttackSetData via scan for id=", String(id))
				return s as AttackSetData
	return null
