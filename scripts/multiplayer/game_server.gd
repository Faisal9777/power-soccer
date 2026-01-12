extends Node

signal hud_update(score_blue:int, score_red:int, time_left:float, phase:String)
signal match_ended(winner:int) # -1 draw, 0 blue, 1 red
# Injected from Lobby/World before/after _ready:
@export var win_scene_path: String = "res://WinScene.tscn"
@export var lose_scene_path: String = "res://DefeatScene.tscn"
@onready var state: Node = get_node("../ingame_state") as Node

@onready var _blue_zone: Area3D = get_node("Teams/TeamBlue/Goal_A/ScoreZone")
@onready var _red_zone:  Area3D = get_node("Teams/TeamRed/Goal_B/ScoreZone")
var _goal_lock := false  # prevents double-trigger spam
var match_config := {
	"duration_sec": 180.0,         # 3 minutes
	"goal_limit": 5,
	"roster": {},                  # {peer_id: {"name":..., "team": BLUE|RED}}
}
# config
var _duration_sec := 180
var _goal_limit := 0
var _roster := {}
var _end_ms: int = -1             # replicated ALWAYS during prestart
var _cd_ms: int = -2
var _all_team_assinged_color := false   
var _scoreboard_instance: Control
var _network_endpoint : Node
var _client : Node
var GameClient := load("res://scripts/multiplayer/game_client.gd")

var game : Dictionary = {}
# ---------- UI ----------
#var _ui_layer: CanvasLayer
#var _hud_layer: CanvasLayer
#var _time_label: Label
#var _score_box: HBoxContainer
#var _score_blue_lbl: Label
#var _score_sep_lbl: Label
#var _score_red_lbl: Label
#var _countdown_label: Label  

var game_data : Dictionary = {}

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
const BLUE := Color(0.20, 0.60, 1.00)
const RED  := Color(1.00, 0.30, 0.30)

func setup(s_cfg: Dictionary, blue: Node3D, red: Node3D, ball_sp: Node3D, scene: Node3D) -> void:
	_duration_sec = s_cfg.get("duration_sec")
	_goal_limit = s_cfg.get("goal_limit")
	_roster = s_cfg.get("roster")
	spawns_blue  = blue
	spawns_red   = red
	ball_spawn   = ball_sp
	ball_scene  = scene


func set_scoreboard(scoreboard : Control) -> void:
	_client.set_scoreboard(scoreboard)
	#var stats_array = get_stats_in_array()
	#_scoreboard_instance.set_stats(stats_array)

func get_stats_in_array() -> Array[Dictionary]:
	var stats: Array[Dictionary] = []

	for k in game.keys():
		var pid: int = int(k)
		var e := game[k] as Dictionary

		# name: prefer _game entry; fall back to GameState.roster
		var name_val: String = ""
		if e.has("name"):
			name_val = String(e["name"])

		# team: derive from your helper
		var team_val := e["team"] as int


		# build one row
		var row: Dictionary = {
			"id": k,
			"name": name_val,
			"team": team_val,
			"goals": int(e.get("goals", 0)),
			"assists": int(e.get("assists", 0)),
			"saves": int(e.get("saves", 0)),  # default to 0 if you don't track it
		}
		stats.append(row)

	# (Optional) stable ordering by id
	stats.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return stats

func start_game() -> void:
	if multiplayer.is_server():
		 # server owns it (peer 1)
		_start_clock_server()
		_start_match_authoritative()

func _build_position_snapshots() -> Dictionary:
	var snapshots: Dictionary = {}  # { pid:int : { "path": NodePath, "global_transform": Transform3D } }

	for k in GameState.roster.keys():
		var pid := int(k)

		# Each roster entry is something like:
		# { "name": ..., "team": ..., "player_path": NodePath or String }
		var entry := GameState.roster[pid] as Dictionary
		if !entry.has("player_path"):
			continue

		var raw_path = entry["player_path"]
		var path: NodePath = raw_path if raw_path is NodePath else NodePath(raw_path)

		var player := get_node_or_null(path) as Node3D
		if player == null:
			# Player not spawned / already freed
			continue

		# Build one snapshot for this player:
		# - store the path so clients can resolve the node
		# - store the full global_transform (position + rotation + scale)
		var snap: Dictionary = {
			"path": path,
			"global_transform": player.global_transform,
		}

		snapshots[pid] = snap
	return snapshots

func _start_clock_server() -> void:
	var now := Time.get_ticks_msec()
	_end_ms = now + _duration_sec * 1000
	state.time_left_ms = _duration_sec * 1000  # will sync to clients on first tick

