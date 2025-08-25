extends Control
class_name PrefightView

@export var phase_label_path: NodePath
@export var timer_label_path: NodePath
@export var mode_label_path: NodePath
@export var grid_path: NodePath
@export var previews_bar_path: NodePath

var _phase_label: Label
var _timer_label: Label
var _mode_label: Label
var _grid: PrefightCharacterGrid
var _previews_bar: HBoxContainer

# Per-player UI
var _preview_by_source: Dictionary[int, Label] = {}                # source_id -> Label
var _preview_state_by_source: Dictionary[int, PlayerPreviewState] = {} # source_id -> PlayerPreviewState

var _pending_roster: Array = []

class PlayerPreviewState:
	var character: String
	var set: String
	var mode: String
	var map: String
	func _init() -> void:
		character = "-"
		set = "-"
		mode = "-"
		map = "-"

func _ready() -> void:
	_phase_label = _get_or_find_label(phase_label_path, "PhaseLabel")
	_timer_label = _get_or_find_label(timer_label_path, "TimerLabel")
	_mode_label = _get_or_find_label(mode_label_path, "ModeLabel")
	_grid = _get_or_find_grid(grid_path, "Grid")
	if _grid == null:
		push_warning("PrefightView: Grid node not found or missing PrefightCharacterGrid script.")
	if String(previews_bar_path) != "" and has_node(previews_bar_path):
		_previews_bar = get_node(previews_bar_path) as HBoxContainer
	else:
		_previews_bar = find_child("PreviewsBar", true, false) as HBoxContainer
	if not _pending_roster.is_empty() and _grid:
		_apply_pending_roster()

func set_phase(name: String) -> void:
	if _phase_label:
		_phase_label.text = name

func set_timer(seconds: int) -> void:
	if _timer_label:
		_timer_label.text = str(seconds)

func set_mode(mode_id: String) -> void:
	if _mode_label:
		_mode_label.text = "Mode: " + mode_id

func set_map(map_id: String) -> void:
	if _mode_label:
		_mode_label.text = "Map: " + map_id

func set_roster(roster_ids: Array) -> void:
	if not is_node_ready() or _grid == null:
		_pending_roster = roster_ids.duplicate()
		call_deferred("_apply_pending_roster")
		return
	_grid.build_roster(roster_ids)

func set_roster_data(items: Array) -> void:
	if not is_node_ready() or _grid == null:
		_pending_roster = items.duplicate()
		call_deferred("_apply_pending_roster")
		return
	_grid.build_roster_data(items)

func _apply_pending_roster() -> void:
	if _pending_roster.is_empty():
		return
	if _grid == null:
		_grid = _get_or_find_grid(grid_path, "Grid")
	if _grid:
		var use_data: bool = false
		for item in _pending_roster:
			if item is SelectableData:
				use_data = true
				break
		if use_data:
			_grid.build_roster_data(_pending_roster)
		else:
			_grid.build_roster(_pending_roster)
		_pending_roster.clear()

func ensure_player(source_id: int, color: Color) -> void:
	if _grid:
		_grid.set_player_color(source_id, color)
	if _previews_bar and not _preview_by_source.has(source_id):
		var row: HBoxContainer = HBoxContainer.new()
		var swatch: ColorRect = ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(24, 24)
		row.add_child(swatch)
		var lbl: Label = Label.new()
		_preview_by_source[source_id] = lbl
		_preview_state_by_source[source_id] = PlayerPreviewState.new()
		row.add_child(lbl)
		_previews_bar.add_child(row)
		_refresh_preview_label(source_id)

func set_player_character(source_id: int, id_str: String) -> void:
	if not _preview_by_source.has(source_id):
		ensure_player(source_id, Color.WHITE)
	if _grid:
		_grid.move_player_marker(source_id, id_str)
	var st: PlayerPreviewState = _ensure_state(source_id)
	st.character = id_str
	_refresh_preview_label(source_id)

func set_player_set(source_id: int, set_id: String) -> void:
	if _grid:
		_grid.move_player_marker(source_id, set_id)
	var st: PlayerPreviewState = _ensure_state(source_id)
	st.set = set_id
	_refresh_preview_label(source_id)

func set_player_mode(source_id: int, mode_id: String) -> void:
	if _grid:
		_grid.move_player_marker(source_id, mode_id)
	var st: PlayerPreviewState = _ensure_state(source_id)
	st.mode = mode_id
	_refresh_preview_label(source_id)

func set_player_map(source_id: int, map_id: String) -> void:
	if _grid:
		_grid.move_player_marker(source_id, map_id)
	var st: PlayerPreviewState = _ensure_state(source_id)
	st.map = map_id
	_refresh_preview_label(source_id)

func clear_players() -> void:
	for lbl in _preview_by_source.values():
		if is_instance_valid(lbl):
			var row: Control = lbl.get_parent() as Control
			if row and is_instance_valid(row):
				row.queue_free()
	_preview_by_source.clear()
	_preview_state_by_source.clear()

# -----------------
# Helpers
# -----------------
func _ensure_state(source_id: int) -> PlayerPreviewState:
	var existing = _preview_state_by_source.get(source_id, null)
	if existing is PlayerPreviewState:
		return existing as PlayerPreviewState
	var st := PlayerPreviewState.new()
	_preview_state_by_source[source_id] = st
	return st

func _refresh_preview_label(source_id: int) -> void:
	var lbl: Label = _preview_by_source.get(source_id, null)
	if not lbl:
		return
	var st: PlayerPreviewState = _ensure_state(source_id)
	lbl.text = "P" + str(source_id) \
		+ " - Character: " + String(st.character) \
		+ "  Set: " + String(st.set) \
		+ "  Mode: " + String(st.mode) \
		+ "  Map: " + String(st.map)

func _get_or_find_label(path: NodePath, fallback_name: String) -> Label:
	if String(path) != "" and has_node(path):
		return get_node(path) as Label
	return find_child(fallback_name, true, false) as Label

func _get_or_find_grid(path: NodePath, fallback_name: String) -> PrefightCharacterGrid:
	if String(path) != "" and has_node(path):
		return get_node(path) as PrefightCharacterGrid
	return find_child(fallback_name, true, false) as PrefightCharacterGrid
