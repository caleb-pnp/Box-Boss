extends GameControllerBase
class_name PreFightController

@export var char_select_sec: float = 5
@export var set_select_sec: float = 5
@export var mode_select_sec: float = 5
@export var map_select_sec: float = 5
@export var summary_sec: float = 1

@export var boxer_library: BoxerLibrary = preload("res://data/BoxerLibrary.tres")
@export var attack_set_library: AttackSetLibrary = preload("res://data/AttackSetLibrary.tres")
@export var mode_library: ModeLibrary = preload("res://data/ModeLibrary.tres")
@export var map_library: MapLibrary = preload("res://data/MapLibrary.tres")

@export var view_scene: PackedScene = preload("res://gui/character_select.tscn")

enum Phase { CHARACTER, ATTACK_SET, MODE, MAP, SUMMARY, DONE }
var _phase: int = Phase.CHARACTER
var _time_left: float = 0.0
var _router: PunchInputRouter
var _view: PrefightView

# Prevent new players from joining after character select
var _roster_locked: bool = false

const PLAYER_COLORS: Array[Color] = [
	Color(0.95, 0.25, 0.25),
	Color(0.25, 0.6, 0.95),
	Color(0.35, 0.85, 0.4),
	Color(0.95, 0.8, 0.3),
]

class PlayerSel:
	var source_id: int
	var color: Color
	var character_id: StringName
	var attack_set_id: StringName
	func _init(src: int, col: Color) -> void:
		source_id = src
		color = col
		character_id = &""
		attack_set_id = &""

var _players_by_source: Dictionary = {}
var _players: Array[PlayerSel] = []

# Per-phase cached id lists (for cycling)
var _boxer_ids: Array[StringName] = []
var _attack_set_ids: Array[StringName] = []
var _map_ids: Array[StringName] = []

# Mode selection (per-player picks and final choice)
var _mode_choice_by_source: Dictionary = {} # source_id -> StringName (mode id)
var _chosen_mode: StringName = &""

# Map selection (per-player picks and final choice)
var _map_choice_by_source: Dictionary = {} # source_id -> StringName (map id)
var _chosen_map_id: StringName = &""

# Last compiled params handed to the next controller (for debugging/telemetry)
var _last_start_params: Dictionary = {}

# Prevent multiple launches
var _did_launch: bool = false

func _init() -> void:
	requires_map_ready = false

func on_enter(_params: Dictionary) -> void:
	print("[PreFight] on_enter: resetting state. char=", char_select_sec, " set=", set_select_sec, " mode=", mode_select_sec, " map=", map_select_sec, " summary=", summary_sec)
	_phase = Phase.CHARACTER
	_time_left = char_select_sec
	_roster_locked = false
	_players_by_source.clear()
	_players.clear()
	_mode_choice_by_source.clear()
	_map_choice_by_source.clear()
	_last_start_params.clear()
	_did_launch = false

	# Snapshot ids from libraries for quick cycling
	_boxer_ids = boxer_library.ids() if boxer_library else []
	_attack_set_ids = attack_set_library.ids() if attack_set_library else []
	_map_ids = map_library.ids() if map_library else []

	print("[PreFight] Libraries snapshot: boxers=", _boxer_ids.size(), " sets=", _attack_set_ids.size(), " maps=", _map_ids.size())

	# Seed RNG
	randomize()

	# Initialize chosen mode/map to first available (if any)
	_chosen_mode = mode_library.ids()[0] if mode_library and not mode_library.ids().is_empty() else StringName("")
	_chosen_map_id = map_library.ids()[0] if map_library and not map_library.ids().is_empty() else StringName("")
	print("[PreFight] Initial defaults: chosen_mode=", String(_chosen_mode), " chosen_map_id=", String(_chosen_map_id))

	_router = PunchInput as PunchInputRouter
	if _router:
		if not _router.punched.is_connected(_on_punched):
			_router.punched.connect(_on_punched)
		print("[PreFight] Input router connected.")
	else:
		push_warning("[PreFight] PunchInputRouter not found; only countdown auto-advance will work.")

	_mount_view()
	if _view:
		if _view.is_node_ready():
			_init_view_ui()
		else:
			call_deferred("_init_view_ui")
	else:
		push_warning("[PreFight] View not mounted; UI feedback will be limited.")

