extends Node
class_name ClientSession

signal joined_server
signal server_found(info)
signal cloud_match_created(info)
signal cloud_match_create_failed(message)

var sync: Node
var _cloud_list_request: HTTPRequest = null
var _cloud_create_request: HTTPRequest = null
var _cloud_refresh_timer: Timer = null
var _pending_cloud_join: Dictionary = {}
var _cloud_join_attempts := 0
var _cloud_join_generation := 0
var _cloud_join_retry_scheduled := false

const ENDPOINTS = preload("res://scripts/shared/endpoints.gd")
const CLOUD_REFRESH_SEC := 3.0
const CLOUD_JOIN_MAX_ATTEMPTS := 6
const CLOUD_JOIN_INITIAL_DELAY_SEC := 0.75
const CLOUD_JOIN_RETRY_DELAY_SEC := 1.25
const CLOUD_JOIN_ATTEMPT_TIMEOUT_SEC := 3.0

func _ready() -> void:
	_ensure_cloud_list_request()
	_ensure_cloud_create_request()
	_ensure_cloud_refresh_timer()
	if not Network.connection_failed.is_connected(_on_network_connection_failed):
		Network.connection_failed.connect(_on_network_connection_failed)

func stop_discovery() -> void:
	if is_instance_valid(_cloud_refresh_timer):
		_cloud_refresh_timer.stop()
	Network.stop_discovery()

func start_discovery() -> void:
	if not Network.server_found.is_connected(_on_server_found):
		Network.server_found.connect(_on_server_found)
	Network.start_discovery()
	_start_cloud_polling()

