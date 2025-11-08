extends Node
class_name Game

signal hud_update(score_blue:int, score_red:int, time_left:float, phase:String)
signal match_ended(winner:int) # -1 draw, 0 blue, 1 red
# Injected from Lobby/World before/after _ready:
@export var win_scene_path: String = "res://WinScene.tscn"
@export var lose_scene_path: String = "res://DefeatScene.tscn"


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
var _end_ms: int = -1
var _game : Dictionary = {}
var countdown_ms: int = 0                 # replicated ALWAYS during prestart
var _cd_ms: int = -2
var is_paused := true 
var _all_team_assinged_color := false   
# ---------- replicated property ----------
var time_left_ms: int = 0    # <— this is the ONLY thing we sync
var blue_score: int = 0           # NEW: server writes, clients read
var red_score: int = 0  
var can_process := true;
var scene_path_to_load := ""
# ---------- UI ----------
var _ui_layer: CanvasLayer
var _hud_layer: CanvasLayer
var _time_label: Label
var _score_box: HBoxContainer
var _score_blue_lbl: Label
var _score_sep_lbl: Label
var _score_red_lbl: Label
var _countdown_label: Label  

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

func get_stats_in_array() -> Array[Dictionary]:
	print("_game: ", _game)
	var stats: Array[Dictionary] = []

	for k in GameState.roster.keys():
		var pid: int = int(k)
		var e := _game[k] as Dictionary

		# name: prefer _game entry; fall back to GameState.roster
		var name_val: String = ""
		if e.has("name"):
			name_val = String(e["name"])
		else:
			name_val = String(GameState.roster.get(pid, {}).get("name", ""))

		# team: derive from your helper
		var team_val := GameState.Team.BLUE
		if not GameState.is_blue(pid):
			team_val = GameState.Team.RED

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
	print("stats: ", stats)
	return stats

func _start_clock_server() -> void:
	var now := Time.get_ticks_msec()
	_end_ms = now + _duration_sec * 1000
	time_left_ms = _duration_sec * 1000  # will sync to clients on first tick

func _start_countdown_server() -> void:
	is_paused = true
	_countdown_label.show()
	var now := Time.get_ticks_msec()
	_cd_ms = now + 3* 1000
	countdown_ms = 3 * 1000  # will sync to clients on first tick

func _start_game() -> void:
	is_paused = false
	for k in GameState.roster.keys():
		var p := get_node(GameState.roster[k]["player_path"]) as Node3D
		#print("the player's id is: ", pid)
		if p == null:
			continue
		p.freeze(false)

func _set_game() -> void:
	_spawn_ball_at(ball_spawn.global_transform.origin)
	#_spawn_players_from_roster()
	_position_players()
	_start_countdown_server() 

# ---------- UI helpers ----------
func _create_timer_ui() -> void:
	# Canvas overlay so it’s always on top
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 100
	add_child(_ui_layer)

	var root := Control.new()
	root.name = "HUDRoot"
	root.size = get_viewport().get_visible_rect().size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(root)

	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.text = "00:00"
	_time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 28)
	_time_label.add_theme_color_override("font_color", Color(1,1,1))
	_time_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_time_label.add_theme_constant_override("outline_size", 4)

	# Top-center preset, then nudge down a bit
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(0, 18)
	root.add_child(_time_label)

func _build_hud_ui() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 100
	add_child(_hud_layer)

	var root := Control.new()
	root.size = get_viewport().get_visible_rect().size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)

	# Stack nicely using a VBoxContainer
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vbox.position = Vector2(0, 12)  # nudge down from the very top
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vbox)

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 28)
	_time_label.add_theme_color_override("font_color", Color(1,1,1))
	_time_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_time_label.add_theme_constant_override("outline_size", 4)
	_time_label.text = "00:00"
	vbox.add_child(_time_label)

	_score_box = HBoxContainer.new()
	_score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_score_box)

	_score_blue_lbl = Label.new()
	_score_blue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_blue_lbl.add_theme_font_size_override("font_size", 26)
	_score_blue_lbl.add_theme_color_override("font_color", Color(0.20, 0.60, 1.00))  # BLUE
	_score_blue_lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_score_blue_lbl.add_theme_constant_override("outline_size", 3)
	_score_blue_lbl.text = "BLUE 0"
	_score_box.add_child(_score_blue_lbl)

	_score_sep_lbl = Label.new()
	_score_sep_lbl.add_theme_font_size_override("font_size", 26)
	_score_sep_lbl.add_theme_color_override("font_color", Color(0.85,0.85,0.85))     # separator
	_score_sep_lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.6))
	_score_sep_lbl.add_theme_constant_override("outline_size", 2)
	_score_sep_lbl.text = " : "
	_score_box.add_child(_score_sep_lbl)

	_score_red_lbl = Label.new()
	_score_red_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_red_lbl.add_theme_font_size_override("font_size", 26)
	_score_red_lbl.add_theme_color_override("font_color", Color(1.00, 0.30, 0.30))  # RED
	_score_red_lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_score_red_lbl.add_theme_constant_override("outline_size", 3)
	_score_red_lbl.text = "RED 0"
	_score_box.add_child(_score_red_lbl)
	
	# Big center countdown label (separate, in the middle of the screen)
	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 64)
	_countdown_label.add_theme_color_override("font_color", Color(1,1,1))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.9))
	_countdown_label.add_theme_constant_override("outline_size", 6)
	_countdown_label.visible = false
	root.add_child(_countdown_label)

