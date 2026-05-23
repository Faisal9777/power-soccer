# CloudHeartbeatTransport.gd
class_name CloudHeartbeatTransport
extends IAnnounceTransport

var http: HTTPRequest = null
var endpoint := ""

func _init(_endpoint: String):
	endpoint = _endpoint

func attach_to_node(node: Node):
	if http != null:
		return
	http = HTTPRequest.new()
	http.name = "CloudHeartbeatRequest"
	node.add_child(http)

func send(payload: Dictionary) -> void:
	if endpoint == "" or http == null:
		return
	var json = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err := http.request(endpoint, headers, HTTPClient.METHOD_POST, json)
	if err != OK and err != ERR_BUSY:
		push_warning("Cloud heartbeat failed to queue: %s" % err)
