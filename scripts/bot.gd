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

const GUARD_RADIUS: float = 30.0      # how close to goal center before "keeper mode" starts
const SLIDE_DEADZONE: float = 0.1     # how close along the line before we stop sliding

const FIELD_MID_Z := 0.0          # centre line of field (same as your World plane_z)
const MID_ARRIVE_RADIUS := 5.0    # how close to the ball is “reached”
const MID_HOME_TOL := 0.5         # how close to spawn is “home”

# 🔹 NEW: tackle behaviour
const OPP_HUG_RADIUS := 5.0       # how close to the ball the opponent must be ("hugging")
const BOT_TACKLE_RADIUS := 6    # how close WE must be to start tackling

# 🔹 NEW: pass behaviour (midfielder)
const BOT_CONTROL_RADIUS := 4.5    # how close WE must be to "own" the ball
const PASS_MIN_FORCE := 1.0       # soft short pass
const PASS_MAX_FORCE := 6.0       # strongest pass
const PASS_MAX_DIST  := 25.0      # distance at which we use MAX_FORCE
const PASS_COOLDOWN_SEC := 1.5

const TEAMMATE_BALL_RADIUS := 5.0   # how close a teammate must be to "own" the ball

# 🔹 Forward logic
const CENTER_BAND_Z := 4.0   # how wide the "centre zone" is around FIELD_MID_Z

const FWD_CONTROL_RADIUS := 4.0        # how close forward must be to "own" the ball
const FWD_DRIBBLE_FORCE := 0.6         # soft nudge towards goal
const FWD_FINAL_SHOT_FORCE := 10.0     # big shot near goal
const FWD_FINAL_SHOT_DIST := 35.0      # if ball is this close to goal → use final shot
const FWD_KICK_COOLDOWN_SEC := 0.8     # delay between touches so it doesn't spam
const FWD_DANGER_RADIUS := 10.0  
const FWD_TRAP_MAX_AGE_SEC := 2.0   # how long after a pass the special first-trap is allowed

const BALL_CONTROL_MAX_HEIGHT := 1.8
# how many meters above/below the player's origin we still consider "reachable"

var _forward_home_point: Vector3 = Vector3.ZERO
var _forward_home_valid: bool = false

var _next_pass_time_sec := 0.0
var _next_forward_kick_time_sec := 0.0
var _forward_dribble_phase: int = 0     # 0 = dribble kick, 1 = trap phase

var _goal_point: Vector3 = Vector3.ZERO
var _home_goal_point: Vector3 = Vector3.ZERO
var _goal_valid: bool = false
var _cached_team: int = -1

var _spawn_point: Vector3

var _debug_last_tackle := false

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


func _ready() -> void:
	super._ready()
	# We can pick the goal on all peers; only the server will actually drive the bot.
	_pick_goal_point()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_update_bot_input(delta)
	super._physics_process(delta)


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
	var pos3: Vector3 = global_transform.origin
	var pos2 := Vector2(pos3.x, pos3.z)
	var home2 := Vector2(_home_goal_point.x, _home_goal_point.z)

	var ball := _get_ball()
	var dist_to_home := pos2.distance_to(home2)

	# ---------- GUARD MODE: slide along a line in front of the posts ----------
	if ball != null and _has_goal_line and dist_to_home <= GUARD_RADIUS and _goal_forward != Vector3.ZERO:
		var ball3 := ball.global_transform.origin
		var ball2 := Vector2(ball3.x, ball3.z)

		# Line we are actually guarding: posts line shifted forward by guard_depth
		var base_center3: Vector3 = _goal_line_center + _goal_forward * guard_depth
		var base_center2 := Vector2(base_center3.x, base_center3.z)
		var dir2 := Vector2(_goal_line_dir.x, _goal_line_dir.z)  # normalized

		# project ball onto *guard line*
		var rel_ball := ball2 - base_center2
		var t_ball: float = rel_ball.dot(dir2)
		# clamp inside posts span, so we never go beyond them
		t_ball = clampf(t_ball, -_goal_line_half_len, _goal_line_half_len)

		# target point on the guard line where we want to stand
		var slide_point3: Vector3 = base_center3 + _goal_line_dir * t_ball
		slide_point3.y = _home_goal_point.y
		_goal_point = slide_point3

		# distance from us to that point (in XZ)
		var target2 := Vector2(slide_point3.x, slide_point3.z)
		var delta2 := target2 - pos2
		var dist_slide := delta2.length()

		# close enough → just stand and be a wall
		if dist_slide <= SLIDE_DEADZONE:
			return

		# world direction along the ground toward our slide_point
		var slide_dir3 := Vector3(delta2.x, 0.0, delta2.y).normalized()

		# decompose that direction into mvx/mvz using our own yaw
		var yaw := rotation.y
		var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
		fwd.y = 0.0
		fwd = fwd.normalized()

		var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
		right.y = 0.0
		right = right.normalized()

		var mvx := slide_dir3.dot(right) * slide_move_strength
		var mvz := slide_dir3.dot(fwd) * slide_move_strength

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

	var pid := owner_peer_id
	var am_blue := GameState.is_blue(pid)

	if am_blue:
		return ball_z <= FIELD_MID_Z             # blue half
	else:
		return ball_z >= FIELD_MID_Z             # red half


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

