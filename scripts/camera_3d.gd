extends Camera3D

@export var target_path: NodePath
@export var height: float = 1.6
@export var distance: float = 5.0
@export var min_distance: float = 2.5
@export var max_distance: float = 8.0
@export var mouse_sens: float = 0.008
@export var invert_y: bool = false
@export var follow_speed: float = 12.0
@export var collision_mask: int = 1
@export var collision_padding: float = 0.2

var _target: Node3D
var _yaw: float = 0.0
var _pitch: float = -0.25
var _min_pitch: float = deg_to_rad(-70.0)
var _max_pitch: float = deg_to_rad(75.0)
var _wheel_step: float = 0.7
var _captured: bool = true

func _ready() -> void:
	_target = get_node_or_null(target_path)
	current = true
	_captured = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	# toggle capture with Esc
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_captured = not _captured
		if _captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# mouse rotates the camera (always-on)
	if event is InputEventMouseMotion and _captured:
		var mm := event as InputEventMouseMotion
		var sy: float = (1.0 if invert_y else -1.0)
		_yaw -= mm.relative.x * mouse_sens
		_pitch += mm.relative.y * mouse_sens * sy
		_pitch = clamp(_pitch, _min_pitch, _max_pitch)

	# wheel zoom
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - _wheel_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + _wheel_step)

func _process(delta: float) -> void:
	if _target == null:
		return

	# 1) Mouse-driven orientation only (no look_at):
	var R := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)  # rotation from yaw/pitch

	# 2) Focus point above the player
	var focus: Vector3 = _target.global_transform.origin + Vector3(0, height, 0)

	# 3) Desired position = focus + rotated back offset
	var desired_pos: Vector3 = focus + R * Vector3(0, 0, -distance)

	# 4) Wall avoidance (ray from focus to desired_pos)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired_pos)
	q.collision_mask = collision_mask
	q.hit_from_inside = true
	var hit := space.intersect_ray(q)
	if hit.size() > 0:
		var hit_pos: Vector3 = hit.position
		var back_dir: Vector3 = (focus - hit_pos).normalized()
		desired_pos = hit_pos + back_dir * collision_padding

	# 5) Smoothly move camera position
	var t := 1.0 - exp(-follow_speed * delta)
	global_transform.origin = global_transform.origin.lerp(desired_pos, t)

	# 6) Set rotation directly from yaw/pitch (NO look_at)
	global_transform.basis = R
