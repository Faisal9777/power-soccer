extends Node
class_name ServerSession

signal on_roster_updated
signal joined_server
signal server_found(info)

var _transport_method: IAnnounceTransport
var current_scene := ""
var scene_after_server := ""
var server_info := {}
var can_broadcast := false
var sync: Node
var _broadcast_accum := 0.0
var _empty_shutdown_started := false

const C = preload("res://scripts/shared/scene.gd")
const EMPTY_DEDICATED_SHUTDOWN_DELAY_SEC := 1.0

func set_current_scene(scene: String) -> void:
	current_scene = scene

func change_state(state_info: String) -> void:
	server_info["state"] = state_info
	if state_info == C.LOBBY:
		toggle_broadcast(true)
		get_tree().change_scene_to_file(state_info)

func setup(transport_method, id, port) -> void:
	_transport_method = transport_method
	server_info = {"id": id, "port": port}
	if _transport_method != null and _transport_method.has_method("attach_to_node"):
		_transport_method.attach_to_node(self)

func host(server_name, scene) -> void:
	scene_after_server = scene
	server_info["server_name"] = server_name
	if not Network.peer_joined.is_connected(_on_peer_connected):
		Network.peer_joined.connect(_on_peer_connected)
	if not Network.peer_left.is_connected(_on_peer_disconnected):
		Network.peer_left.connect(_on_peer_disconnected)
	if not Network.all_peers_left.is_connected(_on_all_peers_left):
		Network.all_peers_left.connect(_on_all_peers_left)
	if not Network.server_started.is_connected(_on_hosting_started):
		Network.server_started.connect(_on_hosting_started)
	Network.host(server_info)

func handle_data(msg, data) -> void:
	if msg == NetCodes.Msg.REGISTER_PEER:
		_srv_register_player(data)

func disable_broadcast() -> void:
	can_broadcast = false
	_broadcast_accum = 0.0

func toggle_broadcast(trigger) -> void:
	can_broadcast = trigger
	if not can_broadcast:
		_broadcast_accum = 0.0

func _process(delta: float) -> void:
	if not can_broadcast:
		return

	_broadcast_accum += delta
	if _broadcast_accum < NetConfig.BROADCAST_INTERVAL:
		return

	_broadcast_accum = 0.0
	_broadcast()

func _broadcast() -> void:
	server_info["lobby_size"] = GameState.get_lobby_size()
	server_info["players_connected"] = GameState.get_players_connected()
	server_info["state"] = current_scene if current_scene != "" else C.LOBBY
	server_info["name"] = server_info.get("server_name", "Unnamed Server")
	server_info["is_dedicated"] = GameState.is_dedicated

	_transport_method.send(server_info)

func _on_hosting_started() -> void:
	can_broadcast = true
	current_scene = C.LOBBY
	sync = await SessionManager.create_network_sync()
	await get_tree().process_frame
	get_tree().change_scene_to_file(scene_after_server)

func _on_joined_server() -> void:
	joined_server.emit()

func _on_server_found(info) -> void:
	server_found.emit(info)

func _on_peer_connected(id) -> void:
	_empty_shutdown_started = false
	GameState.roster[id] = {"name": "", "ready": false}

func _on_peer_disconnected(id: int) -> void:
	if GameState.roster.has(id):
		GameState.roster.erase(id)
	if multiplayer.is_server() and can_broadcast:
		_broadcast()

func _on_all_peers_left() -> void:
	if not GameState.is_dedicated_server() or _empty_shutdown_started:
		return

	_empty_shutdown_started = true
	call_deferred("_shutdown_empty_dedicated_server")

func _shutdown_empty_dedicated_server() -> void:
	await get_tree().create_timer(EMPTY_DEDICATED_SHUTDOWN_DELAY_SEC).timeout
	if not GameState.is_dedicated_server():
		return
	if multiplayer.get_peers().size() > 0:
		_empty_shutdown_started = false
		return

	can_broadcast = false
	print("No players remain on dedicated server. Shutting down match.")
	get_tree().quit()

func _srv_register_player(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var id = payload.get("id", 0)
	var player_name := String(payload.get("name", "Unknown"))
	_remove_duplicate_name(player_name, int(id))
	var rec: Dictionary = GameState.roster.get(id, {})
	rec["name"] = player_name
	rec["ready"] = bool(rec.get("ready", false))
	GameState.roster[id] = rec

	var roster_info := {"roster": GameState.roster, "scene": C.LOBBY}
	sync.send_data_id(id, NetCodes.Msg.ROSTER_DATA, roster_info)

func _remove_duplicate_name(player_name: String, current_id: int) -> void:
	if player_name == "":
		return
	for key in GameState.roster.keys():
		var peer_id := int(key)
		if peer_id == current_id:
			continue
		var rec: Dictionary = GameState.roster[key]
		if String(rec.get("name", "")) == player_name:
			GameState.roster.erase(key)
