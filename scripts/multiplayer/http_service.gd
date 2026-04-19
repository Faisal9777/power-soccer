class_name HttpService

signal request_completed(result, response_code, headers, body)

var is_request_active := false
var http : HTTPRequest

func _init(parent):
	http = HTTPRequest.new()
	http.request_completed.connect(_on_request_completed)
	parent.add_child(http)

func post(url: String, headers, body: String):
	if is_request_active:
		return

	is_request_active = true
	var err = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		is_request_active = false

func http_get(url: String, headers):
	if is_request_active:
		return

	is_request_active = true
	var err = http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		is_request_active = false

func _on_request_completed(result, response_code, headers, body):
	print("response after the request: ", result)
	is_request_active = false
	request_completed.emit(result, response_code, headers, body)
