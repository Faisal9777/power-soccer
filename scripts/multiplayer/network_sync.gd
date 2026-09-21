extends Node

var session
var can_send := true

func setup(_session):
	session = _session

func send_data_id(id, data):
	if not multiplayer.is_server() and Input.is_action_pressed("debug"):
		data["debug"] = Input.is_action_pressed("debug")
		print("send data id client debug------------------------------------------------------------------------------------------------------------")
		#var value1 = data.get("value")
		#if value1 != null:
			#var value2 = value1.get("value")
			#if value2 != null:
				#var value3 = value2.get("value")
				#if value3.get("debug") != null and value3.get("debug"):
					#print("send data id client debug------------------------------------------------------------------------------------------------------------")
		
	process_data.rpc_id(id, data)

#func send_data_id(id, data):
	#if not multiplayer.is_server():
		#var value1 = data.get("value")
		#if value1 != null:
			#var value2 = value1.get("value")
			#if value2 != null:
				#var value3 = value2.get("value")
				#if value3.get("debug") != null and value3.get("debug"):
					#print("send data id client debug------------------------------------------------------------------------------------------------------------")
					#can_send = false
					#process_data.rpc_id(id, data)
	#if can_send:
		#process_data.rpc_id(id, data)

func send_data_all(data):
	rpc("process_data", data)

@rpc("any_peer")
func process_data(data):
	if multiplayer.is_server() and data.get("debug"):
		print("process_data server debug???????????????????????????????????????????????????????????????????????????????????????????????")
		#var value1 = data.get("value")
		#if value1 != null:
			#var value2 = value1.get("value")
			#if value2 != null:
				#var value3 = value2.get("value")
				#if value3.get("debug") != null and value3.get("debug"):
					#print("process_data server debug???????????????????????????????????????????????????????????????????????????????????????????????")
	if session:
		session.handle_data(data)
