extends CharacterBody3D

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.5
@export var jump_velocity: float = 6.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var air_control: float = 0.4
@export var kick_force: float = 16.0
@export var kick_up: float = 3.0
@export var shoot_cooldown: float = 0.25

@export var show_aim_arrow: bool = true
@export var aim_min_len: float = 0.3
@export var aim_max_len: float = 3.0

@export var turn_speed: float = 12.0

var current_ball: RigidBody3D = null
var aim_active: bool = false
var aim_dir: Vector3 = Vector3.ZERO      # direction from player to contact point
var aim_contact: Vector3 = Vector3.ZERO  # world-space contact point on ball surface
var aim_arrow: Node3D = null
var arrow_shaft: MeshInstance3D = null
var arrow_head: MeshInstance3D = null

@onready var ground_ray: RayCast3D = $GroundRay
@onready var kick_area: Area3D = $KickArea

var _cooldowns := {
	"shoot": 0.0
}

func _face_camera_yaw(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target_yaw: float = cam.global_transform.basis.get_euler().y
	var cur := rotation
	cur.y = lerp_angle(cur.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))
	rotation = cur

func _ready() -> void:
	if $KickArea:
		$KickArea.body_entered.connect(_on_kick_area_body_entered)
		$KickArea.body_exited.connect(_on_kick_area_body_exited)
	_ensure_aim_arrow()

func _physics_process(delta: float) -> void:
	_update_cooldowns(delta)
	apply_gravity(delta)
	if _is_aiming():
		_face_ball_yaw(delta)   # only while RMB held & ball in area
	else:
		_face_camera_yaw(delta)
	var input_dir = _get_input_dir()
	_move(input_dir, delta)
	_handle_jump()
	_update_aim(delta)   # <-- add this
	_handle_shoot()

func _update_cooldowns(delta: float) -> void:
	for k in _cooldowns.keys():
		_cooldowns[k] = max(_cooldowns[k] - delta, 0.0)

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Small stick-to-ground if needed
		if velocity.y < 0.0:
			velocity.y = 0.0

func _get_input_dir() -> Vector3:
	var dir = Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	# Use camera-relative movement if you have a Camera3D in the scene
	var forward := (cam.basis * Vector3.FORWARD)
	forward.y = 0
	forward = forward.normalized()
	var right := (cam.basis * Vector3.RIGHT)
	right.y = 0
	right = right.normalized()

	if Input.is_action_pressed("move_forward"): dir += forward
	if Input.is_action_pressed("move_back"):    dir -= forward
	if Input.is_action_pressed("move_right"):   dir += right
	if Input.is_action_pressed("move_left"):    dir -= right

	return dir.normalized()

func _move(input_dir: Vector3, delta: float) -> void:
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	var lateral_vel := velocity
	lateral_vel.y = 0.0

	var target_vel = input_dir * target_speed

	# Ground vs air control
	var accel := 12.0 if is_on_floor() else 12.0 * air_control

	lateral_vel = lateral_vel.lerp(target_vel, clamp(accel * delta, 0.0, 1.0))

	velocity.x = lateral_vel.x
	velocity.z = lateral_vel.z

	# Rotate towards movement direction (optional)
	#if input_dir.length() > 0.1:
		#look_at(global_transform.origin + input_dir, Vector3.UP)

	move_and_slide()

func _handle_jump() -> void:
	# Use ray or is_on_floor() for robust ground check
	var grounded = is_on_floor() or (ground_ray and ground_ray.is_colliding())
	if grounded and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

func _handle_shoot() -> void:
	if aim_active and current_ball != null and Input.is_action_just_pressed("shoot") and _cooldowns["shoot"] == 0.0:
		_cooldowns["shoot"] = shoot_cooldown
		_kick_at_contact()

func _perform_kick() -> void:
	if not is_instance_valid(kick_area):
		return
	var fwd := -global_transform.basis.z.normalized()

	# pick the nearest ball in the area (avoids double-kicking multiple balls)
	var nearest: RigidBody3D = null
	var best_d := INF

	for body in kick_area.get_overlapping_bodies():
		print("  •", body.name, "groups:", body.get_groups())
		if body is RigidBody3D and body.is_in_group("ball"):
			print("the ball is found")
			var d := global_transform.origin.distance_to(body.global_transform.origin)
			if d < best_d:
				best_d = d
				nearest = body

	if nearest:
		# optional: only kick if roughly in front of the player
		var to_ball := (nearest.global_transform.origin - global_transform.origin).normalized()
		if fwd.dot(to_ball) >= 0.2:  # -1..1; >0 means in front cone
			var impulse := fwd * kick_force + Vector3.UP * kick_up
			nearest.apply_impulse(impulse)
			
