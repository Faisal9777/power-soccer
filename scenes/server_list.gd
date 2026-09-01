extends Control

# Reference to the VBoxContainer
@onready var server_list = $ScrollContainer/ServerListContainer
const C = preload("res://scripts/shared/scene.gd")
const SCRIPT_PATHS = preload("res://scripts/shared/script_path.gd")
var known_servers := {}
var cleanup_timer := 0.0
var session_node : Node

func handle_data(data):
	var msg = data.get("message")
	if msg == NetCodes.state_message.CHANGE_STATE:
		var state_info = data.get("value")
		StateHandler.change_state(state_info.get("state"), state_info.get("state_data"))

func _ready():
	session_node = await SessionManager.create_client_session(SCRIPT_PATHS.CLIENT_SESSION)
	#_populate_server_list()
	session_node.server_found.connect(_on_server_found)
	session_node.start_discovery()
	StateHandler.register_state(self)

func _process(delta : float):
	_check_server_status()
	if Input.is_action_pressed("debug") and session_node:
		session_node.join({"ip":"172.21.222.53", "port":6000})

func _on_server_found(data):
	if not data.has("ip") or not data.has("port"):
		return  # invalid packet

	var key = str(data.id)
	#print("data: ", data) 
	#print("known_servers: ", known_servers)
	# Server is fresh
	if known_servers.has(key):
		known_servers[key]["entry"].update_status(data)
		known_servers[key]["last_seen"] = Time.get_unix_time_from_system()
	else:
		# Add new server
		var entry = preload(C.SERVER_ENTRY).instantiate()
		# Store in known_servers
		known_servers[key] = {
			"last_seen": Time.get_unix_time_from_system(),
			"entry": entry
		}
		server_list.add_child(entry)
		entry.setup(data)
	   
		# Optional: connect join button
		entry.join_button.pressed.connect(_on_connect_button_pressed.bind(data))

func _check_server_status():
	var now = Time.get_unix_time_from_system()
	var to_remove := []


	# Step 1: Find stale servers
	for key in known_servers.keys():
		var last_seen = known_servers[key]["last_seen"]


		if now - last_seen > 5:  # 5 seconds threshold
			to_remove.append(key)


	# Step 2: Remove them safely
	for key in to_remove:
		_remove_server(key)


func _remove_server(key):
	if not known_servers.has(key):
		return


	var entry = known_servers[key]["entry"]


	if is_instance_valid(entry):
		entry.queue_free()  # remove UI


	known_servers.erase(key)  # remove from dictionary


	print("Removed stale server:", key)


func _on_connect_button_pressed(data) -> void:
	GameState.reset_lobby()
	session_node.join(data)
