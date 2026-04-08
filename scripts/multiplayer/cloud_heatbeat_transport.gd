# CloudHeartbeatTransport.gd
class_name CloudHeartbeatTransport
extends IAnnounceTransport

var http := HTTPRequest.new()
var endpoint := ""

func _init(_endpoint: String):
	endpoint = _endpoint

func attach_to_node(node: Node):
	node.add_child(http)

func send(payload: Dictionary) -> void:
	var json = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	http.request(endpoint, headers, HTTPClient.METHOD_POST, json)
