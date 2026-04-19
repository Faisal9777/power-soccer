# CloudHeartbeatTransport.gd
class_name CloudHeartbeatTransport
extends IAnnounceTransport

var _http_service : HttpService
var _endpoint := ""

func _init(endpoint: String, http_service):
	_endpoint = endpoint
	_http_service = http_service

func send(payload: Dictionary) -> void:
	var json = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	_http_service.post(_endpoint, headers, json)
