# res://bot.gd
extends "res://scripts/player.gd"

@export var stop_distance: float = 0.7   # how close to the goal/target before we stop
@export var move_strength: float = 1.0   # how hard we push when walking to home
@export var slide_move_strength: float = 2.0  # how hard we push when sliding on the line

# Only the goal centers need explicit paths (from World)
@export var blue_goal_rel_path: NodePath = ^"Teams/TeamBlue/Goal_A"
@export var red_goal_rel_path:  NodePath = ^"Teams/TeamRed/Goal_B"

# How far in front of the goal line the bot should stand (in meters)

@export var guard_depth: float = 2.5
@export var dive_extra_distance := 0.40  # meters
@export var dive_ball_speed := 18.0
@export var dive_speed := 4.0
@export var dive_duration := 0.35
@export var dive_cooldown := 1.0
@export var prediction_time := 0.35

@export var recovery_time := 3.0
const DIVE_TILT := deg_to_rad(90.0)
var _is_diving := false
var _dive_timer := 0.0
var _dive_cd := 0.0
var _dive_dir := Vector3.ZERO
var _dive_velocity := Vector3.ZERO
var _dive_target := Vector3.ZERO
var _recovery_timer := 0.0
var _hold_timer := 0.0

const MIN_DIVE_SPEED := 20.0
const MAX_DIVE_SPEED := 40.0

const MIN_DIVE_TIME := 0.12
const MAX_DIVE_TIME := 0.35

const MAX_EXTRA_TIME := 0.50

const GUARD_RADIUS: float = 30.0      # how close to goal center before "keeper mode" starts
const SLIDE_DEADZONE: float = 0.1     # how close along the line before we stop sliding

const FIELD_MID_Z := 0.0          # centre line of field (same as your World plane_z)
const MID_ARRIVE_RADIUS := 5.0    # how close to the ball is “reached”
const MID_HOME_TOL := 0.5         # how close to spawn is “home”

# 🔹 NEW: tackle behaviour
const OPP_HUG_RADIUS := 10.0    # how close to the ball the opponent must be ("hugging")
const BOT_TACKLE_RADIUS := 18.0  # how close WE must be to start tackling

# 🔹 NEW: pass behaviour (midfielder)
const BOT_CONTROL_RADIUS := 5.0   # how close WE must be to "own" the ball
const PASS_MIN_FORCE := 2.0       # soft short pass
const PASS_MAX_FORCE := 4.5       # strongest pass
const PASS_MAX_DIST  := 25.0      # distance at which we use MAX_FORCE
const PASS_COOLDOWN_SEC := 1.5

const TEAMMATE_BALL_RADIUS := 5.0   # how close a teammate must be to "own" the ball

# 🔹 Forward logic
const CENTER_BAND_Z := 4.0   # how wide the "centre zone" is around FIELD_MID_Z

const FWD_CONTROL_RADIUS := 4.0        # how close forward must be to "own" the ball
const FWD_DRIBBLE_FORCE :=1.0       # soft nudge towards goal
const FWD_FINAL_SHOT_FORCE := 10.0     # big shot near goal
const FWD_FINAL_SHOT_DIST := 35.0      # if ball is this close to goal → use final shot
const FWD_KICK_COOLDOWN_SEC := 0.8     # delay between touches so it doesn't spam
const FWD_DANGER_RADIUS := 13.0

const FWD_GOAL_PROX_WEIGHT := 0.18  # 0.10..0.35 (bigger = hug opponent goal more)


const FWD_WING_OFFSET := 15.0  # fallback width if we can't read goal posts

const FWD_HOME_LEFT   := 0
const FWD_HOME_CENTER := 1
const FWD_HOME_RIGHT  := 2

const FWD_FIRST_TRAP_RADIUS := 8.5  # only for the first trap after a pass

# --- Forward facing/alignment ---
const FWD_ALIGN_ANGLE_DEG := 35.0      # if we're more off than this, align first
const FWD_ALIGN_HOLD_SEC  := 0.18      # hold ball briefly while turning

var _align_goal_until_sec := 0.0

# --- pass receive intercept using bot speed (better than closest-approach) ---
const BOT_SPRINT_SPEED_EST := 9.0  # tune to match your bot 

@export var forward_idle_home: int = FWD_HOME_LEFT
# 0 = left edge, 1 = centre, 2 = right edge

# 🔹 NEW: pass-lane + trap for ANY receiver (forward or midfielder)
const PASS_LANE_BLOCK_RADIUS := 2.2   # meters: opponent near the pass line = blocked
const PASS_TRAP_MAX_AGE_SEC := 2.0
const MID_FIRST_TRAP_RADIUS := 8.0    # how close midfielder must get to do the first-trap

# 🔹 NEW: trap normal kicks/shots coming toward the bot
const INCOMING_TRAP_MAX_DIST := 12.0        # ignore far balls
const INCOMING_TRAP_MIN_SPEED := 4.0        # ball must be moving
const INCOMING_TRAP_DOT := 0.85             # how "directly toward me" (0.65~0.85)
const INCOMING_TRAP_PREDICT_SEC := 0.8    # look-ahead for intercept point
const INCOMING_TRAP_RADIUS := 2.5            # when close enough → stop ball
const INCOMING_TRAP_COOLDOWN := 0.25        # prevents jitter re-traps

# --- pass receive intercept tuning ---
const PASS_RECEIVE_MIN_SPEED := 1.0          # if ball slower than this, just chase ball normally
const PASS_RECEIVE_PREDICT_SEC := 10.0       # how far ahead to predict for a pass (0.7..1.4 good)
const PASS_RECEIVE_INTERCEPT_RADIUS := 2.3   # when close enough to intercept point, do trap (2.0..3.0)


const LAST_PASS_FROM_META := &"last_pass_from_path"
const LAST_PASS_TIME_META := &"last_pass_time"
const SELF_PASS_IGNORE_SEC := 0.45  # tweak 0.3..0.6



const BALL_CONTROL_MAX_HEIGHT := 1.8
# how many meters above/below the player's origin we still consider "reachable"

var _forward_home_point: Vector3 = Vector3.ZERO
var _forward_home_valid: bool = false

var _forward_home_center: Vector3 = Vector3.ZERO
var _forward_home_left:   Vector3 = Vector3.ZERO
var _forward_home_right:  Vector3 = Vector3.ZERO

var _next_pass_time_sec := 0.0
var _next_forward_kick_time_sec := 0.0
var _forward_dribble_phase: int = 0     # 0 = dribble kick, 1 = trap phase
var _next_incoming_trap_time_sec := 0.0


var _goal_point: Vector3 = Vector3.ZERO
var _home_goal_point: Vector3 = Vector3.ZERO
var _goal_valid: bool = false
var _cached_team: int = -1

var _spawn_point: Vector3 = Vector3.ZERO
var _spawn_point_valid := false

var ROLE_GOALKEEPER = GameState.Role.GOALKEEPER
var ROLE_MIDFIELDER = GameState.Role.MIDFIELDER
var ROLE_FORWARD    = GameState.Role.FORWARD

var _cached_role: int = -1

# for sliding between the posts
var _goal_line_center: Vector3 = Vector3.ZERO
var _goal_line_dir: Vector3 = Vector3.ZERO    # normalized left→right along goal
var _goal_line_half_len: float = 0.0
var _has_goal_line: bool = false

# forward direction out of the goal, projected on XZ
var _goal_forward: Vector3 = Vector3.ZERO

var _mid_return_home_until_sec := 0.0


func _ready() -> void:
	super._ready()
	if multiplayer.is_server():
		add_to_group("bots")
	# We can pick the goal on all peers; only the server will actually drive the bot.
	_pick_goal_point()



func _physics_process(delta: float) -> void:

	if multiplayer.is_server():
		_update_bot_input(delta)
		super._physics_process(delta)
		if not _is_frozen and not tackle_active and not _external_pull_active and _cooldowns["move"] == 0.0:


			_move_server(_get_input_dir_server(), delta, bool(_net.get("sprint", false)))


# ---------- TEAM RESOLUTION ----------

