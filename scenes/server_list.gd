extends Control

# Reference to the VBoxContainer
@onready var server_list = $ScrollContainer/ServerListContainer
const C = preload("res://scripts/shared/scene.gd")
var known_servers := {}
var cleanup_timer := 0.0

func _ready():
	#_populate_server_list()
	Network.joined_server.connect(_on_joined_server)
	Network.server_found.connect(_on_server_found)
	Network.start_discovery()

func _process(delta : float):
	if Input.is_action_pressed("debug"):
		Network.join("127.0.0.1")

func _on_server_found(data):
	
	if not data.has("ip") or not data.has("port"):
		return  # invalid packet


	var key = str(data.id)
	var last_seen = data["last_seen"]
	#print("data: ", data)
	#print("known_servers: ", known_servers)
	# Server is fresh
	if known_servers.has(key):
		# Update last_seen for existing entry
		known_servers[key]["last_seen"] = last_seen
		known_servers[key]["entry"].update_status(data)
	else:
		# Add new server
		var entry = preload(C.SERVER_ENTRY).instantiate()
		# Store in known_servers
		known_servers[key] = {
			"last_seen": last_seen,
			"entry": entry
		}
		server_list.add_child(entry)
		entry.setup(data)
	   
		# Optional: connect join button
		entry.join_button.pressed.connect(_on_connect_button_pressed.bind(data.ip))
		print("Added new server:", key)

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


func _on_connect_button_pressed(ip) -> void:
	GameState.is_host = false
	GameState.reset_lobby()
	GameState.player_name = Settings.player_name
	GameState.id = randi()
	GameState.roster[GameState.id] = {"name": GameState.player_name, "ready": false}

	# Use the typed IP here:
	Network.stop_discovery()
	Network.join(ip)


func _on_joined_server() -> void:
	get_tree().change_scene_to_file(C.LOBBY)
