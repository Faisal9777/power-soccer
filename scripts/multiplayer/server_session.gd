extends Node
class_name ServerSession

signal on_roster_updated
signal joined_server
signal server_found(info)

var _transport_method : IAnnounceTransport
var current_scene = ""
var scene_data = {}
var scene_after_server = ""
var server_info = {}
var can_broadcast := false
var can_world_state_broadcast := true
var sync : Node
const C = preload("res://scripts/shared/scene.gd")
const server_phase = {
	STARTING = "starting",
	RUNNING = "running",
	INGAME = "ingame",
	STOPPING = "stopping",
	STOPPED = "stopped",
	ERROR = "error"
}

func set_current_scene(scene : String):
	current_scene = scene

func change_state(state_info: String):
	server_info.state = state_info
	var scene_to_load = ""
	if state_info == "Lobby":
		toggle_broadcast(true)
		scene_to_load = C.LOBBY
		_check_all_players()
	if state_info == C.WORLD:
		scene_to_load = C.WORLD
		toggle_broadcast(false)
	elif state_info == "Scoreboard":
		scene_to_load = C.SCORE
		scene_data["next_scene"] = "Lobby"
	elif state_info == "Title":
		Network.close_connection()
		SessionManager.close_session()
		
	current_scene = state_info
	get_tree().change_scene_to_file(scene_to_load)

func setup(transport_method, id, port):
	_transport_method = transport_method
	server_info = {"id" : id, "port" : port}

func host(server_name, scene):
	scene_after_server = scene
	server_info["name"] = server_name
	Network.peer_joined.connect(_on_peer_connected)
	Network.peer_left.connect(_on_peer_left)
	Network.server_started.connect(_on_hosting_started)
	Network.host(server_info)

func toggle_scene_action(domain, event : int, value):
	var scene_data = {"id": multiplayer.get_unique_id(), "domain": domain,"event" : event,"value" : value}
	handle_data(NetCodes.Msg.SCENE_ACTION, scene_data)

func handle_data(msg, data):
	if msg == NetCodes.Msg.REGISTER_PEER:
		_srv_register_player(data)
	elif msg == NetCodes.Msg.SCENE_ACTION:
		_handle_state_action(msg, data)

func disable_broadcast():
	can_broadcast = false

func toggle_broadcast(trigger):
	can_broadcast = trigger


func toggle_world_state_broadcast(trigger):
	can_world_state_broadcast = trigger

func start_game() -> void:
	current_scene = C.WORLD

func _process(delta):
	return
	if Input.is_action_pressed("debug"):
		print("is it the server; ", multiplayer.get_unique_)

func _broadcast():
	if can_broadcast:
		if current_scene == C.LOBBY:
			server_info["status"] = server_phase.RUNNING
		elif current_scene == C.WORLD:
			server_info["status"] = server_phase.INGAME
		server_info["lobby_size"] = GameState.get_lobby_size()
		server_info["players_connected"] = GameState.get_players_connected()
		_transport_method.send(server_info)

func _broadcast_states():
	if not can_world_state_broadcast:
		return
	var state_data = {}
	state_data["roster"] = GameState.roster
	sync.send_data_all(NetCodes.Msg.STATE_DATA, state_data)

func _handle_state_action(msg, data):
	if data.get("domain") == "lobby":
		_handle_lobby_action(msg, data)

func _handle_lobby_action(msg, data):
	if data.event == NetCodes.Lobby_action.READY:
		GameState.roster[data.get("id")]["ready"] = data.get("value")

func _check_all_players():
	for key in GameState.roster.keys():
		var is_active = GameState.roster[key].get("is_active", false)
		if not is_active:
			GameState.roster.erase(key)

func _on_hosting_started():
	can_broadcast = true
	sync = await SessionManager.create_network_sync()
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_broadcast)
	add_child(timer)
	change_state(scene_after_server)


func _on_joined_server():
	joined_server.emit()

func _on_server_found(info):
	server_found.emit(info)

func _on_peer_connected(id):
	GameState.roster[id] = {"name": "", "ready": false, "is_active" : true}

func _on_peer_left(id):
	print("peer left detected in the server for id: ", id)
	if GameState.roster.has(id):
		GameState.roster[id]["is_active"] = false

func _srv_register_player(payload : Dictionary):
	print("_srv_register_player")
	if not multiplayer.is_server():
		return

	var id = payload.get("id", 0)

	GameState.roster[id]["name"] = payload.get('name', "Unknown")
	var server_info := {"roster":GameState.roster, "scene": C.LOBBY}
	sync.send_data_id(id, NetCodes.Msg.ROSTER_DATA, server_info)
	TaskScheduler.schedule(60, _broadcast_states)
