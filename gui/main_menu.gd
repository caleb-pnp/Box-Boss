extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_hide_all_submenus()

	if Main.instance.auto_host_join:
		_on_button_start_game_pressed.call_deferred()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_button_quit_pressed() -> void:
	get_tree().quit()

func _hide_all_submenus() -> void:
	pass

func _on_button_start_game_pressed() -> void:
	Main.instance.execute_command("host")

func _on_button_settings_pressed() -> void:
	pass


func _on_button_join_host_pressed() -> void:
	pass
