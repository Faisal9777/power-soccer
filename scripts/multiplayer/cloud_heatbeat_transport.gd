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
	#print("Heartbeat payload=", json)
	#print("Heartbeat URL=", _endpoint)
	_http_service.post(_endpoint, headers, json)

func validate(user_id, session_token: String = "") -> bool:
	var url = Config.get_value("cloud_server_endpoint")
	var val_url = url + "/validate?user_id=" + str(user_id)
	var headers = ["Content-Type: application/json"]
	if session_token != "":
		headers.append("Authorization: Bearer " + session_token)
	_http_service.http_get(val_url, headers)
	var res = await _http_service.request_completed
	var response_code = res[1]
	var body_text = res[3].get_string_from_utf8()
	var body = JSON.parse_string(body_text)
	print("validate response =", response_code)
	print(body)
	if response_code == 200 and body.get("success", false):
		return true

	return false

func post(endpoint, body, session_token: String = "") -> int:
	var cloud_url = Config.get_value("cloud_server_endpoint")
	var url = cloud_url + endpoint
	var headers = ["Content-Type: application/json"]
	if session_token != "":
		headers.append("Authorization: Bearer " + session_token)
	_http_service.post(url, headers, body)
	var res = await _http_service.request_completed
	return res[1]