func _start_countdown_server() -> void:

	state.is_paused = true
	state.countdown_started = true
	var now := Time.get_ticks_msec()
	_cd_ms = now + 3* 1000
	state.countdown_ms = 3 * 1000  # will sync to clients on first tick

func _start_game() -> void:
	state.is_paused = false
	_toggle_player_process(true)
	#_toggle_player_process(false)

func _toggle_player_process(toggle : bool) -> void:
	var switch := false
	if toggle != true:
		switch = true
		
	for k in GameState.roster.keys():
		var p := get_node(GameState.roster[k]["player_path"]) as Node3D
		#print("the player's id is: ", pid)
		if p == null:
			continue
		p.freeze(switch)

func _set_game() -> void:
	_spawn_ball_at(ball_spawn.global_transform.origin)
	#_spawn_players_from_roster()
	
	#var snapshots = _build_position_snapshots()
	#var snapshots = {"ball_scene" : ball_scene.get_path(),
	#"spawns_blue": spawns_blue.get_path(),
	#"spawns_red": spawns_red.get_path()
	#
	#}
	_position_players2()
	#_client.start_game()
	_start_countdown_server()
	#_network_endpoint.rpc("receive_network_input_dictionary", NetCodes.Msg.GAME_BEGIN,{})


func init(game : Node, network_endpoint : Node, is_also_player : bool, roster : Dictionary) -> void:
	state = game
	_network_endpoint = network_endpoint
	state.set_multiplayer_authority(1)
	if is_also_player:
		_initialize_game_updater(roster)





func _ready() -> void:
	
	set_multiplayer_authority(1)
	#if multiplayer.is_server():
		 ## server owns it (peer 1)
		#_start_clock_server()
		#_start_match_authoritative()


func _start_match_authoritative() -> void:
	var world := get_parent()
	_blue_zone = world.get_node("Teams/TeamBlue/Goal_A/ScoreZone")
	_red_zone = world.get_node("Teams/TeamRed/Goal_B/ScoreZone")
	if is_instance_valid(_blue_zone):
		_blue_zone.body_entered.connect(_on_score_zone_body_entered.bind("blue_goal"))
	if is_instance_valid(_red_zone):
		_red_zone.body_entered.connect(_on_score_zone_body_entered.bind("red_goal"))
	_set_game()
	state.toggle_process(true)
	

func _physics_process(delta: float) -> void:
	if state.can_process:
		if multiplayer.is_server():
				_physics_process_server(delta)

		
		
func _physics_process_server(delta: float) -> void:
	if state.time_left_ms == 0:
		_process_game_end()
	if state.is_paused and state.countdown_ms == 0:
		_start_game()
	if not state.is_paused: 
		if _end_ms > 0:
			var now := Time.get_ticks_msec()
			state.time_left_ms = max(0, _end_ms - now)  # this write replicates automatically
			if state.time_left_ms == 0:
				_on_time_up_server()
	if state.countdown_ms > -2:
		var now := Time.get_ticks_msec()
		var remaining := _cd_ms - now   # ms until countdown end
		state.countdown_ms = int(ceil(remaining / 1000.0))

func _initialize_game_updater(roster : Dictionary) -> void:
	_client  = GameClient.new()
	_client.name = "GameClient"
	_network_endpoint.add_child(_client)
	_client.initialize(roster, _network_endpoint, state.get_path(), ball_scene.get_path(), spawns_blue.get_path(), spawns_red.get_path())


func _on_time_up_server() -> void:
	_end_ms = -1
	# …end match, disable input, show UI, etc.
	_end_match_authoritative("time_up")



func _end_match_authoritative(reason: String) -> void:
	if !multiplayer.is_server(): return
	print("time up")
	

func _position_players2() -> void:
	var blue_placed := 1
	var red_placed  := 1

	# Find a target to face: live Ball if it exists, else the BallSpawn
	var ball := ball_scene
	#var target_pos := ball.global_transform.origin if ball != null else ball_spawn.global_transform.origin
	#var target_pos := ball_spawn.global_position
	for k in GameState.roster.keys():
		var pid := int(k)
		var name := String(GameState.roster.get(pid, {}).get("name", ""))
		var team := int(GameState.roster.get(pid, {}).get("team", 0))
		#print("about to calll _cl_init_entry: ", multiplayer.get_unique_id())
		# initialize only if missing
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
		p.focus_at(ball)
		p.freeze(true)

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
	var p = get_node(path)
	if p:
		p.aim_camera_at(target_pos, 0.0, true)
	else:
		print("tha players path was not found")

