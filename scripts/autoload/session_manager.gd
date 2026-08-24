extends Node

const SESSION_NAME = "Session"
const SYNC_NAME = "Sync"

var session_node: Node = null
var sync_node: Node = null
const C = preload("res://scripts/shared/scene.gd")
const SCRIPT_PATH := preload("res://scripts/shared/script_path.gd")
const LAN_PORT := 24565

func create_lan_server_session(session_path: String, id) -> Node:
	var transport_method = LanBroadcastTransport.new()
	return await _create_server_session(session_path, transport_method, id, LAN_PORT, false)

func create_cloud_server_session(session_path: String, id, port) -> Node:
	var endpoint = _get_endpoint("heartbeat_endpoint")
	var transport_method = NodeUtils.create_cloud_transport(endpoint, self)
	return await _create_server_session(session_path, transport_method, id, port)

func create_client_session(session_path: String) -> Node:
	var endpoint = _get_endpoint("discovery")
	print("the endpoint during client session creation; ", endpoint)
	var discovery = CloudDiscovery.new(endpoint, self)
	session_node = await _create_node(session_path, SESSION_NAME)
	session_node.setup(discovery)
	return session_node

func create_network_sync()-> Node:
	sync_node = await _create_node(SCRIPT_PATH.NETWORK_SYNC, SYNC_NAME)
	sync_node.setup(session_node)
	return sync_node
	

func get_session() -> Node:
	return session_node

func get_network_sync() -> Node:
	return sync_node

func close_session() -> void:
	session_node.queue_free()
	get_tree().change_scene_to_file(C.TITLE)

func change_state(state_info: int):
	StateHandler.change_state(state_info)

func send_data_id(msg, value):
	session_node.send_data_id(msg, value)

func send_data_id_reliable(msg, value):
	session_node.send_data_id_reliable(msg, value)

func send_data(msg, value):
	session_node.send_data(msg, value)

func register_state(state : Node):
	StateHandler.register_state(state)

func _create_node(node_path: String, node_name : String) -> Node:
	var root = get_tree().root

	# If already exists, reuse it
	if root.has_node(node_name):
		root.remove_child(root.get_node(node_name))
	print("loading: ", node_path)
	# Create new session
	var script = load(node_path)
	if script == null:
		print("Failed to load: " + node_path)
		return null

	var node = script.new()
	node.name = node_name
	await NodeUtils.add_child_and_wait_ready(root, node)

	return node

func _get_endpoint(endpoint) -> String:
	Config.load_config()
	return Config.get_value(endpoint)
	

func _create_server_session(session_path: String, transport_method, id, port, is_cloud_session=true) -> Node:
	session_node = await _create_node(session_path, SESSION_NAME)
	session_node.setup(transport_method, id, port, is_cloud_session)
	return session_node

# session_manager.gd — add
func send_movement_id(msg, value):
	session_node.send_movement_id(msg, value)

func send_movement(msg, value):
	session_node.send_movement(msg, value)
