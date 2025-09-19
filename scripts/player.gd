extends CharacterBody3D

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.5
@export var jump_velocity: float = 6.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var air_control: float = 0.4
@export var kick_force: float = 16.0
@export var kick_up: float = 3.0
@export var shoot_cooldown: float = 0.25

@onready var ground_ray: RayCast3D = $GroundRay
@onready var kick_area: Area3D = $KickArea

var _cooldowns := {
	"shoot": 0.0
}

func _physics_process(delta: float) -> void:
	_update_cooldowns(delta)
	apply_gravity(delta)
	var input_dir = _get_input_dir()
	_move(input_dir, delta)
	_handle_jump()
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
	if input_dir.length() > 0.1:
		look_at(global_transform.origin + input_dir, Vector3.UP)

	move_and_slide()

func _handle_jump() -> void:
	# Use ray or is_on_floor() for robust ground check
	var grounded = is_on_floor() or (ground_ray and ground_ray.is_colliding())
	if grounded and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

func _handle_shoot() -> void:
	if Input.is_action_just_pressed("shoot") and _cooldowns["shoot"] == 0.0:
		_cooldowns["shoot"] = shoot_cooldown
		_perform_kick()

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
