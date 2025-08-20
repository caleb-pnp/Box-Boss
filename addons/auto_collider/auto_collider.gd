# auto_collider.gd
@tool # Essential for the script to run in the editor
extends EditorPlugin # <-- This makes it an EditorPlugin

# Define the top-level menu item name
var _main_menu_item_name = "Auto Collider"

# Define names for the sub-menu items (these are not full paths, but just their display names)
var _generate_children_option_name = "Generate Collisions/As Children of Mesh"
var _generate_new_node_option_name = "Generate Collisions/Under 'GeneratedCollisions' Node"
var _make_rigidbody_option_name = "Make Node RigidBody3D" # Direct item under "Auto Collider"
var _make_multiplayer_option_name = "Make Node Multiplayer" # Multiplayer setup option
var _replace_nodes_option_name = "Replace Nodes with Instanced Scene"
var _bake_transform_option_name = "Bake Transform to Mesh"
var _clean_mesh_option_name = "Clean/Rebuild Selected Mesh"

# Member variable to hold your custom submenu
var _auto_collider_submenu: PopupMenu

@export var replace_node_scene: PackedScene :
	set(value):
		replace_node_scene = value
		# This line ensures the property updates immediately in the plugin settings
		# if the plugin is active and you change it.
		if Engine.is_editor_hint():
			update_plugin_state() # Will cause the plugin to reload its properties
	get:
		return replace_node_scene


func _enter_tree():
	print("Auto Collider Plugin: Initializing...")

	# 1. Create the PopupMenu that will act as our submenu
	_auto_collider_submenu = PopupMenu.new()
	_auto_collider_submenu.set_name("AutoColliderSubMenu")

	# 2. Add your menu items to this new submenu, assigning unique integer IDs
	# These IDs will be used to identify which item was pressed in the handler function.
	_auto_collider_submenu.add_item(_generate_children_option_name, 1) # ID 1
	_auto_collider_submenu.add_item(_generate_new_node_option_name, 2) # ID 2
	_auto_collider_submenu.add_separator() # Optional: Add a visual separator

	_auto_collider_submenu.add_item(_make_rigidbody_option_name, 3) # ID 3
	_auto_collider_submenu.add_item(_make_multiplayer_option_name, 4) # ID 4
	_auto_collider_submenu.add_separator()

	_auto_collider_submenu.add_item(_bake_transform_option_name, 6) # --- NEW ---
	_auto_collider_submenu.add_item(_clean_mesh_option_name, 7) # Using a new ID
	_auto_collider_submenu.add_separator()

	_auto_collider_submenu.add_item(_replace_nodes_option_name, 5) # ID 5

	# 3. Connect the submenu's 'id_pressed' signal to a single handler method in your plugin.
	# This handler will receive the ID of the pressed item.
	_auto_collider_submenu.id_pressed.connect(self._on_auto_collider_menu_pressed)

	# 4. Add this PopupMenu as a submenu under "Project -> Tools -> Auto Collider"
	add_tool_submenu_item(_main_menu_item_name, _auto_collider_submenu)

	print("Plugin: Entered tree. '%s' submenu added." % _main_menu_item_name)


func _exit_tree():
	# --- MODIFIED: This is the correct way to remove a submenu ---
	# You only need to remove the main menu item you added.
	remove_tool_menu_item(_main_menu_item_name)
	print("Auto Collider Plugin: Menu removed.")

# New handler function for the "Auto Collider" submenu items
# This function will receive the ID of the menu item that was pressed.
func _on_auto_collider_menu_pressed(id: int):
	match id:
		1: # Corresponds to _generate_children_option_name
			# Call your existing function with the correct arguments
			_on_generate_collisions_pressed(true)
		2: # Corresponds to _generate_new_node_option_name
			_on_generate_collisions_pressed(false)
		3: # Corresponds to _make_rigidbody_option_name
			_on_make_rigidbody_pressed()
		4: # Corresponds to _make_multiplayer_option_name
			_on_make_multiplayer_pressed()
		5: # Corresponds to _replace_nodes_option_name
			_on_replace_nodes_pressed()
		6: # --- NEW ---
			_on_bake_transform_pressed()
		7:
			_on_clean_mesh_pressed()
		_: # Fallback for unknown IDs (shouldn't happen if IDs are managed correctly)
			print("Plugin: Unknown Auto Collider menu item pressed with ID: %s" % id)

