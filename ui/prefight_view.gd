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

var _preview_by_source: Dictionary = {} # source_id -> Label
var _pending_roster: Array = []

func _ready() -> void:
	_phase_label = _get_or_find_label(phase_label_path, "PhaseLabel")
	_timer_label = _get_or_find_label(timer_label_path, "TimerLabel")
	_mode_label = _get_or_find_label(mode_label_path, "ModeLabel")
	_grid = _get_or_find_grid(grid_path, "Grid") as PrefightCharacterGrid
	if _grid == null:
		push_warning("PrefightView: Grid node not found or missing PrefightCharacterGrid script.")
	if String(previews_bar_path) != "" and has_node(previews_bar_path):
		_previews_bar = get_node(previews_bar_path) as HBoxContainer
	else:
		_previews_bar = find_child("PreviewsBar", true, false) as HBoxContainer
	if not _pending_roster.is_empty() and _grid:
		_apply_pending_roster()

func set_phase(name: String) -> void:
	if _phase_label: _phase_label.text = name

func set_timer(seconds: int) -> void:
	if _timer_label: _timer_label.text = str(seconds)

func set_mode(mode_id: String) -> void:
	if _mode_label: _mode_label.text = "Mode: " + mode_id

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
	if _pending_roster.is_empty(): return
	if _grid == null:
		_grid = _get_or_find_grid(grid_path, "Grid") as PrefightCharacterGrid
	if _grid:
		var use_data := false
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
	if _grid: _grid.set_player_color(source_id, color)
	if _previews_bar and not _preview_by_source.has(source_id):
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(24, 24)
		row.add_child(swatch)
		var lbl := Label.new()
		lbl.text = "P" + str(source_id) + " - Character: -  Set: -"
		row.add_child(lbl)
		_previews_bar.add_child(row)
		_preview_by_source[source_id] = lbl

func set_player_character(source_id: int, id_str: String) -> void:
	if _grid: _grid.move_player_marker(source_id, id_str)
	var lbl: Label = _preview_by_source.get(source_id, null)
	if lbl:
		var pieces := lbl.text.split("  Set: ")
		var existing_set := pieces[1] if pieces.size() > 1 else "-"
		lbl.text = "P" + str(source_id) + " - Character: " + id_str + "  Set: " + existing_set

func set_player_set(source_id: int, set_id: String) -> void:
	# Move the colored marker on the grid during Attack Set phase too
	if _grid: _grid.move_player_marker(source_id, set_id)
	var lbl: Label = _preview_by_source.get(source_id, null)
	if lbl:
		var pieces := lbl.text.split("  Set: ")
		var char_part := pieces[0] if pieces.size() > 0 else ("P" + str(source_id) + " - Character: -")
		lbl.text = char_part + "  Set: " + set_id

func clear_players() -> void:
	for n in _preview_by_source.values():
		if is_instance_valid(n): n.queue_free()
	_preview_by_source.clear()

func _get_or_find_label(path: NodePath, fallback_name: String) -> Label:
	if String(path) != "" and has_node(path): return get_node(path) as Label
	return find_child(fallback_name, true, false) as Label

func _get_or_find_grid(path: NodePath, fallback_name: String) -> GridContainer:
	if String(path) != "" and has_node(path): return get_node(path) as GridContainer
	return find_child(fallback_name, true, false) as GridContainer