func _install_synchronizer() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	add_child(sync)                        # child of Game; default root_path targets parent ("..")

	var cfg := SceneReplicationConfig.new()

	var p_time := NodePath(".:time_left_ms")
	var p_blue := NodePath(".:blue_score")
	var p_red  := NodePath(".:red_score")
	var p_cd := NodePath(".:countdown_ms")
	var p_ps := NodePath(".:is_paused")
	var p_process := NodePath(".:can_process")
	var p_end_scene := NodePath(".:scene_path_to_load")

	cfg.add_property(p_time)
	cfg.add_property(p_blue)
	cfg.add_property(p_red)
	cfg.add_property(p_cd)
	cfg.add_property(p_ps)
	cfg.add_property(p_process)
	cfg.add_property(p_end_scene)

	# Time updates every frame -> ALWAYS (unreliable, frequent)
	cfg.property_set_replication_mode(p_time, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	# Scores change infrequently -> ON_CHANGE (reliable)
	cfg.property_set_replication_mode(p_blue, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.property_set_replication_mode(p_red,  SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.property_set_replication_mode(p_cd,    SceneReplicationConfig.REPLICATION_MODE_ALWAYS)     # 3s, smooth
	cfg.property_set_replication_mode(p_ps,    SceneReplicationConfig.REPLICATION_MODE_ALWAYS)     # 3s, smooth
	cfg.property_set_replication_mode(p_process,    SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(p_end_scene,    SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	sync.replication_interval = 0.0   # send time every multiplayer tick


func _begin_countdown() -> void:
	if _time_label == null: return
	


func _update_label(rem_ms: int) -> void:
	if _time_label == null: return
	var s := int(ceil(rem_ms / 1000.0))
	var m := s / 60
	var sec := s % 60
	_time_label.text = "%02d:%02d" % [m, sec]

func _update_score_label(blue:int, red:int) -> void:
	if _score_blue_lbl: _score_blue_lbl.text = "BLUE %d" % blue
	if _score_red_lbl:  _score_red_lbl.text  = "%d RED" % red

func _update_countdown_ui(ms:int) -> void:
	if ms > 0:
		#var s := int(ceil(ms / 1000.0))
		_countdown_label.text = str(ms)     # "3", "2", "1"
		_countdown_label.show()
	
	elif ms == 0:
		_countdown_label.text = "GO!"
		_countdown_label.show()

	elif ms == -1:
		_countdown_label.hide()
		

		

func _ready() -> void:
	
	_build_hud_ui()
	# 1) Create synchronizer as a child (now it has a valid multiplayer & tree)
	_install_synchronizer()

	set_multiplayer_authority(1)
	if multiplayer.is_server():
		 # server owns it (peer 1)
		_start_clock_server()
		_start_match_authoritative()
		
	# clients just wait for RPC updates

func _start_match_authoritative() -> void:
	var world := get_parent()
	_blue_zone = world.get_node("Teams/TeamBlue/Goal_A/ScoreZone")
	_red_zone = world.get_node("Teams/TeamRed/Goal_B/ScoreZone")
	if is_instance_valid(_blue_zone):
		_blue_zone.body_entered.connect(_on_score_zone_body_entered.bind("blue_goal"))
	if is_instance_valid(_red_zone):
		_red_zone.body_entered.connect(_on_score_zone_body_entered.bind("red_goal"))
	_set_game()
	

func _physics_process(delta: float) -> void:
	if can_process:
		if multiplayer.is_server():
				_physics_process_server(delta)
		if not is_paused:
			# Everyone (server + clients) renders from replicated time_left_ms
			_update_label(time_left_ms)
		
		_update_countdown_ui(countdown_ms)
		_update_score_label(blue_score, red_score)


func _physics_process_server(delta: float) -> void:
	if time_left_ms == 0:
		_process_game_end()
	if is_paused and countdown_ms == 0:
		_start_game()
	if not is_paused: 
		if _end_ms > 0:
			var now := Time.get_ticks_msec()
			time_left_ms = max(0, _end_ms - now)  # this write replicates automatically
			if time_left_ms == 0:
				_on_time_up_server()
	if countdown_ms > -2:
		var now := Time.get_ticks_msec()
		var remaining := _cd_ms - now   # ms until countdown end
		countdown_ms = int(ceil(remaining / 1000.0))



func _on_time_up_server() -> void:
	_end_ms = -1
	# …end match, disable input, show UI, etc.
	_end_match_authoritative("time_up")



func _end_match_authoritative(reason: String) -> void:
	if !multiplayer.is_server(): return
	print("time up")
	


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

func _position_players() -> void:
	var blue_placed := 1
	var red_placed  := 1

	# Find a target to face: live Ball if it exists, else the BallSpawn
	var ball := ball_scene
	#var target_pos := ball.global_transform.origin if ball != null else ball_spawn.global_transform.origin
	var target_pos := ball_spawn.global_position
	for k in GameState.roster.keys():
		var pid := int(k)
		# initialize only if missing
		var entry := _game.get_or_add(pid, {
			"name": String(GameState.roster.get(pid, {}).get("name","")),
			"goals": 0,
			"assists": 0,
			"saves": 0,
		}) as Dictionary
		var p := get_node(GameState.roster[k]["player_path"]) as Node3D
		#print("the player's id is: ", pid)
		if p == null:
			continue

		if GameState.is_blue(pid):
			var sp := spawns_blue.get_node_or_null("Spawn%d" % blue_placed) as Node3D
			if sp:
				p.global_transform = sp.global_transform
				blue_placed += 1
				if not _all_team_assinged_color: rpc("_cl_set_team_id", p.get_path(), true)
		else:
			var sp := spawns_red.get_node_or_null("Spawn%d" % red_placed) as Node3D
			if sp:
				p.global_transform = sp.global_transform
				red_placed += 1
				if not _all_team_assinged_color:  rpc("_cl_set_team_id", p.get_path(), false)
		# tell that specific client to aim their camera
		p.focus_at(ball)
		p.freeze(true)
	_all_team_assinged_color = true

func _process_game_end() -> void:
	can_process = false
	var blue_scene := ""
	var red_scene := ""
	if blue_score > red_score:
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


@rpc("authority", "reliable", "call_local")
func _cl_set_team_id(p_path: NodePath, is_blue : bool) -> void:
	var p := get_node(p_path)
	_set_player_team_color(p, is_blue)


func _set_player_team_color(p: Node3D, is_blue: bool) -> void:
	var col := BLUE
	if not is_blue: col = RED
	_tint_recursive(p, col)

func _tint_recursive(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			var sc: int = mesh.get_surface_count()
			var s: int = 0
			while s < sc:
				var base_mat: Material = mi.get_surface_override_material(s)
				if base_mat == null:
					base_mat = mesh.surface_get_material(s)

				var new_mat: Material
				if base_mat != null:
					new_mat = base_mat.duplicate(true)
				else:
					new_mat = StandardMaterial3D.new()

				if new_mat is StandardMaterial3D:
					var sm: StandardMaterial3D = new_mat as StandardMaterial3D
					sm.albedo_color = col
				elif new_mat is ShaderMaterial:
					var sh: ShaderMaterial = new_mat as ShaderMaterial
					# your shader must have a 'tint_color' uniform (change name if different)
					sh.set_shader_parameter("tint_color", col)

				mi.set_surface_override_material(s, new_mat)
				s += 1

	# recurse children
	var children: Array = n.get_children()
	for i in children.size():
		var child: Node = children[i] as Node
		_tint_recursive(child, col)

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
func _handle_goal(which_goal: String, ball : Node3D) -> void:
	# Example: ball in *red* goal means BLUE scores
	var scoring_team := "red"
	if which_goal == "blue_goal":
		scoring_team = "blue"
	_add_point(scoring_team, ball)
	# Wait 3 seconds, then reset
	# Show "Goal!" on every client (server does NOT run it)
	var secs := 3
	rpc("_cl_handle_goal_outcome", "Goal!", secs)
	# server waits locally; this does not block clients
	await get_tree().create_timer(secs).timeout
	_set_game()
	_goal_lock = false
	

func _add_point(scoring_team: String, ball : Node3D) -> void:
	var goal_player = ball.get_player(0)
	var assist_player = ball.get_player(1)
	if goal_player != -1 and not GameState.is_in_the_same_team(goal_player, scoring_team):
		_game[goal_player]["goals"] += 1
	else:
		_game[goal_player]["goals"] -= 1
	if assist_player != -1 and not GameState.is_in_the_same_team(goal_player, scoring_team):
		_game[goal_player]["assists"] += 1
	if scoring_team == "red":
		blue_score += 1
	else:
		red_score += 1
	print("_game after goal is scored: ", _game)

@rpc("authority", "reliable", "call_local") 
func _cl_handle_goal_outcome(text: String, seconds: float) -> void:
	await _show_banner_for(text, seconds)

func _show_banner_for(text: String, seconds: float) -> void:
	if _countdown_label == null:  # or is_instance_valid(_countdown_label)
		return
	_countdown_label.text = text
	_countdown_label.show()
	var t := get_tree().create_timer(seconds)  # local, per-client
	await t.timeout
	_countdown_label.hide()



# On the same node (path) on all peers:
@rpc("authority", "reliable", "call_local")  # server calls; clients execute
func _cl_end_match(text: String, seconds: float, scene_path_to_load: String) -> void:
	await _show_banner_for(text, seconds)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(scene_path_to_load)



	#print("the player with id ", goal_player,
	  #" goaled who belongs to ", scoring_team,
	  #" whose goal is now ", GameState.roster[goal_player]["goals"])