# --- Helper Function: Read RigidBody3D settings from plugin.cfg ---
# This function MUST be a member of the EditorPlugin class.
func _get_rigidbody_settings() -> Dictionary:
	var settings = {}
	# Use default values that match plugin.cfg for robustness
	settings.mass = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_mass", 1.0)
	settings.friction = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_friction", 0.5)
	settings.bounce = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_bounce", 0.0)
	settings.linear_damp = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_linear_damp", 0.1)
	settings.angular_damp = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_angular_damp", 1.0)
	settings.lock_linear_y = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_lock_linear_y", true)
	settings.lock_angular_x = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_lock_angular_x", false)
	settings.lock_angular_z = ProjectSettings.get_setting("plugins/auto_collider/rigidbody_lock_angular_z", false)
	return settings


# --- Helper Function: Read multiplayer_object script path from plugin.cfg ---
func _get_multiplayer_object_script_path() -> String:
	return ProjectSettings.get_setting("plugins/auto_collider/multiplayer_object_script_path", "res://addons/auto_collider/multiplayer_object.gd")


# --- Helper function to recursively set owner for a node and its children ---
# This is crucial for nodes added/reparented in editor tools to appear in scene tree and be saved.
func _set_owner_recursively(node: Node, new_owner: Node):
	node.owner = new_owner # Set owner for the current node
	for child in node.get_children():
		if child is Node: # Ensure it's a Node before recursing
			_set_owner_recursively(child, new_owner)


# --- Function for "Generate Collisions" menu items (StaticBody3D with ConcavePolygonShape3D) ---
func _on_generate_collisions_pressed(generate_as_children_of_mesh_instance: bool):
	print("Auto Collider Plugin: Generating collisions (Mode: %s)..." % ("Children of MeshInstance3D" if generate_as_children_of_mesh_instance else "Under 'GeneratedCollisions' Node3D"))

	var editor_selection = EditorInterface.get_selection()
	if editor_selection == null:
		print("ERROR: Could not get EditorInterface selection. This tool must be run within the Godot editor with a scene open.")
		return

	var selected_nodes = editor_selection.get_selected_nodes()
	if selected_nodes.is_empty():
		print("No MeshInstance3D nodes selected. Please select one or more MeshInstance3D nodes in the 3D viewport.")
		return

	var scene_root = get_tree().get_edited_scene_root()
	if scene_root == null:
		print("ERROR: No edited scene root found. Is a scene open and active?")
		return

	# Logic for the dedicated parent node (only used if "new node" mode is selected)
	var dedicated_parent_node: Node3D = null
	if not generate_as_children_of_mesh_instance:
		# find_child to 3 arguments (pattern, recursive, owned) - CORRECT for your version
		var temp_parent_candidate = scene_root.find_child("GeneratedCollisions", true, false) # owned=false

		if temp_parent_candidate != null:
			if temp_parent_candidate is Node3D: # Manually check type
				dedicated_parent_node = temp_parent_candidate
			else:
				print("Warning: Found node named 'GeneratedCollisions' but it is not a Node3D. Creating a new one and cleaning up old.")
				temp_parent_candidate.queue_free()
				temp_parent_candidate = null

		if not dedicated_parent_node:
			dedicated_parent_node = Node3D.new()
			dedicated_parent_node.name = "GeneratedCollisions"
			scene_root.add_child(dedicated_parent_node)
			dedicated_parent_node.owner = scene_root
			print("Created new 'GeneratedCollisions' Node3D.")
		else:
			print("Using existing 'GeneratedCollisions' Node3D.")


	var created_count = 0
	for node in selected_nodes:
		if node is MeshInstance3D:
			if node.mesh == null:
				print("Skipping MeshInstance3D '%s' as it has no mesh assigned." % node.name)
				continue

			var mesh_instance = node
			var mesh = mesh_instance.mesh

			var static_body = StaticBody3D.new()
			static_body.name = mesh_instance.name + "_collision"

			var collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape"

			var generated_shape: Shape3D = null # This will hold the TrimeshShape

			# For ConcavePolygonShape3D (Trimesh collision)
			if mesh:
				generated_shape = mesh.create_trimesh_shape()

				if generated_shape == null:
					print("Warning: Failed to create TrimeshShape from mesh '%s'. Skipping." % mesh_instance.name)
					static_body.queue_free()
					continue
			else:
				print("Warning: Mesh data missing for '%s'. Skipping." % mesh_instance.name)
				static_body.queue_free()
				continue

			collision_shape.shape = generated_shape

			# Conditional Parenting Logic
			if generate_as_children_of_mesh_instance:
				mesh_instance.add_child(static_body)
				static_body.transform = Transform3D.IDENTITY
				static_body.owner = scene_root
				static_body.add_child(collision_shape)
				collision_shape.owner = scene_root
				print("Created collision for: '%s' (StaticBody3D: '%s' as CHILD of MeshInstance3D)" % [mesh_instance.name, static_body.name])
			else:
				if dedicated_parent_node == null:
					print("ERROR: Dedicated parent node is null. This should not happen in 'new node' mode. Skipping collision for '%s'." % mesh_instance.name)
					static_body.queue_free()
					continue

				dedicated_parent_node.add_child(static_body)
				static_body.global_transform = mesh_instance.global_transform
				static_body.owner = scene_root
				static_body.add_child(collision_shape)
				collision_shape.owner = scene_root
				print("Created collision for: '%s' (StaticBody3D: '%s' under 'GeneratedCollisions' Node3D)" % [mesh_instance.name, static_body.name])

			created_count += 1

	print("Finished creating %d collision shapes for selected meshes." % created_count)


