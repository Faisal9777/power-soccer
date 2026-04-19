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
