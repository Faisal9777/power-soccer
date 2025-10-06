extends CharacterBody3D

@export var ball_path: NodePath = NodePath("../Ball")
@export var goal_path: NodePath = NodePath("../../Goal_B")

@export var move_speed: float = 6.0
@export var accel: float = 12.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Kick tuning ---
@export var kick_range: float = 1.0          # how close to be to kick
@export var kick_power: float = 18.0          # stronger so it’s obvious
@export var kick_up: float = 0.6              # small lift so it doesn’t dig into ground
@export var kick_align_dot: float = 0.2       # 0.2 = very permissive
@export var shoot_cooldown: float = 0.5       # time between kicks
@export var backoff_time: float = 0.35        # step back after kick
@export var backoff_speed: float = 5.0

var _ball: RigidBody3D
var _goal: Node3D
var _cooldown := 0.0
var _backoff_timer := 0.0
var _backoff_dir := Vector3.ZERO

func _ready() -> void:
	_ball = get_node(ball_path) as RigidBody3D
	_goal = get_node(goal_path) as Node3D

func _physics_process(delta: float) -> void:
	# gravity
	if !is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _cooldown > 0.0: _cooldown -= delta
	if _backoff_timer > 0.0:
		_backoff_timer -= delta
		_move_towards(_backoff_dir, delta, backoff_speed)
		move_and_slide()
		return

	# --- Chase the ball ---
	var to_ball := _ball.global_transform.origin - global_transform.origin
	to_ball.y = 0.0
	var dist := to_ball.length()
	var dir_to_ball := Vector3.ZERO if to_ball == Vector3.ZERO else to_ball.normalized()

	# close enough? try to kick toward goal_B
	if dist <= kick_range and _cooldown <= 0.0:
		_try_kick()
	else:
		_move_towards(dir_to_ball, delta, move_speed)

	move_and_slide()

func _move_towards(dir: Vector3, delta: float, target_speed: float) -> void:
	var desired := dir * target_speed
	var h := velocity; h.y = 0.0
	h = h.lerp(desired, clamp(accel * delta, 0.0, 1.0))
	velocity.x = h.x
	velocity.z = h.z

	# face the movement direction
	if dir != Vector3.ZERO:
		var yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clamp(8.0 * delta, 0.0, 1.0))

func _try_kick() -> void:
	# compute direction from ball to goal
	var ball_pos := _ball.global_transform.origin
	var goal_pos := _goal.global_transform.origin
	var to_goal := goal_pos - ball_pos
	to_goal.y = 0.0
	var dir := Vector3.ZERO if to_goal == Vector3.ZERO else to_goal.normalized()

	# (optional) require rough alignment of bot → ball with ball → goal
	var bot_to_ball := _ball.global_transform.origin - global_transform.origin
	bot_to_ball.y = 0.0
	var aligned := (Vector3.ZERO if bot_to_ball == Vector3.ZERO else bot_to_ball.normalized()).dot(dir) > kick_align_dot

	if aligned:
		var impulse := dir * kick_power + Vector3.UP * kick_up
		_ball.apply_impulse(impulse)
		_cooldown = shoot_cooldown

		# back off a little so we don’t stick to the ball
		_backoff_dir = -dir
		_backoff_timer = backoff_time
	else:
		# small nudge toward alignment if we’re on the wrong side
		_backoff_dir = (ball_pos - goal_pos).normalized()
		_backoff_timer = 0.2
