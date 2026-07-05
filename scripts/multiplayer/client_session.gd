extends Node
class_name ClientSession

signal joined_server
signal server_found(info)

var cloud_discovery : CloudDiscovery
var can_discover = false
var is_connected = false
var http_service : HttpService
var scene_data := {}
var current_scene := -1
var current_state : Node
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
	if Network.server_found.is_connected(_on_server_found):
		Network.server_found.disconnect(_on_server_found)
	if cloud_discovery.lobbies_received.is_connected(_on_lobbies_found):
		cloud_discovery.lobbies_received.disconnect(_on_lobbies_found)
	if cloud_discovery.discovery_failed.is_connected(_on_discovery_failed):
		cloud_discovery.discovery_failed.disconnect(_on_discovery_failed)
	cloud_discovery.stop_search()

func start_discovery():
	if is_connected:
		return
	cloud_discovery.lobbies_received.connect(_on_lobbies_found)
	cloud_discovery.discovery_failed.connect(_on_discovery_failed)
	cloud_discovery.start_search(2.0)
	Network.server_found.connect(_on_server_found)
	Network.start_discovery()

func toggle_scene_action(domain, event : int, value):
	var scene_data = {"id": multiplayer.get_unique_id(), "state": domain ,"value" : value}
	sync.send_data_id(1, event, scene_data)

func change_state(state_info: int):
	current_state = null
	current_scene = state_info
	if state_info == NetCodes.States.SCOREBOARD:
		scene_data["next_scene"] = NetCodes.States.LOBBY

func send_data_id(target_id, msg, value):
	value["state"] = current_scene
	sync.send_data_id(target_id, msg, value)

func send_data(msg, value):
	value["state"] = current_scene
	sync.send_data_all(msg, value)

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
	var state = data.get("state")
	if state == NetCodes.States.SESSION:
		if msg == NetCodes.Msg.ROSTER_DATA:
			_cl_sync_roster(data)
		if msg == NetCodes.Msg.STATE_DATA:
			GameState.roster = data["roster"]
	elif not state == current_scene:
		return
	elif current_state:
		current_state.handle_data(msg, data)

func disconnect_connection() -> void:
	_disconnect()

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
	print("joined server")
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)
	is_connected = true
	var payload := {"name" : Settings.player_name, "id" : multiplayer.get_unique_id(),
	"state" : NetCodes.States.SESSION}
	sync = s
	sync.send_data_id(1, NetCodes.Msg.REGISTER_PEER, payload)

func _on_server_disconnected() -> void:
	_disconnect()

func _on_connection_failed() -> void:
	_disconnect()

func _disconnect() -> void:
	is_connected = false
	_disconnect_from_events()
	GameState.clear()
	Network.close_connection()
	SessionManager.change_state(NetCodes.States.TITLE)

func _cl_sync_roster(server_info):
	BlockingOverlay.hide()
	GameState.roster = server_info["roster"]
	stop_discovery()
	get_tree().change_scene_to_file(server_info["scene"])

func _disconnect_from_events():
	if Network.joined_server.is_connected(_on_joined_server):
		Network.joined_server.disconnect(_on_joined_server)

	if Network.connection_failed.is_connected(_on_connection_failed):
		Network.connection_failed.disconnect(_on_connection_failed)

	if Network.server_disconnected.is_connected(_on_server_disconnected):
		Network.server_disconnected.disconnect(_on_server_disconnected)
func _exit_tree():
	_disconnect_from_events()