func _get_my_team() -> int:
	if _cached_team != -1:
		return _cached_team

	var my_path := get_path()

	# 1) PRIMARY: find my record in the roster by player_path
	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]
		if rec.has("player_path") and rec["player_path"] == my_path:
			_cached_team = int(rec.get("team", GameState.Team.BLUE))
			return _cached_team

	# 2) FALLBACK: use owner_peer_id *only* if no direct match
	if GameState.roster.has(owner_peer_id):
		_cached_team = int(GameState.roster[owner_peer_id].get("team", GameState.Team.BLUE))
		return _cached_team

	# 3) LAST RESORT: assume BLUE
	_cached_team = GameState.Team.BLUE
	return _cached_team


func _get_my_role() -> int:
	if _cached_role != -1:
		return _cached_role

	var my_path := get_path()

	# 1) PRIMARY: find my record by player_path
	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]
		if rec.has("player_path") and rec["player_path"] == my_path:
			_cached_role = int(rec.get("role", ROLE_MIDFIELDER))
			return _cached_role

	# 2) FALLBACK: owner_peer_id
	if GameState.roster.has(owner_peer_id):
		_cached_role = int(GameState.roster[owner_peer_id].get("role", ROLE_MIDFIELDER))
	else:
		_cached_role = ROLE_MIDFIELDER

	return _cached_role

func _get_role_for_node(n: Node) -> int:
	if n == null:
		return ROLE_MIDFIELDER

	var path := n.get_path()
	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]
		if not rec.has("player_path"):
			continue
		if rec["player_path"] == path:
			return int(rec.get("role", ROLE_MIDFIELDER))

	return ROLE_MIDFIELDER


# ---------- GOAL & POSTS SETUP ----------

func _pick_goal_point() -> void:
	_goal_valid = false
	_has_goal_line = false
	_goal_forward = Vector3.ZERO

	var world: Node = get_tree().current_scene
	if world == null:
		print("bot.gd: no current_scene")
		return

	var my_team := _get_my_team()
	var goal_path: NodePath = blue_goal_rel_path if my_team == GameState.Team.BLUE else red_goal_rel_path
	print("bot.gd: picking goal for team ", my_team, " path=", goal_path)

	var goal_node := world.get_node_or_null(goal_path) as Node3D
	if goal_node == null:
		print("bot.gd: could not find goal for team ", my_team, " at path: ", goal_path)
		return

	# Base goal center at bot's ground height
	var goal_center: Vector3 = goal_node.global_transform.origin
	goal_center.y = global_transform.origin.y

	# Try to figure out "field direction" using BallSpawn if present
	var field_dir := Vector3.ZERO
	var ball_spawn_node := world.get_node_or_null("BallSpawn") as Node3D
	if ball_spawn_node:
		field_dir = ball_spawn_node.global_transform.origin - goal_center
	else:
		# Fallback: use goal's -Z as "forward"
		field_dir = -goal_node.global_transform.basis.z

	field_dir.y = 0.0
	if field_dir.length() < 0.001:
		field_dir = Vector3.FORWARD
	_goal_forward = field_dir.normalized()

	# Our home position is guard_depth meters in front of the goal line (toward field)
	_home_goal_point = goal_center + _goal_forward * guard_depth
	_goal_point = _home_goal_point
	_goal_valid = true

	# ---- find posts (search recursively, not just direct children) ----
	var post_left  := goal_node.find_child("Post_L", true, false) as Node3D
	var post_right := goal_node.find_child("Post_R", true, false) as Node3D

	if post_left == null or post_right == null:
		print("bot.gd: missing Post_L/Post_R somewhere under ", goal_node.get_path())
		return

	var L: Vector3 = post_left.global_transform.origin
	var R: Vector3 = post_right.global_transform.origin

	# Put posts on same ground height as home
	L.y = _home_goal_point.y
	R.y = _home_goal_point.y

	var seg: Vector3 = R - L
	var seg_len: float = seg.length()
	if seg_len < 0.001:
		print("bot.gd: posts are at the same position; goal line invalid.")
		return

	_goal_line_center = (L + R) * 0.5
	_goal_line_dir = seg / seg_len           # normalized
	_goal_line_half_len = seg_len * 0.5
	_has_goal_line = true

	print("BOT ", owner_peer_id, " team=", my_team, " guarding ", goal_path,
		" line from ", L, " to ", R, " guard_depth=", guard_depth)


func _get_ball() -> RigidBody3D:
	if current_ball != null and is_instance_valid(current_ball):
		return current_ball
	return get_tree().get_first_node_in_group("ball") as RigidBody3D


# ---------- AI: high level ----------

func _update_bot_input(delta: float) -> void:
	if !_goal_valid:
		_pick_goal_point()
		if !_goal_valid:
			_reset_net()
			return

	_reset_net()  # start neutral every tick

	var role := _get_my_role()


	if role == ROLE_GOALKEEPER:
		_update_goalkeeper_input(delta)
	else:
		_update_outfield_input(delta, role)


# ---------- GOALKEEPER ----------

func _update_goalkeeper_input(delta: float) -> void:
	if _recovery_timer > 0.0:
		_recovery_timer -= delta
		_reset_net()

		if _recovery_timer <= 0.0:
			rotation.z = 0.0

		return

	if _hold_timer > 0.0:
		_hold_timer -= delta
		_reset_net()
		if _hold_timer <= 0.0:
			var held_ball := _get_ball()
			if held_ball and held_ball.latched and held_ball.latched_to == self:
				held_ball.unlatch()
				var fwd := _goal_forward
				held_ball.apply_hit(fwd * 18.0 + Vector3(0, 6.0, 0), held_ball.global_transform.origin, owner_peer_id)
		return

	var pos3: Vector3 = global_transform.origin
	if _dive_cd > 0.0:
		_dive_cd -= delta

	var ball := _get_ball()
	if ball and not ball.latched:
		if global_transform.origin.distance_to(ball.global_transform.origin) < 2.5:
			ball.latch_to_keeper(self)
			_hold_timer = 0.8
			_is_diving = false
			return

	if _is_diving:
		_dive_timer -= delta
		if _dive_timer <= 0.0 or _dive_velocity.length() < 1.0 or ball_latched:
			_is_diving = false
		return
	var pos2 := Vector2(pos3.x, pos3.z)
	var home2 := Vector2(_home_goal_point.x, _home_goal_point.z)

	var dist_to_home := pos2.distance_to(home2)

	# ---------- GUARD MODE: keeper holds center, dives to predicted ball impact ----------
	if ball != null and _has_goal_line and dist_to_home <= GUARD_RADIUS and _goal_forward != Vector3.ZERO:
		var ball3 := ball.global_transform.origin
		var ball_vel := ball.linear_velocity
		var speed := ball_vel.length()
		var predicted_ball := ball3

		if speed > 0.1:
			predicted_ball += ball_vel * prediction_time
		var ball2 := Vector2(predicted_ball.x, predicted_ball.z)

		# Line we are actually guarding: posts line shifted forward by guard_depth
		var base_center3: Vector3 = _goal_line_center + _goal_forward * guard_depth
		var base_center2 := Vector2(base_center3.x, base_center3.z)
		var dir2 := Vector2(_goal_line_dir.x, _goal_line_dir.z)  # normalized

		# Project ball onto guard line → this is where we need to be to make the save
		var rel_ball := ball2 - base_center2
		var t_ball: float = rel_ball.dot(dir2)
		t_ball = clampf(t_ball, -_goal_line_half_len, _goal_line_half_len)

		# Dive target: the predicted ball impact point on the guard line
		var dive_target3 := base_center3 + _goal_line_dir * t_ball
		dive_target3.y = _home_goal_point.y

		# Keeper's normal guard position: always the CENTER of the goal line
		var keeper_guard_point := base_center3
		keeper_guard_point.y = _home_goal_point.y
		_goal_point = keeper_guard_point

		# delta2 / dist_slide: used for normal walk-back-to-center movement
		var delta2 := Vector2(keeper_guard_point.x, keeper_guard_point.z) - pos2
		var dist_slide := delta2.length()

		# Always run dive check first — being centered must NOT block it
		var dangerous := false
		var keeper_time := 0.0
		var ball_time := 0.0
		var extra_time := 0.0

		if speed > dive_ball_speed:
			var toward_goal := ball_vel.normalized().dot(-_goal_forward)

			if toward_goal > 0.8 and _dive_cd <= 0.0:
				# Keeper dives whenever a fast shot is heading for goal — no extra_time requirement
				dangerous = true

				var dist_to_dive_target := Vector2(dive_target3.x, dive_target3.z).distance_to(pos2)
				keeper_time = dist_to_dive_target / slide_move_strength
				ball_time = prediction_time
				extra_time = keeper_time - ball_time

		if dangerous:
			var dive_delta := Vector2(dive_target3.x, dive_target3.z) - pos2
			var dive_dir3 := Vector3(dive_delta.x, 0.0, dive_delta.y).normalized()

			var dive_strength = clamp(
				extra_time / MAX_EXTRA_TIME,
				0.0,
				1.0
			)

			var dive_speed := lerpf(
				MIN_DIVE_SPEED,
				MAX_DIVE_SPEED,
				dive_strength
			)

			_is_diving = true
			_dive_timer = lerpf(
				MIN_DIVE_TIME,
				MAX_DIVE_TIME,
				dive_strength
			)
			_dive_cd = dive_cooldown
			_dive_dir = dive_dir3
			if _dive_dir.dot(Vector3.RIGHT) > 0.0:
				rotation.z = -DIVE_TILT   # Diving right
			else:
				rotation.z = DIVE_TILT    # Diving left
			_dive_velocity = dive_dir3 * dive_speed
			_dive_target = dive_target3  + dive_dir3 * dive_extra_distance

			print("--------------------------------")
			print("dist_to_dive_target =", Vector2(dive_target3.x, dive_target3.z).distance_to(pos2))
			print("keeper_time =", keeper_time)
			print("ball_time =", ball_time)
			print("extra_time =", extra_time)
			print("dive_strength =", dive_strength)
			print("dive_speed =", dive_speed)
			print("dive_Adir =", dive_dir3)

			return

		# Only walk back to center if keeper is not already there
		if dist_slide > SLIDE_DEADZONE:
			var center_dir3 := Vector3(delta2.x, 0.0, delta2.y).normalized()
			var yaw := rotation.y
			var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
			fwd.y = 0.0
			fwd = fwd.normalized()

			var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
			right.y = 0.0
			right = right.normalized()

			var mvx := center_dir3.dot(right) * slide_move_strength
			var mvz := center_dir3.dot(fwd) * slide_move_strength

			_net["mvx"] = clampf(mvx, -1.0, 1.0)
			_net["mvz"] = clampf(mvz, -1.0, 1.0)
			_net["sprint"] = true

		return

	# ---------- DEFAULT: walk to home guard point in front of goal ----------
	var to_home3: Vector3 = _home_goal_point - global_transform.origin
	to_home3.y = 0.0
	var dist_home: float = to_home3.length()

	if dist_home <= stop_distance:
		# already basically at center, nothing to do
		return

	var dir_move3: Vector3 = to_home3 / max(dist_home, 0.0001)

	var yaw2 := rotation.y
	var fwd2 := Vector3.FORWARD.rotated(Vector3.UP, yaw2)
	fwd2.y = 0.0
	fwd2 = fwd2.normalized()

	var right2 := Vector3.RIGHT.rotated(Vector3.UP, yaw2)
	right2.y = 0.0
	right2 = right2.normalized()

	var mvx2: float = dir_move3.dot(right2) * move_strength
	var mvz2: float = dir_move3.dot(fwd2) * move_strength

	_net["mvx"] = clampf(mvx2, -1.0, 1.0)
	_net["mvz"] = clampf(mvz2, -1.0, 1.0)
	_net["sprint"] = true


