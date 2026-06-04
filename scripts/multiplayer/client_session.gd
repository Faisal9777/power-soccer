extends Node
class_name ClientSession

signal joined_server
signal server_found(info)

var cloud_discovery : CloudDiscovery
var can_discover = false
var http_service : HttpService
var scene_data := {}
var sync : Node
var ENDPOINTS = preload("res://scripts/shared/endpoints.gd")
const C = preload("res://scripts/shared/scene.gd")
const REQUEST_TIMEOUT_MS = 10.0  # seconds

var _timeout_timer: SceneTreeTimer = null

func setup(discovery):
	cloud_discovery = discovery
	add_child(discovery)

func stop_discovery():
	Network.stop_discovery()
	cloud_discovery.stop_search()

func start_discovery():
	cloud_discovery.lobbies_received.connect(_on_lobbies_found)
	cloud_discovery.discovery_failed.connect(_on_discovery_failed)
	cloud_discovery.start_search(2.0)
	Network.server_found.connect(_on_server_found)
	Network.start_discovery()

func toggle_scene_action(event : int, value):
	var scene_data = {"id": multiplayer.get_unique_id(),"event" : event,"value" : value}
	sync.send_data_id(1, NetCodes.Msg.SCENE_ACTION, scene_data)

func change_state(state_info: String):
	var scene_to_load = ""
	if state_info == C.WORLD:
		scene_to_load = C.WORLD
	elif state_info == "Scoreboard":
		scene_to_load = C.SCORE
		scene_data["next_scene"] = "Lobby"
	elif state_info == "Lobby":
		scene_to_load = C.LOBBY

	get_tree().change_scene_to_file(scene_to_load)

func host_cloud_server():
	BlockingOverlay.show_overlay("Creating Server...") 
	http_service = HttpService.new(self) 
	Config.load_config() 
	var url = Config.get_value("cloud_server_endpoint") + ENDPOINTS.CREATE_LOBBY 
	var headers = ["Content-Type: application/json"] 
	var body = "{}"
	http_service.request_completed.connect(_on_request_completed) 
	http_service.post(url, headers, body)

	_timeout_timer = get_tree().create_timer(REQUEST_TIMEOUT_MS)
	_timeout_timer.timeout.connect(_on_request_timeout)

func join(server_info):
	var ip = server_info["ip"]
	var port = server_info["port"]
	Network.joined_server.connect(_on_joined_server)
	Network.join(ip, port)

func handle_data(msg, data):
	if msg == NetCodes.Msg.ROSTER_DATA:
		_cl_sync_roster(data)
	if msg == NetCodes.Msg.STATE_DATA:
		GameState.roster = data["roster"]

func _on_request_completed(result, response_code, headers, body):
	if _timeout_timer:
		_timeout_timer.timeout.disconnect(_on_request_timeout)
		_timeout_timer = null
	if response_code != 200:
		BlockingOverlay.hide()
		print("Failed")
		return

	var json = JSON.parse_string(body.get_string_from_utf8())

	join(json)

func _on_request_timeout() -> void:
	BlockingOverlay.hide_overlay()
	http_service.request_completed.disconnect(_on_request_completed)
	print("Server creation timed out")
	# show error to user here


func _on_server_found(info):
	server_found.emit(info)

func _on_discovery_failed(info):
	print("discoveryy failed with: ", info)

func _on_lobbies_found(lobbies):
	for lobby in lobbies:
		_on_server_found(lobby)

func _on_joined_server(s):
	var payload := {"name" : Settings.player_name, "id" : multiplayer.get_unique_id()}
	sync = s
	sync.send_data_id(1, NetCodes.Msg.REGISTER_PEER, payload)

func _cl_sync_roster(server_info):
	BlockingOverlay.hide()
	GameState.roster = server_info["roster"]
	get_tree().change_scene_to_file(server_info["scene"])