func _find_best_human_teammate_target(ball_pos: Vector3) -> Node3D:
	var my_team := _get_my_team()
	var best: Node3D = null
	var best_dist := INF

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		# same team only
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		# skip myself
		if int(pid) == owner_peer_id:
			continue

		# must be human-controlled
		if not _is_human_player(rec):
			continue

		if not rec.has("player_path"):
			continue

		var n := get_tree().current_scene.get_node_or_null(rec["player_path"]) as Node3D
		if n == null:
			continue

		var pos := n.global_transform.origin
		pos.y = 0.0

		var d := pos.distance_to(ball_pos)
		if d < best_dist:
			best_dist = d
			best = n

	return best


func _find_best_forward_target(ball_pos: Vector3) -> Node3D:
	var my_team := _get_my_team()
	var best: Node3D = null
	var best_dist := INF
	var ball2 := Vector2(ball_pos.x, ball_pos.z)

	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]

		# same team only
		var team := int(rec.get("team", GameState.Team.BLUE))
		if team != my_team:
			continue

		# ❌ skip myself completely
		if int(pid) == owner_peer_id:
			continue

		# must be a forward
		var role := int(rec.get("role", ROLE_MIDFIELDER))
		if role != ROLE_FORWARD:
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
			best = n

	return best

func _mark_ball_pass_for_forward_trap(
	ball: RigidBody3D,
	from_role: int,
	now_sec: float,
	receiver: Node
) -> void:
	if ball == null or receiver == null:
		return

	var info := {
		"team": _get_my_team(),
		"from_role": from_role,   # ROLE_MIDFIELDER or ROLE_FORWARD
		"timestamp": now_sec,
		"used": false,
		"receiver_path": receiver.get_path(),   # 👈 who should get the special trap
	}
	ball.set_meta("forward_trap_info", info)


func _forward_consume_pass_trap(ball: RigidBody3D, now_sec: float) -> bool:
	if ball == null:
		return false
	if not ball.has_meta("forward_trap_info"):
		return false

	var info = ball.get_meta("forward_trap_info")
	if not (info is Dictionary):
		return false

	# already used by someone
	if bool(info.get("used", false)):
		return false

	# Must be same team as passer
	var team := int(info.get("team", -1))
	if team != _get_my_team():
		return false

	# 👇 NEW: must be the *intended* receiver
	if info.has("receiver_path"):
		var expected_path: NodePath = info["receiver_path"]
		if expected_path != get_path():
			# not my pass to trap
			return false

	# Only for a short time after the pass
	var age := now_sec - float(info.get("timestamp", now_sec))
	if age > FWD_TRAP_MAX_AGE_SEC:
		return false

	# Only if the pass came from MID or FWD
	var from_role := int(info.get("from_role", ROLE_MIDFIELDER))
	if from_role != ROLE_MIDFIELDER and from_role != ROLE_FORWARD:
		return false

	# ✅ OK, this forward is the correct receiver → consume the trap
	info["used"] = true
	ball.set_meta("forward_trap_info", info)
	return true

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

	ball.apply_impulse(impulse, Vector3.ZERO)
	_next_pass_time_sec = now_sec + PASS_COOLDOWN_SEC

	# 👇 NEW: mark that this was a MID → FORWARD pass,
	# so the receiving forward can do a first-touch trap.
	var target_role := _get_role_for_node(target)
	if target_role == ROLE_FORWARD:
		_mark_ball_pass_for_forward_trap(ball, _get_my_role(), now_sec, target)


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

	ball.apply_impulse(impulse, Vector3.ZERO)
	_next_pass_time_sec = now_sec + PASS_COOLDOWN_SEC

	# 👇 NEW: if this was FORWARD → FORWARD (or to a human forward),
	# mark it so the receiving forward can do a first-touch trap.
	var target_role := _get_role_for_node(target)
	if target_role == ROLE_FORWARD:
		_mark_ball_pass_for_forward_trap(ball, _get_my_role(), now_sec, target)


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

	var center: Vector3
	if ball_spawn:
		center = ball_spawn.global_transform.origin
	else:
		center = Vector3.ZERO

	var opp_goal: Node3D = null
	if am_blue:
		opp_goal = red_goal
	else:
		opp_goal = blue_goal

	var home := center

	if opp_goal != null:
		var opp_pos := opp_goal.global_transform.origin
		# midpoint between centre spot and opponent goal → "centre of their half"
		home = (center + opp_pos) * 0.5

	# keep at our ground height
	home.y = global_transform.origin.y

	# make sure it's actually in opponent half (relative to FIELD_MID_Z)
	if am_blue:
		home.z = max(home.z, FIELD_MID_Z + 1.0)
	else:
		home.z = min(home.z, FIELD_MID_Z - 1.0)

	_forward_home_point = home
	_forward_home_valid = true

	print("FORWARD", owner_peer_id, " home set to ", _forward_home_point, " am_blue=", am_blue)


