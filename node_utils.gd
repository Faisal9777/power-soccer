# NodeUtils.gd
class_name NodeUtils

static func add_child_and_wait_ready(parent: Node, child: Node) -> void:
	parent.call_deferred("add_child", child)
	await child.ready

static func create_http_and_wait(parent: Node) -> HttpService:
	var http := HttpService.new(parent)
	return http

static func create_cloud_transport(endpoint, parent: Node) -> CloudHeartbeatTransport:
	var http = create_http_and_wait(parent)
	var t = CloudHeartbeatTransport.new(endpoint, http)

	return t

static func init_input_source(parent: Node) -> Node:
	var t = InputSource.new()
	parent.add_child(t)

	return t

static func create_game_client(parent: Node, cl, name, state, scoreboard, controllers) -> Node:
	var t = create_node(parent, cl, name)
	t.setup(state, scoreboard, controllers)
	return t

static func create_node(parent: Node, cl, name : String) -> Node:
	var t = cl.new()
	t.name = name
	parent.add_child(t)

	return t
