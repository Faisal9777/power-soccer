extends Node

const PORT := 24565

signal server_started
signal server_found(server_info)
signal joined_server
signal peer_joined(id: int)
signal peer_left(id: int)
signal all_peers_left
signal connection_failed
signal server_disconnected

var _signals_hooked_server := false
var _signals_hooked_client := false

# TWO UDP SOCKETS (important)
var udp_broadcast := PacketPeerUDP.new()
var udp_discovery := PacketPeerUDP.new()

var is_host := false
var server_info = {}

const C = preload("res://scripts/shared/scene.gd")

# =========================
# HOST
# =========================
func host(info: Dictionary) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
		server_started.emit()
		return

	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(PORT, 16)

	if err != OK:
		push_error("Host failed: %s" % err)
		return

	multiplayer.multiplayer_peer = enet

	if !_signals_hooked_server:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_signals_hooked_server = true
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	info["id"] = id
	# Start broadcasting
	_start_broadcast(info)

	is_host = true
	print("Server started on port ", PORT)
	server_started.emit()


func change_state(state_info: String):
	server_info.state = state_info


# =========================
# JOIN
# =========================
func join(ip: String) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		push_warning("Already connected/hosting.")
		return

	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(ip, PORT)

	if err != OK:
		push_error("Join failed: %s" % err)
		return

	multiplayer.multiplayer_peer = enet

	if !_signals_hooked_client:
		multiplayer.connected_to_server.connect(func():
			print("Joined ", ip, ":", PORT)
			joined_server.emit()
		)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		_signals_hooked_client = true


# =========================
# DISCOVERY (CLIENT)
# =========================
func start_discovery() -> void:
	print("starting discovery")
	var err := udp_discovery.bind(NetConfig.DISCOVERY_PORT)
	if err != OK:
		push_error("Discovery bind failed: %s" % err)
		return

	udp_discovery.set_broadcast_enabled(true)


func stop_discovery():
	udp_discovery.close()


func _poll_discovery():
	while udp_discovery.get_available_packet_count() > 0:
		var packet = udp_discovery.get_packet()
		var ip = udp_discovery.get_packet_ip()

		var parsed = JSON.parse_string(packet.get_string_from_utf8())

		# JSON.parse_string returns Variant (no .error)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		# ❗ Prevent self-detection (important)
		if is_host:
			continue

		parsed["ip"] = ip
		server_found.emit(parsed)


# =========================
# BROADCAST (SERVER)
# =========================
func _start_broadcast(info: Dictionary):
	udp_broadcast.set_broadcast_enabled(true)
	udp_broadcast.bind(0) # random port
	server_info = info
	server_info["port"] = PORT


func _broadcast():
	server_info["last_seen"] = Time.get_unix_time_from_system()
	server_info["lobby_size"] = GameState.lobby_data["lobby_size"]
	server_info["players_connected"] = GameState.lobby_data["players_connected"]

	var json = JSON.stringify(server_info)
	udp_broadcast.set_dest_address(NetConfig.BROADCAST_IP, NetConfig.DISCOVERY_PORT)
	udp_broadcast.put_packet(json.to_utf8_buffer())


# =========================
# PROCESS LOOP
# =========================
func _process(delta):
	if is_host:
		_broadcast()
	else:
		_poll_discovery()


# =========================
# PEER EVENTS
# =========================
func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return

	peer_left.emit(id)

	if multiplayer.get_peers().size() == 0 and GameState.is_dedicated:
		all_peers_left.emit()

	GameState.clear()


# =========================
# CONNECTION EVENTS
# =========================
func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	server_disconnected.emit()


# =========================
# CLEANUP / QUIT
# =========================
func clear() -> void:
	close_connection()
	get_tree().change_scene_to_file(C.TITLE)


func close_connection() -> void:
	GameState.clear()

	var peer := multiplayer.multiplayer_peer
	if peer != null and peer is ENetMultiplayerPeer:
		(peer as ENetMultiplayerPeer).close()

	multiplayer.multiplayer_peer = null
	is_host = false

	# 🔥 Close BOTH sockets
	udp_broadcast.close()
	udp_discovery.close()
