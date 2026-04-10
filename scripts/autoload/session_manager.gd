extends Node

const SESSION_NAME = "Session"
const SYNC_NAME = "Sync"

var session_node: Node = null
var sync_node: Node = null
const SCRIPT_PATH := preload("res://scripts/shared/script_path.gd")

func create_lan_server_session(session_path: String) -> Node:
	var transport_method = LanBroadcastTransport.new()
	return _create_server_session(session_path, transport_method)

func create_cloud_server_session(session_path: String) -> Node:
	var endpoint = Configuration.get_value("heartbeat_endpoint")
	var transport_method = CloudHeartbeatTransport.new(endpoint)
	return _create_server_session(session_path, transport_method)

func create_client_session(session_path: String) -> Node:
	session_node = _create_node(session_path, SESSION_NAME)
	return session_node

func create_network_sync()-> Node:
	sync_node = _create_node(SCRIPT_PATH.NETWORK_SYNC, SYNC_NAME)
	sync_node.setup(session_node)
	return sync_node
	

func get_session() -> Node:
	return session_node

func get_network_sync() -> Node:
	return sync_node

func _create_node(node_path: String, node_name : String) -> Node:
	var root = get_tree().root

	# If already exists, reuse it
	if root.has_node(node_name):
		root.remove_child(root.get_node(node_name))

	# Create new session
	var script = load(node_path)
	if script == null:
		print("Failed to load: " + node_path)
		return null

	var node = script.new()
	node.name = node_name
	root.add_child(node)

	print("Session created at:", node.get_path())
	return node

func _create_server_session(session_path: String, transport_method) -> Node:
	session_node = _create_node(session_path, SESSION_NAME)
	session_node.setup(transport_method)
	return session_node
