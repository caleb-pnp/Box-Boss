extends SelectableData
class_name MapData

# Human-friendly text already available from SelectableData:
# - id: StringName
# - display_name: String
# - icon: Texture2D (optional preview)
# Add map-specific fields below.

@export_multiline var description: String = ""

# Use a lazy-loaded path (avoids preload dependency chains)
@export_file("*.tscn") var scene_path: String = ""

# Optional conventions the game can use (not required)
@export var spawn_group_name: StringName = &"spawn"   # where controllers can look for spawn points
@export var music_stream: AudioStream = null          # background music for this map (optional)
