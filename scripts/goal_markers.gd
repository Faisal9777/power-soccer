# GoalMarkerHUD.gd (Godot 4.x)
extends Control

# --- Scene paths (set these in the Inspector) ---
@export var camera_path: NodePath      = NodePath("../../Camera3D")
@export var blue_goal_path: NodePath   = NodePath("../../Goal_A")
@export var green_goal_path: NodePath  = NodePath("../../Goal_B")
@export var ball_path: NodePath        = NodePath("../../Ball")            # NEW

# --- Per-target vertical offsets (in meters) ---
@export var blue_offset_below_m:  float = 1.0   # meters below blue goal center
@export var green_offset_below_m: float = 1.0   # meters below green goal center
@export var ball_marker_gap_px:   float = 24.0  # constant on-screen gap above the ball, in pixels  # NEW

# --- Marker nodes under this Control ---
@export var blue_marker_path:  NodePath = NodePath("BlueMarker")
@export var green_marker_path: NodePath = NodePath("GreenMarker")
@export var ball_marker_path:  NodePath = NodePath("BallMarker")           # NEW

# --- Tuning ---
@export var edge_margin: float          = 48.0         # keep inside screen edge
@export var hide_when_closer_than: float = 1.0         # meters
@export var clamp_on_screen: bool        = true        # also clamp when visible
@export var always_on_edge: bool         = false       # force markers to rim even if target is visible  # NEW

# If your arrow art points UP, keep this; if it points RIGHT set to 0.0
const ARROW_UP_BIAS := PI * 0.5

@onready var cam: Camera3D          = get_node_or_null(camera_path)
@onready var goal_blue: Node3D      = get_node_or_null(blue_goal_path)
@onready var goal_green: Node3D     = get_node_or_null(green_goal_path)
@onready var ball: Node3D           = get_node_or_null(ball_path)            # NEW

@onready var m_blue: TextureRect    = get_node_or_null(blue_marker_path)
@onready var m_green: TextureRect   = get_node_or_null(green_marker_path)
@onready var m_ball: TextureRect    = get_node_or_null(ball_marker_path)     # NEW


func _process(_dt: float) -> void:
	if not cam:
		return

	if not ball:
		var balls := get_tree().get_nodes_in_group("ball")
		if balls.size() > 0 and balls[0] is Node3D:
			ball = balls[0]

	_update_marker(goal_blue,  m_blue,  Vector3(0.0, -blue_offset_below_m, 0.0))
	_update_marker(goal_green, m_green, Vector3(0.0, -green_offset_below_m, 0.0))
	_update_marker(ball,       m_ball,  Vector3.ZERO, false, ball_marker_gap_px)   # CHANGED: no rotation, fixed pixel gap

func _update_marker(
	target: Node3D,
	marker: TextureRect,
	world_offset: Vector3,
	rotate_with_direction: bool = true,   # NEW — default keeps blue/green unchanged
	screen_gap_px: float = 0.0            # NEW — default keeps blue/green unchanged
) -> void:
	if not marker:
		return
	if not target or not cam:
		marker.visible = false
		return

	# viewport size (typed)
	var vp_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)

	# target pos (with offset)
	var world_pos: Vector3 = target.global_transform.origin + world_offset

	var cam_xf := cam.global_transform
	var cam_pos := cam_xf.origin
	var to_target := world_pos - cam_pos
	var dist := to_target.length()
	if dist < hide_when_closer_than:
		marker.visible = false
		return

	var cam_forward := -cam_xf.basis.z
	var in_front := cam_forward.dot(to_target) > 0.0

	# Project to screen
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	var pos: Vector2 = screen_pos

	# Decide where to place the marker
	if always_on_edge:
		var dir_from_center: Vector2 = (screen_pos - vp_size * 0.5).normalized()
		pos = (vp_size * 0.5) + dir_from_center * (min(vp_size.x, vp_size.y) * 0.5 - edge_margin)
	elif not in_front:
		# push to screen edge in the direction relative to camera right/up
		var cam_right := cam_xf.basis.x
		var cam_up := cam_xf.basis.y
		var dir2: Vector2 = Vector2(cam_right.dot(to_target), -cam_up.dot(to_target)).normalized()
		pos = (vp_size * 0.5) + dir2 * (min(vp_size.x, vp_size.y) * 0.5 - edge_margin)

	# Clamp inside screen
	if clamp_on_screen or not in_front or always_on_edge:
		pos.x = clamp(pos.x, edge_margin, vp_size.x - edge_margin)
		pos.y = clamp(pos.y, edge_margin, vp_size.y - edge_margin)

	marker.visible = true

	# CHANGED: branch so the ball marker skips the arrow-rotation math entirely
	if rotate_with_direction:
		# Place + rotate (arrow points from screen center to marker)
		marker.position = pos - marker.size * 0.5
		var v: Vector2 = (pos - vp_size * 0.5)
		if v.length_squared() > 0.0001:
			marker.rotation = atan2(v.y, v.x) - ARROW_UP_BIAS
	else:
		# Stay upright; anchor the icon's bottom-center tip a fixed pixel
		# gap above the target, so the gap looks the same near or far.
		marker.rotation = 0.0
		marker.position = Vector2(pos.x - marker.size.x * 0.5, pos.y - marker.size.y - screen_gap_px)