# --- Function for "Make RigidBody3D" menu item ---
func _on_make_rigidbody_pressed():
	print("Auto Collider Plugin: 'Make RigidBody3D' menu item clicked.")

	var editor_selection = EditorInterface.get_selection()
	if editor_selection == null:
		print("ERROR: Could not get EditorInterface selection. This tool must be run within the Godot editor with a scene open.")
		return

	var selected_nodes = editor_selection.get_selected_nodes()
	if selected_nodes.is_empty():
		print("No Node3D objects selected. Please select one or more Node3D objects (e.g., traffic cones) to convert to RigidBody3D.")
		return

	var scene_root = get_tree().get_edited_scene_root()
	if scene_root == null:
		print("ERROR: No edited scene root found. Is a scene open and active?")
		return

	var rigidbody_settings = _get_rigidbody_settings()
	var converted_count = 0

	for selected_node in selected_nodes: # 'selected_node' is the Node3D parent like "Cone_Root_Node3D"
		if not (selected_node is Node3D):
			print("Skipping node '%s': Not a Node3D. Please select Node3D objects as the root of your object (e.g., cone)." % selected_node.name)
			continue

		# --- Store original global transform before modifying the tree ---
		var original_node_global_transform = selected_node.global_transform

		# Find the MeshInstance3D child within the selected Node3D
		var temp_mesh_instance_candidate = selected_node.find_child("*", true, false) # owned=false
		var mesh_instance: MeshInstance3D = null
		if temp_mesh_instance_candidate != null and temp_mesh_instance_candidate is MeshInstance3D:
			mesh_instance = temp_mesh_instance_candidate

		if mesh_instance == null or mesh_instance.mesh == null:
			print("Skipping node '%s': Does not contain a MeshInstance3D with a mesh to generate collision from." % selected_node.name)
			continue

		var original_parent = selected_node.get_parent()
		if original_parent == null:
			print("Skipping node '%s': Cannot convert root node of the scene to RigidBody3D (it must have a parent)." % selected_node.name)
			continue

		# --- START MODIFYING THE TREE ---
		# 1. Create the new RigidBody3D
		var new_rigidbody = RigidBody3D.new()
		new_rigidbody.name = selected_node.name + "_rigidbody"

		# 2. Add new_rigidbody to the scene tree IMMEDIATELY (as sibling to selected_node)
		original_parent.add_child(new_rigidbody)
		new_rigidbody.owner = scene_root # Set owner for saving

		# 3. Now set its global transform. It's safe because it's inside the tree.
		new_rigidbody.global_transform = original_node_global_transform
		new_rigidbody.global_transform.basis = new_rigidbody.global_transform.basis.orthonormalized() # Removes scale, keeps rotation

		# 4. Use call_deferred to apply physics properties (to avoid Invalid Assignment error)
		new_rigidbody.call_deferred("set", "mass", rigidbody_settings.mass)
		new_rigidbody.call_deferred("set", "friction", rigidbody_settings.friction)
		new_rigidbody.call_deferred("set", "bounce", rigidbody_settings.bounce)
		new_rigidbody.call_deferred("set", "linear_damp", rigidbody_settings.linear_damp)
		new_rigidbody.call_deferred("set", "angular_damp", rigidbody_settings.angular_damp)
		new_rigidbody.call_deferred("set", "lock_linear_y", rigidbody_settings.lock_linear_y)
		new_rigidbody.call_deferred("set", "lock_angular_x", rigidbody_settings.lock_angular_x)
		new_rigidbody.call_deferred("set", "lock_angular_z", rigidbody_settings.lock_angular_z)

		# 5. Create and set up the CollisionShape3D
		var new_collision_shape = CollisionShape3D.new()
		new_collision_shape.name = "CollisionShape"

		var generated_shape_resource: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		var vertices: PackedVector3Array

		if mesh_instance.mesh:
			# Use create_convex_shape() to get initial points, then scale them
			var base_convex_shape_resource = mesh_instance.mesh.create_convex_shape()

			if base_convex_shape_resource != null and base_convex_shape_resource is ConvexPolygonShape3D:
				vertices = base_convex_shape_resource.get_points() # Get the points from the unscaled shape
			else:
				print("Warning: create_convex_shape() failed or returned non-ConvexPolygonShape3D for '%s'. Skipping." % mesh_instance.name)
				new_rigidbody.queue_free() # Clean up new_rigidbody if shape fails
				continue

			# Scale the vertices directly before setting them back in the shape resource
			var actual_scale_for_shape = original_node_global_transform.basis.get_scale()
			var scaled_vertices: PackedVector3Array
			scaled_vertices.resize(vertices.size())
			for i in range(vertices.size()):
				scaled_vertices[i] = vertices[i] * actual_scale_for_shape

			generated_shape_resource.set_points(scaled_vertices)

			if generated_shape_resource.get_points().is_empty():
				print("Warning: No vertices found or shape generation failed for mesh '%s'. Skipping RigidBody3D conversion." % mesh_instance.name)
				new_rigidbody.queue_free()
				continue
		else:
			print("Warning: Mesh data missing for '%s'. Skipping RigidBody3D conversion." % mesh_instance.name)
			new_rigidbody.queue_free()
			continue

		new_collision_shape.shape = generated_shape_resource

		# CollisionShape3D local scale must be IDENTITY (1,1,1)
		new_collision_shape.transform = Transform3D.IDENTITY

		new_rigidbody.add_child(new_collision_shape)
		new_collision_shape.owner = scene_root

		# --- FIX: Use reparent() for the original Node3D ---
		# This will handle remove_child from original_parent and add_child to new_rigidbody.
		# preserve_global_transform = true will automatically calculate selected_node.transform
		# to match its original global transform relative to its new parent (new_rigidbody).
		# This also automatically preserves its original scale.
		selected_node.reparent(new_rigidbody, true)

		# --- Call _set_owner_recursively *after* all parenting is done ---
		# This ensures owner is set for selected_node and all its children.
		_set_owner_recursively(selected_node, scene_root)

		# 9. Clean up any old StaticBody3D collisions
		var temp_static_body_candidate = selected_node.find_child("*", true, false) # owned=false
		var old_static_body_collision: StaticBody3D = null
		if temp_static_body_candidate != null and temp_static_body_candidate is StaticBody3D:
			old_static_body_collision = temp_static_body_candidate

		if old_static_body_collision != null and old_static_body_collision.name.ends_with("_collision"):
			print("Info: Removing old StaticBody3D collision for '%s' (child of original Node3D)." % old_static_body_collision.name)
			old_static_body_collision.queue_free() # Queue for deletion

		converted_count += 1
		print("Converted '%s' (Node3D) to RigidBody3D '%s'." % [selected_node.name, new_rigidbody.name])

	print("Finished converting %d nodes to RigidBody3D." % converted_count)

