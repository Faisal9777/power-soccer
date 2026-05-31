extends Camera3D

@export var target_path: NodePath
@export var ball_target_path: NodePath

# First-person head height
@export var height: float = 1.6

# Distance: FP if ~0, TP if > 0
@export var distance: float = 0.0          # ✅ start in first-person
@export var min_distance: float = 0.0      # FP distance
@export var max_distance: float = 10.0
@export var goal_third_person_distance: float = 6.0  # TP distance when toggled

@export var invert_y: bool = false
@export var follow_speed: float = 12.0

@export var collision_mask: int = 1
@export var collision_padding: float = 0.2

@onready var _is_mobile: bool = OS.has_feature("mobile")

var rotation_manager : LocalController

var _look_touch_id: int = -1

@export var lead_factor: float = 0.0   # (not used yet) try 0.1..0.25 to lead targets slightly

var _dy_accum: float = 0.0    # yaw delta since last read
var _dp_accum: float = 0.0    # pitch delta since last read
@export var self_layer_ui: int = 19
var _self_layer_mask: int
var _aim_mode: bool = false
var _target: Node3D
var _follow_target: Node3D
var _target_ball: Node3D
@export var joystick_path :NodePath
var joystick: Control = null
@export var _yaw: float = 0.0
@export var _pitch: float = -0.25

var _wheel_step: float = 0.7
var _captured: bool = true
var _pending_face_point: Vector3 = Vector3.ZERO
var _has_pending_face: bool = false
var _is_frozen := false
@export var front_is_plus_z: bool = true
var is_debugging := false
func _ready() -> void:
	_self_layer_mask = 1 << (self_layer_ui - 1)
	_target = get_node_or_null(target_path)
	_target_ball = get_node_or_null("Ball")
	activate()
	_apply_fp_tp_self_visibility()  # ✅ ensure correct on start

func snap_to(target_transform : Transform3D) -> void:
	# -------------------------------------------------
	# SNAP FOLLOW TARGET
	# -------------------------------------------------
	if is_instance_valid(_follow_target) and _follow_target.has_method("snap_to"):

		_follow_target.snap_to(target_transform)
	# -------------------------------------------------
	# BUILD CURRENT CAMERA BASIS
	# -------------------------------------------------
	var cam_basis := (
		Basis(Vector3.UP, _yaw)
		* Basis(Vector3.RIGHT, _pitch)
	)

	var fwd_3d := -cam_basis.z

	# -------------------------------------------------
	# COMPUTE FINAL CAMERA POSITION
	# (the exact place smoothing would converge to)
	# -------------------------------------------------
	var desired_pos := _compute_desired_camera_position(
		target_transform,
		fwd_3d
	)

	global_position = desired_pos

func set_joystick(n: Control) -> void:
	joystick = n

func set_rotation_source(r_manager : LocalController) -> void:
	rotation_manager = r_manager

# ----------------------------
# Activation / Deactivation API
# ----------------------------
func activate() -> void:
	if OS.has_feature("server"):
		_set_active(false)
		return
	_set_active(true)
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
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_active(on: bool) -> void:
	current = on
	set_process(on)
	set_physics_process(on)
	set_process_input(on)
	set_process_unhandled_input(on)

func set_follow(target: Node) -> void:
	_follow_target = target

func focus_at(target: Node) -> void:
	_target = target


# ----------------------------
# Public toggle for UI/other code
# ----------------------------
func set_aim_mode(on: bool) -> void:
	_aim_mode = on
	if not _is_mobile:
		_captured = not on
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE)

# ----------------------------
# Desktop input (mouse)
# ----------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _is_mobile:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_aim_mode = true
			_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			_aim_mode = false
			_captured = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - _wheel_step)
			_apply_fp_tp_self_visibility()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + _wheel_step)
			_apply_fp_tp_self_visibility()

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
			if _touch_on_joystick(st.position):
				return
			if _look_touch_id == -1:
				_look_touch_id = st.index
		else:
			if st.index == _look_touch_id:
				_look_touch_id = -1

	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touch_on_joystick(sd.position):
			return
		if sd.index == _look_touch_id:
			var sy: float = (1.0 if invert_y else -1.0)
			#_yaw   -= sd.relative.x * mouse_sens
			#_pitch += sd.relative.y * mouse_sens * sy
			#_pitch  = clamp(_pitch, _min_pitch, _max_pitch)
#
			#_dy_accum += -sd.relative.x * mouse_sens
			#_dp_accum +=  sd.relative.y * mouse_sens * sy

func consume_facing_delta() -> Dictionary:
	var dy := _dy_accum
	var dp := _dp_accum
	_dy_accum = 0.0
	_dp_accum = 0.0
	return {"yaw_delta": dy, "pitch_delta": dp}


func freeze_rotation(trigger) -> void:
	_is_frozen = trigger

func _process(delta: float) -> void:
	_update_facing(delta)
	

