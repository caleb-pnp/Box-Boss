extends Control

# Change the starting value to 1
var _dot_count: int = 0
var _loading_timer: float = 0.0
var _progress: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func set_progress(progress: float):
	_progress = progress * 100 # percentage out of 100

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Add the frame time to our timer
	_loading_timer += delta

	# Check if half a second has passed
	if _loading_timer >= 0.5:
		# Reset the timer for the next interval
		_loading_timer = 0.0

		# Increase the number of dots, and loop back to 1 if it gets too high
		_dot_count += 1
		if _dot_count > 4:
			_dot_count = 0

		# Build the string and update the label's text
		%LoadingLabel.text = "LOADING" + ".".repeat(_dot_count)

	if _progress > 0:
		%PercentageLabel.text = "%d%%" % int(round(_progress))
