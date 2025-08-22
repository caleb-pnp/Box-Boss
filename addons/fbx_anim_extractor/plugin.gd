@tool
extends EditorPlugin

const MENU_EXTRACT_FBX := "FBX: Extract Animation..."
const MENU_REMOVE_ROOT := "Animations: Remove Mixamo Root Motion..."

var _fbx_dialog: FileDialog
var _lib_dialog: FileDialog

func _enter_tree() -> void:
	# Project menu entries
	add_tool_menu_item(MENU_EXTRACT_FBX, Callable(self, "_on_extract_menu_pressed"))
	add_tool_menu_item(MENU_REMOVE_ROOT, Callable(self, "_on_remove_root_menu_pressed"))

func _exit_tree() -> void:
	remove_tool_menu_item(MENU_EXTRACT_FBX)
	remove_tool_menu_item(MENU_REMOVE_ROOT)
	if is_instance_valid(_fbx_dialog):
		_fbx_dialog.queue_free()
	if is_instance_valid(_lib_dialog):
		_lib_dialog.queue_free()

# ----------------------------
# FBX -> Animation extractor
# ----------------------------
func _on_extract_menu_pressed() -> void:
	if not is_instance_valid(_fbx_dialog):
		_fbx_dialog = FileDialog.new()
		_fbx_dialog.title = "Select FBX file(s) to extract animation from"
		_fbx_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_fbx_dialog.current_dir = "res://"
		_fbx_dialog.use_native_dialog = false
		_fbx_dialog.add_filter("*.fbx ; FBX scenes")
		_fbx_dialog.files_selected.connect(_on_fbx_files_chosen)
		_fbx_dialog.file_selected.connect(_on_fbx_file_chosen)
		get_editor_interface().get_base_control().add_child(_fbx_dialog)
	_fbx_dialog.popup_centered_ratio(0.75)

func _on_fbx_file_chosen(path: String) -> void:
	_close_fbx_dialog_and_defer([path])

func _on_fbx_files_chosen(paths: PackedStringArray) -> void:
	_close_fbx_dialog_and_defer(paths)

func _close_fbx_dialog_and_defer(paths: PackedStringArray) -> void:
	if is_instance_valid(_fbx_dialog):
		_fbx_dialog.hide()
		_fbx_dialog.queue_free()
		_fbx_dialog = null
	call_deferred("_process_fbx_paths_after_dialog_close", paths)

func _process_fbx_paths_after_dialog_close(paths: PackedStringArray) -> void:
	for p in paths:
		_extract_one_fbx(p)

func _extract_one_fbx(fbx_path: String) -> void:
	if not fbx_path.to_lower().ends_with(".fbx"):
		push_warning("Skipping non-FBX: %s" % fbx_path)
		return

	var scene := ResourceLoader.load(fbx_path)
	if scene == null or not (scene is PackedScene):
		push_error("Failed to load FBX as PackedScene: %s" % fbx_path)
		return

	var root := (scene as PackedScene).instantiate()
	if root == null:
		push_error("Failed to instantiate scene: %s" % fbx_path)
		return

	var ap := _find_animation_player(root)
	if ap == null:
		push_error("No AnimationPlayer found in: %s" % fbx_path)
		root.free()
		return

	var anim_names := ap.get_animation_list()
	if anim_names.is_empty():
		push_error("AnimationPlayer has no animations in: %s" % fbx_path)
		root.free()
		return

	if anim_names.size() != 1:
		push_warning("Found %d animations in %s; extracting the first: %s" % [anim_names.size(), fbx_path, anim_names[0]])

	var src_name: StringName = anim_names[0]
	var src_anim := ap.get_animation(src_name)
	if src_anim == null:
		push_error("Failed to get animation '%s' from: %s" % [String(src_name), fbx_path])
		root.free()
		return

	var anim: Animation = src_anim.duplicate(true)
	if anim == null:
		push_error("Failed to duplicate animation for: %s" % fbx_path)
		root.free()
		return

	var dir := fbx_path.get_base_dir()
	var file_base := fbx_path.get_file().get_basename()
	var out_dir := dir.path_join("extracted")
	_ensure_dir(out_dir)

	# Save as <basename>.tres (no ".anim")
	var out_path := out_dir.path_join("%s.tres" % file_base)
	var err := ResourceSaver.save(anim, out_path)
	if err != OK:
		push_error("Failed to save animation to: %s (err=%d)" % [out_path, err])
	else:
		print("Extracted:", fbx_path, " -> ", out_path)
		_refresh_filesystem_and_focus(out_path)

	root.free()

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found != null:
			return found
	return null

