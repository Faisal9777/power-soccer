extends Node

var session


func setup(_session):
	session = _session

func send_data_id(id, data):
	process_data.rpc_id(id, data)

func send_data_all(data):
	rpc("process_data", data)

@rpc("any_peer")
func process_data(data):
	if session:
		session.handle_data(data)
