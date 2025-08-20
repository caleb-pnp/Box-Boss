extends HBoxContainer

@export var player_name: String
@export var is_ready: bool

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$PlayerName.text = player_name
	if is_ready:
		$PlayerStatus.text = "READY"
	else:
		$PlayerStatus.text = "LOADING..."