# -------------------------------------------
# Root motion remover via Project menu
# -------------------------------------------
func _on_remove_root_menu_pressed() -> void:
	if not is_instance_valid(_lib_dialog):
		_lib_dialog = FileDialog.new()
		_lib_dialog.title = "Select AnimationLibrary or Animation .tres/.res file(s)"
		_lib_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_lib_dialog.current_dir = "res://"
		_lib_dialog.use_native_dialog = false
		_lib_dialog.add_filter("*.tres ; Text Resources")
		_lib_dialog.add_filter("*.res ; Binary Resources")
		_lib_dialog.files_selected.connect(_on_lib_files_chosen)
		_lib_dialog.file_selected.connect(_on_lib_file_chosen)
		get_editor_interface().get_base_control().add_child(_lib_dialog)
	_lib_dialog.popup_centered_ratio(0.75)

func _on_lib_file_chosen(path: String) -> void:
	_close_lib_dialog_and_defer([path])

func _on_lib_files_chosen(paths: PackedStringArray) -> void:
	_close_lib_dialog_and_defer(paths)

func _close_lib_dialog_and_defer(paths: PackedStringArray) -> void:
	if is_instance_valid(_lib_dialog):
		_lib_dialog.hide()
		_lib_dialog.queue_free()
		_lib_dialog = null
	call_deferred("_process_lib_paths_after_dialog_close", paths)

func _process_lib_paths_after_dialog_close(paths: PackedStringArray) -> void:
	# Build a flat list of animations, coming either from AnimationLibrary or standalone Animation resources
	var entries: Array = []
	for p in paths:
		var res := ResourceLoader.load(p)
		if res == null:
			continue
		if res is AnimationLibrary:
			var lib := res as AnimationLibrary
			for anim_name in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				if anim != null:
					entries.append({
						"name": anim_name,
						"source_type": "library",
						"library_path": p,
						"save_path": p,
						"animation": anim,
						"is_locomotion": _is_locomotion_animation(anim_name)
					})
		elif res is Animation:
			# Standalone Animation
			var basename: String = p.get_file().get_basename()
			entries.append({
				"name": basename,
				"source_type": "animation",
				"save_path": p,
				"animation": res,
				"is_locomotion": _is_locomotion_animation(basename)
			})
		# Ignore other resource types

	if entries.is_empty():
		_show_error_dialog("No AnimationLibrary or Animation resources found in the selected files.")
		return

	_show_animation_selection_dialog_from_entries(entries)

func _show_animation_selection_dialog_from_entries(entries: Array) -> void:
	var dialog := AnimationSelectionDialog.new()
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.setup_animations(entries)
	dialog.animations_confirmed.connect(_process_selected_animations)
	dialog.popup_centered(Vector2i(550, 450))

func _process_selected_animations(selected_animations: Array) -> void:
	var processed_count := 0
	var libs_to_save := {} # map library_path -> true
	var last_saved_path: String = ""

	print("Processing selected animations...")
	for anim_data in selected_animations:
		var animation: Animation = anim_data["animation"] as Animation
		var source_type := String(anim_data.get("source_type", "library"))
		var name: String = String(anim_data.get("name", ""))
		var save_path: String = String(anim_data.get("save_path", ""))

		print("Processing animation: ", name, " from ", save_path, " (", source_type, ")")
		if _remove_root_motion_from_animation(animation):
			processed_count += 1
			if source_type == "library":
				libs_to_save[save_path] = true
				last_saved_path = save_path
			else:
				# Standalone Animation: save directly
				var err := ResourceSaver.save(animation, save_path)
				if err != OK:
					push_error("Failed to save Animation: %s (err=%d)" % [save_path, err])
				else:
					print("Animation saved: ", save_path)
					last_saved_path = save_path
			print("  ✓ Root motion removed from: ", name)
		else:
			print("  ⚠ No Hips track found in: ", name)

	# Save modified libraries once
	for lib_path in libs_to_save.keys():
		var resource := ResourceLoader.load(lib_path)
		if resource is AnimationLibrary:
			var err2 := ResourceSaver.save(resource, lib_path)
			if err2 != OK:
				push_error("Failed to save AnimationLibrary: %s (err=%d)" % [lib_path, err2])
			else:
				print("AnimationLibrary saved: ", lib_path)

	if last_saved_path != "":
		_refresh_filesystem_and_focus(last_saved_path)

	print("Root motion removal completed! Processed ", processed_count, " animations")
	_show_completion_dialog(processed_count, selected_animations.size())

func _is_locomotion_animation(anim_name: String) -> bool:
	var s := anim_name.to_lower()
	for k in ["forward", "left", "right", "backward", "walk", "run", "jog", "sprint", "strafe"]:
		if s.find(k) != -1:
			return true
	return false

func _remove_root_motion_from_animation(animation: Animation) -> bool:
	var hips_track_idx := -1
	# Find a position track that targets "Hips"
	for i in range(animation.get_track_count()):
		if animation.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var p := animation.track_get_path(i)
		if String(p).find("Hips") != -1:
			hips_track_idx = i
			break

	if hips_track_idx == -1:
		return false

	var keyframe_count := animation.track_get_key_count(hips_track_idx)
	for k in range(keyframe_count):
		var v: Vector3 = animation.track_get_key_value(hips_track_idx, k)
		animation.track_set_key_value(hips_track_idx, k, Vector3(0.0, v.y, 0.0))
	print("    Modified ", keyframe_count, " keyframes in Hips track")
	return true

