extends Node

signal server_started
signal server_found(server_info)
signal joined_server
signal peer_joined(id: int)
signal peer_left(id: int)
signal all_peers_left
signal connection_failed
signal server_disconnected
var recent_servers := {}

const ENET_TIMEOUT_LIMIT := 32
const ENET_TIMEOUT_MIN := 15000
const ENET_TIMEOUT_MAX := 45000
const ENET_PING_INTERVAL := 1500

var _signals_hooked_server := false
var _signals_hooked_client := false

# TWO UDP SOCKETS (important)
var udp_broadcast := PacketPeerUDP.new()
var udp_discovery := PacketPeerUDP.new()

var is_host := false

const C = preload("res://scripts/shared/scene.gd")

func _configure_peer(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer

	if peer == null:
		return

	if !(peer is ENetMultiplayerPeer):
		return

	var enet_peer := peer as ENetMultiplayerPeer
	var packet_peer := enet_peer.get_peer(peer_id)

	if packet_peer == null:
		return

	packet_peer.set_timeout(
		ENET_TIMEOUT_LIMIT,
		ENET_TIMEOUT_MIN,
		ENET_TIMEOUT_MAX
	)

 
	print(
		"Configured ENet peer ",
		peer_id,
		" timeout_min=",
		ENET_TIMEOUT_MIN,
		" timeout_max=",
		ENET_TIMEOUT_MAX
	)
	
# =========================
# HOST
# =========================
func host(info: Dictionary) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
		server_started.emit()
		return
	var port := info.get("port", 0) as int
	var enet := ENetMultiplayerPeer.new()
	var err2 := enet.create_server(port, 16)

	if err2 != OK:
		push_error("Host failed: %s" % err2)
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
	udp_broadcast.close()

	var err := udp_broadcast.bind(NetConfig.DISCOVERY_PORT)

	if err != OK:
		print("Broadcast bind failed: ", err)
		return

	udp_broadcast.set_broadcast_enabled(true)
func probe(data: Dictionary) -> void:
	var ip: String = data.get("ip", "")
	
	if ip == "":
		print("❌ Invalid probe data:", data)
		return
	
	print("📡 Probing:", ip)
	
	var msg := {
		"type": "DISCOVER",
		"timestamp": Time.get_ticks_msec()
	}
	
	var json := JSON.stringify(msg)
	
	udp_discovery.set_dest_address(ip, NetConfig.DISCOVERY_PORT)
	udp_discovery.put_packet(json.to_utf8_buffer())

# =========================
# JOIN
# =========================
func join(ip: String, port: int) -> bool:
	stop_discovery()

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
	print("Starting discovery")

	udp_discovery.close()

	var err := udp_discovery.bind(NetConfig.DISCOVERY_PORT)

	if err != OK:
		print("Discovery bind failed: %s" % err)
		return

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
					"id": GameState.info.name + "_" + str(NetConfig.PORT),
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

func _poll_host_discovery():

	while udp_broadcast.get_available_packet_count() > 0:

		var packet = udp_broadcast.get_packet()
		var ip = udp_broadcast.get_packet_ip()
		var port = udp_broadcast.get_packet_port()

		var parsed = JSON.parse_string(packet.get_string_from_utf8())

		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		if parsed.get("type") != "DISCOVER":
			continue

		var response := {
			"type": "DISCOVER_RESPONSE",
			"server_id": GameState.info.name + "_" + str(NetConfig.PORT),
			"name": GameState.info.name,
			"players_connected": GameState.get_players_connected(),
			"lobby_size": GameState.get_lobby_size(),
			"port": NetConfig.PORT,
			"timestamp": parsed.get("timestamp", 0)
		}

		udp_broadcast.set_dest_address(ip, port)
		udp_broadcast.put_packet(JSON.stringify(response).to_utf8_buffer())
func _poll_client_discovery():

	while udp_discovery.get_available_packet_count() > 0:

		var packet = udp_discovery.get_packet()
		var ip = udp_discovery.get_packet_ip()

		var parsed = JSON.parse_string(packet.get_string_from_utf8())

		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		if parsed.get("type") != "DISCOVER_RESPONSE":
			continue

		parsed["ip"] = ip

		var ping = Time.get_ticks_msec() - parsed.get("timestamp", 0)
		parsed["ping"] = ping

		var key = parsed["server_id"]

		var now = Time.get_ticks_msec()

		if recent_servers.has(key):

			if now - recent_servers[key] < 500:
				continue

		recent_servers[key] = now
		server_found.emit(parsed)
# =========================
# PROCESS LOOP
# =========================
func _process(delta):
	if is_host:
		_poll_host_discovery()
	else:
		_poll_client_discovery()

# =========================
# PEER EVENTS
# =========================
func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return

	_configure_peer(id)

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
	# Server peer is always peer ID 1 on clients
	_configure_peer(1)

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
	udp_discovery.close()
	udp_broadcast.close()
