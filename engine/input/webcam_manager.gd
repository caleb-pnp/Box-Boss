# WebcamManager.gd
extends Node

signal login_successful(user_id: int)
signal throw_detected(hand: LeanDetector.ThrowHand)

@export var login_detector: Node
@export var lean_detector: Node

var _active_detector: Node = null

func _exit_tree() -> void:
	# First, check if the login_detector node exists
	if login_detector:
		# If it exists, then check for and disconnect the signal
		var callable = Callable(self, "_on_login_successful")
		if login_detector.is_connected("login_successful", callable):
			login_detector.disconnect("login_successful", callable)

	# Do the same for the lean_detector
	if lean_detector:
		var callable = Callable(self, "_on_throw_detected")
		if lean_detector.is_connected("throw_detected", callable):
			lean_detector.disconnect("throw_detected", callable)

func _ready():
	if login_detector:
		login_detector.connect("login_successful", Callable(self, "_on_login_successful"))
	else:
		printerr("WebcamManager: LoginDetector node not assigned in the editor!")

	if lean_detector:
		lean_detector.connect("throw_detected", Callable(self, "_on_throw_detected"))
	else:
		printerr("WebcamManager: LeanDetector node not assigned in the editor!")


# --- MODIFIED: More robust activation logic ---
func activate_login_detector():
	# Guard clause: if it's already the active one, do nothing.
	if _active_detector == login_detector:
		return

	print("WebcamManager: Switching to Login Detector...")
	# Deactivate the OTHER detector(s) explicitly, ignoring the current state.
	if lean_detector:
		lean_detector.deactivate()

	# Now, activate the target detector and set the state.
	_active_detector = login_detector
	if _active_detector:
		_active_detector.activate()
	print("WebcamManager: Login Detector is now active.")


# --- MODIFIED: More robust activation logic ---
func activate_lean_detector():
	# Guard clause: if it's already the active one, do nothing.
	if _active_detector == lean_detector:
		return

	print("WebcamManager: Switching to Lean Detector...")
	# Deactivate the OTHER detector(s) explicitly, ignoring the current state.
	if login_detector:
		login_detector.deactivate()

	# Now, activate the target detector and set the state.
	_active_detector = lean_detector
	if _active_detector:
		_active_detector.activate()
	print("WebcamManager: Lean Detector is now active.")


# --- MODIFIED: Deactivate ALL known detectors ---
func deactivate_all():
	print("WebcamManager: Deactivating all detectors...")
	if login_detector:
		login_detector.deactivate()
	if lean_detector:
		lean_detector.deactivate()
	_active_detector = null
	print("WebcamManager: All detectors are now deactivated.")


# --- Signal Forwarding (Unchanged) ---
func _on_login_successful(user_id):
	emit_signal("login_successful", int(user_id))

func _on_throw_detected(hand: LeanDetector.ThrowHand):
	emit_signal("throw_detected", hand)


# --- Getter for Polling (Unchanged) ---
func get_lean_axis() -> float:
	if lean_detector and lean_detector.is_inside_tree():
		return lean_detector.get_lean_axis()
	return 0.0