func _show_error_dialog(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Mixamo Root Motion Remover - Error"
	dialog.dialog_text = message
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _show_completion_dialog(processed_count: int, total_selected: int) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Mixamo Root Motion Remover"
	var status := "✓ SUCCESS: Selected animations had their Hips X and Z positions set to 0.0" if processed_count > 0 else "⚠ WARNING: No animations were processed (no Hips tracks found)"
	dialog.dialog_text = "Root motion removal completed!\n\nProcessed: %d animations\nSelected: %d animations\n\n%s" \
		% [processed_count, total_selected, status]
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

# ----------------------------
# Animation selection dialog
# ----------------------------
class AnimationSelectionDialog:
	extends ConfirmationDialog
	signal animations_confirmed(selected_animations: Array)

	var _data: Array = []
	var _checkboxes: Array = []
	var _select_all: CheckBox
	var _scroll: ScrollContainer
	var _vbox: VBoxContainer
	var _children_removal_queue: Array = []

	func _init() -> void:
		title = "Select Animations for Root Motion Removal"
		min_size = Vector2i(550, 450)

		var main := VBoxContainer.new()
		main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main.add_theme_constant_override("separation", 8)
		add_child(main)

		var header := Label.new()
		header.text = "Select the animations you want to remove root motion from:"
		main.add_child(header)

		_select_all = CheckBox.new()
		_select_all.text = "Select All / Deselect All"
		_select_all.toggled.connect(_on_select_all_toggled)
		main.add_child(_select_all)

		_scroll = ScrollContainer.new()
		_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.custom_minimum_size = Vector2(0, 100)
		main.add_child(_scroll)

		_vbox = VBoxContainer.new()
		_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_vbox.add_theme_constant_override("separation", 4)
		_scroll.add_child(_vbox)

		confirmed.connect(_on_confirmed)

	func setup_animations(anims: Array) -> void:
		_data = anims
		_checkboxes.clear()
		_children_removal_queue.clear()

		for child in _vbox.get_children():
			_children_removal_queue.append(child)
		for child in _children_removal_queue:
			child.queue_free()
		_children_removal_queue.clear()

		for anim_data in _data:
			var cb := CheckBox.new()
			var display := String(anim_data.get("name", ""))
			# tag standalone anims for clarity
			var src := String(anim_data.get("source_type", "library"))
			if src == "animation":
				display += " (standalone)"
			if anim_data.get("is_locomotion", false):
				display += " (locomotion)"
				cb.button_pressed = true
			cb.text = display
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb.toggled.connect(_on_any_checkbox_toggled)
			_vbox.add_child(cb)
			_checkboxes.append(cb)
		_update_select_all_state()

	func _on_select_all_toggled(pressed: bool) -> void:
		for cb in _checkboxes:
			cb.button_pressed = pressed

	func _on_any_checkbox_toggled(_pressed: bool) -> void:
		_update_select_all_state()

	func _update_select_all_state() -> void:
		var all_selected := true
		var any_selected := false
		for cb in _checkboxes:
			if cb.button_pressed:
				any_selected = true
			else:
				all_selected = false
		_select_all.set_pressed_no_signal(all_selected)
		get_ok_button().disabled = not any_selected

	func _on_confirmed() -> void:
		var selected := []
		for i in range(_checkboxes.size()):
			if _checkboxes[i].button_pressed:
				selected.append(_data[i])
		animations_confirmed.emit(selected)
		queue_free()

# ----------------------------
# Utility
# ----------------------------
func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var mk := DirAccess.make_dir_recursive_absolute(path)
	if mk != OK:
		push_error("Could not create directory: %s (err=%d)" % [path, mk])

func _refresh_filesystem_and_focus(path: String = "") -> void:
	# Force a rescan so new folders/files appear immediately in the FileSystem dock.
	var fs := get_editor_interface().get_resource_filesystem()
	if fs:
		fs.scan() # full rescan; cheap enough after small batches
	# Optionally select the newly created/saved file to bring it into view.
	if path != "":
		call_deferred("_select_file_in_dock", path)

func _select_file_in_dock(path: String) -> void:
	var dock := get_editor_interface().get_file_system_dock()
	if not dock:
		return

	# Godot 4.x
	if dock.has_method("navigate_to_path"):
		dock.navigate_to_path(path) # works with file or directory paths
		return

	# Godot 3.x fallback
	if dock.has_method("select_file"):
		dock.select_file(path)
		return

	# Last resort: at least open the directory
	var dir := path.get_base_dir()
	if dock.has_method("navigate_to_path"):
		dock.navigate_to_path(dir)
