extends Node

var session


func setup(_session):
	session = _session

func send_data_id(id, msg, data):
	process_data.rpc_id(id, msg, data)

func send_data_id_reliable(id, msg, data):
	process_reliable_data.rpc_id(id, msg, data)

func send_data_all(msg, data):
	rpc("process_data", msg, data)

@rpc("any_peer")
func process_data(msg, data):
	if session:
		session.handle_data(msg, data)

@rpc("any_peer", "reliable")
func process_reliable_data(msg, data):
	if session:
		session.handle_data(msg, data)
# network_sync.gd — add alongside your existing methods
func send_movement_id(id, msg, data):
	process_movement.rpc_id(id, msg, data)

func send_movement_all(msg, data):
	rpc("process_movement", msg, data)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func process_movement(msg, data):
	if session:
		session.handle_data(msg, data)
