# res://scripts/multiplayer/world_server.gd
extends Node
var GameServer := load("res://scripts/multiplayer/game_server.gd")

var _players: Dictionary[int, CharacterBody3D] = {}
var _players_input: Dictionary = {} 
var _input_accum: float = 0.0
var _network_endpoint : Node
var _peers_ready := 0
var _is_also_player := true
# Input pump
const NET_INPUT_HZ: float = 30.0
var last_server_seq:= {}
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
		_peers_ready += 1
		_camera_setup(ball_path, joystick_path)
	print("ball path: ", ball_scene.get_path())
	#_debug_data(roster, ingame, ball_scene, blue_spawns, red_spawns)
	var data := {"roster" : roster, "state_path": ingame.get_path(), "ball_path" : ball_scene.get_path(),
	"blue_path" : blue_spawns.get_path(), "red_path" : red_spawns.get_path(), "joystick_path": joystick_path}
	_network_endpoint.rpc("receive_network_input_dictionary", NetCodes.Msg.INIT_BEGIN, data)

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

	var last := int(last_server_seq[peer_id])
	if seq <= last:
		return # old/out-of-order

	# ✅ Missing-seq-proof: keep ONLY the latest cmd; overwrite older
	last_server_seq[peer_id] = seq
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
		_peers_ready += 1
		#print("_peers_ready: ", _peers_ready)
		if _peers_ready == GameState.roster.size():
			_network_endpoint.start_game()

func get_node_track() -> Node3D:
	return

func _ready() -> void:
	print("update is new yea")
	_network_endpoint = get_parent()
	if GameState.is_dedicated_server():
		_is_also_player = false
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
	var step: float = 1.0 / NET_INPUT_HZ
	while _input_accum >= step:
		_input_accum -= step
		_broadcast_snapshots()

# WorldServer.gd (server side)
#@export var SNAPSHOT_HZ: float = 5.0   # debug: 5 snapshots/sec (big delay)
#var _snap_accum: float = 0.0
#
#func _physics_process(delta: float) -> void:
	#_input_accum += delta
	#var step: float = 1.0 / NET_INPUT_HZ
	#while _input_accum >= step:
		#_input_accum -= step
		## input tick stuff (apply inputs, etc.)
		## _send_local_input() if you do that here
#
	## snapshots on a slower clock
	#_snap_accum += delta
	#var snap_step := 1.0 / SNAPSHOT_HZ
	#while _snap_accum >= snap_step:
		#_snap_accum -= snap_step
		#_broadcast_snapshots()

func _broadcast_snapshots() -> void:
	var snapshots := {}

	for peer_id in _players.keys():  # your list of Player nodes on server
		var snapshot := _players[peer_id].get_snapshot() as Dictionary
		snapshot["last_server_seq"] = int(last_server_seq.get(peer_id, -1))
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
	
	var joystick : Node3D = get_node(joystick_path) 
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
	for peer_id in _players_input.keys():
		if not _players.has(peer_id):
			continue

		var player: Node = _players[peer_id]
		var cmd := _players_input[peer_id] as Dictionary

		# If you want, you can add a timeout safety here later.
		player.update_player_states(cmd, delta)

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
