extends CharacterBody3D

# --- Scene refs ---
@export var ball_path: NodePath = NodePath("../Ball")
@export var goal_path: NodePath = NodePath("../../Goal_B")

# --- Movement ---
@export var walk_speed: float = 6.0
@export var accel: float = 12.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Shoot (kick) ---
@export var kick_range: float = 1.0
@export var kick_power: float = 16.0
@export var kick_up: float = 0.6
@export var shoot_cooldown: float = 0.4

# --- Dribble (small nudges while moving) ---
@export var dribble_range: float = 1.2
@export var dribble_cooldown: float = 0.45
@export var dribble_impulse: float = 0.9
@export var dribble_forward_bias: float = 0.35   # extra push forward so ball stays ahead
@export var dribble_up: float = 0.15
@export var dribble_cone_dot: float = 0.0        # -1..1; 0 = 90° cone in front

# --- Tackle (dash + poke) ---
@export var tackle_start_range: float = 3.0
@export var tackle_time: float = 0.35
@export var tackle_speed: float = 12.0
@export var tackle_impulse: float = 6.0
@export var tackle_up: float = 0.2
@export var tackle_cooldown: float = 1.2

var _ball: RigidBody3D
var _goal: Node3D

# timers/state
var _shoot_cd := 0.0
var _dribble_cd := 0.0
var _tackle_cd := 0.0
var _tackle_time_left := 0.0

func _ready() -> void:
	_ball = get_node(ball_path) as RigidBody3D
	_goal = get_node(goal_path) as Node3D

func _physics_process(delta: float) -> void:
	# gravity
	if !is_on_floor(): velocity.y -= gravity * delta
	else: velocity.y = 0.0

	# cooldowns
	if _shoot_cd > 0.0: _shoot_cd -= delta
	if _dribble_cd > 0.0: _dribble_cd -= delta
	if _tackle_cd > 0.0: _tackle_cd -= delta

	var bot_pos := global_transform.origin
	var ball_pos := _ball.global_transform.origin
	var to_ball := ball_pos - bot_pos; to_ball.y = 0.0
	var dist_to_ball := to_ball.length()
	var dir_to_ball := Vector3.ZERO if to_ball == Vector3.ZERO else to_ball.normalized()

	var forward := (-global_transform.basis.z); forward.y = 0.0
	forward = Vector3.ZERO if forward == Vector3.ZERO else forward.normalized()

	# Tackle slide in progress?
	if _tackle_time_left > 0.0:
		_tackle_time_left -= delta
		_move_flat(forward, tackle_speed, delta) # keep sliding forward
		_check_tackle_hit()
		move_and_slide()
		return

	# 1) If close and can shoot → shoot
	if dist_to_ball <= kick_range and _shoot_cd <= 0.0:
		_try_kick()
		move_and_slide()
		return

	# 2) If in range and off-angle, try a tackle dash
	if dist_to_ball <= tackle_start_range and _tackle_cd <= 0.0 and _should_tackle():
		_start_tackle()
		move_and_slide()
		return

	# 3) Default: chase + dribble when in front & close
	_move_flat(dir_to_ball, walk_speed, delta)
	if dist_to_ball <= dribble_range:
		_maybe_dribble(forward, ball_pos)
	move_and_slide()

# --- Steering helper ---
func _move_flat(dir: Vector3, target_speed: float, delta: float) -> void:
	var desired := dir * target_speed
	var h := velocity; h.y = 0.0
	h = h.lerp(desired, clamp(accel * delta, 0.0, 1.0))
	velocity.x = h.x
	velocity.z = h.z
	# face motion / target
	if dir != Vector3.ZERO:
		var yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clamp(10.0 * delta, 0.0, 1.0))

# --- Shoot/kick toward goal ---
func _try_kick() -> void:
	var ball_pos := _ball.global_transform.origin
	var to_goal := _goal.global_transform.origin - ball_pos; to_goal.y = 0.0
	var dir := Vector3.ZERO if to_goal == Vector3.ZERO else to_goal.normalized()
	var impulse := dir * kick_power + Vector3.UP * kick_up
	_ball.apply_impulse(impulse)
	_shoot_cd = shoot_cooldown

# --- Dribble nudges (front cone + cooldown) ---
func _maybe_dribble(forward: Vector3, ball_pos: Vector3) -> void:
	if _dribble_cd > 0.0: return
	var to_ball := ball_pos - global_transform.origin; to_ball.y = 0.0
	if to_ball == Vector3.ZERO: return
	var n_to_ball := to_ball.normalized()
	var in_front := forward.dot(n_to_ball) >= dribble_cone_dot
	if !in_front: return

	# push mostly forward with a little “keep-ahead” bias
	var impulse := forward * (dribble_impulse * (1.0 + dribble_forward_bias)) \
		+ Vector3.UP * dribble_up
	_ball.apply_impulse(impulse)
	_dribble_cd = dribble_cooldown

# --- Tackle logic ---
func _should_tackle() -> bool:
	# Simple heuristic: tackle if we’re roughly lined up behind the ball toward the goal
	var ball_pos := _ball.global_transform.origin
	var to_goal := _goal.global_transform.origin - ball_pos; to_goal.y = 0.0
	var to_ball := ball_pos - global_transform.origin; to_ball.y = 0.0
	if to_ball == Vector3.ZERO or to_goal == Vector3.ZERO:
		return false
	return to_ball.normalized().dot(to_goal.normalized()) > 0.3

func _start_tackle() -> void:
	_tackle_time_left = tackle_time
	_tackle_cd = tackle_cooldown
	# give forward burst
	var fwd := (-global_transform.basis.z); fwd.y = 0.0
	fwd = Vector3.ZERO if fwd == Vector3.ZERO else fwd.normalized()
	velocity.x = fwd.x * tackle_speed
	velocity.z = fwd.z * tackle_speed

func _check_tackle_hit() -> void:
	# if close enough during tackle, poke the ball and add tiny lift
	var ball_pos := _ball.global_transform.origin
	var to_ball := ball_pos - global_transform.origin; to_ball.y = 0.0
	if to_ball.length() <= maxf(kick_range, 0.9):
		var to_goal := _goal.global_transform.origin - ball_pos; to_goal.y = 0.0
		var dir := Vector3.ZERO if to_goal == Vector3.ZERO else to_goal.normalized()
		_ball.apply_impulse(dir * tackle_impulse + Vector3.UP * tackle_up)
