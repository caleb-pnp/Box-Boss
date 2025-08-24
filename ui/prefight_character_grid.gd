extends GridContainer
class_name PrefightCharacterGrid

@export var grid_columns: int = 4
@export var tile_scene: PackedScene = preload("res://ui/character_tile.tscn")

var _tiles: Array[CharacterTile] = []
var _index_by_id: Dictionary = {}              # String (id) -> tile index
var _current_index_by_source: Dictionary = {}  # source_id -> tile index
var _color_by_source: Dictionary = {}          # source_id -> Color

func _ready() -> void:
	self.columns = max(1, grid_columns)

func build_roster(roster_ids: Array) -> void:
	_clear_grid()
	_index_by_id.clear()
	for i in range(roster_ids.size()):
		var id_any = roster_ids[i]
		var id_str := String(id_any)
		var id_sname := StringName(id_str)
		var tile := _make_tile(id_sname)
		_index_by_id[id_str] = i
		_tiles.append(tile)
		add_child(tile)

func build_roster_data(items: Array) -> void:
	_clear_grid()
	_index_by_id.clear()
	for i in range(items.size()):
		var item = items[i]
		if item is SelectableData:
			var d: SelectableData = item
			var id_str := String(d.id)
			var tile := _make_tile(StringName(id_str))
			tile.set_from_data(d)
			_index_by_id[id_str] = i
			_tiles.append(tile)
			add_child(tile)
		else:
			push_warning("PrefightCharacterGrid: Non-SelectableData in build_roster_data at index " + str(i))

func set_player_color(source_id: int, color: Color) -> void:
	_color_by_source[source_id] = color

func move_player_marker(source_id: int, id_any: Variant) -> void:
	var key := String(id_any)
	if not _index_by_id.has(key):
		return
	var new_index: int = int(_index_by_id[key])
	_move_marker_to_index(source_id, new_index)

func set_tile_icon(id_any: Variant, tex: Texture2D) -> void:
	var key := String(id_any)
	if not _index_by_id.has(key): return
	var i: int = int(_index_by_id[key])
	if i >= 0 and i < _tiles.size():
		_tiles[i].icon = tex

func _make_tile(id: StringName) -> CharacterTile:
	var tile: CharacterTile = (tile_scene.instantiate() as CharacterTile) if tile_scene else CharacterTile.new()
	tile.character_id = id
	tile.custom_minimum_size = Vector2(180, 200)
	return tile

func _move_marker_to_index(source_id: int, new_index: int) -> void:
	var color: Color = _color_by_source.get(source_id, Color.WHITE)
	if _current_index_by_source.has(source_id):
		var old_i: int = int(_current_index_by_source[source_id])
		if old_i >= 0 and old_i < _tiles.size():
			_tiles[old_i].set_occupied(source_id, color, false)
	if new_index >= 0 and new_index < _tiles.size():
		_tiles[new_index].set_occupied(source_id, color, true)
	_current_index_by_source[source_id] = new_index

func _clear_grid() -> void:
	for child in get_children():
		child.queue_free()
	_tiles.clear()
	_current_index_by_source.clear()
	_index_by_id.clear()
