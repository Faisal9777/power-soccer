class_name CloudHeartbeatTransport
extends IAnnounceTransport

var _http_service: HttpService
var _endpoint: String = ""

func _init(endpoint: String, http_service: HttpService) -> void:
	_endpoint = endpoint
	_http_service = http_service

func send(payload: Dictionary) -> void:
	var json: String = JSON.stringify(payload)
	var headers: Array[String] = ["Content-Type: application/json"]
	
	# If your HttpService.post method is a coroutine (uses HTTPRequest/await), 
	# consider awaiting it here if you need to block or sequence heartbeats:
	_http_service.post(_endpoint, headers, json)