#func _position_players2() -> void:
	#var blue_placed := 1
	#var red_placed  := 1
#
	## Find a target to face: live Ball if it exists, else the BallSpawn
	#var ball := ball_scene
	##var target_pos := ball.global_transform.origin if ball != null else ball_spawn.global_transform.origin
	#var target_pos := ball_spawn.global_position
	#for k in GameState.roster.keys():
		#var pid := int(k)
		#var name := String(GameState.roster.get(pid, {}).get("name", ""))
		#var team := int(GameState.roster.get(pid, {}).get("team", 0))
		##print("about to calll _cl_init_entry: ", multiplayer.get_unique_id())
		## initialize only if missing
		#var p := get_node(GameState.roster[k]["player_path"]) as Node3D
		##print("the player's id is: ", pid)
		#if p == null:
			#continue
#
		#if GameState.is_blue(pid):
			#var sp := spawns_blue.get_node_or_null("Spawn%d" % blue_placed) as Node3D
			#if sp:
				#p.global_transform = sp.global_transform
				#blue_placed += 1
		#else:
			#var sp := spawns_red.get_node_or_null("Spawn%d" % red_placed) as Node3D
			#if sp:
				#p.global_transform = sp.global_transform
				#red_placed += 1
		## tell that specific client to aim their camera
#
		#_init_entry(pid, name, team)
		#p.focus_at(ball)
		#p.freeze(true)


#func _init_entry(pid: int, name: String, team: int) -> void:
	## Each peer (and the caller) runs this locally
	#game.get_or_add(pid, {
		#"name": name,
		#"goals": 0,
		#"team": team,
		#"assists": 0,
		#"saves": 0,
	#}) as Dictionary
	#if _scoreboard_instance:
		#var stats_array = get_stats_in_array()
		#_scoreboard_instance.set_stats(stats_array)

func _process_game_end() -> void:
	state.toggle_process(false)
	var blue_scene := ""
	var red_scene := ""
	if state.blue_score > state.red_score:
		blue_scene = win_scene_path
		red_scene = lose_scene_path
	else:
		blue_scene = lose_scene_path
		red_scene = win_scene_path
	for k in GameState.roster.keys():
		var p := get_node(GameState.roster[k]["player_path"]) as Node3D		
		p.freeze(true)
		var pid = int(k)
		if GameState.is_blue(pid):
			rpc_id(pid, "_cl_end_match", "End!", 3.0, blue_scene)
		else:
			rpc_id(pid, "_cl_end_match", "End!", 3.0, red_scene)


#@rpc("authority", "reliable", "call_local")
#func _cl_set_team_id(p_path: NodePath, is_blue : bool) -> void:
	#var p := get_node(p_path)
	#_set_player_team_color(p, is_blue)



func _pick_spawn(team:int, blue_i:int, red_i:int) -> Node3D:
	return spawns_blue[min(blue_i, spawns_blue.size()-1)] if team == GameState.Team.BLUE \
		else spawns_red[min(red_i, spawns_red.size()-1)]

func _spawn_ball_at(pos: Vector3) -> void:
	# Reuse if exists; otherwise instance
	#var ball := ball_holder.get_node_or_null("Ball")
	var ball := ball_scene
	_stop_ball(ball)
	if ball == null:
		print("ball was not found")
	pos.y += 3
	ball.global_transform.origin = pos

func _stop_ball(ball: RigidBody3D) -> void:
	if ball == null: return
	# Clear instantaneous motion
	ball.linear_velocity  = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	# Clear any continuous forces/torques that would re-accelerate it
	ball.constant_force   = Vector3.ZERO
	ball.constant_torque  = Vector3.ZERO
	# Optional: make sure it actually stops this frame
	ball.sleeping = true


func _freeze_all_players(v: bool) -> void:
	for p in players_root.get_children():
		if p.has_method("freeze_input"):
			p.call("freeze_input", v)


func _countdown_seconds(s: float) -> Signal:
	var t := get_tree().create_timer(s)
	return t.timeout
func _on_score_zone_body_entered(body: Node3D, which_goal: String) -> void:         # server-only logic
	if _goal_lock: return
	if not body.is_in_group("ball"): return       # tag your ball with group "ball"
	_goal_lock = true
	_handle_goal(which_goal, body)