func _init_view_ui() -> void:
	print("[PreFight] Initializing view UI. Has boxer_library=", boxer_library != null)
	if not _view:
		push_warning("[PreFight] _init_view_ui called without a view.")
		return
	if boxer_library:
		_view.set_roster_data(boxer_library.all())
	else:
		_view.set_roster(_boxer_ids)
	_view.set_phase("Character Select")
	_view.set_timer(int(ceil(_time_left)))
	_view.set_mode(String(_chosen_mode) if String(_chosen_mode) != "" else "Choose a mode")

func on_exit() -> void:
	print("[PreFight] on_exit: cleaning up view and input.")
	if _router and _router.punched.is_connected(_on_punched):
		_router.punched.disconnect(_on_punched)
	_unmount_view()

func on_map_ready(_map_instance: Node3D) -> void:
	# Not used (requires_map_ready=false)
	pass

func tick(delta: float) -> void:
	if _phase == Phase.DONE and _did_launch:
		return

	_time_left = max(0.0, _time_left - delta)
	if _view:
		_view.set_timer(int(ceil(_time_left)))
	if _time_left > 0.0:
		return

	# Time for a phase transition
	match _phase:
		Phase.CHARACTER:
			print("[PreFight] Phase CHARACTER complete. Locking roster and advancing to ATTACK_SET.")
			_roster_locked = true
			_phase = Phase.ATTACK_SET
			_time_left = set_select_sec
			if _view:
				_view.set_phase("Attack Set Select")
				if attack_set_library:
					_view.set_roster_data(attack_set_library.all())
				else:
					_view.set_roster(_attack_set_ids)
		Phase.ATTACK_SET:
			print("[PreFight] Phase ATTACK_SET complete. Advancing to MODE.")
			_phase = Phase.MODE
			_time_left = mode_select_sec
			_mode_choice_by_source.clear()
			if _view:
				_view.set_phase("Mode Select")
				if mode_library:
					_view.set_roster_data(mode_library.all())
				else:
					push_warning("[PreFight] ModeLibrary not assigned; cannot show modes.")
		Phase.MODE:
			print("[PreFight] Phase MODE complete. Finalizing mode selection and advancing to MAP.")
			_finalize_mode_choice()
			_phase = Phase.MAP
			_time_left = map_select_sec
			_map_choice_by_source.clear()
			if _view:
				_view.set_phase("Map Select")
				if map_library:
					_view.set_roster_data(map_library.all())
				else:
					push_warning("[PreFight] MapLibrary not assigned; cannot show maps.")
		Phase.MAP:
			print("[PreFight] Phase MAP complete. Finalizing map selection and entering SUMMARY.")
			_finalize_map_choice()
			_enter_summary_phase()
		Phase.SUMMARY:
			if _did_launch:
				print("[PreFight] SUMMARY reached zero but launch already triggered; ignoring.")
				return
			print("[PreFight] SUMMARY countdown complete. Launching next controller...")
			_phase = Phase.DONE
			_start_chosen_mode()
		_:
			print("[PreFight] tick() reached unexpected phase:", _phase)

func on_punch(_source_id: int, _force: float) -> void:
	pass

