extends CharacterBody3D

# --- References ----
@export var ball_path: NodePath = NodePath("../Ball")        # Bot is at Scene/Bot → ball is Scene/Ball
@export var goal_path: NodePath = NodePath("../../Goal_B")   # Root sibling

# --- Tuning ----
@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var accel: float = 12.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var stop_dist: float = 0.8           # stop before overlapping the ball
@export var shoot_cooldown: float = 0.7
@export var kick_power: float = 10.0
@export var kick_up: float = 1.0
@export var shoot_align_dot: float = 0.6     # 1 = perfectly lined up

var _ball: RigidBody3D
var _goal: Node3D
var _cooldown: float = 0.0

enum { CHASE_BALL, LINE_UP_SHOT }
var _state: int = CHASE_BALL

func _ready() -> void:
	_ball = get_node(ball_path) as RigidBody3D
	_goal = get_node(goal_path) as Node3D

func _physics_process(delta: float) -> void:
	# gravity
	if !is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _cooldown > 0.0:
		_cooldown -= delta

	var to_ball: Vector3 = _ball.global_transform.origin - global_transform.origin
	to_ball.y = 0.0
	var dist_to_ball := to_ball.length()
	var dir_to_ball := Vector3.ZERO if to_ball == Vector3.ZERO else to_ball.normalized()


	match _state:
		CHASE_BALL:
			_move_towards(dir_to_ball, delta, sprint_speed)
			if dist_to_ball <= stop_dist:
				_state = LINE_UP_SHOT

		LINE_UP_SHOT:
			var ball_to_goal := (_goal.global_transform.origin - _ball.global_transform.origin); ball_to_goal.y = 0.0
			var bot_to_ball := (_ball.global_transform.origin - global_transform.origin); bot_to_ball.y = 0.0
			var align := bot_to_ball.normalized().dot(ball_to_goal.normalized())

			if align > shoot_align_dot and _cooldown <= 0.0:
				_kick_towards_goal()
				_cooldown = shoot_cooldown
				_state = CHASE_BALL
			else:
				# move to a point behind the ball (opposite the goal) to line up a shot
				var behind_point := _ball.global_transform.origin - ball_to_goal.normalized() * 1.2
				var to_point := behind_point - global_transform.origin
				to_point.y = 0.0
				_move_towards(to_point.normalized(), delta, move_speed)
				if dist_to_ball > stop_dist * 1.5:
					_state = CHASE_BALL

	move_and_slide()

func _move_towards(dir: Vector3, delta: float, target_speed: float) -> void:
	var desired := dir * target_speed
	var h := velocity; h.y = 0.0
	h = h.lerp(desired, clamp(accel * delta, 0.0, 1.0))
	velocity.x = h.x
	velocity.z = h.z

	# rotate to face motion
	if dir != Vector3.ZERO:
		var target_yaw := atan2(-dir.x, -dir.z) # -Z forward
		var cur := rotation
		cur.y = lerp_angle(cur.y, target_yaw, clamp(8.0 * delta, 0.0, 1.0))
		rotation = cur

func _kick_towards_goal() -> void:
	var ball_pos := _ball.global_transform.origin
	var to_goal := _goal.global_transform.origin - ball_pos
	to_goal.y = 0.0
	var impulse := to_goal.normalized() * kick_power + Vector3.UP * kick_up
	_ball.apply_impulse(impulse)