# --- Function for "Make Multiplayer Node" menu item (generic Node3D multiplayer setup) ---
func _on_make_multiplayer_pressed():
	print("Auto Collider Plugin: 'Make Multiplayer Node' menu item clicked.")

	var editor_selection = EditorInterface.get_selection()
	if editor_selection == null:
		print("ERROR: Could not get EditorInterface selection. This tool must be run within the Godot editor with a scene open.")
		return

	var selected_nodes = editor_selection.get_selected_nodes()
	if selected_nodes.is_empty():
		print("No Node3D objects selected. Please select one or more Node3D objects to make multiplayer.")
		return

	var scene_root = get_tree().get_edited_scene_root()
	if scene_root == null:
		print("ERROR: No edited scene root found. Is a scene open and active?")
		return

	var multiplayer_script_path = _get_multiplayer_object_script_path()
	var multiplayer_script = load(multiplayer_script_path)
	if multiplayer_script == null:
		push_error("ERROR: Failed to load multiplayer object script from '%s'. Please check plugin.cfg setting." % multiplayer_script_path)
		return

	var configured_count = 0

	for node in selected_nodes:
		if not (node is Node3D): # Ensure it's a 3D node
			print("Skipping '%s': Not a Node3D. Can only make Node3D-derived objects multiplayer." % node.name)
			continue

		## Check if it already has a MultiplayerSynchronizer
		#var existing_sync = node.find_child("MultiplayerSynchronizer", false) # Direct child
		#if existing_sync != null:
			#print("Node '%s' already has a MultiplayerSynchronizer. Skipping multiplayer setup." % node.name)
			#continue