# ---------- COMMON MOVEMENT HELPERS ----------

func _update_outfield_input(delta: float, role: int) -> void:
	if role == ROLE_MIDFIELDER:
		_update_midfielder_input(delta)
	elif role == ROLE_FORWARD:
		_update_forward_input(delta)
	else:
		# unknown role → stand still
		_reset_net()


func _reset_net() -> void:
	_net["mvx"] = 0.0
	_net["mvz"] = 0.0
	_net["sprint"] = false

	_net["jump_pressed"] = false
	_net["tackle_pressed"] = false
	_net["dribble"] = false
	_net["stop_ball"] = false
	_net["shoot_down"] = false
	_net["shoot_up"] = false
	_net["rmb"] = false
	_net["latch_toggle"] = false

	_net["facing"] = {"yaw_delta": 0.0, "pitch_delta": 0.0}
	_net["cam_yaw"] = rotation.y


func _move_towards_direction(dir3: Vector3, sprint: bool) -> void:
	if dir3 == Vector3.ZERO:
		return
	var yaw := rotation.y

	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	fwd.y = 0.0
	fwd = fwd.normalized()

	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	right.y = 0.0
	right = right.normalized()

	var mvx := dir3.dot(right)
	var mvz := dir3.dot(fwd)

	_net["mvx"] = clampf(mvx, -1.0, 1.0)
	_net["mvz"] = clampf(mvz, -1.0, 1.0)
	_net["cam_yaw"] = yaw
	_net["sprint"] = sprint


func _face_point(target: Vector3) -> void:
	var origin := global_transform.origin
	var to_target := target - origin
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return            # avoid look_at error when positions are same

	look_at(origin + to_target, Vector3.UP)
	rotation.x = 0.0
	rotation.z = 0.0

	_net["cam_yaw"] = rotation.y


func _go_home_idle() -> void:
	# walk back to spawn point, then stand still
	var origin := global_transform.origin
	var to_home := _spawn_point - origin
	to_home.y = 0.0

	var dist_home := to_home.length()
	if dist_home <= MID_HOME_TOL:
		# close enough → idle (no input)
		_reset_net()
		return

	# 👇 face home first (this updates rotation.y)
	_face_point(_spawn_point)

	# then move in world direction to home
	var dir3 = to_home / max(dist_home, 0.0001)
	_move_towards_direction(dir3, false)


func _is_ball_in_my_half(ball: Node3D) -> bool:
	if ball == null:
		return false

	var ball_z := ball.global_transform.origin.z

	# Prefer the actual side where this bot spawned.
	if _spawn_point_valid:
		var home_z := _spawn_point.z

		# Ball and home are on the same side of midfield.
		if home_z < FIELD_MID_Z:
			return ball_z <= FIELD_MID_Z
		elif home_z > FIELD_MID_Z:
			return ball_z >= FIELD_MID_Z

	# Fallback only if home hasn't been initialized yet.
	var my_team := _get_my_team()

	if my_team == GameState.Team.BLUE:
		return ball_z <= FIELD_MID_Z
	else:
		return ball_z >= FIELD_MID_Z


func _is_ball_in_opponent_half(ball: Node3D) -> bool:
	if ball == null:
		return false

	var ball_z := ball.global_transform.origin.z
	var am_blue := GameState.is_blue(owner_peer_id)

	if am_blue:
		# opponent = red half (z > 0)
		return ball_z >= FIELD_MID_Z
	else:
		# opponent = blue half (z < 0)
		return ball_z <= FIELD_MID_Z


func _is_ball_in_center_band(ball: Node3D) -> bool:
	if ball == null:
		return false

	var ball_z := ball.global_transform.origin.z
	return abs(ball_z - FIELD_MID_Z) <= CENTER_BAND_Z


func _go_forward_home() -> void:
	if not _forward_home_valid:
		_compute_forward_home()
		if not _forward_home_valid:
			return

	# 👉 choose the safest home each frame based on opponent positions
	_pick_best_forward_idle_home_by_opponents()

	var origin := global_transform.origin
	var home := _forward_home_point
	home.y = origin.y

	var to_home := home - origin
	to_home.y = 0.0
	var dist_home := to_home.length()

	# close enough → idle here, facing opponent goal
	if dist_home <= MID_HOME_TOL:
		_reset_net()

		var world := get_tree().current_scene
		if world:
			var am_blue := GameState.is_blue(owner_peer_id)
			var opp_goal := world.get_node_or_null(
				red_goal_rel_path if am_blue else blue_goal_rel_path
			) as Node3D
			if opp_goal:
				_face_point(opp_goal.global_transform.origin)
		return

	# not home yet → run there
	_face_point(home)
	var dir3 = to_home / max(dist_home, 0.0001)
	_move_towards_direction(dir3, true)  # sprint into position


# ---------- OPPONENT / TEAMMATE QUERIES ----------

