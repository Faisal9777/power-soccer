# res://scripts/multiplayer/world_server.gd
extends Node
var GameServer := load("res://scripts/multiplayer/game_server.gd")

var _players: Dictionary[int, CharacterBody3D] = {}
var _players_input: Dictionary = {} 
var _input_accum: float = 0.0
var _network_endpoint : Node
var _peers_ready := 0
var _expected_ready_peers := 0
var _ready_peer_ids := {}
var _game_begin_sent := false
var _is_also_player := true
# Snapshot pump
const NET_SNAPSHOT_HZ: float = 45.0
const INPUT_STALE_MSEC: int = 250
var last_server_seq:= {}
var last_received_seq := {}
var last_received_msec := {}
var stale_input_events := {}
var input_stale_active := {}
var _server_tick := 0
func start_init(players: Dictionary,
	ingame: Node,
	blue_spawns: Node3D,
	red_spawns: Node3D,
	ball_spawn: Node3D,
	ball_scene: Node3D,
	match_len_sec: int,
	goal_limit: int,
	roster: Dictionary,
	ball_path : NodePath, 
	joystick_path : NodePath) -> void:
	_players = players
	_peers_ready = 0
	_expected_ready_peers = _count_expected_human_peers(roster)
	_ready_peer_ids.clear()
	_game_begin_sent = false
	var _game_server = GameServer.new()
	# Give Game everything it needs *before* it's added (so _ready can safely use them)
	_game_server.setup({
			"duration_sec": match_len_sec,
			"goal_limit":   goal_limit,
			"roster":       roster,
		}, blue_spawns, red_spawns, ball_spawn, ball_scene)
	_game_server.init(ingame, _network_endpoint, _is_also_player, roster)
	_network_endpoint.set_game(_game_server)
	ingame.set_roster(GameState.roster)
	if _is_also_player:
		_mark_peer_ready(multiplayer.get_unique_id())
		_camera_setup(ball_path, joystick_path)
	print("ball path: ", ball_scene.get_path())
	#_debug_data(roster, ingame, ball_scene, blue_spawns, red_spawns)
	var data := {"roster" : roster, "state_path": ingame.get_path(), "ball_path" : ball_scene.get_path(),
	"blue_path" : blue_spawns.get_path(), "red_path" : red_spawns.get_path(), "joystick_path": joystick_path}
	_network_endpoint.rpc("receive_network_input_dictionary", NetCodes.Msg.INIT_BEGIN, data)
	_try_start_game()

func process_input(cmd: Dictionary, peer_id: int) -> void:
	var seq := int(cmd.get("seq", -1))
	if seq < 0:
		return

	# Absolute angles now (no deltas)
	var mvx := float(cmd.get("mvx", 0.0))
	var mvz := float(cmd.get("mvz", 0.0))
	var yaw := float(cmd.get("yaw", 0.0))
	var pitch := float(cmd.get("pitch", 0.0))

	# optional debug gating
	var moved : bool = abs(mvx) > 0.01 or abs(mvz) > 0.01
	var looked := false # abs(yaw) > ... doesn't mean "looked" for absolute; ignore or track change yourself

	if not _players_input.has(peer_id):
		_players_input[peer_id] = {}   # will store the LATEST cmd (Dictionary)
		last_server_seq[peer_id] = -1
		last_received_seq[peer_id] = -1
		last_received_msec[peer_id] = Time.get_ticks_msec()
		stale_input_events[peer_id] = 0
		input_stale_active[peer_id] = false

	var last := int(last_received_seq.get(peer_id, -1))
	if seq <= last:
		return # old/out-of-order

	# Missing-seq-proof: keep ONLY the latest cmd; overwrite older.
	# last_server_seq is updated after the command is actually simulated.
	last_received_seq[peer_id] = seq
	last_received_msec[peer_id] = Time.get_ticks_msec()
	input_stale_active[peer_id] = false
	_players_input[peer_id] = cmd

#func process_input(cmd: Dictionary, peer_id : int) -> void:
	##var player: CharacterBody3D = _players[peer_id]
	##player.update_player_states(cmd)
	#var seq := int(cmd.get("seq", -1))
	##print("recieved input from the client: ", peer_id)
	#var mvx := float(cmd.get("mvx", 0.0))
	#var mvz := float(cmd.get("mvz", 0.0))
	#var yaw := float(cmd.get("yaw_delta", 0.0))
	#var pitch := float(cmd.get("pitch_delta", 0.0))
#
	#var moved : bool = abs(mvx) > 0.01 or abs(mvz) > 0.01
	#var looked : bool= abs(yaw) > 0.001 or abs(pitch) > 0.001
	#if seq < 0:
		#return
#
	#if not _players_input.has(peer_id):
		#_players_input[peer_id] = {}       # seq -> cmd
		#last_server_seq[peer_id] = -1
