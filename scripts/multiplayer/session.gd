extends Node

signal on_roster_updated
signal joined_server
signal server_found(info)

var current_scene = ""
var server_info = {}
var can_broadcast := false
const C = preload("res://scripts/shared/scene.gd")
const PORT := 24565

func set_current_scene(scene : String):
	current_scene = scene


func change_state(state_info: String):
	server_info.state = state_info

func stop_discovery():
	Network.stop_discovery()

func start_discovery():
	Network.start_discovery()

func join(ip):
	if GameState.lobby_size > GameState.get_players_connected():
		Network.joined_server.connect(_on_joined_server)
		Network.server_found.connect(_on_server_found)
		Network.join(ip)

func _ready():
	Network.server_started.connect(_on_hosting_started)
	Network.peer_joined.connect(_on_peer_connected)

func _process(delta : float):
	if current_scene == C.LOBBY and can_broadcast:
		_broadcast()

func _broadcast():
	server_info["last_seen"] = Time.get_unix_time_from_system()
	server_info["lobby_size"] = GameState.get_lobby_size()
	server_info["players_connected"] = GameState.get_players_connected()
	server_info['port'] = PORT
	Network.broadcast(server_info)


func _on_hosting_started(info):
	Network.enable_broadcast()
	server_info = info
	current_scene = server_info["current_scene"]
	can_broadcast = true

func _on_joined_server():
	joined_server.emit()

func _on_server_found(info):
	server_found.emit(info)

func _on_peer_connected(id):
	GameState.roster[id] = {"name": "", "ready": false}

@rpc("any_peer")
func _srv_register_player(payload : Dictionary):
	if not multiplayer.is_server():
		return

	var id = payload.get("id", 0)

	GameState.roster[id]["name"] = payload.get('name', "Unknown")
	rpc_id(id, "_cl_sync_roster", GameState.roster)

@rpc("call_local")
func _cl_sync_roster(roster):
	GameState.roster = roster
	on_roster_updated.emit()