func _ensure_aim_arrow() -> void:
	if not show_aim_arrow:
		return
	aim_arrow = Node3D.new()
	aim_arrow.name = "AimArrow"
	add_child(aim_arrow)

	# ---- Shaft: Box aligned with local Z so we can just scale Z for length
	arrow_shaft = MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.08, 0.08, 1.0)  # 1.0 long along Z
	arrow_shaft.mesh = shaft_mesh
	# Put the box so its back is at z = 0 and tip is at z = -1 (center at -0.5)
	arrow_shaft.position = Vector3(0, 0, -0.5)
	aim_arrow.add_child(arrow_shaft)

	# ---- Head: small cone at the tip. CylinderMesh with top_radius=0 = cone.
	arrow_head = MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0   # cone
	head_mesh.bottom_radius = 0.12
	head_mesh.height = 0.24
	arrow_head.mesh = head_mesh
	# Cylinders point along Y; rotate so it points along -Z
	arrow_head.rotation_degrees.x = 90.0
	# Place at the tip (local -Z). After scaling Z, this will move with the tip.
	arrow_head.position = Vector3(0, 0, -1.0)
	aim_arrow.add_child(arrow_head)

	_show_arrow(false)

func _show_arrow(v: bool) -> void:
	if arrow_shaft: arrow_shaft.visible = v
	if arrow_head: arrow_head.visible = v

func _get_ball_radius(ball: RigidBody3D) -> float:
	# Try to find a SphereShape3D radius; fallback to ~0.12m
	var r := 0.12
	for child in ball.get_children():
		if child is CollisionShape3D and child.shape is SphereShape3D:
			r = child.shape.radius
			break
	return r

func _update_aim(delta: float) -> void:
	# Arrow only exists while a ball is in the KickArea
	if not aim_active or current_ball == null:
		_show_arrow(false)
		return

	var C: Vector3 = current_ball.global_transform.origin
	var R: float = _get_ball_radius(current_ball)

	if _is_aiming():
		# --- Mouse-driven contact (ray -> sphere)
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			_show_arrow(false)
			return
		var mp: Vector2 = get_viewport().get_mouse_position()
		var ro: Vector3 = cam.project_ray_origin(mp)
		var rd: Vector3 = cam.project_ray_normal(mp).normalized()

		var oc: Vector3 = ro - C
		var b: float = 2.0 * rd.dot(oc)
		var c: float = oc.dot(oc) - R * R
		var disc: float = b * b - 4.0 * c
		var contact: Vector3 = Vector3.ZERO
		if disc >= 0.0:
			var sd: float = sqrt(disc)
			var t1: float = (-b - sd) * 0.5
			var t2: float = (-b + sd) * 0.5
			var t: float = -1.0
			if t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2
			if t > 0.0:
				contact = ro + rd * t
		if contact == Vector3.ZERO:
			var t_closest: float = -rd.dot(oc)
			var closest: Vector3 = ro + rd * maxf(t_closest, 0.0)
			var dir_to: Vector3 = closest - C
			if dir_to == Vector3.ZERO:
				dir_to = global_transform.origin - C
			contact = C + dir_to.normalized() * R
		aim_contact = contact
	else:
		# --- Fixed contact: front-facing surface toward the player (no mouse)
		var dir := (C - global_transform.origin).normalized()
		aim_contact = C - dir * R

	# Common: drive the arrow from player -> contact
	var vec: Vector3 = aim_contact - global_transform.origin
	if vec == Vector3.ZERO:
		_show_arrow(false)
		return
	var dist: float = maxf(vec.length(), aim_min_len)  # no upper clamp
	aim_dir = vec.normalized()

	_show_arrow(true)
	aim_arrow.global_transform.origin = global_transform.origin
	aim_arrow.look_at(aim_arrow.global_transform.origin + aim_dir, Vector3.UP)
	aim_arrow.scale = Vector3(1.0, 1.0, dist)
func _kick_at_contact() -> void:
	if not is_instance_valid(current_ball):
		return

	# Impulse points from CONTACT toward CENTER (bottom hit -> upward, top hit -> downward, etc.)
	var C := current_ball.global_transform.origin
	var hit_point := aim_contact
	var impulse_dir := (C - hit_point).normalized()

	var linear := impulse_dir * kick_force
	var lift := Vector3.UP * kick_up
	var J := linear + lift

	# Apply at contact point to generate spin (torque = r x J)
	var local_contact := current_ball.to_local(hit_point)
	current_ball.apply_impulse(J, local_contact)

func _on_kick_area_body_entered(body: Node) -> void:
	if body is RigidBody3D and body.is_in_group("ball"):
		current_ball = body
		aim_active = true
		var C := current_ball.global_transform.origin
		var R := _get_ball_radius(current_ball)
		var dir := (C - global_transform.origin).normalized()
		aim_contact = C - dir * R
		aim_dir = (aim_contact - global_transform.origin).normalized()

func _on_kick_area_body_exited(body: Node) -> void:
	if body == current_ball:
		current_ball = null
		aim_active = false
		_show_arrow(false)
		
func _is_aiming() -> bool:
	return aim_active and current_ball != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
func _face_ball_yaw(delta: float) -> void:
	if current_ball == null: return
	var to_ball: Vector3 = current_ball.global_transform.origin - global_transform.origin
	to_ball.y = 0.0
	if to_ball == Vector3.ZERO: return
	var target_yaw: float = atan2(-to_ball.x, -to_ball.z) # -Z is forward
	var cur := rotation
	cur.y = lerp_angle(cur.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))
	rotation = cur