#
	#var last := int(last_server_seq[peer_id])
	#if seq <= last:
		#return # old/duplicate
#
	#var buf: Dictionary = _players_input[peer_id]
	#buf[seq] = cmd

func process_input_dictionary(msg: int, value : Dictionary) -> void:
	#print("the msg recieved in receive_network_input_dictionary is: ", msg)
	if msg == NetCodes.Msg.INIT_DONE:
		var sender_id := multiplayer.get_remote_sender_id()
		if sender_id <= 0:
			sender_id = int(value.get("peer_id", 0))
		_mark_peer_ready(sender_id)
		_try_start_game()

func _count_expected_human_peers(roster: Dictionary) -> int:
	var count := 0
	for k in roster.keys():
		var peer_id := int(k)
		if GameState.is_dedicated_server() and peer_id == 1:
			continue
		var rec: Dictionary = roster.get(k, {})
		if not bool(rec.get("is_bot", false)):
			count += 1
	return count

func _is_bot_peer(peer_id: int) -> bool:
	var rec: Dictionary = GameState.roster.get(peer_id, {})
	return bool(rec.get("is_bot", false))

func _mark_peer_ready(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if _is_bot_peer(peer_id):
		return
	if _ready_peer_ids.has(peer_id):
		return
	_ready_peer_ids[peer_id] = true
	_peers_ready = _ready_peer_ids.size()

func _try_start_game() -> void:
	if _game_begin_sent:
		return
	if _expected_ready_peers <= 0:
		return
	if _peers_ready < _expected_ready_peers:
		return
	_game_begin_sent = true
	_network_endpoint.start_game()
	_network_endpoint.rpc("receive_network_input_dictionary", NetCodes.Msg.GAME_BEGIN, {})

func get_node_track() -> Node3D:
	return

func _ready() -> void:
	_network_endpoint = get_parent()
	if GameState.is_dedicated_server():
		_is_also_player = false
	Network.all_peers_left.connect(_on_all_peers_left)
	Network.peer_left.connect(_on_peer_left)
	#_network_endpoint.build_game_controller()
	#_network_endpoint.build_game_updater(GameState.roster)
	#print("about to tell the cclient to start game init")
	#_network_endpoint.rpc("receive_network_input_dictionary", NetCodes.Msg.INIT_BEGIN, GameState.roster)


func _physics_process(delta: float) -> void:
	if _is_also_player:
		var p : Node = _players[multiplayer.get_unique_id()]
		var inp_data := p.get_input_data() as Dictionary
		p.update_player_states(inp_data, delta)
	_update_local_player_states(delta)
	_input_accum += delta
	var step: float = 1.0 / NET_SNAPSHOT_HZ
	while _input_accum >= step:
		_input_accum -= step
		_broadcast_snapshots()
		
func _broadcast_snapshots() -> void:
	var snapshots := {}
	_server_tick += 1

	for peer_id in _players.keys():  # your list of Player nodes on server
		var snapshot := _players[peer_id].get_snapshot() as Dictionary
		snapshot["last_server_seq"] = int(last_server_seq.get(peer_id, -1))
		snapshot["server_tick"] = _server_tick
		snapshot["input_age_ms"] = Time.get_ticks_msec() - int(last_received_msec.get(peer_id, Time.get_ticks_msec()))
		snapshot["input_stale"] = bool(input_stale_active.get(peer_id, false))
		snapshot["stale_input_events"] = int(stale_input_events.get(peer_id, 0))
		snapshots[peer_id] = snapshot

	_network_endpoint.rpc("receive_network_input", snapshots, multiplayer.get_unique_id())

func _broadcast_snapshots2() -> void:
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

	# If nothing to send, bail out
	if snapshots.is_empty():
		return

	# Broadcast to all peers (you can pick reliable/unreliable as you prefer)
	_network_endpoint.rpc("receive_network_input", snapshots, multiplayer.get_unique_id())


func _build_player_paths() -> Dictionary:
	var paths := {}
	for peer_id in _players.keys():
		var p: Node = _players[peer_id]
		paths[peer_id] = p.get_path()  # NodePath
	return paths

func _camera_setup(ball_path : NodePath, joystick_path : NodePath) -> void:
	var cam: Camera3D = get_node_or_null("/root/World/Scene/Camera3D") as Camera3D
	var p := _players[multiplayer.get_unique_id()] 
	if cam == null:
		cam = p.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return

	# Wire camera (existing)
	cam.current = true
	if cam.has_method("set_target"): cam.call_deferred("set_target", p)
	if cam.has_method("activate"):   cam.call_deferred("activate")
	if cam.has_method("set_ball"):   cam.call_deferred("set_ball", ball_path)

	var joystick : Node = get_node("/root/World/CanvasLayer/UI/JoyStick")
	# NEW: give the camera its joystick
	if joystick and cam.has_method("set_joystick"):
		cam.call_deferred("set_joystick", joystick)

	# Hand joystick to player (as you already do)
	if p.has_method("attach_camera"):
		p.call_deferred("attach_camera", cam, joystick)

#func _update_local_player_states(delta : float) -> void:
	#for peer_id in _players_input.keys():
		#var player := _players[peer_id]
		#var buf: Dictionary = _players_input[peer_id]
#
		#var next_seq := int(last_server_seq.get(peer_id, -1)) + 1
		#
		##print("next seq: ", next_seq)
		##print("buffer; ", buf)
		#if buf.has(next_seq):
			#var input := buf[next_seq] as Dictionary
			#buf.erase(next_seq)  # remove the one we just applied
			#player.update_player_states(input, delta)
			#last_server_seq[peer_id] = next_seq
		#else:
			## no next input yet -> do nothing for now (later: hold last / idle)
			#pass

func _update_local_player_states(delta : float) -> void:
	var now := Time.get_ticks_msec()

	for peer_id in _players_input.keys():
		if not _players.has(peer_id):
			continue

		var player: Node = _players[peer_id]
		var cmd := _players_input[peer_id] as Dictionary
		var seq := int(cmd.get("seq", -1))
		var last_applied := int(last_server_seq.get(peer_id, -1))
		var input_age := now - int(last_received_msec.get(peer_id, now))
		var input_is_stale := input_age > INPUT_STALE_MSEC

		if input_is_stale:
			if not bool(input_stale_active.get(peer_id, false)):
				stale_input_events[peer_id] = int(stale_input_events.get(peer_id, 0)) + 1
			input_stale_active[peer_id] = true
			cmd = _make_idle_command(cmd)
		else:
			input_stale_active[peer_id] = false

		if (input_is_stale or seq > last_applied) and player.has_method("apply_net_input"):
			player.apply_net_input(cmd)
		if player.has_method("update_player_states"):
			player.update_player_states(cmd, delta)
		if seq >= 0 and seq > last_applied:
			last_server_seq[peer_id] = seq

func _make_idle_command(cmd: Dictionary) -> Dictionary:
	var idle := cmd.duplicate(true)
	idle["mvx"] = 0.0
	idle["mvz"] = 0.0
	idle["sprint"] = false
	idle["jump_pressed"] = false
	idle["tackle_pressed"] = false
	idle["dribble"] = false
	idle["dribble_pressed"] = false
	idle["dribble_event_id"] = 0
	idle["stop_ball"] = false
	idle["shoot_down"] = false
	idle["shoot_up"] = false
	idle["shoot_release_id"] = 0
	idle["shoot_held_msec"] = 0
	idle["rmb"] = false
	idle["assist_pass_pressed"] = false
	idle["latch_toggle"] = false
	idle["ability_toggle"] = false
	idle["ability_action1"] = false
	idle["ability_action2"] = false
	idle["ability_action3"] = false
	return idle

func _on_peer_left(id : int) -> void:
	_players_input.erase(id)
	last_server_seq.erase(id)
	last_received_seq.erase(id)
	last_received_msec.erase(id)
	stale_input_events.erase(id)
	input_stale_active.erase(id)
	_ready_peer_ids.erase(id)
	_peers_ready = _ready_peer_ids.size()
	if GameState.roster.has(id):
		GameState.roster.erase(id)
	_expected_ready_peers = _count_expected_human_peers(GameState.roster)
	_try_start_game()

func _on_all_peers_left() -> void:
	if GameState.is_dedicated_server():
		get_tree().quit()
		return
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
		

func _debug_data(roster: Dictionary, ingame: Node, ball_scene: Node, blue_spawns: Node, red_spawns: Node) -> void:
	print("--- BUILD DATA DEBUG ---")

	print("roster size =", roster.size(), " empty? ", roster.is_empty())

	print("ingame =", ingame, " valid? ", is_instance_valid(ingame))
	if is_instance_valid(ingame):
		print("state_path =", ingame.get_path(), " empty? ", ingame.get_path().is_empty())

	print("ball_scene =", ball_scene, " valid? ", is_instance_valid(ball_scene))
	if is_instance_valid(ball_scene):
		print("ball_path =", ball_scene.get_path(), " empty? ", ball_scene.get_path().is_empty())

	print("blue_spawns =", blue_spawns, " valid? ", is_instance_valid(blue_spawns))
	if is_instance_valid(blue_spawns):
		print("blue_path =", blue_spawns.get_path(), " empty? ", blue_spawns.get_path().is_empty())

	print("red_spawns =", red_spawns, " valid? ", is_instance_valid(red_spawns))
	if is_instance_valid(red_spawns):
		print("red_path =", red_spawns.get_path(), " empty? ", red_spawns.get_path().is_empty())

	print("--- END BUILD DATA DEBUG ---")
