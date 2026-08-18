extends Discovery
class_name CloudDiscovery

signal lobbies_received(lobbies: Array)
signal discovery_failed(error: String)

var can_search = false
var endpoint: String
var http_service: HttpService

func _init(base_endpoint: String, node):
	endpoint = base_endpoint
	http_service = HttpService.new(node)
	http_service.request_completed.connect(_on_request_completed)

func start_search(wait_time):
	can_search = true
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.autostart = wait_time
	timer.timeout.connect(_find_data)
	add_child(timer)

func stop_search():
	can_search = false

func _find_data():
	if !can_search:
		return

	var headers = [
		"Authorization: Bearer " + AuthManager.session_token
	]
	http_service.http_get(endpoint, headers)

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
	print(data)
	# Expecting something like: [{id, name, players}, ...]
	if typeof(data) == TYPE_ARRAY:
		lobbies_received.emit(data)
		return

	if typeof(data) == TYPE_DICTIONARY:
		# Backend returned one lobby
		lobbies_received.emit([data])
		return

	discovery_failed.emit("Invalid lobby format")
