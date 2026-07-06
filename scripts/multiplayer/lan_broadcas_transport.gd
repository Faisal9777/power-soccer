# LanBroadcastTransport.gd
class_name LanBroadcastTransport
extends IAnnounceTransport

var udp := PacketPeerUDP.new()

func _init():
	udp.set_broadcast_enabled(true)
	udp.bind(0) # random port

func get_broadcast_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			var p = addr.split(".")
			return "%s.%s.%s.255" % [p[0], p[1], p[2]]
	return "255.255.255.255"

func send(payload: Dictionary) -> void:
	var json = JSON.stringify(payload)
	udp.set_dest_address(get_broadcast_ip(), NetConfig.DISCOVERY_PORT)
	udp.put_packet(json.to_utf8_buffer())