func create_cloud_match(payload: Dictionary) -> void:
	_ensure_cloud_create_request()
	var base_url := String(Configuration.get_value("cloud_server_endpoint", "")).strip_edges()
	if base_url == "":
		cloud_match_create_failed.emit("Cloud server URL is not configured.")
		return

	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify(payload)
	var err := _cloud_create_request.request(
		base_url + ENDPOINTS.CREATE_MATCH,
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK and err != ERR_BUSY:
		cloud_match_create_failed.emit("Cloud match request failed: %s" % err)

func join(server_info: Dictionary) -> bool:
	var ip := String(server_info.get("ip", ""))
	var port := int(server_info.get("port", 0))
	if ip == "" or port <= 0:
		return false

	if not Network.joined_server.is_connected(_on_joined_server):
		Network.joined_server.connect(_on_joined_server)
	return Network.join(ip, port)

func join_cloud_match(server_info: Dictionary) -> void:
	_pending_cloud_join = server_info.duplicate(true)
	_cloud_join_attempts = 0
	_cloud_join_generation += 1
	_cloud_join_retry_scheduled = false
	_start_cloud_join_after_delay(_cloud_join_generation, CLOUD_JOIN_INITIAL_DELAY_SEC)

func handle_data(msg, data) -> void:
	if msg == NetCodes.Msg.ROSTER_DATA:
		_cl_sync_roster(data)

func _start_cloud_polling() -> void:
	var base_url := String(Configuration.get_value("cloud_server_endpoint", "")).strip_edges()
	if base_url == "":
		return

	_ensure_cloud_list_request()
	_ensure_cloud_refresh_timer()
	_request_cloud_servers()
	_cloud_refresh_timer.start()

func _ensure_cloud_list_request() -> void:
	if is_instance_valid(_cloud_list_request):
		return

	_cloud_list_request = HTTPRequest.new()
	_cloud_list_request.name = "CloudServerListRequest"
	add_child(_cloud_list_request)
	_cloud_list_request.request_completed.connect(_on_cloud_list_request_completed)

func _ensure_cloud_create_request() -> void:
	if is_instance_valid(_cloud_create_request):
		return

	_cloud_create_request = HTTPRequest.new()
	_cloud_create_request.name = "CloudMatchCreateRequest"
	add_child(_cloud_create_request)
	_cloud_create_request.request_completed.connect(_on_cloud_create_request_completed)

func _ensure_cloud_refresh_timer() -> void:
	if is_instance_valid(_cloud_refresh_timer):
		return

	_cloud_refresh_timer = Timer.new()
	_cloud_refresh_timer.name = "CloudServerRefreshTimer"
	_cloud_refresh_timer.wait_time = CLOUD_REFRESH_SEC
	_cloud_refresh_timer.one_shot = false
	add_child(_cloud_refresh_timer)
	_cloud_refresh_timer.timeout.connect(_request_cloud_servers)

func _request_cloud_servers() -> void:
	if not is_instance_valid(_cloud_list_request):
		return

	var url := String(Configuration.get_value("cloud_server_endpoint", "")).strip_edges()
	if url == "":
		return

	var err := _cloud_list_request.request(url + ENDPOINTS.SERVERS)
	if err != OK and err != ERR_BUSY:
		push_warning("Cloud server list request failed: %s" % err)

func _on_cloud_list_request_completed(_result, response_code, _headers, body) -> void:
	if response_code != 200:
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var servers: Array = []

	if typeof(parsed) == TYPE_ARRAY:
		servers = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		servers = parsed.get("servers", [])

	for entry in servers:
		if typeof(entry) == TYPE_DICTIONARY:
			server_found.emit(entry)

func _on_cloud_create_request_completed(_result, response_code, _headers, body) -> void:
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200:
		var message := "Cloud match creation failed."
		if typeof(parsed) == TYPE_DICTIONARY:
			message = String(parsed.get("error", message))
		cloud_match_create_failed.emit(message)
		return

	if typeof(parsed) != TYPE_DICTIONARY:
		cloud_match_create_failed.emit("Cloud match creation returned invalid data.")
		return

	var server_info = parsed.get("server", {})
	if typeof(server_info) != TYPE_DICTIONARY:
		cloud_match_create_failed.emit("Cloud match creation did not return a server.")
		return

	cloud_match_created.emit(server_info)
	join_cloud_match(server_info)

func _on_server_found(info) -> void:
	server_found.emit(info)

func _on_joined_server() -> void:
	_pending_cloud_join = {}
	_cloud_join_generation += 1
	_cloud_join_retry_scheduled = false
	sync = await SessionManager.create_network_sync()
	var payload := {"name": Settings.player_name, "id": multiplayer.get_unique_id()}
	sync.send_data_id(1, NetCodes.Msg.REGISTER_PEER, payload)
	joined_server.emit()

func _cl_sync_roster(server_info: Dictionary) -> void:
	GameState.roster = server_info["roster"]
	get_tree().change_scene_to_file(server_info["scene"])

func _start_cloud_join_after_delay(generation: int, delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	_try_pending_cloud_join(generation)

func _try_pending_cloud_join(generation: int) -> void:
	if generation != _cloud_join_generation or _pending_cloud_join.is_empty():
		return

	_cloud_join_retry_scheduled = false
	if _cloud_join_attempts >= CLOUD_JOIN_MAX_ATTEMPTS:
		var ip := String(_pending_cloud_join.get("ip", ""))
		var port := int(_pending_cloud_join.get("port", 0))
		_pending_cloud_join = {}
		_cloud_match_join_failed("Cloud match was created, but this device could not join %s:%d." % [ip, port])
		return

	_cloud_join_attempts += 1
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		Network.close_connection()

	var queued := join(_pending_cloud_join)
	if queued:
		_watch_cloud_join_attempt(generation, _cloud_join_attempts)
	else:
		_schedule_cloud_join_retry(generation)

func _watch_cloud_join_attempt(generation: int, attempt: int) -> void:
	await get_tree().create_timer(CLOUD_JOIN_ATTEMPT_TIMEOUT_SEC).timeout
	if generation != _cloud_join_generation or attempt != _cloud_join_attempts:
		return
	if _pending_cloud_join.is_empty():
		return
	_schedule_cloud_join_retry(generation)

func _on_network_connection_failed() -> void:
	if _pending_cloud_join.is_empty():
		return
	_schedule_cloud_join_retry(_cloud_join_generation)

func _cloud_match_join_failed(message: String) -> void:
	_cloud_join_generation += 1
	_cloud_join_retry_scheduled = false
	cloud_match_create_failed.emit(message)

func _schedule_cloud_join_retry(generation: int) -> void:
	if generation != _cloud_join_generation or _cloud_join_retry_scheduled:
		return
	_cloud_join_retry_scheduled = true
	_start_cloud_join_after_delay(generation, CLOUD_JOIN_RETRY_DELAY_SEC)
