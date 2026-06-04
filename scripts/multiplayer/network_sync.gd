extends Node

var session


func setup(_session):
	session = _session

func send_data_id(id, msg, data):
	process_data.rpc_id(id, msg, data)

func send_data_all(msg, data):
	rpc("process_data", msg, data)

@rpc("any_peer")
func process_data(msg, data):
	if session:
		session.handle_data(msg, data)