func _is_opponent_in_pass_lane(
	ball_pos: Vector3,
	target_pos: Vector3,
	lane_radius: float,
	max_height_diff: float = 9999.0
) -> bool:
	var my_team := _get_my_team()

	var a := Vector2(ball_pos.x, ball_pos.z)
	var b := Vector2(target_pos.x, target_pos.z)
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 < 0.0001:
		return false

	var world := get_tree().current_scene
	if world == null:
		return false

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team == my_team:
			continue

		if not rec.has("player_path"):
			continue

		var n := world.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var p3 := n.global_transform.origin
		if abs(p3.y - ball_pos.y) > max_height_diff:
			continue

		var p := Vector2(p3.x, p3.z)

		# projection of p onto segment a->b
		var t := clampf((p - a).dot(ab) / ab_len2, 0.0, 1.0)

		# ignore opponents basically at the endpoints (near ball or near receiver)
		if t < 0.08 or t > 0.92:
			continue

		var proj := a + ab * t
		if p.distance_to(proj) <= lane_radius:
			return true

	return false


func _find_best_midfielder_target(ball_pos: Vector3) -> Node3D:
	var my_team := _get_my_team()
	var world := get_tree().current_scene
	if world == null:
		return null

	var best: Node3D = null
	var best_score := INF
	var ball2 := Vector2(ball_pos.x, ball_pos.z)

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		if int(pid) == owner_peer_id:
			continue

		var role := int(rec.get("role", ROLE_MIDFIELDER))
		if role != ROLE_MIDFIELDER:
			continue

		if not rec.has("player_path"):
			continue

		var n := world.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var p := n.global_transform.origin
		var d := Vector2(p.x, p.z).distance_to(ball2)

		# Prefer humans slightly (optional, but nice)
		var penalty := 0.0 if _is_human_player(rec) else 5.0
		var score := d + penalty

		if score < best_score:
			best_score = score
			best = n

	return best


func _find_nearest_opponent_to_ball(ball_pos: Vector3, max_ball_dist: float, max_height_diff: float = 9999.0) -> Node3D:
	var my_team := _get_my_team()
	var best: Node3D = null
	var best_dist := max_ball_dist

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		# skip my own team
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team == my_team:
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var pos := n.global_transform.origin

		# ignore opponents who are far below/above the ball (can't really contest it)
		var hdiff = abs(ball_pos.y - pos.y)
		if hdiff > max_height_diff:
			continue

		# horizontal distance
		var pos_flat := Vector2(pos.x, pos.z)
		var ball_flat := Vector2(ball_pos.x, ball_pos.z)
		var d := pos_flat.distance_to(ball_flat)

		if d < best_dist:
			best_dist = d
			best = n

	return best

func _find_best_human_teammate_target(ball_pos: Vector3, exclude_path: NodePath = NodePath("")) -> Node3D:
	var my_team := _get_my_team()
	var best: Node3D = null
	var best_dist := INF

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		if int(pid) == owner_peer_id:
			continue

		if not _is_human_player(rec):
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		# ✅ NEW: exclude the passer
		if exclude_path != NodePath("") and n.get_path() == exclude_path:
			continue

		var pos := n.global_transform.origin
		pos.y = 0.0

		var d := pos.distance_to(ball_pos)
		if d < best_dist:
			best_dist = d
			best = n

	return best


func _find_best_forward_target(ball_pos: Vector3, exclude_path: NodePath = NodePath("")) -> Node3D:
	var my_team := _get_my_team()
	var best: Node3D = null
	var best_dist := INF
	var ball2 := Vector2(ball_pos.x, ball_pos.z)

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		if int(pid) == owner_peer_id:
			continue

		var role := int(rec.get("role", ROLE_MIDFIELDER))
		if role != ROLE_FORWARD:
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		# ✅ NEW: don't pass back to excluded player
		if exclude_path != NodePath("") and n.get_path() == exclude_path:
			continue

		var pos := n.global_transform.origin
		var pos2 := Vector2(pos.x, pos.z)
		var d := pos2.distance_to(ball2)

		if d < best_dist:
			best_dist = d
			best = n

	return best

func _mark_ball_pass_trap(
	ball: RigidBody3D,
	from_role: int,
	now_sec: float,
	receiver: Node
) -> void:
	if ball == null or receiver == null:
		return

	var info := {
		"team": _get_my_team(),
		"from_role": from_role,
		"timestamp": now_sec,
		"used": false,
		"receiver_path": receiver.get_path(),
		"from_path": get_path(),  # ✅ NEW: who made the pass
	}
	ball.set_meta(PASS_TRAP_META_KEY, info)


func _has_pending_pass_trap(ball: RigidBody3D, now_sec: float) -> bool:
	if ball == null:
		return false
	if not ball.has_meta(PASS_TRAP_META_KEY):
		return false

	var info = ball.get_meta(PASS_TRAP_META_KEY)
	if not (info is Dictionary):
		return false

	if bool(info.get("used", false)):
		return false

	if int(info.get("team", -1)) != _get_my_team():
		return false

	if info.has("receiver_path"):
		var expected_path: NodePath = info["receiver_path"]
		if expected_path != get_path():
			return false

	var age := now_sec - float(info.get("timestamp", now_sec))
	if age > PASS_TRAP_MAX_AGE_SEC:
		return false

	var from_role := int(info.get("from_role", ROLE_MIDFIELDER))
	if from_role != ROLE_MIDFIELDER and from_role != ROLE_FORWARD:
		return false

	return true


func _consume_pass_trap(ball: RigidBody3D, now_sec: float) -> bool:
	if not _has_pending_pass_trap(ball, now_sec):
		return false

	var info: Dictionary = ball.get_meta(PASS_TRAP_META_KEY)
	info["used"] = true
	ball.set_meta(PASS_TRAP_META_KEY, info)
	return true

func _try_trap_incoming_ball(ball: RigidBody3D, now_sec: float) -> bool:
	if ball == null:
		return false
	if now_sec < _next_incoming_trap_time_sec:
		return false

	# ✅ Put the check HERE (top), before any trap math.
	# --- ignore trapping our OWN pass for a brief moment ---
	if ball.has_meta(PASS_TRAP_META_KEY):
		var info = ball.get_meta(PASS_TRAP_META_KEY)
		if info is Dictionary:
			var from_path: NodePath = info.get("from_path", NodePath(""))
			var ts: float = float(info.get("timestamp", now_sec))
			var age := now_sec - ts

			# If I was the passer, don't trap it for a short time
			if from_path == get_path() and age < 0.6:
				return false

	var origin := global_transform.origin
	var ball_pos := ball.global_transform.origin

	# must be reachable height-wise
	if abs(ball_pos.y - origin.y) > BALL_CONTROL_MAX_HEIGHT:
		return false

	# flat velocity + speed
	var v := ball.linear_velocity
	v.y = 0.0
	var speed := v.length()
	if speed < INCOMING_TRAP_MIN_SPEED:
		return false

	# flat vector from ball to me
	var to_me := origin - ball_pos
	to_me.y = 0.0
	var dist := to_me.length()
	if dist < 0.01 or dist > INCOMING_TRAP_MAX_DIST:
		return false

	# is the ball moving toward me?
	var v_n := v / speed
	var to_n := to_me / dist
	var toward := v_n.dot(to_n)
	if toward < INCOMING_TRAP_DOT:
		return false

	# predict closest approach point (intercept)
	var speed2 := maxf(0.001, speed * speed)
	var t := clampf(to_me.dot(v) / speed2, 0.0, INCOMING_TRAP_PREDICT_SEC)
	var intercept := ball_pos + v * t
	intercept.y = origin.y

	# drive toward intercept
	_face_point(intercept)

	var to_i := intercept - origin
	to_i.y = 0.0
	var di := to_i.length()

	if di > INCOMING_TRAP_RADIUS:
		_move_towards_direction(to_i / maxf(di, 0.0001), true)
		return true

	# close enough: TRAP (stop ball)
	if _has_pending_pass_trap(ball, now_sec):
		_consume_pass_trap(ball, now_sec)

	ball.linear_velocity = Vector3.ZERO
	_net["stop_ball"] = true

	_next_incoming_trap_time_sec = now_sec + INCOMING_TRAP_COOLDOWN
	return true


