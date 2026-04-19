extends Node
class_name ClientSession

signal joined_server
signal server_found(info)

var cloud_discovery : CloudDiscovery
var http_service : HttpService
var sync : Node
var ENDPOINTS = preload("res://scripts/shared/endpoints.gd")

func setup(discovery):
	cloud_discovery = discovery

func stop_discovery():
	Network.stop_discovery()
	cloud_discovery.stop_discovery()

func start_discovery():
	cloud_discovery.lobbies_received.connect(_on_lobbies_found)
	cloud_discovery.start_discovery()
	Network.server_found.connect(_on_server_found)
	Network.start_discovery()

func change_state(state_info: String):
	get_tree().change_scene_to_file(state_info)

func host_cloud_server():
	http_service = HttpService.new(self)
	Config.load_config()
	var url = Config.get_value("cloud_server_endpoint") + ENDPOINTS.CREATE_LOBBY
	
	var headers = ["Content-Type: application/json"]
	var body = "{}" # can send player info later
	print('the url is: ', url)
	http_service.request_completed.connect(_on_request_completed)
	http_service.post(url, headers, body)

func join(server_info):
	var ip = server_info["ip"]
	var port = server_info["port"]
	print("the ip is; ", ip)
	print("the port is; ", port)
	Network.joined_server.connect(_on_joined_server)
	Network.join(ip, port)

func handle_data(msg, data):
	if msg == NetCodes.Msg.ROSTER_DATA:
		_cl_sync_roster(data)

func _on_request_completed(result, response_code, headers, body):
	print("request completed")
	if response_code != 200:
		print("Failed")
		return

	var json = JSON.parse_string(body.get_string_from_utf8())

	join(json)

func _on_server_found(info):
	server_found.emit(info)

func _on_lobbies_found(lobbies):
	for lobby in lobbies:
		_on_server_found(lobby)

func _on_joined_server(sync):
	var payload := {"name" : Settings.player_name, "id" : multiplayer.get_unique_id()}
	sync.send_data_id(1, NetCodes.Msg.REGISTER_PEER, payload)

func _cl_sync_roster(server_info):
	
	GameState.roster = server_info["roster"]
	get_tree().change_scene_to_file(server_info["scene"])