func _process2(delta: float) -> void:
	if not is_instance_valid(_target):
		return

	var t_target := _target.global_transform
	var focus := t_target.origin + Vector3(0.0, height, 0.0)

	# Focus mode: look at ball from focus point
	if _aim_mode and is_instance_valid(_target_ball):
		global_position = focus
		look_at(_target_ball.global_position, Vector3.UP)
		return

	# Use aim direction if your proxy includes it; otherwise just use forward
	# (Optionally: store forward basis in the proxy if you want.)
	var fwd_3d := -t_target.basis.z
	var fwd_xz := Vector3(fwd_3d.x, 0.0, fwd_3d.z)
	if fwd_xz.length_squared() < 1e-6:
		fwd_xz = Vector3.FORWARD
	else:
		fwd_xz = fwd_xz.normalized()

	# First-person
	if distance <= 0.05:
		global_position = focus
		look_at(focus + fwd_3d.normalized(), Vector3.UP)
		return

	# Third-person desired position
	var desired_pos := focus - fwd_xz * distance

	# Wall avoidance ray
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired_pos)
	q.collision_mask = collision_mask
	q.hit_from_inside = true

	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var hit_pos: Vector3 = hit.position
		var back_dir: Vector3 = (focus - hit_pos).normalized()
		desired_pos = hit_pos + back_dir * collision_padding

	# Smooth camera rig movement
	var t := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired_pos, t)
	look_at(focus + fwd_3d.normalized(), Vector3.UP)

func init(proxy, joystick) -> void:
	activate()
	current = true
	near = max(near, 0.12)
	set_joystick(joystick)
	set_follow(proxy)

func _update_facing(delta) -> void:
	if rotation_manager:
		var sy: float = (-1.0 if invert_y else 1.0)
		_yaw = rotation_manager.look_yaw
		_pitch = rotation_manager.look_pitch
		_apply_rotation(delta)

func _apply_rotation(delta: float) -> void:

	var target_transform := (
		_follow_target.global_transform
		if is_instance_valid(_follow_target)
		else global_transform
	)

	if not _is_frozen:

		if is_instance_valid(_target):

			var dir := (
				_target.global_position
				- global_position
			).normalized()

			_yaw = atan2(dir.x, dir.z)

			_pitch = clamp(
				asin(dir.y),
				rotation_manager.min_pitch,
				rotation_manager.max_pitch
			)

	var cam_basis := (
		Basis(Vector3.UP, _yaw)
		* Basis(Vector3.RIGHT, _pitch)
	)

	var fwd_3d := -cam_basis.z

	var desired_pos := _compute_desired_camera_position(
		target_transform,
		fwd_3d
	)
	# -------------------------------------------------
	# SMOOTH FOLLOW
	# -------------------------------------------------
	var t := 1.0 - exp(-follow_speed * delta)

	global_position = global_position.lerp(
		desired_pos,
		t
	)

	look_at(
		global_position + fwd_3d,
		Vector3.UP
	)

# ----------------------------
# FP/TP helpers (called from Game/World/UI)
# ----------------------------
func set_goal_third_person_view() -> void:
	_aim_mode = false
	distance = clamp(goal_third_person_distance, min_distance, max_distance)
	_apply_fp_tp_self_visibility()

func set_first_person_view() -> void:
	distance = min_distance
	_apply_fp_tp_self_visibility()

func _apply_fp_tp_self_visibility() -> void:
	return
	if distance <= 0.05:
		# First person:
		# hide player body
		cull_mask &= ~RenderLayers.PLAYER_BODY_MASK
	else:
		# Third person:
		# show player body
		cull_mask |= RenderLayers.PLAYER_BODY_MASK

	# Always show UI-related visuals
	cull_mask |= RenderLayers.PLAYER_UI_MASK

func _compute_desired_camera_position(target_transform: Transform3D, fwd_3d: Vector3) -> Vector3:

	var focus := (
		target_transform.origin
		+ Vector3(0.0, height, 0.0)
	)

	var fwd_xz := Vector3(
		fwd_3d.x,
		0.0,
		fwd_3d.z
	).normalized()
	# -------------------------------------------------
	# ORBIT POSITION
	# -------------------------------------------------
	var desired_pos := (
		focus
		- fwd_xz * distance
	)
	# -------------------------------------------------
	# WALL AVOIDANCE
	# -------------------------------------------------
	var space := get_world_3d().direct_space_state

	var q := PhysicsRayQueryParameters3D.create(
		focus,
		desired_pos
	)

	q.collision_mask = collision_mask
	q.hit_from_inside = true

	var hit := space.intersect_ray(q)

	if not hit.is_empty():

		var back_dir : Vector3= (
			focus - hit.position
		).normalized()

		desired_pos = (
			hit.position
			+ back_dir * collision_padding
		)

	return desired_pos

func get_center_ray() -> Dictionary:
	var vp := get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	var ro := project_ray_origin(center)
	var rd := project_ray_normal(center).normalized()
	return {"origin": ro, "dir": rd}