func _find_best_human_forward_target(ball_pos: Vector3, exclude_path: NodePath = NodePath("")) -> Node3D:
	var my_team := _get_my_team()
	var best: Node3D = null
	var best_dist := INF

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue
		if int(pid) == owner_peer_id:
			continue

		if not _is_human_player(rec):
			continue

		var role := int(rec.get("role", ROLE_MIDFIELDER))
		if role != ROLE_FORWARD:
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		if exclude_path != NodePath("") and n.get_path() == exclude_path:
			continue

		var p := n.global_transform.origin
		p.y = 0.0
		var d := p.distance_to(ball_pos)

		if d < best_dist:
			best_dist = d
			best = n

	return best



func _try_pass_to_forward_only(ball: RigidBody3D, ignore_cooldown: bool = false, exclude_path: NodePath = NodePath("")) -> void:
	if ball == null:
		return

	var now_sec := Time.get_ticks_msec() / 1000.0
	if (not ignore_cooldown) and now_sec < _next_pass_time_sec:
		return

	var ball_pos := ball.global_transform.origin

	# 1) Prefer HUMAN forward (not the passer)
	var target := _find_best_human_forward_target(ball_pos, exclude_path)

	# 2) else any forward (not the passer)
	if target == null:
		target = _find_best_forward_target(ball_pos, exclude_path)

	# 3) else any HUMAN teammate (not the passer)
	if target == null:
		target = _find_best_human_teammate_target(ball_pos, exclude_path)

	# 🚫 If the ONLY available option is the passer, then just don't pass.
	if target == null:
		return

	# --- normal ground pass ---
	var target_pos := target.global_transform.origin
	target_pos.y = ball_pos.y

	var dir := target_pos - ball_pos
	dir.y = 0.0
	var dist := dir.length()
	if dist < 0.1:
		return

	dir = dir.normalized()

	var t := clampf(dist / PASS_MAX_DIST, 0.0, 1.0)
	var force = lerp(PASS_MIN_FORCE, PASS_MAX_FORCE, t)
	var impulse = dir * force

	var lv := ball.linear_velocity
	lv.y = 0.0
	ball.linear_velocity = lv
	ball.set_meta(LAST_PASS_FROM_META, get_path())
	ball.set_meta(LAST_PASS_TIME_META, now_sec)

	ball.apply_hit(impulse, Vector3.ZERO, owner_peer_id)
	_next_pass_time_sec = now_sec + PASS_COOLDOWN_SEC

	# mark trap for receiver
	_mark_ball_pass_trap(ball, _get_my_role(), now_sec, target)


func _try_pass_to_forward(ball: RigidBody3D) -> void:
	if ball == null:
		print("BOT", owner_peer_id, " _try_pass_to_forward: ball is NULL")
		return

	var now_sec := Time.get_ticks_msec() / 1000.0
	if now_sec < _next_pass_time_sec:
		# still on cooldown
		return

	var ball_pos := ball.global_transform.origin

	# 1) Prefer nearest HUMAN teammate
	var target := _find_best_human_teammate_target(ball_pos)

	# 2) If no human teammate found, fall back to any FORWARD (bot or human)
	if target == null:
		target = _find_best_forward_target(ball_pos)

	if target == null:
		print("BOT", owner_peer_id, " PASS: no valid human/forward teammate found, skipping")
		return

	var target_pos := target.global_transform.origin
	target_pos.y = ball_pos.y     # keep pass at ball height

	var dir := target_pos - ball_pos
	dir.y = 0.0
	var dist := dir.length()

	if dist < 0.1:
		print("BOT", owner_peer_id, " PASS: target too close, dist=", dist)
		return

	dir = dir.normalized()

	# scale force by distance
	var t := clampf(dist / PASS_MAX_DIST, 0.0, 1.0)
	var force = lerp(PASS_MIN_FORCE, PASS_MAX_FORCE, t)
	var impulse = dir * force     # ground pass only

	# keep ball on ground
	var lv := ball.linear_velocity
	lv.y = 0.0
	ball.linear_velocity = lv
	ball.set_meta(LAST_PASS_FROM_META, get_path())
	ball.set_meta(LAST_PASS_TIME_META, now_sec)

	ball.apply_hit(impulse, Vector3.ZERO, owner_peer_id)
	_next_pass_time_sec = now_sec + PASS_COOLDOWN_SEC

	# 👇 NEW: mark that this was a MID → FORWARD pass,
	# so the receiving forward can do a first-touch trap.
	# ✅ Mark trap for ANY receiver (bot forward OR bot midfielder)
	_mark_ball_pass_trap(ball, _get_my_role(), now_sec, target)



	print("BOT", owner_peer_id, " PASS to ", target.name,
		" dist=", dist,
		" force=", force,
		" impulse=", impulse)

func _forward_try_safety_pass(ball: RigidBody3D) -> bool:
	if ball == null:
		return false

	var now_sec := Time.get_ticks_msec() / 1000.0
	if now_sec < _next_pass_time_sec:
		# still on cooldown, don't spam passes
		return false

	var ball_pos := ball.global_transform.origin
	var ball_flat := Vector2(ball_pos.x, ball_pos.z)

	# 1) Nearest HUMAN teammate (any role)
	var human_target := _find_best_human_teammate_target(ball_pos)

	# 2) Nearest FORWARD (bot or human)
	var forward_target := _find_best_forward_target(ball_pos)

	var target: Node3D = null
	var best_dist := INF

	if forward_target != null:
		var fpos := forward_target.global_transform.origin
		var fflat := Vector2(fpos.x, fpos.z)
		best_dist = fflat.distance_to(ball_flat)
		target = forward_target

	if human_target != null:
		var hpos := human_target.global_transform.origin
		var hflat := Vector2(hpos.x, hpos.z)
		var hdist := hflat.distance_to(ball_flat)
		if hdist < best_dist:
			best_dist = hdist
			target = human_target

	if target == null:
		print("FORWARD", owner_peer_id, " SAFETY PASS: no valid target")
		return false

	if best_dist < 0.5:
		# too close to be worth a pass
		return false

	var target_pos := target.global_transform.origin
	target_pos.y = ball_pos.y  # ground pass

	# If we were about to safety-pass to a FORWARD, but an opponent blocks the lane,
	# redirect to a MIDFIELDER instead.
	var target_role := _get_role_for_node(target)
	if target_role == ROLE_FORWARD:
		if _is_opponent_in_pass_lane(ball_pos, target_pos, PASS_LANE_BLOCK_RADIUS, BALL_CONTROL_MAX_HEIGHT):
			var mid_target := _find_best_midfielder_target(ball_pos)
			if mid_target != null:
				target = mid_target
				target_pos = target.global_transform.origin
				target_pos.y = ball_pos.y
				print("FORWARD", owner_peer_id, " SAFETY PASS lane blocked → switching to MID:", target.name)

	var dir := target_pos - ball_pos
	dir.y = 0.0
	var dist := dir.length()

	if dist < 0.01:
		return false

	dir = dir.normalized()

	# scale force by distance
	var t := clampf(dist / PASS_MAX_DIST, 0.0, 1.0)
	var force = lerp(PASS_MIN_FORCE, PASS_MAX_FORCE, t)
	var impulse = dir * force

	# keep pass on the ground
	var lv := ball.linear_velocity
	lv.y = 0.0
	ball.linear_velocity = lv

	ball.set_meta(LAST_PASS_FROM_META, get_path())
	ball.set_meta(LAST_PASS_TIME_META, now_sec)

	ball.apply_hit(impulse, Vector3.ZERO,owner_peer_id )
	_next_pass_time_sec = now_sec + PASS_COOLDOWN_SEC

	# 👇 NEW: if this was FORWARD → FORWARD (or to a human forward),
	# mark it so the receiving forward can do a first-touch trap.
	_mark_ball_pass_trap(ball, _get_my_role(), now_sec, target)



	print("FORWARD", owner_peer_id, " SAFETY PASS to ", target.name,
		" dist=", dist,
		" force=", force,
		" impulse=", impulse)

	return true

