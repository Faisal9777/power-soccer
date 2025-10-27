extends Node
class_name Game

signal hud_update(score_blue:int, score_red:int, time_left:float, phase:String)
signal match_ended(winner:int) # -1 draw, 0 blue, 1 red
# Injected from Lobby/World before/after _ready:
var match_config := {
	"duration_sec": 180.0,         # 3 minutes
	"goal_limit": 5,
	"roster": {},                  # {peer_id: {"name":..., "team": BLUE|RED}}
}
var spawns_blue: Node3D
var spawns_red:  Node3D
var ball_spawn:  Node3D
var ball_scene: Node3D
# Scene references (set on _ready by grabbing from World)
#var spawns_blue: Array[Node3D] = []
#var spawns_red:  Array[Node3D] = []

var players_root: Node
var ball_holder: Node

# State
var score_blue := 0
var score_red  := 0
var time_left  := 0.0
var phase      := "waiting"   # waiting|kickoff|playing|goal_freeze|ended

# Networking
var IS_HOST := GameState.is_host


func setup(cfg: Dictionary, blue: Node3D, red: Node3D, ball_sp: Node3D, scene: Node3D) -> void:
	match_config = cfg
	spawns_blue  = blue
	spawns_red   = red
	ball_spawn   = ball_sp
	ball_scene  = scene

func _ready() -> void:
	# Pull references from World
	var world := get_parent()
	#ball_spawn   = world.get_node("BallSpawn")
	#ball_holder  = world.get_node("BallHolder")
	#players_root = world.get_node("PlayersRoot")
	#for c in world.get_node("Spawns/Blue").get_children():
		#if c is Node3D: spawns_blue.append(c)
	#for c in world.get_node("Spawns/Red").get_children():
		#if c is Node3D: spawns_red.append(c)

	# Connect goal signals
	#world.get_node("Goals/BlueGoalArea").goal_scored.connect(_on_goal_scored)
	#world.get_node("Goals/RedGoalArea").goal_scored.connect(_on_goal_scored)

	if IS_HOST:
		_start_match_authoritative()
	# clients just wait for RPC updates

func _start_match_authoritative() -> void:
	# Spawn players according to roster
	# Spawn ball at center
	_spawn_ball_at(ball_spawn.global_transform.origin)
	#_spawn_players_from_roster()
	_position_players()
	# Init clock
	#time_left = float(match_config.get("duration_sec", 180.0))
	#_set_phase("kickoff")
	#_do_kickoff_positions()
	## small countdown then start
	#await _countdown_seconds(3)
	#_set_phase("playing")

func _process(delta: float) -> void:
	if !IS_HOST: return
	if phase in ["playing", "kickoff"]:
		time_left = max(0.0, time_left - delta)
		_emit_hud()
		if time_left <= 0.0:
			_end_match_if_needed()

func _spawn_players_from_roster() -> void:
	# player_scene should be known (from GameState or exported on World)
	var scene: PackedScene = GameState.player_scene
	var blue_i := 0
	var red_i  := 0
	for pid in match_config.roster.keys():
		var info : Dictionary = match_config.roster[pid]
		var team := int(info.team) if info.has("team") else GameState.Team.BLUE
		var p := scene.instantiate()
		p.name = "P_%s" % str(pid)
		players_root.add_child(p, true)
		# set networking authority if you use per-player authority
		if IS_HOST: p.set_multiplayer_authority(pid)

		var spawn := _pick_spawn(team, blue_i, red_i)
		p.global_transform.origin = spawn.global_transform.origin
		p.call_deferred("reset_state") # clear velocity, stamina, etc.

		if team == GameState.Team.BLUE: blue_i += 1
		else:                           red_i  += 1

@rpc("any_peer", "reliable", "call_local")
func _rpc_aim_camera(target_pos: Vector3, path: NodePath) -> void:
	# On the owning client, call on its local player
	print("_rpc_aim_camera: " , multiplayer.get_unique_id())
	var p = get_node(path)
	if p:
		p.aim_camera_at(target_pos, 0.0, true)
	else:
		print("tha players path was not found")