# ---------- MIDFIELDER ----------

func _update_midfielder_input(delta: float) -> void:
	var ball := _get_ball()
	if ball == null:
		# no ball? just go home and stand there
		_go_home_idle()
		return

	var origin := global_transform.origin
	var ball_pos := ball.global_transform.origin

	# 1) Only chase if ball is in my half
	if _is_ball_in_my_half(ball):
		# horizontal distance (XZ)
		var flat := ball_pos - origin
		flat.y = 0.0
		var my_dist_flat := flat.length()

		# vertical distance
		var height_diff = abs(ball_pos.y - origin.y)

		# Always look at the ball while in chase mode
		_face_point(ball_pos)

		# --- TACKLE CONDITIONS (only if ball is not too high) ---
		var opp := _find_nearest_opponent_to_ball(ball_pos, OPP_HUG_RADIUS, BALL_CONTROL_MAX_HEIGHT)
		var do_tackle := false

		if opp != null:
			if my_dist_flat <= BOT_TACKLE_RADIUS and my_dist_flat > MID_ARRIVE_RADIUS and height_diff <= BALL_CONTROL_MAX_HEIGHT:
				do_tackle = true

		_net["tackle_pressed"] = do_tackle

		# If we are very close to the ball AND it's not a high lob → we "own" it
		if my_dist_flat <= MID_ARRIVE_RADIUS and height_diff <= BALL_CONTROL_MAX_HEIGHT:
			_reset_net()
			_face_point(ball_pos)

			print("BOT", owner_peer_id, " AT BALL | dist_flat=", my_dist_flat, " height_diff=", height_diff)

			if my_dist_flat <= BOT_CONTROL_RADIUS:
				print("BOT", owner_peer_id, " CONTROL BALL → try pass")
				_try_pass_to_forward(ball)
			else:
				print("BOT", owner_peer_id, " within arrive radius but not CONTROL radius (",
					BOT_CONTROL_RADIUS, ")")

			return
		# If we're under the ball but it's too high, just keep moving under it (no pass)

		# --- SPRINT LOGIC ---
		var want_sprint := my_dist_flat > 12.0  # far = sprint, close = jog
		var dir3 = flat / max(my_dist_flat, 0.0001)
		_move_towards_direction(dir3, want_sprint)
		return



	# 2) ball NOT in my half → go back to spawn and idle
	_go_home_idle()


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

	# Forward only engages when ball is:
	#  - in centre band, OR
	#  - in opponent half
	var engage := _is_ball_in_center_band(ball) or _is_ball_in_opponent_half(ball)

	if engage:
		_forward_handle_kick(ball, ball.global_transform.origin)
	else:
		_forward_dribble_phase = 0
		_go_forward_home()


func _forward_handle_kick(ball: RigidBody3D, ball_pos: Vector3) -> void:
	if ball == null:
		return

	var origin := global_transform.origin
	var to_ball := ball_pos - origin
	to_ball.y = 0.0
	var dist_to_ball := to_ball.length()
	var height_diff = abs(ball_pos.y - origin.y)

	# If any teammate is closer to the ball than this forward,
	# stop chasing and go back to home.
	if _teammate_closer_to_ball_than_me(ball_pos, dist_to_ball):
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

	var now_sec := Time.get_ticks_msec() / 1000.0

	# If we're not close enough to control the ball → chase it
	if dist_to_ball > FWD_CONTROL_RADIUS or height_diff > BALL_CONTROL_MAX_HEIGHT:

		_face_point(ball_pos)
		var dir_chase = to_ball / max(dist_to_ball, 0.0001)
		_move_towards_direction(dir_chase, true)
		return

	# We are close: we "own" the ball now
	_face_point(goal_pos)

	# 🎯 FIRST-TOUCH TRAP AFTER PASS
	# If this ball was just passed from a MID/FWD on our team
	# (midfielder → forward, or forward → forward),
	# then on the first touch we simply stop it and use stop_ball once.
	if _forward_consume_pass_trap(ball, now_sec):
		ball.linear_velocity = Vector3.ZERO
		_net["stop_ball"] = true
		_forward_dribble_phase = 0               # next time we start normal dribble cycle
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
		ball.apply_impulse(dir_final * FWD_FINAL_SHOT_FORCE, Vector3.ZERO)
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
		ball.apply_impulse(dir_dribble * FWD_DRIBBLE_FORCE, Vector3.ZERO)
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
func _is_human_player(rec: Dictionary) -> bool:
	# Assumes your roster sets `is_bot = true` for bot entries.
	# Humans either don't have `is_bot` or have it = false.
	return not bool(rec.get("is_bot", false))