func _teammate_near_ball(ball_pos: Vector3, radius: float, my_dist: float) -> bool:
	var my_team := _get_my_team()
	var ball2 := Vector2(ball_pos.x, ball_pos.z)

	var best_dist := radius
	var has_teammate := false

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		# same team only
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		# skip myself
		if int(pid) == owner_peer_id:
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var pos := n.global_transform.origin
		var pos2 := Vector2(pos.x, pos.z)
		var d := pos2.distance_to(ball2)

		if d < best_dist:
			best_dist = d
			has_teammate = true

	# there is a teammate inside radius AND that teammate is closer than me
	if has_teammate and best_dist < my_dist:
		print("BOT", owner_peer_id, " HOLDING: teammate closer to ball (", best_dist, ") than me (", my_dist, ")")
		return true

	return false

func _teammate_controls_ball(ball_pos: Vector3) -> bool:
	var my_team := _get_my_team()
	var ball2 := Vector2(ball_pos.x, ball_pos.z)

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		# same team only
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		# skip myself
		if int(pid) == owner_peer_id:
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var p := n.global_transform.origin

		# must be reachable height-wise
		if abs(ball_pos.y - p.y) > BALL_CONTROL_MAX_HEIGHT:
			continue

		# teammate is close enough to be considered "controlling"
		var p2 := Vector2(p.x, p.z)
		var d := p2.distance_to(ball2)
		if d <= TEAMMATE_BALL_RADIUS:
			return true

	return false


func _bot_forward_closer_to_ball_than_me(ball_pos: Vector3, my_dist: float) -> bool:
	var my_team := _get_my_team()
	var ball2 := Vector2(ball_pos.x, ball_pos.z)

	const EPS := 0.05  # small tolerance to avoid jitter ties

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		# same team only
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		var other_pid := int(pid)

		# skip myself
		if other_pid == owner_peer_id:
			continue

		# ONLY bot forwards
		if not bool(rec.get("is_bot", false)):
			continue

		var role := int(rec.get("role", ROLE_MIDFIELDER))
		if role != ROLE_FORWARD:
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var p2 := Vector2(n.global_transform.origin.x, n.global_transform.origin.z)
		var d := p2.distance_to(ball2)

		# another bot forward is clearly closer
		if d < my_dist - EPS:
			return true

		# tie-break: if basically equal distance, let the lower pid "win"
		if abs(d - my_dist) <= EPS and other_pid < owner_peer_id:
			return true

	return false


func _teammate_closer_to_ball_than_me(ball_pos: Vector3, my_dist: float) -> bool:
	var my_team := _get_my_team()
	var ball2 := Vector2(ball_pos.x, ball_pos.z)

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		# only same team
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		# skip myself
		if int(pid) == owner_peer_id:
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var pos2 := Vector2(n.global_transform.origin.x, n.global_transform.origin.z)
		var d := pos2.distance_to(ball2)

		# teammate is strictly closer to the ball than me
		if d < my_dist:
			return true

	return false


func _compute_forward_home() -> void:
	_forward_home_valid = false

	var world := get_tree().current_scene
	if world == null:
		return

	var ball_spawn := world.get_node_or_null("BallSpawn") as Node3D
	var blue_goal  := world.get_node_or_null(blue_goal_rel_path) as Node3D
	var red_goal   := world.get_node_or_null(red_goal_rel_path) as Node3D

	var am_blue := GameState.is_blue(owner_peer_id)

	# --- centre spot (kickoff point) ---
	var center_spot: Vector3
	if ball_spawn:
		center_spot = ball_spawn.global_transform.origin
	else:
		center_spot = Vector3.ZERO

	var y := global_transform.origin.y
	center_spot.y = y

	# --- opponent goal (the side we attack) ---
	var opp_goal: Node3D = null
	if am_blue:
		opp_goal = red_goal
	else:
		opp_goal = blue_goal

	if opp_goal == null:
		return

	var opp_pos := opp_goal.global_transform.origin
	opp_pos.y = y

	# --- 1) CENTRE HOME: middle of opponent half line ---
	var home_mid := (center_spot + opp_pos) * 0.5
	home_mid.y = y

	# ensure it's actually in opponent half (relative to FIELD_MID_Z)
	if am_blue:
		home_mid.z = max(home_mid.z, FIELD_MID_Z + 1.0)
	else:
		home_mid.z = min(home_mid.z, FIELD_MID_Z - 1.0)

	# --- 2) FORWARD & SIDEWAYS DIRECTIONS ---
	var forward_dir := opp_pos - center_spot
	forward_dir.y = 0.0
	if forward_dir.length() < 0.001:
		# fallback if something is weird
		forward_dir = Vector3(0.0, 0.0, 1.0) if am_blue else Vector3(0.0, 0.0, -1.0)
	forward_dir = forward_dir.normalized()

	# right = UP × forward
	var right_dir := Vector3.UP.cross(forward_dir)
	right_dir.y = 0.0
	if right_dir.length() < 0.001:
		right_dir = Vector3.RIGHT
	right_dir = right_dir.normalized()
	var left_dir := -right_dir

	# --- 3) WING OFFSET: use opp goal posts if available, else constant ---
	var wing_offset := FWD_WING_OFFSET

	var post_left := opp_goal.find_child("Post_L", true, false) as Node3D
	var post_right := opp_goal.find_child("Post_R", true, false) as Node3D
	if post_left != null and post_right != null:
		var L := post_left.global_transform.origin
		var R := post_right.global_transform.origin
		L.y = y
		R.y = y

		var goal_center := (L + R) * 0.5
		var half_vec := L * 0.5#- goal_center
		var half_width := half_vec.length()
		if half_width > 0.5:
			wing_offset = half_width  # put wings roughly in line with posts

	# --- 4) BUILD THREE HOMES ON THAT LINE ---
	_forward_home_center = home_mid
	_forward_home_left   = home_mid + left_dir  * wing_offset
	_forward_home_right  = home_mid + right_dir * wing_offset

	# we don't choose which one yet, that will be done per-frame based on opponents
	_forward_home_point = _forward_home_left  # temporary default
	_forward_home_valid = true

	print("FORWARD", owner_peer_id,
		" homes:",
		" center=", _forward_home_center,
		" left=", _forward_home_left,
		" right=", _forward_home_right,
		" wing_offset=", wing_offset,
		" am_blue=", am_blue)

func _pick_best_forward_idle_home_by_opponents() -> void:
	if not _forward_home_valid:
		_compute_forward_home()
		if not _forward_home_valid:
			return

	var world := get_tree().current_scene
	if world == null:
		return

	var my_team := _get_my_team()

	# opponent goal (the one we attack)
	var am_blue := GameState.is_blue(owner_peer_id)
	var opp_goal := world.get_node_or_null(
		red_goal_rel_path if am_blue else blue_goal_rel_path
	) as Node3D
	if opp_goal == null:
		return

	var opp_goal_pos := opp_goal.global_transform.origin
	opp_goal_pos.y = _forward_home_center.y
	var goal2 := Vector2(opp_goal_pos.x, opp_goal_pos.z)

	var candidates: Array[Vector3] = [
		_forward_home_left,
		_forward_home_center,
		_forward_home_right,
	]

	var best_point := _forward_home_center
	var best_score := -INF

	for p in candidates:
		var min_mid_dist := INF
		var any_mid := false

		# ✅ ONLY consider opponent MIDFIELDERS (ignore enemy GK + enemy forwards)
		for pid in GameState.roster.keys():
			var rec: Dictionary = GameState.roster[pid]

			var team := int(rec.get("team", GameState.Team.BLUE))
			if team == my_team:
				continue

			var role := int(rec.get("role", ROLE_MIDFIELDER))
			if role != ROLE_MIDFIELDER:
				continue  # <-- only midfielders matter

			if not rec.has("player_path"):
				continue

			var n := world.get_node_or_null(rec["player_path"]) as Node3D
			if n == null:
				continue

			any_mid = true
			var opp_pos := n.global_transform.origin
			opp_pos.y = p.y
			var d := opp_pos.distance_to(p)
			if d < min_mid_dist:
				min_mid_dist = d

		# if there are no opponent midfielders (e.g., only GK), treat as very safe
		if not any_mid:
			min_mid_dist = 9999.0

		# ✅ “near enemy goal” bonus: smaller distance-to-goal is better
		var p2 := Vector2(p.x, p.z)
		var dist_to_goal := p2.distance_to(goal2)

		# Score = far from midfielders, but also closer to goal
		var score := min_mid_dist - (dist_to_goal * FWD_GOAL_PROX_WEIGHT)

		if score > best_score:
			best_score = score
			best_point = p

	_forward_home_point = best_point

