extends Node

signal auth_started
signal auth_completed(success: bool, player_info: Dictionary)
signal auth_status_changed(message: String)

const LOCAL_PORT := 8080
const SECURE_KEY := "SuperSecretEncryptionKey123!" # Ideally derived or user-unique, used for FileAccess encryption
const SESSION_FILE := "user://session.enc"

var session_token: String = ""
var player_tag: String = ""
var player_name: String = ""

var tcp_server: TCPServer = null
var is_listening := false

var http_client_node: HTTPRequest = null

func _ready() -> void:
	# Add a helper HTTPRequest node
	http_client_node = HTTPRequest.new()
	add_child(http_client_node)
	
	# Load existing session if present
	load_saved_session()

# ==========================================
# PUBLIC API
# ==========================================

# Starts the sign-in flow (or validates saved session)
func login() -> void:
	if session_token != "":
		auth_status_changed.emit("Verifying saved session...")
		verify_session_token(session_token)
	else:
		start_oauth_flow()

# Logs out and clears session
func logout() -> void:
	session_token = ""
	player_tag = ""
	player_name = ""
	if FileAccess.file_exists(SESSION_FILE):
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove("session.enc")
	auth_completed.emit(false, {})

# ==========================================
# OAUTH2 LOOPBACK (PC FLOW)
# ==========================================

func start_oauth_flow() -> void:
	auth_status_changed.emit("Starting Google Sign-In...")
	auth_started.emit()
	
	if OS.has_feature("mobile"):
		# Mobile native/fallback placeholder logic:
		# On mobile, we will later hook into native plugins or custom intent/URI schemes.
		# For now, we will fallback to standard loopback or notify player.
		auth_status_changed.emit("Mobile login requires platform plugin integration.")
		return
		
	# Start TCP server to listen for redirect
	tcp_server = TCPServer.new()
	var err = tcp_server.listen(LOCAL_PORT, "127.0.0.1")
	if err != OK:
		push_error("Failed to start local TCP server on port %d: %d" % [LOCAL_PORT, err])
		auth_status_changed.emit("Auth failed: Local port %d in use." % LOCAL_PORT)
		auth_completed.emit(false, {})
		return
		
	is_listening = true
	set_process(true)
	
	# Get Client ID and Endpoints from Config
	Config.load_config()
	var client_id = Config.get_value("google_client_id", "")
	if client_id == "":
		push_error("google_client_id not set in config!")
		auth_status_changed.emit("Configuration error.")
		auth_completed.emit(false, {})
		return
		
	# Build Google Auth URI
	# For installed desktop apps, standard Google flow with loopback redirect
	var redirect_uri = "http://127.0.0.1:%d" % LOCAL_PORT
	var scope = "openid profile email"
	var auth_url = "https://accounts.google.com/o/oauth2/v2/auth" + \
		"?client_id=" + client_id.uri_encode() + \
		"&redirect_uri=" + redirect_uri.uri_encode() + \
		"&response_type=code" + \
		"&scope=" + scope.uri_encode()
		
	auth_status_changed.emit("Opening web browser...")
	OS.shell_open(auth_url)

func _process(delta: float) -> void:
	if not is_listening or tcp_server == null:
		set_process(false)
		return
		
	if tcp_server.is_connection_available():
		var peer: StreamPeerTCP = tcp_server.take_connection()
		_handle_redirect_connection(peer)

func _handle_redirect_connection(peer: StreamPeerTCP) -> void:
	# Give it a brief moment to receive data
	await get_tree().create_timer(0.2).timeout
	
	var bytes = peer.get_available_bytes()
	if bytes <= 0:
		peer.disconnect_from_host()
		return
		
	var request_str = peer.get_string(bytes)
	var code = _extract_code_from_http_request(request_str)
	
	# Send a simple response to the browser
	var response = "HTTP/1.1 200 OK\r\n" + \
		"Content-Type: text/html\r\n" + \
		"Connection: close\r\n\r\n" + \
		"<html><body><h3>Authentication successful! You can close this window and return to the game.</h3></body></html>"
	peer.put_data(response.to_utf8_buffer())
	peer.disconnect_from_host()
	
	# Stop listening
	is_listening = false
	tcp_server.stop()
	tcp_server = null
	set_process(false)
	
	if code != "":
		auth_status_changed.emit("Exchanging auth code with backend...")
		exchange_code_for_session(code)
	else:
		auth_status_changed.emit("Auth failed: Code not received.")
		auth_completed.emit(false, {})

