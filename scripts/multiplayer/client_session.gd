extends Node
class_name ClientSession

signal joined_server
signal server_found(info)

func stop_discovery():
	Network.stop_discovery()

func start_discovery():
	Network.server_found.connect(_on_server_found)
	Network.start_discovery()


func join(ip):

	Network.joined_server.connect(_on_joined_server)
	Network.join(ip)

func _on_server_found(info):
	server_found.emit(info)

func _on_joined_server():
	print('cliient_session _on_joined_server')
	var payload := {"name" : Settings.player_name, "id" : multiplayer.get_unique_id()}
	rpc_id(1, "_srv_register_player", payload)

@rpc("call_local")
func _cl_sync_roster(roster):
	print("_cl_sync_roster")
	GameState.roster = roster
	joined_server.emit()
