extends Node

@export var character_path: NodePath
@export var serial_listener_path: NodePath # optional: a node that emits signal: hit(strength: float)
@export var enable_keyboard: bool = true

var character: BaseCharacter
var serial_listener: Node

func _ready() -> void:
	character = get_node_or_null(character_path)
	if not character:
		push_warning("PlayerController: character_path is not set.")
		return
	if not serial_listener_path.is_empty():
		serial_listener = get_node_or_null(serial_listener_path)
		if serial_listener and serial_listener.has_signal("hit"):
			serial_listener.connect("hit", Callable(self, "_on_serial_hit"))
		else:
			if serial_listener:
				push_warning("Serial listener does not have 'hit' signal.")

func _physics_process(_delta: float) -> void:
	if not character or not enable_keyboard:
		return

	var move_x := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var move_y := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	character.intents["move_local"] = Vector2(move_x, move_y).limit_length(1.0)

	character.intents["run"] = Input.is_action_pressed("run")
	# If running backward, treat as retreat (lets the character turn away if configured)
	character.intents["retreat"] = move_y < -0.5

	if Input.is_action_just_pressed("punch"):
		_request_attack(0.6) # medium strength from keyboard

func _request_attack(strength: float) -> void:
	character.intents["attack"] = true
	character.intents["attack_strength"] = clamp(strength, 0.0, 1.0)

func _on_serial_hit(strength: float) -> void:
	# Map external punch strength directly to attack strength
	_request_attack(clamp(strength, 0.0, 1.0))
