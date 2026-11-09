extends Node
class_name ClientSession

signal auth_failed
signal rejected(message)
signal joined_server
signal server_found(info)

var cloud_discovery : CloudDiscovery
var can_discover = false
var is_connected = false
var http_service : HttpService
var scene_data := {}
var current_scene := -1
var current_state : Node
var server_id := 1
var sync : Node
var ENDPOINTS = preload("res://scripts/shared/endpoints.gd")
const C = preload("res://scripts/shared/scene.gd")
const REQUEST_TIMEOUT_MS = 3000.0  # seconds
var client_password

var _timeout_timer: SceneTreeTimer = null

func setup(discovery):
	cloud_discovery = discovery
	add_child(discovery)

func get_session_id() -> int:
	return multiplayer.get_unique_id()

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

	if not AuthManager.is_guest():
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

func send_data(value):
	var val = {"message" : NetCodes.message.STATE, "value" : {"value":value}}
	var value2 = value.get("value")
	if value2.get("debug"):
		print("send_data client session")
	sync.send_data_id(server_id, val)

func send_data_id_reliable(msg, value):
	sync.send_data_id_reliable(server_id, msg, value)


func host_cloud_server(name, is_public):
	BlockingOverlay.show_overlay("Creating Server...") 
	http_service = HttpService.new(self) 
	Config.load_config() 
	var url = Config.get_value("cloud_server_endpoint") + ENDPOINTS.CREATE_LOBBY 
	print("Creating cloud server at: ", url)
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + AuthManager.session_token
	]
	http_service.request_completed.connect(_on_request_completed) 
	http_service.post(url, headers, JSON.stringify({ "user_id": GameState.user_id , "is_public" : is_public, "player_name" : name }))

	_timeout_timer = get_tree().create_timer(REQUEST_TIMEOUT_MS)
	_timeout_timer.timeout.connect(_on_request_timeout)

func join(server_info, password):
	var ip = server_info["ip"]
	var port = server_info["port"]
	client_password = password
	if server_info.get("is_public", true):
		Network.joined_server.connect(_on_joined_server)
	else:
		Network.joined_server.connect(_on_joined_private_server)

	Network.join(ip, port)

func handle_data(data):

	var msg = data.get("message")
	var value = data.get("value")
	var action = value.get("action")
	if msg == NetCodes.message.SESSION:
		if action == NetCodes.session_message.SESSION_DATA:
			GameState.roster = value.get("roster")
		elif action == NetCodes.session_message.REGISTRATION_COMPLETE:
				_cl_sync_roster(value)
		if action == NetCodes.Msg.AUTH_OK:
			var payload := {
				"name" : Settings.player_name,
				"id" : multiplayer.get_unique_id(),
				"action" : NetCodes.session_message.REGISTER_PEER,
				"user_id" : GameState.user_id,
				"session_token": AuthManager.session_token
			}
			sync.send_data_id_reliable(server_id, {"message" : NetCodes.message.SESSION, "value":payload})
		if action == NetCodes.Msg.AUTH_FAILED:
			auth_failed.emit()
		if action == NetCodes.session_message.REJECT:
			var message = data.get("message", "")
			rejected.emit(message)
	else:
		StateHandler.handle_data(value.get("value"))

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
	if json.get("response") == NetCodes.ResponseType.REJOIN:
		BlockingOverlay.show_overlay("Rejoining previous game")

	join(json,"")


func _on_request_timeout() -> void:
	BlockingOverlay.hide_overlay()
	http_service.request_completed.disconnect(_on_request_completed)
	print("Server creation timed out")
	# show error to user here


func _on_server_found(info):
	var res = info.get("response")
	if res == NetCodes.ResponseType.REJOIN:
		print("Found lobby which was left")
	server_found.emit(info)

func _on_discovery_failed(info):
	print("discoveryy failed with: ", info)

func _on_lobbies_found(lobbies):
	for lobby in lobbies:
		_on_server_found(lobby)

func _on_joined_server(s):
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)
	is_connected = true
	var payload := {"name" : Settings.player_name, "id" : multiplayer.get_unique_id(),
	"action" : NetCodes.session_message.REGISTER_PEER, "user_id" : GameState.user_id, "session_token" : AuthManager.session_token}
	sync = s
	sync.send_data_id_reliable(1, {"message" : NetCodes.message.SESSION,"value":payload})
	
func _on_joined_private_server(s):
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)
	is_connected = true
	sync = s
	
	var payload := {
		"id" : multiplayer.get_unique_id(),
		"password": client_password,
		"session_token": AuthManager.session_token,
		"action" :  NetCodes.Msg.AUTH_REQUEST,
		"user_id" : GameState.user_id
	}

	sync.send_data_id(server_id, {"message" : NetCodes.message.SESSION, "value":payload})

func _on_server_disconnected() -> void:
	_disconnect()

func _on_connection_failed() -> void:
	_disconnect()

func _disconnect() -> void:
	if is_connected:
		_disconnect_from_events()
		GameState.clear()
		Network.close_connection()
		is_connected = false
		StateHandler.change_state(NetCodes.States.TITLE)


func _cl_sync_roster(server_info):
	BlockingOverlay.hide()
	server_id = server_info.get("server_id", 1)
	#StateHandler.on_connected_to_server(server_info)
	stop_discovery()

func _disconnect_from_events():
	if Network.joined_server.is_connected(_on_joined_server):
		Network.joined_server.disconnect(_on_joined_server)

	if Network.connection_failed.is_connected(_on_connection_failed):
		Network.connection_failed.disconnect(_on_connection_failed)

	if Network.server_disconnected.is_connected(_on_server_disconnected):
		Network.server_disconnected.disconnect(_on_server_disconnected)

func _exit_tree():
	_disconnect_from_events()
func close_connection():
	is_connected = false

	Network.close_connection()
# client_session.gd — add
func send_movement_id(msg, value):
	sync.send_movement_id(server_id, msg, value)

func send_movement(msg, value):
	value["state"] = current_scene
	sync.send_movement_all(msg, value)
