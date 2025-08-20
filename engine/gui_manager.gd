extends Control

enum GUI_SCENE {NONE, LOBBY, PRE_GAME, GAME_HUD, LOADING, SCORING, SPECTATING}

@export var loading_scene:PackedScene = preload("res://gui/loading.tscn")
@export var lobby_scene:PackedScene = preload("res://gui/lobby.tscn")
@export var pre_game_scene:PackedScene = preload("res://gui/pre_game.tscn")
# the actual game scene is not managed by the GUI manager
@export var game_hud_scene:PackedScene = preload("res://gui/game_hud.tscn")
@export var scoring_hud_scene:PackedScene = preload("res://gui/scoring_hud.tscn")

var _active_scene: GUI_SCENE # important, so if the scene is already active; it doesn't load twice
var _current_scene_instace = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _remove_all():
	for child in get_children():
		child.hide()
		child.queue_free()

# loading screen
func show_loading(progress: float = 0):
	if _active_scene != GUI_SCENE.LOADING:
		_remove_all()
		var loading_scene_instance = loading_scene.instantiate()
		add_child(loading_scene_instance)
		_current_scene_instace = loading_scene_instance
		_active_scene = GUI_SCENE.LOADING

	if is_instance_valid(_current_scene_instace) and progress > 0:
		_current_scene_instace.set_progress(progress)

# hide loading screen
func hide_all():
	_remove_all()
	_current_scene_instace = null
	_active_scene = GUI_SCENE.NONE

# show lobby screen
func show_lobby():
	if _active_scene != GUI_SCENE.LOBBY:
		_remove_all()
		var lobby_instance = lobby_scene.instantiate()
		add_child(lobby_instance)
		_current_scene_instace = lobby_instance
		_active_scene = GUI_SCENE.LOBBY

# show pre game screen
func show_pre_game():
	if _active_scene != GUI_SCENE.PRE_GAME:
		_remove_all()
		var pre_game_instance = pre_game_scene.instantiate()
		add_child(pre_game_instance)
		_current_scene_instace = pre_game_instance
		_active_scene = GUI_SCENE.PRE_GAME

# show game hud
func show_game_hud():
	if _active_scene != GUI_SCENE.GAME_HUD:
		_remove_all()
		var game_hud_instance = game_hud_scene.instantiate()
		add_child(game_hud_instance)
		_current_scene_instace = game_hud_instance
		_active_scene = GUI_SCENE.GAME_HUD

# showing scoring hud
func show_scoring_hud():
	if _active_scene != GUI_SCENE.SCORING:
		_remove_all()
		var scoring_hud_instance = scoring_hud_scene.instantiate()
		add_child(scoring_hud_instance)
		_current_scene_instace = scoring_hud_instance
		_active_scene = GUI_SCENE.SCORING
