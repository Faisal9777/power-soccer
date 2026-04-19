extends Discovery
class_name CloudDiscovery

signal lobbies_received(lobbies: Array)
signal discovery_failed(error: String)

var endpoint: String
var http_service: HttpService

func _init(base_endpoint: String, node):
	endpoint = base_endpoint
	http_service = HttpService.new(node)


func _init(base_endpoint: String, node):
	endpoint = base_endpoint
	http_service = HttpService.new(node)

func _init(base_endpoint: String, node):
	endpoint = base_endpoint
	http_service = HttpService.new(node)


func find_lobbies():
	
	http_service.http_get(endpoint, [])
	http_service.request_completed.connect(_on_request_completed)


func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		discovery_failed.emit("Bad response code: %s" % response_code)
		return

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())

	if parse_err != OK:
		discovery_failed.emit("JSON parse error")
		return

	var data = json.data

	# Expecting something like: [{id, name, players}, ...]
	if typeof(data) != TYPE_ARRAY:
		discovery_failed.emit("Invalid lobby format")
		return

	lobbies_received.emit(data)
