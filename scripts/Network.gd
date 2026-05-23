extends Node

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

const C = preload("res://scripts/shared/scene.gd")

# =========================
# HOST
# =========================
func host(info: Dictionary) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
		server_started.emit()
		return
	var port := info.get("port", 0) as int
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, 16)

	if err != OK:
		push_error("Host failed: %s" % err)
		return

	multiplayer.multiplayer_peer = enet

	if !_signals_hooked_server:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_signals_hooked_server = true
	# Start broadcasting

	is_host = true
	print("Server started on port ", port)
	server_started.emit()
	udp_discovery.bind(NetConfig.DISCOVERY_PORT)
	udp_discovery.set_broadcast_enabled(true)

func probe(data: Dictionary) -> void:
	var ip: String = data.get("ip", "")
	
	if ip == "":
		print("❌ Invalid probe data:", data)
		return
	
	print("📡 Probing:", ip)
	
	var msg := {
		"type": "DISCOVER"
	}
	
	var json := JSON.stringify(msg)
	
	udp_discovery.set_dest_address(ip, NetConfig.DISCOVERY_PORT)
	udp_discovery.put_packet(json.to_utf8_buffer())

# =========================
# JOIN
# =========================
func join(ip: String, port: int) -> bool:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		if multiplayer.is_server():
			push_warning("Already hosting.")
			return false
		close_connection()

	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(ip, port)

	if err != OK:
		push_error("Join failed: %s" % err)
		connection_failed.emit()
		return false

	multiplayer.multiplayer_peer = enet
	if not multiplayer.connected_to_server.is_connected(_on_connection_successful):
		multiplayer.connected_to_server.connect(_on_connection_successful)
	if !_signals_hooked_client:
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		_signals_hooked_client = true
	return true


# =========================
# DISCOVERY (CLIENT)
# =========================
func start_discovery() -> void:
	print("starting discovery2")
	var err := udp_discovery.bind(NetConfig.DISCOVERY_PORT)
	if err != OK:
		print("Discovery bind failed: %s" % err)
		return

	udp_discovery.bind(NetConfig.DISCOVERY_PORT)
	udp_discovery.set_broadcast_enabled(true)

func stop_discovery():
	udp_discovery.close()


func _poll_discovery():
	while udp_discovery.get_available_packet_count() > 0:
		var packet = udp_discovery.get_packet()
		var ip = udp_discovery.get_packet_ip()
		var port = udp_discovery.get_packet_port()

		var parsed = JSON.parse_string(packet.get_string_from_utf8())

		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		# =========================
		# 🟢 IF WE ARE HOST → RESPOND
		# =========================
		if is_host:
			if parsed.get("type") == "DISCOVER":
				
				var response := {
					"id": multiplayer.get_unique_id(),
					"name": GameState.info.name,
					"players_connected": GameState.get_players_connected(),
					"lobby_size": GameState.get_lobby_size(),
					"ping": 0,
					"port": NetConfig.PORT
				}
				
				udp_discovery.set_dest_address(ip, port)
				udp_discovery.put_packet(JSON.stringify(response).to_utf8_buffer())
			
			continue

		# =========================
		# 🔵 IF CLIENT → RECEIVE SERVER
		# =========================
		parsed["ip"] = ip
		server_found.emit(parsed)

# =========================
# PROCESS LOOP
# =========================
func _process(delta):
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



# =========================
# CONNECTION EVENTS
# =========================
func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	server_disconnected.emit()

func _on_connection_successful() -> void:
	joined_server.emit()


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
