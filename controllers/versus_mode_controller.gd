extends GameControllerBase
class_name VersusModeController

@export var boxer_library: BoxerLibrary
@export var attack_set_library: AttackSetLibrary
# Optional default AttackLibrary for spawned characters
@export var attack_library_default: AttackLibrary

var _players_param: Array[Dictionary] = []   # [{ source_id, color, character_id, attack_set_id }, ...]
var _map_id: StringName = &""
var _map_instance: Node3D = null
var _spawned: Array[BaseCharacter] = []

func _init() -> void:
	# Versus gameplay needs the map to be ready before setup
	requires_map_ready = true

func on_enter(params: Dictionary) -> void:
	# Read the selections compiled by PreFightController
	_players_param = params.get("players", []) as Array[Dictionary]
	_map_id = params.get("map_id", StringName(""))
	if String(_map_id) == "":
		push_warning("[VersusMode] No map_id provided in params. Ensure Game.begin_local_controller received a map ref.")

	# Do NOT load maps here; Game/MapManager owns that and the overlay

func on_exit() -> void:
	# Clean up only your own spawned gameplay nodes. Game owns the map lifecycle.
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	_map_instance = null

func on_map_ready(map_instance: Node3D) -> void:
	# Called by Game once the map is in the scene and ready.
	_map_instance = map_instance
	if not _map_instance:
		push_error("[VersusMode] on_map_ready called with null map instance.")
		return

	_spawn_players_from_boxer_data()
	_pair_targets()
	_setup_cameras()

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

	for i in _players_param.size():
		var p: Dictionary = _players_param[i]
		var char_id: StringName = p.get("character_id", StringName(""))
		if String(char_id) == "":
			push_warning("[VersusMode] Player " + str(i) + " missing character_id; skipping spawn.")
			continue

		var boxer := _lookup_boxer_data(char_id)
		if boxer == null or boxer.scene == null:
			push_warning("[VersusMode] No BoxerData or scene for id=" + String(char_id))
			continue

		var boxer_instance := boxer.scene.instantiate()
		if boxer_instance == null:
			push_warning("[VersusMode] Failed to instance boxer scene for " + String(char_id))
			continue

		# Try to find the BaseCharacter node: root or a CharacterBody3D within
		var actor: BaseCharacter = null
		if boxer_instance is BaseCharacter:
			actor = boxer_instance as BaseCharacter
		elif boxer_instance is CharacterBody3D:
			actor = boxer_instance as BaseCharacter
		else:
			actor = boxer_instance.get_node_or_null(".") as BaseCharacter
			if actor == null:
				actor = boxer_instance.get_tree().get_first_node_in_group("base_character") as BaseCharacter
			if actor == null:
				for n in boxer_instance.get_children():
					if n is CharacterBody3D:
						actor = n as BaseCharacter
						break

		# Parent the instance into the map
		_map_instance.add_child(boxer_instance)

		# Position and face direction
		var xform := _get_spawn_transform(i, spawns, _players_param.size())
		if boxer_instance is Node3D:
			(boxer_instance as Node3D).global_transform = xform
		elif actor:
			actor.global_transform = xform

		# Configure actor (attack set, library, cosmetics) if found
		if actor:
			_apply_attack_selection(actor, p)
			_apply_player_color(boxer_instance, p.get("color", Color.WHITE))
			actor.name = "Player_" + str(p.get("source_id", i))
			_spawned.append(actor)
		else:
			push_warning("[VersusMode] Could not find BaseCharacter in boxer scene for " + String(char_id))

func _apply_attack_selection(actor: BaseCharacter, player_params: Dictionary) -> void:
	# AttackLibrary default (if actor didn't already get one from scene)
	if attack_library_default and actor.attack_library == null:
		actor.attack_library = attack_library_default

	# Set the chosen AttackSetData by id, if available
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

