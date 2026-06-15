extends Node
class_name ServerSession

signal on_roster_updated
signal joined_server
signal server_found(info)

var _transport_method : IAnnounceTransport
var current_scene = ""
var server_password: int  = 0

var scene_data = {}
var scene_after_server = ""
var server_info = {}
var can_broadcast := false
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
	if state_info == C.WORLD:
		scene_to_load = C.WORLD
	elif state_info == "Scoreboard":
		scene_to_load = C.SCORE
		scene_data["next_scene"] = "Lobby"
		
	current_scene = state_info
	get_tree().change_scene_to_file(scene_to_load)

func setup(transport_method, id, port):
	_transport_method = transport_method
	server_info = {"id" : id, "port" : port}

func host(server_name, is_public, scene):
	scene_after_server = scene
	server_info["name"] = server_name
	server_info["is_public"] = is_public
	server_password = randi_range(100000, 999999)
	Network.peer_joined.connect(_on_peer_connected)
	Network.server_started.connect(_on_hosting_started)
	Network.host(server_info)

func toggle_scene_action(domain, event : int, value):
	var scene_data = {"id": multiplayer.get_unique_id(), "domain": domain,"event" : event,"value" : value}
	handle_data(NetCodes.Msg.SCENE_ACTION, scene_data)

func handle_data(msg, data):
	if msg == NetCodes.Msg.AUTH_REQUEST:
		_authenticate_password(data)
	if msg == NetCodes.Msg.REGISTER_PEER:
		_srv_register_player(data)
	elif msg == NetCodes.Msg.SCENE_ACTION:
		_handle_state_action(msg, data)

func disable_broadcast():
	can_broadcast = false

func toggle_broadcast(trigger):
	can_broadcast = trigger

func start_game() -> void:
	current_scene = C.WORLD

func _process(delta):
	if Input.is_action_pressed("debug"):
		var node = get_node("World")
		var indent = "the path of the node is: "
		if node:
			print(indent + node.name)

			for child in node.get_children():
				print("the child is: ", child.name)
		else:
			print("node was not found")

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
	var state_data = {}
	state_data["roster"] = GameState.roster
	sync.send_data_all(NetCodes.Msg.STATE_DATA, state_data)

func _handle_state_action(msg, data):
	if data.get("domain") == "lobby":
		_handle_lobby_action(msg, data)

func _handle_lobby_action(msg, data):
	if data.event == NetCodes.Lobby_action.READY:
		GameState.roster[data.get("id")]["ready"] = data.get("value")

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

var peer_identities := {}

func _on_peer_connected(id):
	GameState.roster[id] = {"name": "", "ready": false}

func _srv_register_player(payload : Dictionary):
	print("_srv_register_player")
	if not multiplayer.is_server():
		return

	var id = payload.get("id", 0)
	var player_info = peer_identities.get(id, {})
	var actual_name = player_info.get("player_name", payload.get('name', "Unknown"))
	var tag = player_info.get("player_tag", "")

	GameState.roster[id]["name"] = actual_name
	GameState.roster[id]["player_tag"] = tag

	var server_info := {"roster":GameState.roster, "scene": C.LOBBY}
	sync.send_data_id(id, NetCodes.Msg.ROSTER_DATA, server_info)
	TaskScheduler.schedule(60, _broadcast_states)

func _authenticate_password(payload):
	var id = payload.get("id", 0)
	var password = payload.get("password", "")
	var session_token = payload.get("session_token", "")
	
	# 1. Password check if lobby is private (server_password != 0)
	if server_password != 0:
		var pass_int = 0
		if password is String:
			pass_int = password.to_int()
		else:
			pass_int = int(password)
		if pass_int != server_password:
			sync.send_data_id(id, NetCodes.Msg.AUTH_FAILED, {})
			return
			
	# 2. Session validation via Node.js
	var player_info = await _verify_token_with_backend(session_token)
	if player_info.is_empty():
		sync.send_data_id(id, NetCodes.Msg.AUTH_FAILED, {})
		return
		
	peer_identities[id] = player_info
	sync.send_data_id(id, NetCodes.Msg.AUTH_OK, {})

func _verify_token_with_backend(token: String) -> Dictionary:
	if token == "":
		return {}
		
	Config.load_config()
	var backend_url = Config.get_value("cloud_server_endpoint", "http://127.0.0.1:3000")
	var verify_url = backend_url + "/api/auth/verify"
	
	var http_client = HTTPRequest.new()
	add_child(http_client)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + token
	]
	
	var err = http_client.request(verify_url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http_client.queue_free()
		return {}
		
	var response = await http_client.request_completed
	http_client.queue_free()
	
	var response_code = response[1]
	var body = response[3]
	
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			if data.has("player_tag"):
				return {
					"player_tag": data["player_tag"],
					"player_name": data.get("player_name", "Player")
				}
	return {}