#func _handle_goal(which_goal: String, ball : Node3D) -> void:
	## Example: ball in *red* goal means BLUE scores
	#var scoring_team := "red"
	#if which_goal == "blue_goal":
		#scoring_team = "blue"
	#_add_point(scoring_team, ball)
	## Wait 3 seconds, then reset
	## Show "Goal!" on every client (server does NOT run it)
	#var secs := 3
	#rpc("_cl_handle_goal_outcome", "Goal!", secs)
	## server waits locally; this does not block clients
	#await get_tree().create_timer(secs).timeout
	#_set_game()
	#_goal_lock = false	

func _handle_goal(which_goal: String, ball : Node3D) -> void:
	# Example: ball in *red* goal means BLUE scores
	var scoring_team := "red"
	if which_goal == "blue_goal":
		scoring_team = "blue"
	_add_point(scoring_team, ball)
	# Wait 3 seconds, then reset
	# Show "Goal!" on every client (server does NOT run it)
	state.is_paused = false
	var secs := 3
	state.goal_scored = true
	await get_tree().create_timer(secs).timeout
	state.goal_scored = false
	
	_set_game()
	_goal_lock = false

func _add_point(scoring_team: String, ball : Node3D) -> void:
	var goal_player = ball.get_player(0)
	var assist_player = ball.get_player(1)
	#if goal_player != -1 and not GameState.is_in_the_same_team(goal_player, scoring_team):
		#game[goal_player]["goals"] += 1
	#else:
		#game[goal_player]["goals"] -= 1
	#if assist_player != -1 and not GameState.is_in_the_same_team(goal_player, scoring_team):
		#game[goal_player]["assists"] += 1
	#if scoring_team == "red":
		#blue_score += 1
	#else:
		#red_score += 1
	#var stats_array = get_stats_in_array()
	#_scoreboard_instance.set_stats(stats_array)
	_apply_goal_update(scoring_team, goal_player, assist_player, GameState.is_in_the_same_team(goal_player, scoring_team))
	#rpc("_cl_apply_goal_update", scoring_team, goal_player, assist_player, GameState.is_in_the_same_team(goal_player, scoring_team))

@rpc("authority", "reliable", "call_local")
func _cl_apply_goal_update(scoring_team : String, goal_player : int, assist_player : int, is_in_the_same_team : bool) -> void:
	if goal_player != -1 and not is_in_the_same_team:
		state.add_goal(goal_player)
	else:
		state.sub_goal(goal_player)
	if assist_player != -1 and not is_in_the_same_team:
		state.add_assist(assist_player)
	if scoring_team == "red":
		state.blue_score += 1
	else:
		state.red_score += 1
	#var stats_data = state.get_game_data()
	#_scoreboard_instance.set_stats(stats_data)

func _apply_goal_update(scoring_team : String, goal_player : int, assist_player : int, is_in_the_same_team : bool) -> void:
	if goal_player != -1 and not is_in_the_same_team:
		state.add_goal(goal_player)
	else:
		state.sub_goal(goal_player)
	if assist_player != -1 and not is_in_the_same_team:
		state.add_assist(assist_player)
	if scoring_team == "red":
		state.blue_score += 1
	else:
		state.red_score += 1
	#var stats_data = state.get_game_data()
	#

@rpc("authority", "reliable", "call_local") 
func _cl_handle_goal_outcome(text: String, seconds: float) -> void:
	await _show_banner_for(text, seconds)

func _show_banner_for(text: String, seconds: float) -> void:
	#if _countdown_label == null:  # or is_instance_valid(_countdown_label)
		#return
	#_countdown_label.text = text
	#_countdown_label.show()
	#var t := get_tree().create_timer(seconds)  # local, per-client
	#await t.timeout
	#_countdown_label.hide()
	return



# On the same node (path) on all peers:
@rpc("authority", "reliable", "call_local")  # server calls; clients execute
func _cl_end_match(text: String, seconds: float, scene_path_to_load: String) -> void:
	await _show_banner_for(text, seconds)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(scene_path_to_load)
# On the same node (path) on all peers:
@rpc("any_peer", "reliable")  # server calls; clients execute
func _cl_set_game(game : String) -> void:
	print("_cl_set_game: ", game)
	print("multiplayer.get_unique_id(): ", multiplayer.get_unique_id())
	#_game = game

func transmission_completed() -> void:
	_start_countdown_server()
	#_game = game


	#print("the player with id ", goal_player,
	  #" goaled who belongs to ", scoring_team,
	  #" whose goal is now ", GameState.roster[goal_player]["goals"])
