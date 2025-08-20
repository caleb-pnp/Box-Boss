# loading_screen.gd
extends Control

# Signal to tell Main that the new scene resource is ready.
signal load_complete(loaded_scene_resource: PackedScene)
signal load_failed(target_scene_path: String)

@onready var progress_bar: ProgressBar = $MarginContainer/VBoxContainer/ProgressBar

const MAX_VISUAL_SPEED = 0.2
var displayed_progress = 0.0

var target_scene_path: String

func _ready() -> void:
	pass

# Main will call this function to kick off the loading process.
func start_load(target_scene_path: String):
	self.target_scene_path = target_scene_path
	ResourceLoader.load_threaded_request(target_scene_path)
	# Enable the _process function to start checking the status.
	set_process(true)

func _process(delta: float) -> void:
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(target_scene_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var target_progress = progress[0]
			displayed_progress = move_toward(displayed_progress, target_progress, MAX_VISUAL_SPEED * delta)
			progress_bar.value = displayed_progress * 100

		ResourceLoader.THREAD_LOAD_LOADED:
			# Loading is done. Stop this _process loop.
			set_process(false)
			# Animate the bar to 100% before finishing.
			_finalize_and_emit()

		ResourceLoader.THREAD_LOAD_FAILED:
			printerr("Failed to load scene: %s" % target_scene_path)
			set_process(false)
			load_failed.emit(target_scene_path)

# This function now just handles the final animation and emitting the signal.
func _finalize_and_emit() -> void:
	var tween = create_tween()
	tween.tween_property(progress_bar, "value", 100, 0.5)
	await tween.finished

	# Get the loaded resource.
	var packed_scene = ResourceLoader.load_threaded_get(target_scene_path)

	# Tell Main that the resource is ready, and pass it along.
	load_complete.emit(packed_scene)
