extends Control
class_name LoadingScreen

signal load_complete(loaded_scene_resource: PackedScene)
signal load_failed(target_scene_path: String)

@export var base_text: String = "LOADING"
@export var dot_interval_sec: float = 0.5
@export var max_dots: int = 4
@export var auto_hide_on_complete: bool = false
@export var auto_hide_delay_sec: float = 0.0
@export var visual_rate: float = 0.8

@onready var progress_bar: ProgressBar = get_node_or_null("%ProgressBar")
@onready var loading_label: Label = get_node_or_null("%LoadingLabel")
@onready var percentage_label: Label = get_node_or_null("%PercentageLabel")

var _dot_count: int = 0
var _dot_timer: float = 0.0
var _displayed_progress: float = 0.0  # 0..1
var _target_progress: float = 0.0     # 0..1
var _pending_auto_hide: bool = false
var _in_progress: bool = false
var _use_external: bool = false

var target_scene_path: String = ""

func _ready() -> void:
	visible = false
	_refresh_labels(true)
	_update_progress_ui()

func start_load(path: String) -> void:
	if _in_progress:
		push_warning("[LoadingScreen] start_load called while already loading; ignoring new request.")
		return
	target_scene_path = path
	_in_progress = true
	_use_external = false
	_target_progress = 0.0
	_displayed_progress = 0.0
	_pending_auto_hide = false
	_show_screen()

	var err := ResourceLoader.load_threaded_request(target_scene_path)
	if err != OK:
		_in_progress = false
		emit_signal("load_failed", target_scene_path)
		return

	set_process(true)

func begin_external(message: String = "") -> void:
	if _in_progress:
		push_warning("[LoadingScreen] begin_external called while already busy; ignoring.")
		return
	if message != "":
		base_text = message
	_in_progress = true
	_use_external = true
	_target_progress = 0.0
	_displayed_progress = 0.0
	_pending_auto_hide = false
	_show_screen()
	set_process(true)

func update_progress(p: float) -> void:
	_target_progress = clamp(p, 0.0, 1.0)

func set_progress(p: float) -> void:
	update_progress(p)

func finish_external() -> void:
	_target_progress = 1.0
	if not _in_progress or not _use_external:
		return
	_finalize_visual_then(_on_external_done)

func _on_external_done() -> void:
	_in_progress = false
	_use_external = false
	if auto_hide_on_complete:
		_do_auto_hide()

func _process(delta: float) -> void:
	if visible:
		_dot_timer += delta
		if _dot_timer >= dot_interval_sec:
			_dot_timer = 0.0
			_dot_count += 1
			if _dot_count > max_dots:
				_dot_count = 0
			_refresh_labels()

	_displayed_progress = move_toward(_displayed_progress, _target_progress, visual_rate * delta)
	_update_progress_ui()

	if _in_progress and not _use_external:
		var prog: Array = []
		var status := ResourceLoader.load_threaded_get_status(target_scene_path, prog)

		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if prog.size() > 0:
				_target_progress = clamp(float(prog[0]), 0.0, 1.0)

		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			_finalize_visual_then(_emit_loaded)

		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			_in_progress = false
			printerr("Failed to load scene: %s" % target_scene_path)
			emit_signal("load_failed", target_scene_path)

func _emit_loaded() -> void:
	var res := ResourceLoader.load_threaded_get(target_scene_path)
	_in_progress = false
	if res == null or not (res is PackedScene):
		emit_signal("load_failed", target_scene_path)
		return
	emit_signal("load_complete", res as PackedScene)
	if auto_hide_on_complete:
		_do_auto_hide()

func _finalize_visual_then(cb: Callable) -> void:
	if progress_bar:
		var tween := create_tween()
		tween.tween_property(progress_bar, "value", 100.0, 0.35)
		tween.finished.connect(cb)
	else:
		cb.call()

func _show_screen() -> void:
	visible = true
	set_process(true) # ensure animations and smoothing run
	_dot_count = 0
	_dot_timer = 0.0
	_refresh_labels(true)
	_update_progress_ui()

func hide_screen() -> void:
	# Forcefully stop and allow future begin_external/start_load calls
	_in_progress = false
	_use_external = false
	_pending_auto_hide = false
	set_process(false)
	visible = false

func _do_auto_hide() -> void:
	if _pending_auto_hide:
		return
	_pending_auto_hide = true
	if auto_hide_delay_sec > 0.0:
		var t := get_tree().create_timer(auto_hide_delay_sec)
		t.timeout.connect(hide_screen)
	else:
		hide_screen()

func _refresh_labels(force: bool = false) -> void:
	if loading_label:
		loading_label.text = base_text + ".".repeat(_dot_count)
	if percentage_label and (force or _displayed_progress > 0.0):
		percentage_label.text = "%d%%" % int(round(_displayed_progress * 100.0))

func _update_progress_ui() -> void:
	if progress_bar:
		progress_bar.value = _displayed_progress * 100.0
	if percentage_label:
		percentage_label.text = "%d%%" % int(round(_displayed_progress * 100.0))
