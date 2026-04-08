# LanBroadcastTransport.gd
class_name LanBroadcastTransport
extends IAnnounceTransport

var udp := PacketPeerUDP.new()

func _init():
	udp.set_broadcast_enabled(true)
	udp.bind(0) # random port

func send(payload: Dictionary) -> void:
	var json = JSON.stringify(payload)
	udp.set_dest_address(NetConfig.BROADCAST_IP, NetConfig.DISCOVERY_PORT)
	udp.put_packet(json.to_utf8_buffer())
