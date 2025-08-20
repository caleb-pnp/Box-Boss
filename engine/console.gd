extends CanvasLayer

signal console_command(command, params)

@onready var main = Main.instance
@onready var line_edit = $HBoxContainer/LineEdit

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _input(event):
	if event.is_action_pressed("toggle_console") and not event.is_echo():
		# Consume the event immediately so nothing else sees it.
		get_viewport().set_input_as_handled()

		# Perform the toggle logic.
		if self.visible:
			self.hide()
			line_edit.release_focus()
		else:
			self.show()
			line_edit.grab_focus()
			line_edit.clear()

func _on_line_edit_text_submitted(new_text: String) -> void:
	# 1. Clear input and hide console
	line_edit.clear()
	line_edit.release_focus()
	self.hide()

	# 2. Basic validation
	if new_text.is_empty():
		return

	# 3. Parse the text by spaces for flexibility
	# The 'false' argument prevents empty entries if there are multiple spaces
	var parts = new_text.strip_edges().split(" ", false)

	# The first part is the command
	var command = parts[0].to_lower()

	# All other parts are the arguments, stored in an Array
	var args = parts.slice(1)

	# 4. Execute the command
	main.execute_command(command, args)
