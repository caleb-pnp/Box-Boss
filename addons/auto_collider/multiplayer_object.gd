# multiplayer_object.gd
extends PhysicsBody3D # Base class for RigidBody3D, CharacterBody3D, StaticBody3D

# Variables to store the object's original state when the scene first loads.
var _original_transform: Transform3D
var _original_linear_velocity: Vector3 = Vector3.ZERO
var _original_angular_velocity: Vector3 = Vector3.ZERO


func _ready():
	# Store original state (captured once on scene load)
	_original_transform = global_transform
	if self.get_class() == "RigidBody3D": # Only RigidBody3D has these properties
		_original_linear_velocity = self.linear_velocity
		_original_angular_velocity = self.angular_velocity


# Function to reset the object to its original position/rotation/velocity
@rpc("any_peer", "call_remote", "reliable")
func reset_object_state():
	self.global_transform = _original_transform
	if self.get_class() == "RigidBody3D": # Use string comparison
		self.linear_velocity = _original_linear_velocity
		self.angular_velocity = _original_angular_velocity