# ---------- MIDFIELDER ----------

func _update_midfielder_input(delta: float) -> void:
	var ball := _get_ball()

	if ball == null:
		_go_home_idle()
		return

	var now_sec := Time.get_ticks_msec() / 1000.0

	# After receiving/releasing the ball, immediately return home.
	if now_sec < _mid_return_home_until_sec:
		_go_home_idle()
		return

	var origin := global_transform.origin
	var ball_pos := ball.global_transform.origin

	# =========================================================
	# MIDFIELDER ENGAGEMENT RULE
	# ONLY engage when ball is in our own half.
	# =========================================================
	if not _is_ball_in_my_half(ball):
		_go_home_idle()
		return

	# =========================================================
	# From here onward, all midfielder ball logic is allowed.
	# =========================================================

	# Designated pass receiver
	var pending_trap := _has_pending_pass_trap(ball, now_sec)

	# Incoming ball interception
	if not pending_trap:
		if _try_trap_incoming_ball(ball, now_sec):
			return

	# Special pass-receive logic
	if pending_trap:
		var flat := ball_pos - origin
		flat.y = 0.0

		var dist_flat := flat.length()
		var height_diff = abs(ball_pos.y - origin.y)

		_face_point(ball_pos)

		if dist_flat <= MID_FIRST_TRAP_RADIUS \
		and height_diff <= BALL_CONTROL_MAX_HEIGHT:

			if _consume_pass_trap(ball, now_sec):
				ball.linear_velocity = Vector3.ZERO

				var exclude_path := NodePath("")

				if ball.has_meta(PASS_TRAP_META_KEY):
					var info = ball.get_meta(PASS_TRAP_META_KEY)

					if info is Dictionary and info.has("from_path"):
						exclude_path = info["from_path"]

				_try_pass_to_forward_only(ball, true, exclude_path)

				_mid_return_home_until_sec = now_sec + 1.2
				_go_home_idle()
				return

		var dir3 = flat / max(dist_flat, 0.0001)
		_move_towards_direction(dir3, true)
		return

	# =========================================================
	# NORMAL MIDFIELDER LOGIC
	# =========================================================

	# If teammate already controls the ball, go home.
	if _teammate_controls_ball(ball_pos):
		_go_home_idle()
		return

	var flat := ball_pos - origin
	flat.y = 0.0

	var my_dist_flat := flat.length()
	var height_diff = abs(ball_pos.y - origin.y)

	_face_point(ball_pos)

	# Tackle logic
	var opp := _find_nearest_opponent_to_ball(
		ball_pos,
		OPP_HUG_RADIUS,
		BALL_CONTROL_MAX_HEIGHT
	)

	var do_tackle := false

	if opp != null:
		if my_dist_flat <= BOT_TACKLE_RADIUS \
		and my_dist_flat > MID_ARRIVE_RADIUS \
		and height_diff <= BALL_CONTROL_MAX_HEIGHT:
			do_tackle = true

	_net["tackle_pressed"] = do_tackle

	## Ball reached
	#if my_dist_flat <= MID_ARRIVE_RADIUS \
	#and height_diff <= BALL_CONTROL_MAX_HEIGHT:
#
		#_reset_net()
		#_face_point(ball_pos)
#
		#if my_dist_flat <= BOT_CONTROL_RADIUS:
			#_try_pass_to_forward(ball)
#
		#return
	if my_dist_flat <= MID_ARRIVE_RADIUS \
	and height_diff <= BALL_CONTROL_MAX_HEIGHT:

		_reset_net()

		if my_dist_flat <= BOT_CONTROL_RADIUS:
			var kick_direction := origin - ball_pos
			kick_direction.y = 0.0

			if kick_direction.length_squared() > 0.0001:
				kick_direction = kick_direction.normalized()

				ball.linear_velocity = Vector3.ZERO
				ball.apply_hit(
					kick_direction * 24.0,
					Vector3.ZERO,
					owner_peer_id
				)

			_mid_return_home_until_sec = now_sec + 0.5
			_go_home_idle()
			return

		_face_point(ball_pos)
		return
	# Chase
	var want_sprint := my_dist_flat > 10.0

	var dir3 = flat / max(my_dist_flat, 0.0001)

	_move_towards_direction(dir3, want_sprint)


# ---------- FORWARD (DRIBBLE + FINAL SHOT) ----------

func _update_forward_input(delta: float) -> void:
	if not _forward_home_valid:
		_compute_forward_home()

	var ball := _get_ball()
	if ball == null:
		# No ball → just go to "home" in opponent half
		_forward_dribble_phase = 0
		_go_forward_home()
		return
		
	var now_sec := Time.get_ticks_msec() / 1000.0

	# ✅ NEW: trap normal human kicks/shots coming toward me (even if ball isn't in engage zone)
	if _try_trap_incoming_ball(ball, now_sec):
		return

	# ✅ NEW: if this forward is the intended receiver, engage anywhere on the field
	var pending_trap := _has_pending_pass_trap(ball, now_sec)

	# Forward engages when:
	#  - it has a pending trap (was passed to), OR
	#  - ball in centre band, OR
	#  - ball in opponent half
	var engage := pending_trap or _is_ball_in_center_band(ball) or _is_ball_in_opponent_half(ball)

	if engage:
		_forward_handle_kick(ball, ball.global_transform.origin)
	else:
		_forward_dribble_phase = 0
		_go_forward_home()

func _predict_intercept_point(ball_pos: Vector3, ball_vel: Vector3, origin: Vector3, max_t: float) -> Vector3:
	# Predict closest-approach point along the ball's current travel direction (ground plane).
	var v := ball_vel
	v.y = 0.0
	var speed := v.length()
	if speed < 0.001:
		var p := ball_pos
		p.y = origin.y
		return p

	var to_me := origin - ball_pos
	to_me.y = 0.0

	# t = argmin ||(ball_pos + v t) - origin||  (clamped)
	var speed2 := speed * speed
	var t := clampf(to_me.dot(v) / maxf(speed2, 0.001), 0.0, max_t)

	var p2 := ball_pos + v * t
	p2.y = origin.y
	return p2

func _predict_intercept_runner(
	ball_pos: Vector3,
	ball_vel: Vector3,
	runner_pos: Vector3,
	runner_speed: float,
	max_t: float
) -> Vector3:
	var v := ball_vel
	v.y = 0.0
	var d := ball_pos - runner_pos
	d.y = 0.0

	var vv := v.dot(v)
	if vv < 0.0001:
		var p := ball_pos
		p.y = runner_pos.y
		return p

	# Solve |d + v t|^2 = (s t)^2
	# => (vv - s^2)t^2 + 2(d·v)t + d·d = 0
	var s2 := runner_speed * runner_speed
	var a := vv - s2
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)

	var t := 0.0

	if abs(a) < 0.0001:
		# Linear fallback: b t + c = 0
		if abs(b) > 0.0001:
			t = -c / b
		else:
			t = 0.0
	else:
		var disc := b*b - 4.0*a*c
		if disc < 0.0:
			t = 0.0
		else:
			var sdisc := sqrt(disc)
			var t1 := (-b - sdisc) / (2.0*a)
			var t2 := (-b + sdisc) / (2.0*a)

			# pick smallest positive time
			t = INF
			if t1 > 0.0: t = min(t, t1)
			if t2 > 0.0: t = min(t, t2)
			if t == INF: t = 0.0

	t = clampf(t, 0.0, max_t)

	var p2 := ball_pos + v * t
	p2.y = runner_pos.y
	return p2