#
		## 1. Add MultiplayerSynchronizer
		#var synchronizer = MultiplayerSynchronizer.new()
		#synchronizer.name = "MultiplayerSynchronizer"
		#node.add_child(synchronizer)
		#synchronizer.owner = scene_root
#
		## --- FIX: Create and configure SceneReplicationConfig resource ---
		#var replication_config = SceneReplicationConfig.new()
#
		## Add global_transform property
		#replication_config.add_property(NodePath(".:position"))
		#replication_config.add_property(NodePath(".:rotation"))
		## Set its replication mode (e.g., always for transforms)
		#replication_config.property_set_replication_mode(NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		#replication_config.property_set_replication_mode(NodePath(".:rotation"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
#
		## Check if it's a physics body and add relevant properties
		#var is_physics_body_node = (node is RigidBody3D or node is CharacterBody3D or node is StaticBody3D) # Covers common physics body types
		#if is_physics_body_node:
			## Add linear_velocity
			#replication_config.add_property(NodePath(".:linear_velocity"))
			#replication_config.property_set_replication_mode(NodePath(".:linear_velocity"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
#
			## Add angular_velocity
			#replication_config.add_property(NodePath(".:angular_velocity"))
			#replication_config.property_set_replication_mode(NodePath(".:angular_velocity"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
#
#
		## Assign the configured SceneReplicationConfig to the MultiplayerSynchronizer
		#synchronizer.replication_config = replication_config
#
		#synchronizer.replication_interval = 0.05 # MAX

		# 3. Attach the generic multiplayer script
		node.set_script(multiplayer_script)

		# 4. Ensure the root node being modified is owned.
		node.owner = scene_root

		# 5. Add the node to the 'multiplayer_object' group ---
		node.add_to_group("multiplayer_object", true)

		configured_count += 1
		print("Configured '%s' as a multiplayer node." % node.name)

	print("Finished configuring %d nodes for multiplayer." % configured_count)




func _on_replace_nodes_pressed():
	# CORRECTED: Use popup_quick_open for opening the resource quick open dialog
	# It takes a callback and an optional array of base types to filter by.
	# To filter for scenes, you'd specify "PackedScene".
	EditorInterface.popup_quick_open(Callable(self, "_on_scene_selected"), ["PackedScene"])

