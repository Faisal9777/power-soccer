extends Camera3D

@export var target_path: NodePath
@export var ball_target_path: NodePath

# First-person head height
@export var height: float = 1.6

# Distance: FP if ~0, TP if > 0
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

@export var lead_factor: float = 0.0   # (not used yet) try 0.1..0.25 to lead targets slightly

var _aim_mode: bool = false
var _target: Node3D
var _target_ball: Node3D
@export var joystick_path :NodePath
@onready var joystick := get_node_or_null(joystick_path)
var _yaw: float = 0.0
var _pitch: float = -0.25
var _min_pitch: float = deg_to_rad(-70.0)
var _max_pitch: float = deg_to_rad(75.0)
var _wheel_step: float = 0.7
var _captured: bool = true
var _pending_face_point: Vector3 = Vector3.ZERO
var _has_pending_face: bool = false
@export var front_is_plus_z: bool = true
func _ready() -> void:
	_target = get_node_or_null(target_path)
	_target_ball = get_node_or_null("Ball")
	# Auto-activate on clients / editor. On dedicated servers, activation will no-op.
	activate()

# ----------------------------
# Activation / Deactivation API
# ----------------------------
func activate() -> void:
	# If this is a dedicated headless server, don't run a camera.
	if OS.has_feature("server"):
		_set_active(false)
		return
	_set_active(true)
	# Mouse capture/visibility based on platform and aim state
	if _is_mobile:
		_captured = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_captured = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
func _touch_on_joystick(pos: Vector2) -> bool:
	if joystick:
		return joystick.get_global_rect().has_point(pos)
	return false
	
func deactivate() -> void:
	_set_active(false)
	# Release mouse if we had captured it
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_active(on: bool) -> void:
	current = on
	set_process(on)
	set_physics_process(on)
	set_process_input(on)
	set_process_unhandled_input(on)

# Optional helpers (useful for runtime swaps)
func set_target(player: Node3D) -> void:
	_target = player
	
func set_ball(ball_path: NodePath) -> void:
	var ball := get_node(ball_path)
	_target_ball = ball

# Public: ask the camera to face a world point next physics tick
func face_towards(target_pos: Vector3, from: Vector3) -> void:
	#print("face towards is called for unique id of: ", multiplayer.get_unique_id()) 
	#print("for the player name: ", _target.name) 
	#print("whoose position is: ", _target.global_position) 
	#print("target_pos: ", target_pos)
	#print("camera's position should be: ", from)
	if _target == null:
		return
	if from.distance_squared_to(target_pos) < 1e-8:
		return

	# Start from the provided world position
	var desired_pos: Vector3 = from

	# Optional: line-of-sight push (ray: target -> camera) to avoid walls
	if collision_mask != 0:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(target_pos, desired_pos)
		q.collision_mask = collision_mask
		q.hit_from_inside = true
		var hit := space.intersect_ray(q)
		if hit.size() > 0:
			var hit_pos: Vector3 = hit.position
			var dir_tc: Vector3 = (desired_pos - target_pos).normalized() # target→camera
			desired_pos = hit_pos - dir_tc * collision_padding            # just before the obstacle

	# Build basis so camera forward points to target
	var dir: Vector3 = (target_pos - desired_pos).normalized()          # world look dir
	if front_is_plus_z:
		dir = -dir                                                      # flip for +Z-front rigs

	var look_basis := Basis().looking_at(dir, Vector3.UP)
	look_basis = look_basis.orthonormalized()

	global_transform = Transform3D(look_basis, desired_pos)

	# Keep yaw/pitch in sync for later frames
	var e: Vector3 = look_basis.get_euler(EULER_ORDER_YXZ)
	_yaw = wrapf(e.y, -PI, PI)
	_pitch = clamp(e.x, -1.55, 1.55)

	if !current:
		current = true
# ----------------------------
# Public toggle for UI/other code
# ----------------------------
func set_aim_mode(on: bool) -> void:
	_aim_mode = on
	if _is_mobile:
		return
	_captured = not on
	if _captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# ----------------------------
# Desktop input (mouse)
# ----------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _is_mobile:
		return  # mobile path handled in _input()

	# RMB toggles aim mode (release mouse for on-screen cursor while aiming)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_aim_mode = true
			_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
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

	# Wheel zoom
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - _wheel_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + _wheel_step)

# ----------------------------
# Mobile input (touch look)
# ----------------------------
func _input(event: InputEvent) -> void:
	if not _is_mobile:
		return

	var vp_size := get_viewport().get_visible_rect().size

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			# ignore touches on joystick UI
			if _touch_on_joystick(st.position):
				return
			if _look_touch_id == -1 and st.position.x >= vp_size.x * 0.5:
				_look_touch_id = st.index
		else:
			if st.index == _look_touch_id:
				_look_touch_id = -1

	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		# ignore joystick area drags
		if _touch_on_joystick(sd.position):
			return
		if sd.index == _look_touch_id:
			var sy: float = (1.0 if invert_y else -1.0)
			_yaw   -= sd.relative.x * mouse_sens
			_pitch += sd.relative.y * mouse_sens * sy
			_pitch  = clamp(_pitch, _min_pitch, _max_pitch)

# ----------------------------
# Camera follow / collision / FP/TP logic
# ----------------------------
func _look() -> void:
	global_position = Vector3(0.000003, 3.100583, 33.0287)
	print("looking")
	print("camera's position: ", global_position)
	
	var pos := Vector3.ZERO
	print("target position: ", pos)
	look_at(pos)
func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var t_player := _target.global_transform
	var focus     := t_player.origin + Vector3(0.0, height, 0.0)

	# Use AimPivot if present, else fall back to the player body
	var pivot := _target.get_node_or_null("AimPivot") as Node3D
	var t_piv: Transform3D = pivot.global_transform if is_instance_valid(pivot) else t_player
	var forward := (-t_piv.basis.z).normalized()  # includes vertical pitch

	# ===== First-person =====
	if distance <= 0.05:
		global_transform.origin = focus
		look_at(focus + forward, Vector3.UP)
		return

	# ===== Third-person =====
	var desired_pos := focus - forward * distance

	# Wall avoidance: from head to desired camera position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired_pos)
	q.collision_mask = collision_mask
	q.hit_from_inside = true
	var hit := space.intersect_ray(q)
	if hit.size() > 0:
		var hit_pos: Vector3 = hit.position
		var back_dir: Vector3 = (focus - hit_pos).normalized()
		desired_pos = hit_pos + back_dir * collision_padding

	# Smooth follow and face the same direction as the character
	var t := 1.0 - exp(-follow_speed * delta)
	global_transform.origin = global_transform.origin.lerp(desired_pos, t)
	look_at(focus + forward, Vector3.UP)