func _forward_handle_kick(ball: RigidBody3D, ball_pos: Vector3) -> void:
	if ball == null:
		return

	var now_sec := Time.get_ticks_msec() / 1000.0
	var pending_trap := _has_pending_pass_trap(ball, now_sec)

	var origin := global_transform.origin
	var to_ball := ball_pos - origin
	to_ball.y = 0.0
	var dist_to_ball := to_ball.length()
	var height_diff = abs(ball_pos.y - origin.y)

	# ✅ Only yield to other forwards if NOT the intended receiver
	if not pending_trap:
		if _bot_forward_closer_to_ball_than_me(ball_pos, dist_to_ball):
			_forward_dribble_phase = 0
			_go_forward_home()
			return


	var world := get_tree().current_scene
	if world == null:
		return

	var am_blue := GameState.is_blue(owner_peer_id)
	var opp_goal := world.get_node_or_null(
		red_goal_rel_path if am_blue else blue_goal_rel_path
	) as Node3D
	if opp_goal == null:
		return

	var goal_pos := opp_goal.global_transform.origin
	goal_pos.y = ball_pos.y
	var to_goal := goal_pos - ball_pos
	to_goal.y = 0.0
	var dist_goal := to_goal.length()

	var ball_vel := ball.linear_velocity
	ball_vel.y = 0.0
	var ball_speed := ball_vel.length()

	var control_radius := FWD_FIRST_TRAP_RADIUS if pending_trap else FWD_CONTROL_RADIUS

		# If we're not close enough to control the ball → intercept (for passes) or chase (otherwise)
	if dist_to_ball > control_radius or height_diff > BALL_CONTROL_MAX_HEIGHT:
		var v := ball.linear_velocity
		v.y = 0.0
		var speed := v.length()

		# ✅ If this forward is the intended receiver of a pass, go to intercept point
		if pending_trap and speed >= PASS_RECEIVE_MIN_SPEED:
			var intercept := _predict_intercept_runner(
				ball_pos,
				ball.linear_velocity,
				origin,
				BOT_SPRINT_SPEED_EST,
				PASS_RECEIVE_PREDICT_SEC
			)


			var to_i := intercept - origin
			to_i.y = 0.0
			var di := to_i.length()

			_face_point(intercept)

			if di > PASS_RECEIVE_INTERCEPT_RADIUS:
				_move_towards_direction(to_i / maxf(di, 0.0001), true)
				return

			# close enough to intercept point → try first-touch trap
			if _consume_pass_trap(ball, now_sec):
				ball.linear_velocity = Vector3.ZERO
				_net["stop_ball"] = true
				_forward_dribble_phase = 0
				_next_forward_kick_time_sec = now_sec + 0.3
				print("FORWARD", owner_peer_id, " INTERCEPT TRAP at predicted point")
				return

		# fallback: normal chase current ball position
		_face_point(ball_pos)
		var dir_chase = to_ball / max(dist_to_ball, 0.0001)
		_move_towards_direction(dir_chase, true)
		return



	# We are close: we "own" the ball now
	_face_point(goal_pos)

	# ✅ ALIGN-TO-GOAL GATE:
	# If we're not facing the goal, stop/hold the ball briefly while we snap-rotate,
	# then continue normal routine next tick.
	if now_sec < _align_goal_until_sec:
		ball.linear_velocity = Vector3.ZERO
		_net["stop_ball"] = true
		return

	var ang := _flat_angle_to_point(goal_pos)
	if ang > deg_to_rad(FWD_ALIGN_ANGLE_DEG):
		_align_goal_until_sec = now_sec + FWD_ALIGN_HOLD_SEC
		_forward_dribble_phase = 0
		ball.linear_velocity = Vector3.ZERO
		_net["stop_ball"] = true
		# avoid immediately kicking on the same frame we turn
		_next_forward_kick_time_sec = maxf(_next_forward_kick_time_sec, now_sec + 0.12)
		return


	# 🎯 FIRST-TOUCH TRAP AFTER PASS
	# If this ball was just passed from a MID/FWD on our team
	# (midfielder → forward, or forward → forward),
	# then on the first touch we simply stop it and use stop_ball once.
	if pending_trap and _consume_pass_trap(ball, now_sec):
		ball.linear_velocity = Vector3.ZERO
		_net["stop_ball"] = true
		_forward_dribble_phase = 0
		_next_forward_kick_time_sec = now_sec + 0.3
		print("FORWARD", owner_peer_id, " FIRST-TOUCH TRAP after pass")
		return

	# 🛡️ If an opponent is very close to the ball/forward,
	# try a safety pass to nearest human or forward.
	# in _forward_handle_kick
	var danger_opp := _find_nearest_opponent_to_ball(ball_pos, FWD_DANGER_RADIUS, BALL_CONTROL_MAX_HEIGHT)

	if danger_opp != null:
		if _forward_try_safety_pass(ball):
			_forward_dribble_phase = 0
			return
		# if no valid target, we fall through to dribble/shot logic


	# 🔥 Final shot if close enough to goal and ball not flying too fast
	if dist_goal <= FWD_FINAL_SHOT_DIST and ball_speed < 6.0 and now_sec >= _next_forward_kick_time_sec:
		ball.linear_velocity = Vector3.ZERO
		var dir_final := to_goal.normalized()
		ball.apply_hit(dir_final * FWD_FINAL_SHOT_FORCE, Vector3.ZERO,owner_peer_id)
		_next_forward_kick_time_sec = now_sec + FWD_KICK_COOLDOWN_SEC
		_forward_dribble_phase = 0
		print("FORWARD", owner_peer_id, " FINAL SHOT dist_goal=", dist_goal)
		return

	# If we're in cooldown, just stay with the ball
	if now_sec < _next_forward_kick_time_sec:
		var dir_follow = to_ball / max(dist_to_ball, 0.0001)
		_move_towards_direction(dir_follow, false)
		return

	# 🥅 Dribble state machine
	if _forward_dribble_phase == 0:
		# Phase 0: small push towards goal
		var dir_dribble := to_goal.normalized()
		ball.linear_velocity = ball_vel      # keep current ground speed
		ball.apply_hit(dir_dribble * FWD_DRIBBLE_FORCE, Vector3.ZERO, owner_peer_id)
		_forward_dribble_phase = 1
		_next_forward_kick_time_sec = now_sec + FWD_KICK_COOLDOWN_SEC
		print("FORWARD", owner_peer_id, " DRIBBLE KICK dist_goal=", dist_goal)
	else:
		# Phase 1: trap/stop the ball when we reach it again
		ball.linear_velocity = Vector3.ZERO
		_net["stop_ball"] = true
		_forward_dribble_phase = 0
		_next_forward_kick_time_sec = now_sec + 0.2
		print("FORWARD", owner_peer_id, " DRIBBLE TRAP dist_goal=", dist_goal)

	# Keep the bot right around the ball
	var dir_stick = to_ball / max(dist_to_ball, 0.0001)
	_move_towards_direction(dir_stick, false)
# ---------- MISC ----------

func set_spawn_to_current() -> void:
	_spawn_point = global_transform.origin
	_spawn_point_valid = true

	print(
		"BOT HOME SET | id=", owner_peer_id,
		" home=", _spawn_point,
		" team=", _get_my_team()
	)

func _is_human_player(rec: Dictionary) -> bool:
	# Assumes your roster sets `is_bot = true` for bot entries.
	# Humans either don't have `is_bot` or have it = false.
	return not bool(rec.get("is_bot", false))  
func _flat_forward_dir() -> Vector3:
	var f := Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	f.y = 0.0
	return f.normalized()

func _flat_angle_to_point(target: Vector3) -> float:
	var origin := global_transform.origin
	var dir := target - origin
	dir.y = 0.0
	if dir.length() < 0.001:
		return 0.0
	dir = dir.normalized()
	var fwd := _flat_forward_dir()
	return acos(clampf(fwd.dot(dir), -1.0, 1.0))

func get_bot_input() -> Dictionary:
	return _net

func _move_server(
	input_dir: Vector3,
	delta: float,
	is_sprinting: bool,
	move_magnitude: float = 1.0
) -> void:
	if _is_diving:
		var to_target := _dive_target - global_transform.origin
		to_target.y = 0.0

		var max_move := _dive_velocity.length() * delta

		if to_target.length() <= max_move:
			global_transform.origin.x = _dive_target.x
			global_transform.origin.z = _dive_target.z
			velocity = Vector3.ZERO
			_dive_velocity = Vector3.ZERO
			_is_diving = false
			_recovery_timer = recovery_time
			return

		velocity.x = _dive_velocity.x
		velocity.z = _dive_velocity.z
		move_and_slide()
		return

	super._move_server(
		input_dir,
		delta,
		is_sprinting,
		move_magnitude
	)