func _on_punched(source_id: int, _force: float) -> void:
	match _phase:
		Phase.CHARACTER:
			var sel := _ensure_player(source_id, true)
			if sel == null or _boxer_ids.is_empty():
				return
			var idx: int = (_boxer_ids.find(sel.character_id) if String(sel.character_id) != "" else -1)
			idx = (idx + 1) % _boxer_ids.size()
			sel.character_id = _boxer_ids[idx]
			print("[PreFight] P", source_id, " picked character=", String(sel.character_id))
			if _view:
				_view.ensure_player(source_id, sel.color)
				_view.set_player_character(source_id, String(sel.character_id))
		Phase.ATTACK_SET:
			if not _players_by_source.has(source_id) or _attack_set_ids.is_empty():
				return
			var sel2: PlayerSel = _players_by_source[source_id]
			var idx2: int = (_attack_set_ids.find(sel2.attack_set_id) if String(sel2.attack_set_id) != "" else -1)
			idx2 = (idx2 + 1) % _attack_set_ids.size()
			sel2.attack_set_id = _attack_set_ids[idx2]
			print("[PreFight] P", source_id, " picked set=", String(sel2.attack_set_id))
			if _view:
				_view.ensure_player(source_id, sel2.color)
				_view.set_player_set(source_id, String(sel2.attack_set_id))
		Phase.MODE:
			# Ignore new/unregistered players once roster is locked
			if not _players_by_source.has(source_id):
				print("[PreFight] Ignoring punch from unknown source ", source_id, " (roster locked).")
				return
			if not mode_library:
				push_warning("[PreFight] ModeLibrary not assigned; cannot pick modes.")
				return
			var ids := mode_library.ids()
			if ids.is_empty():
				push_warning("[PreFight] ModeLibrary has no modes.")
				return
			var current_id: StringName = _mode_choice_by_source.get(source_id, StringName(""))
			var idx3: int = (ids.find(current_id) if String(current_id) != "" else -1)
			idx3 = (idx3 + 1) % ids.size()
			var new_mode: StringName = ids[idx3]
			_mode_choice_by_source[source_id] = new_mode
			print("[PreFight] P", source_id, " cycling mode ->", String(new_mode))
			if _view:
				var existing := _players_by_source[source_id] as PlayerSel
				_view.ensure_player(source_id, existing.color)
				if _view.has_method("set_player_mode"):
					_view.set_player_mode(source_id, String(new_mode))
				_view.set_mode("Choosing (latest): " + String(new_mode))
		Phase.MAP:
			# Ignore new/unregistered players once roster is locked
			if not _players_by_source.has(source_id):
				print("[PreFight] Ignoring punch from unknown source ", source_id, " (roster locked).")
				return
			if not map_library:
				push_warning("[PreFight] MapLibrary not assigned; cannot pick maps.")
				return
			if _map_ids.is_empty():
				_map_ids = map_library.ids()
			if _map_ids.is_empty():
				push_warning("[PreFight] MapLibrary has no maps.")
				return
			var current_map: StringName = _map_choice_by_source.get(source_id, StringName(""))
			var idxm: int = (_map_ids.find(current_map) if String(current_map) != "" else -1)
			idxm = (idxm + 1) % _map_ids.size()
			var new_map: StringName = _map_ids[idxm]
			_map_choice_by_source[source_id] = new_map
			print("[PreFight] P", source_id, " cycling map ->", String(new_map))
			if _view:
				var existing2 := _players_by_source[source_id] as PlayerSel
				_view.ensure_player(source_id, existing2.color)
				if _view.has_method("set_player_map"):
					_view.set_player_map(source_id, String(new_map))
				if _view.has_method("set_map"):
					_view.set_map(String(new_map))
		_:
			# Ignore punches in SUMMARY/DONE or unexpected phases
			return

# Returns existing player or creates a new one if allowed (only during CHARACTER phase).
# When roster is locked or create_if_missing=false, returns null for unknown sources.
func _ensure_player(source_id: int, create_if_missing: bool = true) -> PlayerSel:
	if _players_by_source.has(source_id):
		return _players_by_source[source_id]
	if _roster_locked or not create_if_missing:
		print("[PreFight] Roster locked (or creation disabled). Ignoring new player src=", source_id)
		return null
	var color: Color = PLAYER_COLORS[_players.size() % PLAYER_COLORS.size()]
	var sel := PlayerSel.new(source_id, color)
	_players_by_source[source_id] = sel
	_players.append(sel)
	print("[PreFight] Registered player source_id=", source_id, " color=", color)
	if _view:
		_view.ensure_player(source_id, color)
	return sel

func _finalize_mode_choice() -> void:
	if not mode_library:
		push_warning("[PreFight] ModeLibrary not assigned; cannot finalize mode.")
		return

	var pool: Array[StringName] = []
	for v in _mode_choice_by_source.values():
		var id_sname: StringName = v
		if String(id_sname) != "":
			pool.append(id_sname)

	if pool.is_empty():
		for m in mode_library.ids():
			pool.append(m)

	print("[PreFight] Mode pool size=", pool.size(), " picks=", pool.map(func(x): return String(x)))
	if pool.is_empty():
		push_warning("[PreFight] No modes available in ModeLibrary.")
		_chosen_mode = &""
		if _view:
			_view.set_mode("No modes available")
		return

	var idx := randi() % pool.size()
	_chosen_mode = pool[idx]
	print("[PreFight] Chosen mode=", String(_chosen_mode))
	if _view:
		_view.set_mode("Chosen mode: " + String(_chosen_mode))

