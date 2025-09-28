# GoalMarkerHUD.gd (Godot 4.x)
extends Control

# Paths in your scene
@export var camera_path: NodePath = NodePath("../../Camera3D") # from GoalMarkers → UI → CanvasLayer → World
@export var blue_goal_path: NodePath = NodePath("../../Goal_A")
@export var green_goal_path: NodePath = NodePath("../../Goal_B")
@export var blue_offset_below_m: float = 1.0   # meters below the goal center
@export var green_offset_below_m: float = 1.0
# The two marker nodes under this Control
@export var blue_marker_path: NodePath = NodePath("BlueMarker")
@export var green_marker_path: NodePath = NodePath("GreenMarker")

# Tuning
@export var edge_margin: float = 48.0          # keep inside screen edge
@export var hide_when_closer_than: float = 1.0 # meters
@export var clamp_on_screen: bool = true

# If your arrow art points UP, keep this; change if it points RIGHT (set to 0.0)
const ARROW_UP_BIAS := PI * 0.5

@onready var cam: Camera3D        = get_node_or_null(camera_path)
@onready var goal_blue: Node3D    = get_node_or_null(blue_goal_path)
@onready var goal_green: Node3D   = get_node_or_null(green_goal_path)
@onready var m_blue: Control      = get_node_or_null(blue_marker_path)
@onready var m_green: Control     = get_node_or_null(green_marker_path)

func _process(_dt: float) -> void:
	if not cam:
		return
	_update_marker(goal_blue, m_blue, blue_offset_below_m)
	_update_marker(goal_green, m_green, green_offset_below_m)

func _update_marker(goal: Node3D, marker: TextureRect, below_m: float) -> void:
	if not goal or not cam:
		return

	# Cast to Vector2 so math with 0.5 stays typed
	var vp_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)

	var cam_xf := cam.global_transform
	var cam_pos := cam_xf.origin

	# --- aim below the goal, along world +Y (down on screen is -Y) ---
	var world_pos: Vector3 = goal.global_transform.origin - Vector3(0.0, below_m, 0.0)

	var to_goal := world_pos - cam_pos
	var dist := to_goal.length()
	if dist < hide_when_closer_than:
		marker.visible = false
		return

	var cam_forward := -cam_xf.basis.z
	var in_front := cam_forward.dot(to_goal) > 0.0

	# Project to screen (typed)
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	var pos: Vector2 = screen_pos  # default: float over the (offset) target when visible

	if not in_front:
		# Push to screen edge in correct direction (typed)
		var cam_right := cam_xf.basis.x
		var cam_up := cam_xf.basis.y
		var dir2: Vector2 = Vector2(cam_right.dot(to_goal), -cam_up.dot(to_goal)).normalized()
		pos = (vp_size * 0.5) + dir2 * (min(vp_size.x, vp_size.y) * 0.5 - edge_margin)

	# Clamp inside screen
	if clamp_on_screen or not in_front:
		pos.x = clamp(pos.x, edge_margin, vp_size.x - edge_margin)
		pos.y = clamp(pos.y, edge_margin, vp_size.y - edge_margin)

	# Place + rotate
	marker.position = pos - marker.size * 0.5
	marker.visible = true

	var v: Vector2 = (pos - vp_size * 0.5)
	if v.length_squared() > 0.0001:
		marker.rotation = atan2(v.y, v.x) - ARROW_UP_BIAS
