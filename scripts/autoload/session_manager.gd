extends Node

const SESSION_NAME = "Session"
const SYNC_NAME = "Sync"

var session_node: Node = null
var sync_node: Node = null
const SCRIPT_PATH := preload("res://scripts/shared/script_path.gd")
const LAN_PORT := 24565

func create_lan_server_session(session_path: String, id) -> Node:
	var transport_method = LanBroadcastTransport.new()
	return await _create_server_session(session_path, transport_method, id, LAN_PORT)
func create_cloud_server_session(session_path: String, id, port) -> Node:
	_ensure_config_loaded()

	var endpoint = Configuration.get_value("heartbeat_endpoint")
	var transport_method = CloudHeartbeatTransport.new(endpoint)

	return await _create_server_session(session_path, transport_method, id, port)
	
func create_client_session(session_path: String) -> Node:
	_ensure_config_loaded()
	session_node = await _create_node(session_path, SESSION_NAME)
	return session_node

func create_network_sync() -> Node:
	sync_node = await _create_node(SCRIPT_PATH.NETWORK_SYNC, SYNC_NAME)

	sync_node.setup(session_node)

	return sync_node

func get_session() -> Node:
	return session_node

func get_network_sync() -> Node:
	return sync_node

func _create_node(node_path: String, node_name: String) -> Node:
	var root = get_tree().root

	# Remove existing
	if root.has_node(node_name):
		root.get_node(node_name).queue_free()

	var script = load(node_path)
	if script == null:
		print("Failed to load: " + node_path)
		return null

	var node = script.new()
	node.name = node_name

	root.call_deferred("add_child", node)

	await node.ready

	print("Session created at:", node.get_path())

	return node
	
func _create_server_session(session_path: String, transport_method, id, port) -> Node:
	session_node = await _create_node(session_path, SESSION_NAME)

	session_node.setup(transport_method, id, port)

	return session_node
	
func _ensure_config_loaded() -> void:
	if Configuration.data.is_empty():
		Configuration.load_config()