func _finalize_map_choice() -> void:
	if not map_library:
		push_warning("[PreFight] MapLibrary not assigned; cannot finalize map.")
		return

	var pool: Array[StringName] = []
	for v in _map_choice_by_source.values():
		var id_sname: StringName = v
		if String(id_sname) != "":
			pool.append(id_sname)

	if pool.is_empty():
		for m in map_library.ids():
			pool.append(m)

	print("[PreFight] Map pool size=", pool.size(), " picks=", pool.map(func(x): return String(x)))
	if pool.is_empty():
		push_warning("[PreFight] No maps available in MapLibrary.")
		_chosen_map_id = &""
		if _view and _view.has_method("set_map"):
			_view.set_map("No map available")
		return

	var idx := randi() % pool.size()
	_chosen_map_id = pool[idx]
	print("[PreFight] Chosen map_id=", String(_chosen_map_id))
	if _view and _view.has_method("set_map"):
		_view.set_map(String(_chosen_map_id))

func _enter_summary_phase() -> void:
	print("[PreFight] Entering SUMMARY. summary_sec=", summary_sec)
	_phase = Phase.SUMMARY
	_time_left = summary_sec

	_fill_missing_player_selections()

	if _view:
		_view.set_phase("Starting in...")
		if _view.has_method("set_mode"):
			_view.set_mode("Mode: " + String(_chosen_mode))
		if _view.has_method("set_map"):
			_view.set_map(String(_chosen_map_id))
	print("[PreFight] SUMMARY data: players=", _players_to_dict().size(), " mode=", String(_chosen_mode), " map_id=", String(_chosen_map_id))

func _fill_missing_player_selections() -> void:
	while _players.size() < 2:
		var fake_src: int = 1000 + _players.size()
		var color: Color = PLAYER_COLORS[_players.size() % PLAYER_COLORS.size()]
		var sel := PlayerSel.new(fake_src, color)
		_players_by_source[fake_src] = sel
		_players.append(sel)
		print("[PreFight] Added fake player for minimum count. src=", fake_src)

	for i in _players.size():
		var sel: PlayerSel = _players[i]
		if String(sel.character_id) == "" and not _boxer_ids.is_empty():
			sel.character_id = _boxer_ids[i % _boxer_ids.size()]
			print("[PreFight] Auto-filled character for src=", sel.source_id, " -> ", String(sel.character_id))
			if _view:
				_view.set_player_character(sel.source_id, String(sel.character_id))
		if String(sel.attack_set_id) == "" and not _attack_set_ids.is_empty():
			sel.attack_set_id = _attack_set_ids[i % _attack_set_ids.size()]
			print("[PreFight] Auto-filled attack set for src=", sel.source_id, " -> ", String(sel.attack_set_id))
			if _view:
				_view.set_player_set(sel.source_id, String(sel.attack_set_id))

