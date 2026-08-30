
# GoalMarkerHUD.gd (Godot 4.x)
extends Control

@export var camera_path: NodePath      = NodePath("../../Camera3D")
@export var blue_goal_path: NodePath   = NodePath("../../Goal_A")
@export var green_goal_path: NodePath  = NodePath("../../Goal_B")
@export var ball_path: NodePath        = NodePath("../../Ball")

@export var blue_offset_below_m:  float = 1.0
@export var green_offset_below_m: float = 1.0
@export var ball_marker_gap_px:   float = 24.0

@export var blue_marker_path:  NodePath = NodePath("BlueMarker")
@export var green_marker_path: NodePath = NodePath("GreenMarker")
@export var ball_marker_path:  NodePath = NodePath("BallMarker")

@export var edge_margin: float           = 48.0
@export var hide_when_closer_than: float = 1.0
@export var clamp_on_screen: bool        = true
@export var always_on_edge: bool         = false

const ARROW_UP_BIAS := PI * 0.5

@onready var cam: Camera3D          = get_node_or_null(camera_path)
@onready var goal_blue: Node3D      = get_node_or_null(blue_goal_path)
@onready var goal_green: Node3D     = get_node_or_null(green_goal_path)
@onready var ball: Node3D           = get_node_or_null(ball_path)

@onready var m_blue: TextureRect    = get_node_or_null(blue_marker_path)
@onready var m_green: TextureRect   = get_node_or_null(green_marker_path)
@onready var m_ball: TextureRect    = get_node_or_null(ball_marker_path)


func _process(_dt: float) -> void:
	if not cam:
		return

	if not ball:
		var balls := get_tree().get_nodes_in_group("ball")
		if balls.size() > 0 and balls[0] is Node3D:
			ball = balls[0]

	_update_marker(
		goal_blue,
		m_blue,
		Vector3(0.0, -blue_offset_below_m, 0.0),
		false,
		0.0
	)

	_update_marker(
		goal_green,
		m_green,
		Vector3(0.0, -green_offset_below_m, 0.0),
		false,
		0.0
	)

	_update_marker(
		ball,
		m_ball,
		Vector3.ZERO,
		true,
		ball_marker_gap_px
	)


func _update_marker(
	target: Node3D,
	marker: TextureRect,
	world_offset: Vector3,
	_use_ball_gap: bool = false,
	screen_gap_px: float = 0.0
) -> void:
	if not marker:
		return

	if not target or not cam:
		marker.visible = false
		return

	var vp_size: Vector2 = Vector2(
		get_viewport().get_visible_rect().size
	)

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

	var screen_pos: Vector2 = cam.unproject_position(world_pos)

	var pos := screen_pos

	var screen_center := vp_size * 0.5

	var target_is_offscreen := (
		screen_pos.x < 0.0
		or screen_pos.x > vp_size.x
		or screen_pos.y < 0.0
		or screen_pos.y > vp_size.y
		or not in_front
	)

	if always_on_edge:
		var dir_from_center := (screen_pos - screen_center).normalized()

		if not in_front:
			var cam_right := cam_xf.basis.x
			var cam_up := cam_xf.basis.y

			dir_from_center = Vector2(
				cam_right.dot(to_target),
				-cam_up.dot(to_target)
			).normalized()

		if dir_from_center.length_squared() < 0.0001:
			dir_from_center = Vector2.UP

		pos = screen_center + dir_from_center * (
			min(vp_size.x, vp_size.y) * 0.5 - edge_margin
		)

	elif not in_front:
		var cam_right := cam_xf.basis.x
		var cam_up := cam_xf.basis.y

		var dir2 := Vector2(
			cam_right.dot(to_target),
			-cam_up.dot(to_target)
		).normalized()

		if dir2.length_squared() < 0.0001:
			dir2 = Vector2.UP

		pos = screen_center + dir2 * (
			min(vp_size.x, vp_size.y) * 0.5 - edge_margin
		)

	elif target_is_offscreen:
		var dir_from_center := screen_pos - screen_center

		if dir_from_center.length_squared() < 0.0001:
			dir_from_center = Vector2.UP

		dir_from_center = dir_from_center.normalized()

		pos = screen_center + dir_from_center * (
			min(vp_size.x, vp_size.y) * 0.5 - edge_margin
		)

	if clamp_on_screen or not in_front or always_on_edge:
		pos.x = clamp(
			pos.x,
			edge_margin,
			vp_size.x - edge_margin
		)

		pos.y = clamp(
			pos.y,
			edge_margin,
			vp_size.y - edge_margin
		)

	marker.visible = true

	if target_is_offscreen:
		var direction := pos - screen_center

		if direction.length_squared() > 0.0001:
			marker.rotation = atan2(
				direction.y,
				direction.x
			) - ARROW_UP_BIAS
	else:
		marker.rotation = 0.0

	if _use_ball_gap:
		marker.position = Vector2(
			pos.x - marker.size.x * 0.5,
			pos.y - marker.size.y - screen_gap_px
		)
	else:
		marker.position = pos - marker.size * 0.5
