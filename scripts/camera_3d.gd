extends Camera3D

@export var target_path: NodePath
@export var ball_target_path: NodePath

# First-person head height
@export var height: float = 1.6

# Kept for compatibility (ignored in first-person unless > 0)
@export var distance: float = 0.0
@export var min_distance: float = 0.0
@export var max_distance: float = 0.0

@export var mouse_sens: float = 0.008
@export var invert_y: bool = false
@export var follow_speed: float = 12.0

@export var collision_mask: int = 1
@export var collision_padding: float = 0.2

@onready var _is_mobile: bool = OS.has_feature("mobile")
var _look_touch_id: int = -1
@export var lead_factor: float = 0.0   # 0 = off; try 0.1..0.25 to predict motion a bit
var _aim_mode: bool = false
var _target: Node3D
var _target_ball: Node3D

var _yaw: float = 0.0
var _pitch: float = -0.25
var _min_pitch: float = deg_to_rad(-70.0)
var _max_pitch: float = deg_to_rad(75.0)
var _wheel_step: float = 0.7
var _captured: bool = true

func _ready() -> void:
	_target = get_node_or_null(target_path)
	_target_ball = get_node_or_null(ball_target_path)
	current = true
	_captured = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _is_mobile:
		_captured = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
	if _is_mobile:
		return

	# RMB toggles aim mode (release mouse for on-screen cursor while aiming)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_aim_mode = true
			_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			# sync yaw/pitch to current view before returning to mouse orbit
			var e := global_transform.basis.get_euler()
			_yaw = e.y
			_pitch = clamp(e.x, _min_pitch, _max_pitch)
			_aim_mode = false
			_captured = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	# Rotate camera from mouse when captured (not aiming)
	elif event is InputEventMouseMotion and _captured:
		var mm := event as InputEventMouseMotion
		var sy: float = (1.0 if invert_y else -1.0)
		_yaw -= mm.relative.x * mouse_sens
		_pitch += mm.relative.y * mouse_sens * sy
		_pitch = clamp(_pitch, _min_pitch, _max_pitch)

	# Keep wheel handlers (no-op in FP since distance==0)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - _wheel_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + _wheel_step)

# Camera3D script (add this function)
# In your Camera3D script
func set_aim_mode(on: bool) -> void:
	_aim_mode = on
	if _is_mobile:
		return
	_captured = not on
	if _captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	# Head/eye anchor on the player
	var focus_player: Vector3 = _target.global_transform.origin + Vector3(0.0, height, 0.0)
	var R := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var ball: Node3D = _target_ball
	var has_ball: bool = ball != null

	# ===== FIRST-PERSON (distance ~ 0) =====
	if distance <= 0.05:
		# Stick camera to head exactly; no smoothing, no prediction
		global_transform = Transform3D(R, focus_player)

		# If aiming, only adjust look direction
		if _aim_mode and has_ball:
			look_at(ball.global_transform.origin, Vector3.UP)
		return

	# ===== THIRD-PERSON (distance > 0) =====
	# Compute desired boom position from yaw/pitch
	var desired_pos: Vector3

	if _aim_mode:
		# Stay behind player when aiming (ignore mouse yaw/pitch)
		var player_forward: Vector3 = (-_target.global_transform.basis.z).normalized()
		desired_pos = focus_player - player_forward * distance
	else:
		# Normal mouse-orbit
		desired_pos = focus_player + R * Vector3(0, 0, -distance)

	# Wall avoidance from head to desired camera position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus_player, desired_pos)
	q.collision_mask = collision_mask
	q.hit_from_inside = true
	var hit := space.intersect_ray(q)
	if hit.size() > 0:
		var hit_pos: Vector3 = hit.position
		var back_dir: Vector3 = (focus_player - hit_pos).normalized()
		desired_pos = hit_pos + back_dir * collision_padding

	# Smooth follow and apply rotation
	var t: float = 1.0 - exp(-follow_speed * delta)
	var new_pos := global_transform.origin.lerp(desired_pos, t)

	# In normal mode, use R (mouse yaw/pitch). In aim mode, rotate to face ball/player.
	if _aim_mode:
		global_transform.origin = new_pos
		if has_ball:
			look_at(ball.global_transform.origin, Vector3.UP)
		else:
			look_at(focus_player + (-_target.global_transform.basis.z), Vector3.UP)
	else:
		global_transform = Transform3D(R, new_pos)
func _input(event: InputEvent) -> void:
	if not _is_mobile:
		return  # Desktop uses mouse code in _unhandled_input

	var vp_size := get_viewport().get_visible_rect().size

	# Start/stop a "look finger" on the RIGHT half of the screen
	if event is InputEventScreenTouch:
		if event.pressed:
			if _look_touch_id == -1 and event.position.x >= vp_size.x * 0.5:
				_look_touch_id = event.index
		else:
			if event.index == _look_touch_id:
				_look_touch_id = -1

	# While that finger moves, rotate camera by its delta
	if event is InputEventScreenDrag and event.index == _look_touch_id:
		var sy: float = (1.0 if invert_y else -1.0)
		_yaw -= event.relative.x * mouse_sens
		_pitch += event.relative.y * mouse_sens * sy
		_pitch = clamp(_pitch, _min_pitch, _max_pitch)