func _on_scene_selected(path: String):
	print("Plugin: '_on_scene_selected' called. Selected Path: '%s'." % path)

	# --- Initial selection and path checks ---
	if path.is_empty():
		print("Plugin: Path is empty (user canceled dialog).")
		return

	var editor_interface = get_editor_interface()
	if editor_interface == null:
		print("ERROR: Could not get EditorInterface. This tool must be run within the Godot editor.")
		return

	var selected_nodes = editor_interface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty():
		print("Plugin: No nodes selected when dialog closed. Please select one or more nodes in the 3D viewport.")
		return

	var scene_root = get_tree().get_edited_scene_root()
	if scene_root == null:
		print("ERROR: No edited scene root found. Is a scene open and active?")
		return
	# --- End of initial block ---

	# Load the selected scene resource only once
	var new_scene_resource = load(path)
	if not new_scene_resource is PackedScene:
		print("Plugin: Error: Selected file '%s' is not a valid scene." % path)
		return
	print("Plugin: Successfully loaded new scene resource: '%s'." % path)


	var new_selected_nodes_for_editor = []
	var nodes_processed_count = 0

	if selected_nodes.is_empty(): # This check is redundant here, but harmless.
		print("Plugin: selected_nodes array is unexpectedly empty after re-getting selection.")
		print("Plugin: Internal Error: Selected nodes disappeared during operation.")
		return

	print("Plugin: Starting direct node replacements for %s selected nodes." % selected_nodes.size())
	for node_to_replace in selected_nodes:
		print("\n--- Processing node: '%s' ('%s') ---" % [node_to_replace.get_name(), node_to_replace.get_path()])

		# 1. Type Check: Ensure it's a Node3D
		if not node_to_replace is Node3D:
			print("Plugin: Skipping non-Node3D node: '%s' (Type: '%s')." % [node_to_replace.get_name(), node_to_replace.get_class()])
			continue

		# 2. Validity Check: Ensure the instance is still valid
		if not is_instance_valid(node_to_replace):
			print("Plugin: Skipping invalid node instance: '%s' (ID: %s) - might have been deleted." % [node_to_replace.get_name(), node_to_replace.get_instance_id()])
			continue

		# 3. Parent Check: Ensure it has a parent (not scene root)
		var parent_node = node_to_replace.get_parent()
		if not parent_node:
			print("Plugin: Skipping root node replacement: '%s' (cannot replace scene root directly with this method)." % node_to_replace.get_path())
			print("Plugin: Warning: Cannot replace scene root: '%s'. Skipping." % node_to_replace.get_name())
			continue

		# 4. Store Original Transform and Index (and Name)
		var original_global_transform = node_to_replace.global_transform
		var old_node_idx = node_to_replace.get_index()
		var original_node_name = node_to_replace.get_name() # Store the original name
		print("Plugin: Stored original global transform: %s." % str(original_global_transform))
		print("Plugin: Stored original index: %s." % old_node_idx)
		print("Plugin: Stored original name: '%s'." % original_node_name)


		# 5. Instantiate New Scene
		var new_scene_instance = new_scene_resource.instantiate()
		if not is_instance_valid(new_scene_instance):
			print("Plugin ERROR: Failed to instantiate new scene instance from '%s' for replacing '%s'." % [path, node_to_replace.get_name()])
			print("Plugin: Failed to create instance of selected scene for: '%s'." % node_to_replace.get_name())
			continue
		print("Plugin: Successfully instantiated new scene: '%s' (Type: '%s')." % [new_scene_instance.get_name(), new_scene_instance.get_class()])

		# 6. Type Check for New Instance's Root
		if not new_scene_instance is Node3D:
			print("Plugin ERROR: New scene root is NOT a Node3D (it is a '%s'). Cannot apply 3D transform. Skipping replacement of: '%s'." % [new_scene_instance.get_class(), node_to_replace.get_name()])
			print("Plugin: New scene root ('%s') is not a Node3D. It's a '%s'. Cannot replace." % [new_scene_instance.get_name(), new_scene_instance.get_class()])
			new_scene_instance.queue_free() # Clean up the failed instance
			continue # Skip this node and try next if any

		# --- SYNCHRONOUS OPERATIONS ---

		# 7. Add the new instance as a child FIRST
		print("Plugin: Attempting to add new instance: '%s' to parent: '%s'." % [new_scene_instance.get_name(), parent_node.get_name()])
		parent_node.add_child(new_scene_instance)
		print("Plugin DEBUG: Successfully called add_child for '%s'." % new_scene_instance.get_name())

		# 8. Set owner while it's in the tree
		if not is_instance_valid(scene_root):
			print("Plugin ERROR: Edited scene root is invalid/null. Cannot set owner for '%s'. New instance might not save." % new_scene_instance.get_name())
		else:
			print("Plugin: Setting owner for new instance '%s' to: '%s'." % [new_scene_instance.get_name(), scene_root.get_name()])
			new_scene_instance.owner = scene_root
			print("Plugin DEBUG: Successfully set owner for '%s'." % new_scene_instance.get_name())

		# 9. Move new instance to the original index
		print("Plugin: Moving new instance '%s' to original index: %s." % [new_scene_instance.get_name(), old_node_idx])
		parent_node.move_child(new_scene_instance, old_node_idx) # Keep original order

		# 10. Apply Transform (Position and Rotation Only)
		print("Plugin: Current global transform of new instance BEFORE apply: %s." % str(new_scene_instance.global_transform))
		print("Plugin: Applying global transform (position & rotation only) to new instance '%s'." % new_scene_instance.get_name())

		# Create a new Transform3D that takes only the position and rotation from the original.
		var new_transform = Transform3D()
		new_transform.origin = original_global_transform.origin # Copy position
		new_transform.basis = original_global_transform.basis.orthonormalized() # Copy rotation, remove scale

		new_scene_instance.global_transform = new_transform # Apply this new transform

		print("Plugin: Current global transform of new instance AFTER apply: %s." % str(new_scene_instance.global_transform))

		# Finally, remove and queue free the old node
		print("Plugin: Removing old node: '%s' from parent: '%s'." % [node_to_replace.get_name(), parent_node.get_name()])
		parent_node.remove_child(node_to_replace)

		print("Plugin: Queueing old node '%s' for deletion." % node_to_replace.get_name())
		node_to_replace.queue_free() # Schedule old node for deletion

		# Rename the new instance to the old node's name
		# IMPORTANT: Rename after adding to the tree and setting owner for proper editor update.
		new_scene_instance.set_name(original_node_name)
		print("Plugin: Renamed new instance to: '%s'." % new_scene_instance.get_name())

		# --- END SYNCHRONOUS OPERATIONS ---

		new_selected_nodes_for_editor.append(new_scene_instance)
		nodes_processed_count += 1
		print("--- Finished processing node: '%s' ---\n" % node_to_replace.get_name())


	if nodes_processed_count == 0 and not selected_nodes.is_empty():
		print("Plugin: Warning: No eligible Node3D nodes were replaced (e.g., all selected were root nodes, not Node3D, or instantiation failed).")
		print("Plugin: No eligible nodes replaced out of %s selected." % selected_nodes.size())
		return

	# Select all newly created instances in the editor's scene tree
	editor_interface.get_selection().set_selected_nodes(new_selected_nodes_for_editor)
	print("Plugin: Successfully replaced %s nodes. Selected %s new nodes in editor." % [nodes_processed_count, new_selected_nodes_for_editor.size()])

