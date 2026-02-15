#extends Node
#
#const PORT := 24565
#
#signal server_started
#signal joined_server
#signal peer_joined(id: int)
#signal peer_left(id: int)
#signal connection_failed
#signal server_disconnected
#
#func host() -> void:
	##print("host is called from network")
	#var enet := ENetMultiplayerPeer.new()
	#var err := enet.create_server(PORT, 16)
	#if err != OK:
		#push_error("Host failed: %s" % err)
		#return
	#multiplayer.multiplayer_peer = enet
#
	## Server tracks peer joins/leaves
	#multiplayer.peer_connected.connect(_on_peer_connected)
	#multiplayer.peer_disconnected.connect(_on_peer_disconnected)
#
	#print("Server started on port ", PORT)
	#server_started.emit()
#
#func join(ip: String) -> void:
	#var enet := ENetMultiplayerPeer.new()
	#var err := enet.create_client(ip, PORT)
	#if err != OK:
		#push_error("Join failed: %s" % err)
		#return
	#multiplayer.multiplayer_peer = enet
#
	## Client lifecycle hooks
	#multiplayer.connected_to_server.connect(func ():
		#print("Joined ", ip, ":", PORT)
		#joined_server.emit()
	#)
	#multiplayer.connection_failed.connect(func ():
		#push_error("Connection failed")
		#connection_failed.emit()
	#)
	#multiplayer.server_disconnected.connect(func ():
		#push_error("Server disconnected")
		#server_disconnected.emit()
	#)
#
#func _on_peer_connected(id: int) -> void:
	#peer_joined.emit(id)
#
#func _on_peer_disconnected(id: int) -> void:
	#peer_left.emit(id)
#
## Avoid clashing with Object.disconnect(signal, callable)
#func close_connection() -> void:
	#var peer := multiplayer.multiplayer_peer
	#if peer != null:
		#multiplayer.multiplayer_peer = null
		#if peer is ENetMultiplayerPeer:
			#(peer as ENetMultiplayerPeer).close()
# Network.gd (your version, lightly hardened)
extends Node

const PORT := 24565

signal server_started
signal joined_server
signal peer_joined(id: int)
signal peer_left(id: int)
signal all_peers_left
signal connection_failed
signal server_disconnected

var _signals_hooked_server := false
var _signals_hooked_client := false

func host() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
		server_started.emit()
		return

	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(PORT, 16)
	if err != OK:
		push_error("Host failed: %s" % err)
		return
	multiplayer.multiplayer_peer = enet

	# Hook once per hosting session
	if !_signals_hooked_server:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		#multiplayer.server_disconnected.connect(_on_server_disconnected)
		#multiplayer.connection_failed.connect(_on_connection_failed)
		_signals_hooked_server = true

	print("Server started on port ", PORT)
	server_started.emit()

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
		multiplayer.connected_to_server.connect(func ():
			print("Joined ", ip, ":", PORT)
			joined_server.emit()
		)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected
		)
		_signals_hooked_client = true

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

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	
	server_disconnected.emit()

func clear() -> void:
	close_connection()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

func close_connection() -> void:
	GameState.clear()
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return
	if peer is ENetMultiplayerPeer:
		(peer as ENetMultiplayerPeer).close()  # close transport
	multiplayer.multiplayer_peer = null