func _apply_player_color(root: Node, color: Color) -> void:
	# Optional cosmetic: find a MeshInstance3D named "TeamColor" or with a material override and tint it.
	if not root:
		return
	var mesh := (root as Node).find_child("TeamColor", true, false)
	if mesh and mesh is MeshInstance3D:
		var mi := mesh as MeshInstance3D
		# Try material override first
		if mi.material_override:
			var mat := mi.material_override.duplicate() as StandardMaterial3D
			if mat:
				mat.albedo_color = color
				mi.material_override = mat
		elif mi.get_surface_override_material_count() > 0:
			var mat2 := mi.get_surface_override_material(0)
			if mat2 and mat2 is StandardMaterial3D:
				var dup := (mat2 as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.albedo_color = color
				mi.set_surface_override_material(0, dup)

# Pair players for targeting
func _pair_targets() -> void:
	if _spawned.is_empty():
		return
	if _spawned.size() == 2:
		_spawned[0].set_fight_target(_spawned[1])
		_spawned[1].set_fight_target(_spawned[0])
		return
	for i in _spawned.size():
		var me := _spawned[i]
		var other := _spawned[(i + 1) % _spawned.size()]
		me.set_fight_target(other)

func _setup_cameras() -> void:
	# Ensure there is at least one camera in the scene.
	var cam := get_tree().get_first_node_in_group("game_camera")
	if cam == null and game and game.has_method("ensure_free_camera"):
		game.ensure_free_camera()

# -------------------------------------------------------
# Spawn helpers
# -------------------------------------------------------
func _collect_spawn_points(map_root: Node3D) -> Array[Marker3D]:
	var out: Array[Marker3D] = []

	# Preferred: nodes with SpawnPoint script (auto in "spawn" group)
	for n in map_root.get_tree().get_nodes_in_group("spawn"):
		if n is Marker3D:
			out.append(n as Marker3D)

	# If none found, accept any Marker3D named like "Spawn" underneath
	if out.is_empty():
		for n in map_root.get_children():
			_collect_marker3d_rec(n, out)

	# Sort by index if they have a property "index", else by name
	out.sort_custom(func(a: Marker3D, b: Marker3D) -> bool:
		var ai = a.get("index") if a.has_method("get") else null
		var bi = b.get("index") if b.has_method("get") else null
		if ai is int and bi is int:
			return int(ai) < int(bi)
		return String(a.name) < String(b.name)
	)

	return out

func _collect_marker3d_rec(n: Node, into: Array[Marker3D]) -> void:
	if n is Marker3D and String(n.name).to_lower().begins_with("spawn"):
		into.append(n as Marker3D)
	for c in n.get_children():
		_collect_marker3d_rec(c, into)

func _get_spawn_transform(i: int, spawns: Array[Marker3D], total_players: int) -> Transform3D:
	# Use explicit spawn marker if available
	if i < spawns.size():
		var m := spawns[i]
		var origin := m.global_transform.origin
		# Face toward arena center (0,0,0) as a sane default
		var target := Vector3.ZERO
		var dir := (target - origin)
		if dir.length() < 0.001:
			dir = -Vector3.FORWARD
		else:
			dir = dir.normalized()
		var basis := Basis.looking_at(dir, Vector3.UP)
		return Transform3D(basis, origin)

	# Fallback: place players on a circle around origin
	var radius := 6.0
	if total_players == 2:
		# Two players opposite each other, facing each other
		var angle := 0.0 if i == 0 else PI
		var pos := Vector3(radius * cos(angle), 0.0, radius * sin(angle))
		var facing := -pos.normalized()
		var basis2 := Basis.looking_at(facing, Vector3.UP)
		return Transform3D(basis2, pos)
	else:
		# N players around a circle
		var ang = TAU * float(i) / max(1.0, float(total_players))
		var p := Vector3(radius * cos(ang), 0.0, radius * sin(ang))
		var f := -p.normalized()
		var b := Basis.looking_at(f, Vector3.UP)
		return Transform3D(b, p)

# -------------------------------------------------------
# Lookups
# -------------------------------------------------------
func _lookup_boxer_data(id: StringName) -> BoxerData:
	if not boxer_library:
		return null
	if boxer_library.has_method("get_boxer"):
		return boxer_library.get_boxer(id)
	if boxer_library.has_method("all"):
		for b in boxer_library.all():
			if b is BoxerData and (b as BoxerData).id == id:
				return b as BoxerData
	return null

func _lookup_attack_set_data(id: StringName) -> AttackSetData:
	if not attack_set_library:
		return null
	if attack_set_library.has_method("get_set"):
		return attack_set_library.get_set(id)
	if attack_set_library.has_method("all"):
		for s in attack_set_library.all():
			if s is AttackSetData and (s as AttackSetData).id == id:
				return s as AttackSetData
	return null
