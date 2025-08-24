extends GameControllerBase
class_name PreFightController

@export var char_select_sec: float = 30.0
@export var set_select_sec: float = 30.0
@export var mode_select_sec: float = 15.0

@export var boxer_library: BoxerLibrary = preload("res://data/BoxerLibrary.tres")
@export var attack_set_library: AttackSetLibrary = preload("res://data/AttackSetLibrary.tres")

@export var mode_ids: Array[StringName] = [ &"StrongestWins", &"LiveWindows", &"CommandStyle" ]

@export var view_scene: PackedScene = preload("res://gui/character_select.tscn")
@export var next_map_path: String = ""

enum Phase { CHARACTER, ATTACK_SET, MODE, DONE }
var _phase: int = Phase.CHARACTER
var _time_left: float = 0.0
var _router: PunchInputRouter
var _view: PrefightView

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
var _chosen_mode: StringName = &"StrongestWins"

var _boxer_ids: Array[StringName] = []
var _attack_set_ids: Array[StringName] = []

func _init() -> void:
	requires_map_ready = false

func on_enter(params: Dictionary) -> void:
	if params.has("mode_ids"): mode_ids = params["mode_ids"]

	_phase = Phase.CHARACTER
	_time_left = char_select_sec
	_players_by_source.clear()
	_players.clear()
	_chosen_mode = &"StrongestWins"

	# Snapshot ids from libraries for quick cycling
	_boxer_ids = boxer_library.ids() if boxer_library else []
	_attack_set_ids = attack_set_library.ids() if attack_set_library else []

	_router = get_node_or_null("/root/PunchInput") as PunchInputRouter
	if _router:
		_router.punched.connect(_on_punched)

	_mount_view()
	if _view:
		if _view.is_node_ready():
			_init_view_ui()
		else:
			call_deferred("_init_view_ui")

func _init_view_ui() -> void:
	if not _view: return
	_view.set_roster_data(boxer_library.all())
	_view.set_phase("Character Select")
	_view.set_timer(int(ceil(_time_left)))
	_view.set_mode(String(_chosen_mode))

func on_exit() -> void:
	if _router and _router.punched.is_connected(_on_punched):
		_router.punched.disconnect(_on_punched)
	_unmount_view()

func on_map_ready(_map_instance: Node3D) -> void:
	pass

func tick(delta: float) -> void:
	_time_left = max(0.0, _time_left - delta)
	if _view:
		_view.set_timer(int(ceil(_time_left)))
	if _time_left > 0.0:
		return
	match _phase:
		Phase.CHARACTER:
			_phase = Phase.ATTACK_SET
			_time_left = set_select_sec
			if _view:
				_view.set_phase("Attack Set Select")
				_view.set_roster_data(attack_set_library.all())
		Phase.ATTACK_SET:
			_phase = Phase.MODE
			_time_left = mode_select_sec
			if _view:
				_view.set_phase("Mode Select")
				_view.set_roster(mode_ids) # Modes are still simple strings
		Phase.MODE:
			_phase = Phase.DONE
			_start_chosen_mode()

func on_punch(_source_id: int, _force: float) -> void:
	pass

func _on_punched(source_id: int, _force: float) -> void:
	match _phase:
		Phase.CHARACTER:
			var sel := _ensure_player(source_id)
			if _boxer_ids.is_empty(): return
			var idx: int = (_boxer_ids.find(sel.character_id) if String(sel.character_id) != "" else -1)
			idx = (idx + 1) % _boxer_ids.size()
			sel.character_id = _boxer_ids[idx]
			if _view:
				_view.ensure_player(source_id, sel.color)
				_view.set_player_character(source_id, String(sel.character_id))
		Phase.ATTACK_SET:
			if not _players_by_source.has(source_id) or _attack_set_ids.is_empty(): return
			var sel2: PlayerSel = _players_by_source[source_id]
			var idx2: int = (_attack_set_ids.find(sel2.attack_set_id) if String(sel2.attack_set_id) != "" else -1)
			idx2 = (idx2 + 1) % _attack_set_ids.size()
			sel2.attack_set_id = _attack_set_ids[idx2]
			if _view:
				_view.ensure_player(source_id, sel2.color)
				_view.set_player_set(source_id, String(sel2.attack_set_id))
		Phase.MODE:
			if mode_ids.is_empty(): return
			var i: int = mode_ids.find(_chosen_mode)
			if i < 0: i = 0
			_chosen_mode = mode_ids[(i + 1) % mode_ids.size()]
			if _view:
				_view.set_mode(String(_chosen_mode))

func _ensure_player(source_id: int) -> PlayerSel:
	if _players_by_source.has(source_id):
		return _players_by_source[source_id]
	var color: Color = PLAYER_COLORS[_players.size() % PLAYER_COLORS.size()]
	var sel := PlayerSel.new(source_id, color)
	_players_by_source[source_id] = sel
	_players.append(sel)
	if _view:
		_view.ensure_player(source_id, color)
	return sel

func _start_chosen_mode() -> void:
	while _players.size() < 2:
		var fake_src: int = 1000 + _players.size()
		var color: Color = PLAYER_COLORS[_players.size() % PLAYER_COLORS.size()]
		var sel := PlayerSel.new(fake_src, color)
		sel.character_id = (_boxer_ids[_players.size() % max(1, _boxer_ids.size())] if not _boxer_ids.is_empty() else &"")
		sel.attack_set_id = (_attack_set_ids[_players.size() % max(1, _attack_set_ids.size())] if not _attack_set_ids.is_empty() else &"")
		_players_by_source[fake_src] = sel
		_players.append(sel)
	var params: Dictionary = { "players": _players_to_dict() }
	var map_path: String = next_map_path
	game.begin_local_controller(String(_chosen_mode), map_path, params)

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

func _unmount_view() -> void:
	if _view and is_instance_valid(_view):
		_view.queue_free()
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
