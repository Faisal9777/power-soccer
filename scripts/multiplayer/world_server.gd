# res://scripts/multiplayer/world_server.gd
extends Node
var GameServer := load("res://scripts/multiplayer/game_server.gd")

var _players: Dictionary[int, CharacterBody3D] = {}
var _players_input: Dictionary = {} 
var _input_accum: float = 0.0
var _network_endpoint : Node
var _peers_ready := 0
var _is_also_player := false
var _game : Node
var _client_game : Node
var GameClient := load("res://scripts/multiplayer/game_client.gd")
var p_controller : LocalController
var controllers : Array = []
var broadcast_id : int = -1
var ball: Node
# Input pump
const NET_INPUT_HZ: float = 30.0
var last_server_seq:= {}
var can_process := false
var _replication_manager : ReplicationManager

func start_init(players: Dictionary,
	score_board : Control,
	ingame: Node,
	replication_manager : ReplicationManager,
	blue_spawns: Node3D,
	red_spawns: Node3D,
	ball_spawn: Node3D,
	ball_scene: Node3D,
	match_len_sec: int,
	goal_limit: int,
	roster: Dictionary,
	joystick : Node) -> void:
	ball = ball_scene
	if GameState.roster.has(1):
		_is_also_player = true
	_players = players
	ingame.set_roster(GameState.roster)
	_replication_manager = replication_manager
	_player_controller_setup(players, ball_scene, joystick, controllers)
	_game = GameServer.new()
	add_child(_game)
	# Give Game everything it needs *before* it's added (so _ready can safely use them)
	_game.setup({
			"duration_sec": match_len_sec,
			"goal_limit":   goal_limit,
			"roster":       roster,
		}, blue_spawns, red_spawns, ball_spawn, ball_scene, ingame, roster, controllers)
	_game.game_end.connect(_on_game_end)
	#_debug_data(roster, ingame, ball_scene, blue_spawns, red_spawns)
	var data := {"roster" : roster, "ball_path" : ball_scene.get_path()}
	if _is_also_player:
		_peers_ready +=1
		_client_game = NodeUtils.create_game_client(self, GameClient, "GameClient", ingame, score_board, controllers)
	_network_endpoint.rpc(NetCodes.Rpc.INPUT_STREAM, NetCodes.Msg.INIT_BEGIN, data)

func handle_data(msg, value):
	if msg == NetCodes.Msg.INPUTS:
		process_input_by_id(value["id"], msg, value)
	elif msg == NetCodes.Msg.DISCRETE_INPUTS:
		_client_discrete_input(value["id"], value)

func process_input_by_id(peer_id: int, msg, cmd : Dictionary) -> void:
	var idx = controllers.find_custom(
	func(c):
		return c.id == peer_id
	)

	if idx == -1:
		print("the player does not exist with the id: ", idx)
	var controller = controllers[idx]
	var inputs = cmd.get("inputs", [])
	if inputs and inputs.size() > 0:
		var input = _get_latest_input(inputs)
		controller.input_buffer.push_input(input)


func process_input_dictionary(msg: int, value : Dictionary) -> void:
	#print("the msg recieved in receive_network_input_dictionary is: ", msg)
	if msg == NetCodes.Msg.INIT_DONE:
		_peers_ready += 1
		#print("_peers_ready: ", _peers_ready)
		if _peers_ready == GameState.roster.size():
			_game.game_reset.connect(_on_game_reset)
			_game.start_game(get_parent())
			LoadingUI.hide_loading()
			broadcast_id = TaskScheduler.schedule(60, _broadcast_snapshots)
			can_process = true

func get_node_track() -> Node3D:
	return

func _ready() -> void:
	SessionManager.register_state(self)
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
	if Input.is_action_pressed("debug"):
		_game._process_game_end()
	if can_process:
		_simulate_remote_players(delta)

func _simulate_remote_players(delta) -> void:
	for controller in controllers:
		controller.physics_tick(delta)

func _broadcast_snapshots() -> void:
	if not can_process:
		return
	var snapshots := {}

	for controller in controllers:  # your list of Player nodes on server
		var snapshot := controller.get_snapshot() as Dictionary
		snapshot["seq"] = controller.input_buffer.current_input.get("seq")
		snapshots[controller.id] = snapshot
	
	snapshots["game_state"] = _game.current_state
	SessionManager.send_data(NetCodes.Msg.SNAPSHOTS,snapshots)

func _client_discrete_input(from_id: int, d: Dictionary) -> void:
	if d.get("grapple_toggle", false):
		print("World got grapple toggle from ", from_id)
	if _players.has(from_id):
		#print("_rpc_client_input2")
		var p: CharacterBody3D = _players[from_id]
		if p and p.has_method("apply_net_input"):
			#print("_rpc_client_input3")
			p.apply_net_input(d)

func _build_player_paths() -> Dictionary:
	var paths := {}
	for peer_id in _players.keys():
		var p: Node = _players[peer_id]
		paths[peer_id] = p.get_path()  # NodePath
	return paths

func _player_controller_setup(rosters : Dictionary, ball : Node, joystick: Node, controllers) -> void:
	for k in rosters.keys():
		var peer_id := int(k)
		var entry := GameState.roster[k] as Dictionary
		var ppath: NodePath = entry.get("player_path", NodePath(""))
		var team = entry.get("team")
		var name = entry.get("name")
		if ppath.is_empty():
			print("Roster peer ", peer_id, " has EMPTY player_path")
			continue

		var node := get_node_or_null(ppath)
		if peer_id == multiplayer.get_unique_id():
			var player = get_node(ppath)
			var cam = get_node_or_null("/root/World/Scene/Camera3D") as Camera3D
			cam.init(node, joystick)
			var input_source = NodeUtils.init_input_source(self)
			var input_buffer = LocalInputBuffer.new(input_source)
			p_controller = LocalController.new(node, peer_id, name, team, cam, ball, joystick, input_buffer)
			p_controller.get_body_mesh().visible = false
			controllers.append(p_controller)
		else:
			
			controllers.append(NodeController.new(node, peer_id, name, team, ball, SavedInputBuffer.new()))

		if node != null:
			_players[k] = node



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


func _on_peer_left(id : int) -> void:
	pass

func _on_all_peers_left() -> void:
	print("all peers has lleft has been called in the world server")
	SessionManager.change_state(NetCodes.States.LOBBY)

func _on_game_end(game_end_data) -> void:
	await get_tree().create_timer(3).timeout
	_replication_manager.stop()
	_network_endpoint.rpc(NetCodes.Rpc.INPUT_STREAM, NetCodes.Msg.GAME_END, game_end_data)
	if _is_also_player:
		_client_game.end_game(game_end_data)
	else:
		SessionManager.change_state(NetCodes.States.LOBBY)

func _on_game_reset(game_data) -> void:
	_network_endpoint.rpc(NetCodes.Rpc.INPUT_STREAM, NetCodes.Msg.GAME_BEGIN, game_data)

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


func _get_latest_input(inputs: Array) -> Dictionary:
	return inputs.reduce(func(a, b):
		if a.seq > b.seq:
			return a
		return b)


func _exit_tree():
	TaskScheduler.cancel(broadcast_id)