func _position_players() -> void:
	var blue_placed := 1
	var red_placed  := 1

	# Find a target to face: live Ball if it exists, else the BallSpawn
	var ball := ball_scene
	#var target_pos := ball.global_transform.origin if ball != null else ball_spawn.global_transform.origin
	var target_pos := ball_spawn.global_position
	for k in GameState.roster.keys():
		var pid := int(k)
		var p := get_node(GameState.roster[k]["player_path"]) as Node3D
		#print("the player's id is: ", pid)
		if p == null:
			continue

		if GameState.is_blue(pid):
			var sp := spawns_blue.get_node_or_null("Spawn%d" % blue_placed) as Node3D
			if sp:
				p.global_transform = sp.global_transform
				blue_placed += 1
		else:
			var sp := spawns_red.get_node_or_null("Spawn%d" % red_placed) as Node3D
			if sp:
				p.global_transform = sp.global_transform
				red_placed += 1
		# tell that specific client to aim their camera
		var from := p.global_position
		p.rpc_id(pid, "rpc_aim_camera_at", target_pos, from)



func _face_towards_xz(n: Node3D, target: Vector3) -> void:
	# yaw-only: ignore vertical difference so players don't tilt up/down
	var from := n.global_transform.origin
	var dir := target - from
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		return
	n.look_at(from + dir.normalized(), Vector3.UP)  # -Z will point toward target
func _pick_spawn(team:int, blue_i:int, red_i:int) -> Node3D:
	return spawns_blue[min(blue_i, spawns_blue.size()-1)] if team == GameState.Team.BLUE \
		else spawns_red[min(red_i, spawns_red.size()-1)]

func _spawn_ball_at(pos: Vector3) -> void:
	# Reuse if exists; otherwise instance
	#var ball := ball_holder.get_node_or_null("Ball")
	var ball := ball_scene
	if ball == null:
		print("ball was not found")
	pos.y += 3
	ball.global_transform.origin = pos


func _do_kickoff_positions() -> void:
	# Center ball; move all players to their nearest team spawn (or a formation)
	_spawn_ball_at(ball_spawn.global_transform.origin)
	for p in players_root.get_children():
		if !("team" in p): continue
		var team := int(p.team)
		var idx  : int = p.get("team_index") if p.has_method("get") else 0
		var spawn := _pick_spawn(team, idx, idx)
		p.call("freeze_input", true)
		p.global_transform.origin = spawn.global_transform.origin
		p.call_deferred("reset_state")

func _set_phase(ph: String) -> void:
	phase = ph
	_emit_hud()
	if IS_HOST:
		rpc("_rpc_set_phase", phase, time_left, score_blue, score_red)

@rpc("any_peer", "call_local")
func _rpc_set_phase(ph: String, t: float, sb: int, sr: int) -> void:
	phase = ph; time_left = t; score_blue = sb; score_red = sr
	_emit_hud()

func _emit_hud() -> void:
	emit_signal("hud_update", score_blue, score_red, time_left, phase)

func _on_goal_scored(scoring_team:int) -> void:
	if !IS_HOST or phase == "ended": return
	# Update scores
	if scoring_team == GameState.Team.BLUE: score_blue += 1
	else: score_red += 1
	_set_phase("goal_freeze")

	# Freeze briefly, then respawn & kickoff
	_freeze_all_players(true)
	await _countdown_seconds(2)

	# Decide respawn layout: ball center, both teams to their half spawns
	_do_kickoff_positions()
	await _countdown_seconds(2)

	# Win check (goal limit)
	var limit := int(match_config.get("goal_limit", 0))
	if limit > 0 and (score_blue >= limit or score_red >= limit):
		_end_match_if_needed()
	else:
		_freeze_all_players(false)
		_set_phase("playing")

func _freeze_all_players(v: bool) -> void:
	for p in players_root.get_children():
		if p.has_method("freeze_input"):
			p.call("freeze_input", v)

func _end_match_if_needed() -> void:
	if phase == "ended": return
	_set_phase("ended")
	var winner := -1
	if score_blue > score_red: winner = GameState.Team.BLUE
	elif score_red > score_blue: winner = GameState.Team.RED
	emit_signal("match_ended", winner)
	if IS_HOST:
		rpc("_rpc_goto_victory", winner, score_blue, score_red)

@rpc("any_peer", "call_local")
func _rpc_goto_victory(winner:int, sb:int, sr:int) -> void:
	# Optionally stash result in GameState then change scene
	GameState.last_result = {"winner": winner, "blue": sb, "red": sr}
	get_tree().change_scene_to_file("res://Victory.tscn")

func _countdown_seconds(s: float) -> Signal:
	var t := get_tree().create_timer(s)
	return t.timeout
