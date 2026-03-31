extends Node

var current_scene = ""
var server_info = {}
var can_broadcast := false
const C = preload("res://scripts/shared/scene.gd")
const PORT := 24565

func set_current_scene(scene : String):
	current_scene = scene

func change_state(state_info: String):
	server_info.state = state_info

func _ready():
	Network.server_started.connect(_on_hosting_started)

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
