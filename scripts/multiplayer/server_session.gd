extends Node
class_name ServerSession

signal on_roster_updated
signal joined_server
signal server_found(info)

var _transport_method : IAnnounceTransport
var current_scene := 1 
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

func host(server_name, scene):
	scene_after_server = scene
	server_info["name"] = server_name
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
		server_info["current_state"] = StateHandler.current_scene
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
	var user_id = payload.get("user_id", 0)
	print("[register] incoming id=%s user_id=%s can_other_join=%s is_cloud_session=%s" % [id, user_id, can_other_join, is_cloud_session])

	var existing_peer_id = _find_roster_entry_by_user(user_id)
	var _existing_player = existing_peer_id != -1
	var can_join = _existing_player or can_other_join
	print("[register] existing_peer_id=%s _existing_player=%s can_join=%s" % [existing_peer_id, _existing_player, can_join])

	var should_reject = (
		not can_join
		or (is_cloud_session and not await _verify_auth(user_id))
		or (is_cloud_session and not _existing_player and not await _notify_player_joined(user_id))
	)
	print("[register] should_reject=%s" % should_reject)
	if should_reject:
		print("[register] REJECTING id=%s" % id)
		Network.disconnect_peer(id)
		sync.send_data_id(id, NetCodes.Msg.REJECT, {"message": "Cannot join"})
		return

	if not multiplayer.is_server():
		print("[register] aborting, not server, id=%s" % id)
		return

	if _existing_player:
		var entry = GameState.roster[existing_peer_id]
		GameState.roster.erase(existing_peer_id)
		entry["is_active"] = true
		GameState.roster[id] = entry
		print("[register] reactivated user_id=%s old_peer=%s new_peer=%s entry=%s" % [user_id, existing_peer_id, id, entry])
	else:
		GameState.roster[id] = {"name": payload.get('name', "Unknown"), "ready": false, "is_active": true, "user_id": user_id}
		print("[register] roster set id=%s entry=%s" % [id, GameState.roster[id]])

	var temp_server_info = server_info.duplicate()
	temp_server_info["server_id"] = multiplayer.get_unique_id()
	temp_server_info["state"] = NetCodes.States.SESSION
	temp_server_info["was_reactivated"] = _existing_player
	print("[register] sending REGISTRATION_COMPLETE to id=%s payload=%s" % [id, temp_server_info])

	sync.send_data_id(id, NetCodes.Msg.REGISTRATION_COMPLETE, temp_server_info)
	TaskScheduler.schedule(60, _broadcast_states)
	StateHandler.handle_data(NetCodes.Msg.PLAYER_RECONNECT, {"value" : id, "old_id" : existing_peer_id}, null)
	print("[register] broadcast scheduled, roster size=%s" % GameState.roster.size())


func _verify_auth(user_id) -> bool:
	return await _transport_method.validate(user_id)

func _notify_player_joined(user_id: int) -> bool:
	var body = JSON.stringify({
		"user_id": user_id,
		"server_id": server_info.get("id")
	})
	return await _transport_method.post(NetCodes.backend.PLAYER_JOINED, body) == HTTPClient.RESPONSE_OK

func _find_roster_entry_by_user(user_id) -> int:
	for peer_id in GameState.roster:
		if GameState.roster[peer_id]["user_id"] == user_id:
			return peer_id
	return -1
func _get_all_user_ids() -> Array:
		return GameState.roster.values().map(func(player): return player["user_id"])