func _start_chosen_mode() -> void:
	# Fix: the return must be inside the if-block. An outdented return here would abort always.
	if String(_chosen_mode) == "":
		push_warning("[PreFight] No mode chosen and ModeLibrary is empty. Aborting start.")
		return
	if String(_chosen_map_id) == "":
		push_warning("[PreFight] No map chosen and MapLibrary is empty. Aborting start.")
		return
	if _did_launch:
		print("[PreFight] _start_chosen_mode called again; ignoring.")
		return

	var params: Dictionary = _build_start_params()
	print("[PreFight] Launch params: players=", str(params.get("players", [])), " mode_id=", String(_chosen_mode), " map_id=", String(_chosen_map_id))

	var mode_data := _lookup_mode_data(_chosen_mode)
	if mode_data == null:
		push_warning("[PreFight] ModeData not found for id=" + String(_chosen_mode) + ". Using key fallback.")
	else:
		print("[PreFight] ModeData found. controller_key=", String(mode_data.controller_key), " scene_path=", String(mode_data.controller_scene_path), " script_path=", String(mode_data.controller_script_path))

	# Optional: resolve map scene path for logging
	var map_scene_path: String = ""
	if map_library and map_library.has_method("get_map"):
		var md: MapData = map_library.get_map(_chosen_map_id)
		if md and String(md.scene_path) != "":
			map_scene_path = String(md.scene_path)
	print("[PreFight] Map resolve: id=", String(_chosen_map_id), " scene_path=", map_scene_path)

	# Prefer scene/script if supported by your Game APIs (with 3-arg signature)
	if mode_data and String(mode_data.controller_scene_path) != "" and game.has_method("begin_local_controller_scene"):
		var scene := load(mode_data.controller_scene_path) as PackedScene
		if scene:
			_did_launch = true
			print("[PreFight] begin_local_controller_scene with map_ref=", String(_chosen_map_id))
			game.begin_local_controller_scene(scene, String(_chosen_map_id), params)
			return
	if mode_data and String(mode_data.controller_script_path) != "" and game.has_method("begin_local_controller_script"):
		var script := load(mode_data.controller_script_path) as Script
		if script:
			_did_launch = true
			print("[PreFight] begin_local_controller_script with map_ref=", String(_chosen_map_id))
			game.begin_local_controller_script(script, String(_chosen_map_id), params)
			return

	# Fallback: key-based startup. 2nd arg is the selected map id (or scene path).
	var key_to_start: String = String(_chosen_mode)
	if mode_data and String(mode_data.controller_key) != "":
		key_to_start = String(mode_data.controller_key)

	if not game or not game.has_method("begin_local_controller"):
		push_error("[PreFight] Game.begin_local_controller unavailable; cannot start mode=" + key_to_start)
		return

	_did_launch = true
	print("[PreFight] begin_local_controller key=", key_to_start, " map_ref=", String(_chosen_map_id))
	game.begin_local_controller(key_to_start, String(_chosen_map_id), params)

func _build_start_params() -> Dictionary:
	var params: Dictionary = {
		"players": _players_to_dict(),
		"mode_id": _chosen_mode,
		"map_id": _chosen_map_id
	}

	var mode_data := _lookup_mode_data(_chosen_mode)
	if mode_data and mode_data.default_params:
		for k in mode_data.default_params.keys():
			params[k] = mode_data.default_params[k]

	_last_start_params = params.duplicate(true)
	return params

func _lookup_mode_data(id: StringName) -> ModeData:
	if not mode_library:
		return null
	if mode_library.has_method("get_mode"):
		return mode_library.get_mode(id)
	if mode_library.has_method("all"):
		for m in mode_library.all():
			if m is ModeData and (m as ModeData).id == id:
				return m as ModeData
	return null

func _players_to_dict() -> Array[Dictionary]:
	var arr: Array[Dictionary] = []
	for sel in _players:
		arr.append({
			"source_id": sel.source_id,
			"color": sel.color,
			"character_id": sel.character_id,
			"attack_set_id": sel.attack_set_id
		})
	return arr

func _mount_view() -> void:
	if _view and is_instance_valid(_view): return
	var ui_host := _find_or_make_ui_host()
	var node: Control = null
	if view_scene:
		node = view_scene.instantiate() as Control
	else:
		node = PrefightView.new()
	if node:
		ui_host.add_child(node)
		_view = node as PrefightView
		if _view == null:
			push_warning("[PreFight] The view scene root should have PrefightView script attached.")
		else:
			print("[PreFight] View mounted.")
	else:
		push_warning("[PreFight] Failed to instantiate view scene.")

func _unmount_view() -> void:
	if _view and is_instance_valid(_view):
		_view.queue_free()
		print("[PreFight] View unmounted.")
	_view = null

func _find_or_make_ui_host() -> Control:
	var host: Control = null
	var gui_layer := game.get_node_or_null("GUILayer") as CanvasLayer
	if gui_layer:
		host = gui_layer.get_node_or_null("UIContainer") as Control
		if not host:
			host = Control.new()
			host.name = "UIContainer"
			gui_layer.add_child(host)
	else:
		host = game.get_node_or_null("UIContainer") as Control
		if not host:
			host = Control.new()
			host.name = "UIContainer"
			game.add_child(host)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.anchor_left = 0.0
	host.anchor_top = 0.0
	host.anchor_right = 1.0
	host.anchor_bottom = 1.0
	host.offset_left = 0.0
	host.offset_top = 0.0
	host.offset_right = 0.0
	host.offset_bottom = 0.0
	return host