# --- NEW: Function for "Bake Transform to Mesh" menu item ---
func _on_bake_transform_pressed():
	# Gets the selection directly, just like your other functions
	var editor_selection = get_editor_interface().get_selection()
	var selected_nodes = editor_selection.get_selected_nodes()

	if selected_nodes.is_empty():
		print("Bake Tool: No nodes selected.")
		return
	var baked_count = 0
	for node in selected_nodes:
		if node is MeshInstance3D:
			if _bake_transform(node):
				baked_count += 1
		else:
			print("Bake Tool: Skipping '%s', as it is not a MeshInstance3D." % node.name)

	print("Bake Tool: Finished. Successfully baked transform for %d nodes." % baked_count)


# --- FINAL VERSION: Manually transform vertices ---
func _bake_transform(mesh_instance: MeshInstance3D) -> bool:
	if not mesh_instance.mesh is ArrayMesh:
		return false

	var original_mesh: ArrayMesh = mesh_instance.mesh
	var xform: Transform3D = mesh_instance.transform

	if xform.is_equal_approx(Transform3D.IDENTITY):
		return false

	if original_mesh.get_surface_count() == 0:
		return false

	var new_mesh := ArrayMesh.new()
	# Loop through each surface of the original mesh
	for i in range(original_mesh.get_surface_count()):
		# --- Start of Manual Transform Logic ---

		# 1. Get all the data arrays for the current surface
		var surface_arrays = original_mesh.surface_get_arrays(i)

		# 2. Extract just the vertex positions
		var original_vertices: PackedVector3Array = surface_arrays[ArrayMesh.ARRAY_VERTEX]
		var transformed_vertices := PackedVector3Array()
		transformed_vertices.resize(original_vertices.size())

		# 3. Manually apply the transform to each vertex
		for j in range(original_vertices.size()):
			transformed_vertices[j] = xform * original_vertices[j]

		# 4. Replace the old vertex array with our new transformed one
		surface_arrays[ArrayMesh.ARRAY_VERTEX] = transformed_vertices

		# 5. Create a new surface from the modified array data
		new_mesh.add_surface_from_arrays(
			original_mesh.surface_get_primitive_type(i),
			surface_arrays
		)
		# --- End of Manual Transform Logic ---

	# --- Use the UndoRedo manager as before ---
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Bake Mesh Transform (Manual)")
	undo_redo.add_do_property(mesh_instance, "mesh", new_mesh)
	undo_redo.add_do_property(mesh_instance, "transform", Transform3D.IDENTITY)
	undo_redo.add_undo_property(mesh_instance, "mesh", original_mesh)
	undo_redo.add_undo_property(mesh_instance, "transform", xform)
	undo_redo.commit_action()

	print("Bake Tool: Successfully baked transform for '%s' (manual method)." % mesh_instance.name)
	return true

