extends Node

const SESSION_NAME = "Session"
const SYNC_NAME = "Sync"

var session_node: Node = null
var sync_node: Node = null
const SCRIPT_PATH := preload("res://scripts/shared/script_path.gd")

func get_or_create_session(session_path: String) -> Node:
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
