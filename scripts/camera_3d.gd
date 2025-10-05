extends Camera3D

@export var target_path: NodePath
@export var ball_target_path: NodePath
@export var height: float = 1.6
@export var distance: float = 5.0
@export var min_distance: float = 2.5
@export var max_distance: float = 8.0
@export var mouse_sens: float = 0.008
@export var invert_y: bool = false
@export var follow_speed: float = 12.0
@export var collision_mask: int = 1
@export var collision_padding: float = 0.2


var _aim_mode: bool = false

var _target: Node3D
var _yaw: float = 0.0
var _pitch: float = -0.25
var _min_pitch: float = deg_to_rad(-70.0)
var _max_pitch: float = deg_to_rad(75.0)
var _wheel_step: float = 0.7
var _captured: bool = true
var _target_ball : Node3D

func _ready() -> void:
	#print("camera is getting called")
	# Disable entirely on dedicated server
	#if multiplayer.is_server() and multiplayer.get_peers().size() > 0:
		#current = false
		#set_process(false)
		#set_process_unhandled_input(false)
		#return

	_target = get_node_or_null(target_path)
	if _target == null:
		_target = get_parent() as Node3D   # <-- Player is the parent
	_target_ball = get_node_or_null(ball_target_path)
	if not _target_ball:
		print("could not find the ball trying another way")
		_target_ball = get_node_or_null("Ball")
	if not _target_ball:
		print("still could not find the ball will cause error")
		
	 # Dedicated server? bail out
	#activate()

func activate() -> void:
	if OS.has_feature("server"):
		_set_active(false)
		return
	_set_active(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func deactivate() -> void:
	_set_active(false)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_active(on: bool) -> void:
	current = on
	visible = on
	set_process(on)
	set_process_unhandled_input(on)

func set_ball(ball: Node3D) -> void:
	_target_ball = ball
	
func set_target(player: Node3D) -> void:
	_target = player

func _unhandled_input(event: InputEvent) -> void:
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
	# Only rotate camera from mouse when captured (i.e., not aiming)
	elif event is InputEventMouseMotion and _captured:
		var mm := event as InputEventMouseMotion
		var sy: float = (1.0 if invert_y else -1.0)
		_yaw -= mm.relative.x * mouse_sens
		_pitch += mm.relative.y * mouse_sens * sy
		_pitch = clamp(_pitch, _min_pitch, _max_pitch)

	# Wheel zoom (disable during aim if you prefer: add `and not _aim_mode`)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - _wheel_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + _wheel_step)
func _process(delta: float) -> void:
	if _target == null:
		return

	# Read ball reference (typed to avoid Variant warnings)
	#var ball: Node3D = _target.get("current_ball") as Node3D
	var ball: Node3D = _target_ball
	var has_ball: bool = ball != null
	
	# Player head-height focus (used for "behind player" positioning)
	var focus_player: Vector3 = _target.global_transform.origin + Vector3(0, height, 0)

	if _aim_mode and has_ball:
		# ===== AIM MODE =====
		# 1) POSITION: stay behind the player (ignore mouse yaw/pitch & ball)
		var player_forward: Vector3 = (-_target.global_transform.basis.z).normalized() # -Z is forward
		var desired_pos: Vector3 = focus_player - player_forward * distance
		# (optional shoulder offset)
		# var player_right: Vector3 = _target.global_transform.basis.x.normalized()
		# desired_pos += player_right * 0.3

		# 2) Wall avoidance from player focus -> desired camera pos (NOT from ball)
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(focus_player, desired_pos)
		q.collision_mask = collision_mask
		q.hit_from_inside = true
		var hit := space.intersect_ray(q)
		if hit.size() > 0:
			var hit_pos: Vector3 = hit.position
			var back_dir: Vector3 = (focus_player - hit_pos).normalized()
			desired_pos = hit_pos + back_dir * collision_padding

		# 3) Smoothly move camera to that "behind player" spot
		var t: float = 1.0 - exp(-follow_speed * delta)
		global_transform.origin = global_transform.origin.lerp(desired_pos, t)

		# 4) ROTATION: look at the ball (this does not move the camera)
		var focus_ball: Vector3 = ball.global_transform.origin
		look_at(focus_ball, Vector3.UP)
		return  # stop here; do not run normal mouse-orbit block

	# ===== NORMAL MODE (no RMB) =====
	# Mouse-driven orbit around player (position + rotation from yaw/pitch)
	var R := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var desired_pos_norm: Vector3 = focus_player + R * Vector3(0, 0, -distance)

	# Wall avoidance (player focus -> desired camera pos)
	var space2 := get_world_3d().direct_space_state
	var q2 := PhysicsRayQueryParameters3D.create(focus_player, desired_pos_norm)
	q2.collision_mask = collision_mask
	q2.hit_from_inside = true
	var hit2 := space2.intersect_ray(q2)
	if hit2.size() > 0:
		var hit_pos2: Vector3 = hit2.position
		var back_dir2: Vector3 = (focus_player - hit_pos2).normalized()
		desired_pos_norm = hit_pos2 + back_dir2 * collision_padding

	# Smooth move + apply mouse yaw/pitch rotation
	var t2: float = 1.0 - exp(-follow_speed * delta)
	global_transform.origin = global_transform.origin.lerp(desired_pos_norm, t2)
	global_transform.basis = R