func _extract_code_from_http_request(request: String) -> String:
	# Simple HTTP parser
	# Example GET line: GET /?code=4/0AfgeXv... HTTP/1.1
	var lines = request.split("\n")
	if lines.size() > 0:
		var get_line = lines[0]
		if "GET " in get_line:
			var parts = get_line.split(" ")
			if parts.size() > 1:
				var path = parts[1]
				if "?" in path:
					var query_params = path.split("?")[1].split("&")
					for param in query_params:
						var pair = param.split("=")
						if pair.size() == 2 and pair[0] == "code":
							return pair[1].uri_decode()
	return ""

# ==========================================
# BACKEND COMMUNICATION
# ==========================================

func exchange_code_for_session(code: String) -> void:
	Config.load_config()
	var backend_url = Config.get_value("cloud_server_endpoint", "http://127.0.0.1:3000")
	var login_endpoint = backend_url + "/api/auth/login"
	
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({
		"code": code,
		"platform": "pc",
		"redirect_uri": "http://127.0.0.1:%d" % LOCAL_PORT
	})
	
	var err = http_client_node.request(login_endpoint, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		auth_status_changed.emit("Connection to server failed.")
		auth_completed.emit(false, {})
		return
		
	var response = await http_client_node.request_completed
	_on_exchange_response(response[0], response[1], response[2], response[3])

func _on_exchange_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		auth_status_changed.emit("Server login failed (Code %d)." % response_code)
		auth_completed.emit(false, {})
		return
		
	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(response_text) == OK:
		var data = json.data
		if data.has("session_token") and data.has("player_tag"):
			session_token = data["session_token"]
			player_tag = data["player_tag"]
			player_name = data.get("player_name", "Player")
			
			# Save session locally
			save_session()
			
			auth_status_changed.emit("Welcome, %s!" % player_name)
			auth_completed.emit(true, {
				"session_token": session_token,
				"player_tag": player_tag,
				"player_name": player_name
			})
			return
			
	auth_status_changed.emit("Failed to parse server response.")
	auth_completed.emit(false, {})

func verify_session_token(token: String) -> void:
	Config.load_config()
	var backend_url = Config.get_value("cloud_server_endpoint", "http://127.0.0.1:3000")
	var verify_endpoint = backend_url + "/api/auth/verify"
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + token
	]
	
	var err = http_client_node.request(verify_endpoint, headers, HTTPClient.METHOD_GET)
	if err != OK:
		auth_status_changed.emit("Backend verification failed.")
		auth_completed.emit(false, {})
		return
		
	var response = await http_client_node.request_completed
	_on_verify_response(response[0], response[1], response[2], response[3])

func _on_verify_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) == OK:
			var data = json.data
			player_tag = data["player_tag"]
			player_name = data.get("player_name", "Player")
			auth_status_changed.emit("Session active: %s" % player_name)
			auth_completed.emit(true, {
				"session_token": session_token,
				"player_tag": player_tag,
				"player_name": player_name
			})
			return
			
	# Clear session if invalid/expired
	logout()

# ==========================================
# SECURE STORAGE
# ==========================================

func save_session() -> void:
	var file = FileAccess.open_encrypted_with_pass(SESSION_FILE, FileAccess.WRITE, SECURE_KEY)
	if file != null:
		var data = {
			"session_token": session_token,
			"player_tag": player_tag,
			"player_name": player_name
		}
		file.store_string(JSON.stringify(data))
		file.close()

func load_saved_session() -> void:
	if not FileAccess.file_exists(SESSION_FILE):
		return
		
	var file = FileAccess.open_encrypted_with_pass(SESSION_FILE, FileAccess.READ, SECURE_KEY)
	if file != null:
		var content = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(content) == OK:
			var data = json.data
			if data.has("session_token") and data.has("player_tag"):
				session_token = data["session_token"]
				player_tag = data["player_tag"]
				player_name = data.get("player_name", "Player")
