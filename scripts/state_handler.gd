extends Node
const C = preload("res://scripts/shared/scene.gd")
var current_scene := -1
var current_state : Node

func change_state(state_info: int):
	var scene_to_load = ""
	current_state = null
	current_scene = state_info
	if state_info == NetCodes.States.LOBBY:
		scene_to_load = C.LOBBY
	if state_info == NetCodes.States.WORLD:
		scene_to_load = C.WORLD
	elif state_info == NetCodes.States.SCOREBOARD:
		scene_to_load = C.SCORE
	elif state_info == NetCodes.States.TITLE:
		scene_to_load = C.TITLE
		SessionManager.session_node.disconnect_connection()
		SessionManager.session_node.queue_free()
	get_tree().change_scene_to_file(scene_to_load)

func register_state(state):
	current_state = state

func handle_data(msg, data, state):	
	if not state == current_scene:
		return
	elif current_state:
		current_state.handle_data(msg, data)

func send_data_id(msg, value):
	value["state"] = current_scene
	SessionManager.send_data_id(msg, value)

func send_data_id_reliable(msg, value):
	value["state"] = current_scene
	SessionManager.send_data_id_reliable(msg, value)

func send_data(msg, value):
	value["state"] = current_scene
	SessionManager.send_data(msg, value)

func on_connected_to_server(server_info):
	change_state(server_info.get("current_state"))

# state_handler.gd — add
func send_movement_id(msg, value):
	value["state"] = current_scene
	SessionManager.send_movement_id(msg, value)

func send_movement(msg, value):
	if value is Dictionary:
		value["state"] = current_scene
	SessionManager.send_movement(msg, value)
