extends Node
class_name ServerSession

signal on_roster_updated
signal joined_server
signal server_found(info)

var _transport_method : IAnnounceTransport
var current_scene = ""
var scene_after_server = ""
var server_info = {}
var can_broadcast := false
var sync : Node
const C = preload("res://scripts/shared/scene.gd")
const PORT := 24565

func set_current_scene(scene : String):
	current_scene = scene

func change_state(state_info: String):
	server_info.state = state_info
	if state_info == C.LOBBY:
		toggle_broadcast(true)
		get_tree().change_scene_to_file(state_info)

func setup(transport_method):
	_transport_method = transport_method

func host(server_info, scene):
	scene_after_server = scene
	server_info["port"] = PORT
	Network.host(server_info)

func handle_data(msg, data):
	if msg == NetCodes.Msg.REGISTER_PEER:
		_srv_register_player(data)

func disable_broadcast():
	can_broadcast = false

func toggle_broadcast(trigger):
	can_broadcast = trigger

func _ready():
	Network.server_started.connect(_on_hosting_started)
	Network.peer_joined.connect(_on_peer_connected)

func _process(delta : float):
	if can_broadcast:
		_broadcast()

func _broadcast():
	server_info["last_seen"] = Time.get_unix_time_from_system()
	server_info["lobby_size"] = GameState.get_lobby_size()
	server_info["players_connected"] = GameState.get_players_connected()
	server_info['port'] = PORT
	_transport_method.send(server_info)


func _on_hosting_started(info):
	server_info = info
	current_scene = server_info["current_scene"]
	can_broadcast = true
	sync = SessionManager.create_network_sync()
	get_tree().change_scene_to_file(scene_after_server)


func _on_joined_server():
	joined_server.emit()

func _on_server_found(info):
	server_found.emit(info)

func _on_peer_connected(id):
	GameState.roster[id] = {"name": "", "ready": false}

func _srv_register_player(payload : Dictionary):
	print("_srv_register_player")
	if not multiplayer.is_server():
		return

	var id = payload.get("id", 0)

	GameState.roster[id]["name"] = payload.get('name', "Unknown")
	var server_info := {"roster":GameState.roster, "scene": C.LOBBY}
	sync.send_data_id(id, NetCodes.Msg.ROSTER_DATA, server_info)
