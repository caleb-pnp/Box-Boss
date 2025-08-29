# DamageText3D.gd
extends Label3D

var fade_time := 1.0
var move_speed := Vector3.UP * 1.5
var _timer := 0.0

func _ready():
	modulate.a = 1.0

func setup(text: String, color: Color, fade_time_sec: float = 1.0):
	self.text = text
	self.modulate = color
	self.fade_time = fade_time_sec
	_timer = 0.0

func _process(delta):
	_timer += delta
	translate(move_speed * delta)
	modulate.a = lerp(1.0, 0.0, _timer / fade_time)
	if _timer >= fade_time:
		queue_free()
