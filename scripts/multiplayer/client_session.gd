extends Node
class_name ClientSession

signal joined_server
signal server_found(info)
const CLOUD_URL = "IP:3000"
var http_request: HTTPRequest
var sync : Node

func stop_discovery():
	Network.stop_discovery()

func start_discovery():
	print("the path of the client session: ", get_path())
	Network.server_found.connect(_on_server_found)
	Network.start_discovery()

func host_cloud_server(server_info):
	http_request = HTTPRequest.new()
	add_child(http_request)
	var url = CLOUD_URL + "/create-lobby"
	
	var headers = ["Content-Type: application/json"]
	var body = "{}" # can send player info later
	$HTTPRequest.request_completed.connect(_on_request_completed)
	$HTTPRequest.request(url, headers, HTTPClient.METHOD_POST, body)

func join(server_info):
	var ip = server_info["ip"]
	var port = server_info["port"]
	Network.joined_server.connect(_on_joined_server)
	Network.join(ip, port)

func handle_data(msg, data):
	if msg == NetCodes.Msg.ROSTER_DATA:
		_cl_sync_roster(data)

func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Failed")
		return

	var json = JSON.parse_string(body.get_string_from_utf8())

	join(json)

func _on_server_found(info):
	server_found.emit(info)

func _on_joined_server():
	sync = SessionManager.create_network_sync()
	print("sending payload to the server")
	var payload := {"name" : Settings.player_name, "id" : multiplayer.get_unique_id()}
	sync.send_data_id(1, NetCodes.Msg.REGISTER_PEER, payload)

func _cl_sync_roster(roster):
	print("game state has been recieved from the server")
	GameState.roster = roster
	joined_server.emit()
