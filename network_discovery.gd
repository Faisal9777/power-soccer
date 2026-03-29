extends Node

# NetworkDiscovery.gd
signal server_found(server_info)

var listen_udp := PacketPeerUDP.new()

func start_discovery():
	listen_udp.bind(NetConfig.DISCOVERY_PORT)
	listen_udp.set_broadcast_enabled(true)

func _process(delta):
	# listen
	while listen_udp.get_available_packet_count() > 0:
		var packet = listen_udp.get_packet()
		var ip = listen_udp.get_packet_ip()


		var data = JSON.parse_string(packet.get_string_from_utf8())

		if data == null:
			print("Invalid JSON (null)")
			continue

		if typeof(data) != TYPE_DICTIONARY:
			print("Unexpected JSON format:", data)
			continue
		if data:
			data["ip"] = ip
			emit_signal("server_found", data)


func stop_discovery():
	listen_udp.close()
