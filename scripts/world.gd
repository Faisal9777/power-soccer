extends Node3D
@export var blue_goal_path: NodePath        # assign your Blue goal root (e.g., MeshInstance3D or a Node3D that contains meshes)
@export var green_goal_path: NodePath       # assign your Green goal root

# Optional: if you don't assign NodePaths, these are used to auto-find
@export var blue_goal_group: String = "goal_blue"
@export var green_goal_group: String = "goal_green"
@export var blue_goal_name_hint: String = "BlueGoal"
@export var green_goal_name_hint: String = "GreenGoal"

# Emission setup
@export var blue_emission: Color = Color(0.1, 0.45, 1.0, 1.0)
@export var green_emission: Color = Color(0.0, 1.0, 0.2, 1.0)
@export var emission_energy: float = 1.8   # raise if you want it hotter
@export var unshaded: bool = true          # makes the glow pop regardless of lighting
@export var apply_recursively: bool = true # apply to all MeshInstance3D children

func _ready() -> void:
	var blue_root := _resolve_goal(blue_goal_path, blue_goal_group, blue_goal_name_hint)
	var green_root := _resolve_goal(green_goal_path, green_goal_group, green_goal_name_hint)

	if blue_root:
		_apply_glow_to_hierarchy(blue_root, blue_emission)
	if green_root:
		_apply_glow_to_hierarchy(green_root, green_emission)

# --- helpers ---

func _resolve_goal(path: NodePath, group_name: String, name_hint: String) -> Node:
	# 1) explicit path
	if path != NodePath("") and has_node(path):
		return get_node(path)

	# 2) by group
	if group_name != "":
		var g := get_tree().get_nodes_in_group(group_name)
		if g.size() > 0:
			return g[0]

	# 3) by name hint (search shallow then deep)
	var from_root := get_tree().get_current_scene() if get_tree().get_current_scene() else self
	# shallow search
	for child in from_root.get_children():
		if child.name.findn(name_hint) != -1:
			return child
	# deep search
	return _find_node_deep(from_root, name_hint)

func _find_node_deep(root: Node, name_hint: String) -> Node:
	for c in root.get_children():
		if c.name.findn(name_hint) != -1:
			return c
		var found := _find_node_deep(c, name_hint)
		if found:
			return found
	return null

func _apply_glow_to_hierarchy(root: Node, color: Color) -> void:
	if root is MeshInstance3D:
		_apply_glow_material(root, color)
	if apply_recursively and root is Node:
		for c in root.get_children():
			_apply_glow_to_hierarchy(c, color)

func _apply_glow_material(mi: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy = emission_energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Keep the base albedo dim so emission stands out
	mat.albedo_color = Color(0.05, 0.05, 0.05, 1.0)

	# Apply as override so we don't need to touch sub-mesh surfaces individually
	mi.material_override = mat
