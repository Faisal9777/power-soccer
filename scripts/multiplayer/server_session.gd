extends Node
class_name ServerSession

signal on_roster_updated
signal joined_server
signal server_found(info)

var _transport_method : IAnnounceTransport
var current_scene := 1 
var server_password: int  = 0

var peer_identities := {}

var current_state : Node
var scene_data = {}
var scene_after_server = ""
var server_info = {}
var is_cloud_session := true
var can_broadcast := false
var can_world_state_broadcast := true
var can_track_player := false
var sync : Node
var can_other_join := true
const C = preload("res://scripts/shared/scene.gd")
const server_phase = {
	STARTING = "starting",
	RUNNING = "running",
	INGAME = "ingame",
	STOPPING = "stopping",
	STOPPED = "stopped",
	ERROR = "error"
}

func get_session_id() -> int:
	return multiplayer.get_unique_id()

func set_current_scene(scene : String):
	print("set current scene is called")
	#current_scene = scene

func change_state(state_info: int):
	current_state = null
	can_track_player = false
	server_info.state = state_info
	if state_info == NetCodes.States.LOBBY:
		toggle_broadcast(true)
		can_track_player = true
	elif state_info == NetCodes.States.SCOREBOARD:
		scene_data["next_scene"] = "Lobby"
	current_scene = state_info

func setup(transport_method, id, port, is_remote_session):
	_transport_method = transport_method
	server_info = {"id" : id, "port" : port}
	is_cloud_session = is_remote_session

func host(server_name, is_public, scene):
	scene_after_server = scene
	server_info["name"] = server_name
	server_info["is_lan"] = true

	server_info["is_public"] = is_public
	server_password = randi_range(100000, 999999)

	Network.peer_left.connect(_on_peer_left)
	Network.server_started.connect(_on_hosting_started)
	Network.host(server_info)

func toggle_scene_action(domain, event : int, value):
	var scene_data = {"id": multiplayer.get_unique_id(), "state": domain, "value" : value}
	handle_data(event, scene_data)

func handle_data(msg, data):
	var state = data["state"]
	if state == NetCodes.States.SESSION:
		if msg == NetCodes.Msg.REGISTER_PEER:
			_srv_register_player(data)
			
		if msg == NetCodes.Msg.AUTH_REQUEST:
			_authenticate_password(data)
			
	else:
		StateHandler.handle_data(msg, data, state)

func send_data_id(target_id, msg, value):
	sync.send_data_id(target_id, msg, value)

func send_data(msg, value):
	sync.send_data_all(msg, value)

func disable_broadcast():
	can_broadcast = false

func toggle_broadcast(trigger):
	can_broadcast = trigger


func toggle_world_state_broadcast(trigger):
	can_world_state_broadcast = trigger

func start_game() -> void:
	print("start game is called")
	#current_scene = C.WORLD

func manage_event(msg) -> void:
	print("manage event is called")
	#if current_scene == "World":
		#if msg == NetCodes.MatchAction.END:
			#SessionManager.change_state(NetCodes.States.LOBBY)

func _process(delta):
	if can_track_player:
		_check_all_players()
	if is_cloud_session:
		_check_server_status()

func _broadcast():
	if can_broadcast:
		if current_scene == NetCodes.States.LOBBY:
			server_info["status"] = "%d/%d" % [
				GameState.get_players_connected(),
				GameState.get_lobby_size()
			]
		elif current_scene == NetCodes.States.WORLD:
			server_info["status"] = server_phase.INGAME

		server_info["lobby_size"] = GameState.get_lobby_size()
		server_info["players_connected"] = GameState.get_players_connected()
		server_info["can_other_join"] = can_other_join
		server_info["current_state"] = current_scene
		if is_cloud_session:
			server_info["players"] = _get_all_user_ids()

		_transport_method.send(server_info)

func _broadcast_states():
	if not can_world_state_broadcast:
		return
	var state_data = {}
	state_data["roster"] = GameState.roster
	state_data["state"] = NetCodes.States.SESSION
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
			var body = JSON.stringify({
			"user_id": GameState.roster[key].get("user_id"),
			"server_id": server_info.get("id")
			})
			await _transport_method.post(NetCodes.backend.PLAYER_DISCONNECTED, body) == HTTPClient.RESPONSE_OK
			GameState.roster.erase(key)

func _check_server_status():
	if GameState.get_players_connected() == GameState.get_lobby_size() or current_scene == NetCodes.States.WORLD:
		can_other_join = false
	else:
		can_other_join = true

func _on_hosting_started():
	can_broadcast = true
	sync = await SessionManager.create_network_sync()
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_broadcast)
	add_child(timer)
	SessionManager.change_state(NetCodes.States.LOBBY)


func _on_joined_server():
	joined_server.emit()

func _on_server_found(info):
	server_found.emit(info)

func _on_peer_left(id):
	print("peer left detected in the server for id: ", id)
	if GameState.roster.has(id):
		GameState.roster[id]["is_active"] = false

func _srv_register_player(payload: Dictionary):
	var id = payload.get("id", 0)
	var player_info = peer_identities.get(id, {})
	var actual_name = player_info.get("player_name", payload.get('name', "Unknown"))
	var tag = player_info.get("player_tag", "")

	
	var user_id = payload.get("user_id", 0)
	print("[register] incoming id=%s user_id=%s can_other_join=%s is_cloud_session=%s" % [id, user_id, can_other_join, is_cloud_session])

	var should_reject = not can_other_join or (is_cloud_session and not await _can_join(user_id))
	print("[register] should_reject=%s" % should_reject)
	if should_reject:
		print("[register] REJECTING id=%s" % id)
		Network.disconnect_peer(id)
		sync.send_data_id(id, NetCodes.Msg.REJECT, {"message": "Cannot join"})
		return

	if not multiplayer.is_server():
		print("[register] aborting, not server, id=%s" % id)
		return

	GameState.roster[id] = {"name": "", "ready": false, "is_active": true, "user_id": user_id}
	GameState.roster[id]["name"] = payload.get('name', "Unknown")
	print("[register] roster set id=%s entry=%s" % [id, GameState.roster[id]])

	var temp_server_info = server_info.duplicate()
	temp_server_info["server_id"] = multiplayer.get_unique_id()
	temp_server_info["state"] = NetCodes.States.SESSION
	print("[register] sending REGISTRATION_COMPLETE to id=%s payload=%s" % [id, temp_server_info])

	sync.send_data_id(id, NetCodes.Msg.REGISTRATION_COMPLETE, temp_server_info)
	TaskScheduler.schedule(60, _broadcast_states)
	print("[register] broadcast scheduled, roster size=%s" % GameState.roster.size())

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
		elif server_info["is_lan"] == true:
			sync.send_data_id(id, NetCodes.Msg.AUTH_OK, {})

			
	if server_info["is_lan"] != true :
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


func _notify_player_joined(user_id: int) -> bool:
	var body = JSON.stringify({
		"user_id": user_id,
		"server_id": server_info.get("id")
	})
	return await _transport_method.post(NetCodes.backend.PLAYER_JOINED, body) == HTTPClient.RESPONSE_OK

func _get_all_user_ids() -> Array:
		return GameState.roster.values().map(func(player): return player["user_id"])

func _can_join(user_id):
	var is_validated : bool = await _transport_method.validate(user_id)
	if not is_validated or not await _notify_player_joined(user_id):
		return false
	return true