func _on_clean_mesh_pressed():
	var editor_selection = get_editor_interface().get_selection()
	var selected_nodes = editor_selection.get_selected_nodes()

	if selected_nodes.is_empty():
		print("Clean Tool: No nodes selected.")
		return

	for node in selected_nodes:
		if node is MeshInstance3D:
			_clean_mesh(node)
		else:
			print("Clean Tool: Skipping '%s', not a MeshInstance3D." % node.name)

func _clean_mesh(mesh_instance: MeshInstance3D):
	if not mesh_instance.mesh:
		print("Clean Tool: Skipping '%s', no mesh resource." % mesh_instance.name)
		return

	# --- MODIFIED: Godot 4 manual mesh merging logic ---
	var old_mesh: ArrayMesh = mesh_instance.mesh
	var new_arrays = []
	new_arrays.resize(ArrayMesh.ARRAY_MAX)

	var all_vertices = PackedVector3Array()
	var all_normals = PackedVector3Array()
	var all_uvs = PackedVector2Array()
	var all_indices = PackedInt32Array()

	var vertex_offset = 0
	for i in range(old_mesh.get_surface_count()):
		var surface_arrays = old_mesh.surface_get_arrays(i)

		# Append data from this surface to our master arrays
		all_vertices.append_array(surface_arrays[ArrayMesh.ARRAY_VERTEX])
		all_normals.append_array(surface_arrays[ArrayMesh.ARRAY_NORMAL])
		all_uvs.append_array(surface_arrays[ArrayMesh.ARRAY_TEX_UV])

		var surface_indices = surface_arrays[ArrayMesh.ARRAY_INDEX]
		for j in range(surface_indices.size()):
			# Must offset indices to match the combined vertex array
			all_indices.append(surface_indices[j] + vertex_offset)

		vertex_offset = all_vertices.size()

	new_arrays[ArrayMesh.ARRAY_VERTEX] = all_vertices
	new_arrays[ArrayMesh.ARRAY_NORMAL] = all_normals
	new_arrays[ArrayMesh.ARRAY_TEX_UV] = all_uvs
	new_arrays[ArrayMesh.ARRAY_INDEX] = all_indices

	var new_array_mesh = ArrayMesh.new()
	# Check if there is any data to add to prevent an error
	if not all_vertices.is_empty() and not all_indices.is_empty():
		new_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
	else:
		print("Clean Tool: Skipping '%s', mesh contains no vertex or index data." % mesh_instance.name)
		return

	# --- The UndoRedo logic remains the same ---
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Clean Mesh Geometry")
	undo_redo.add_do_property(mesh_instance, "mesh", new_array_mesh)
	undo_redo.add_undo_property(mesh_instance, "mesh", old_mesh)
	undo_redo.commit_action()

	print("Clean Tool: Successfully rebuilt mesh for '%s'." % mesh_instance.name)

# This function is called by the setter of the exported properties
# to ensure the plugin's state (especially properties shown in Project Settings)
# is updated correctly after a change.
func update_plugin_state():
	# This is a bit of a hack, but it forces the plugin to re-read its @export properties
	# by temporarily disabling and re-enabling itself.
	# Make sure the name matches the one in plugin.cfg
	if EditorInterface.is_plugin_enabled("Auto Collider Tool"): # Replace "Auto Collider Tool" with your actual plugin name if different
		EditorInterface.set_plugin_enabled("Auto Collider Tool", false)
		EditorInterface.set_plugin_enabled("Auto Collider Tool", true)
