extends Control

# countdown layer variables
@onready var countdown_layer = $CountdownLayer
@onready var countdown_number = $CountdownLayer/Control/VBoxContainer/CountdownNumber

# view variables
@onready var game_view = $GameView
@onready var finished_view = $FinishedView
@onready var spectating_view = $SpectatingView
