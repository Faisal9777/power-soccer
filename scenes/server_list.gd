extends Control

# Reference to the VBoxContainer
@onready var server_list = $ScrollContainer/ServerListContainer
const C = preload("res://scripts/shared/scene.gd")
const SCRIPT_PATHS = preload("res://scripts/shared/script_path.gd")
var known_servers := {}
var cleanup_timer := 0.0
var session_node : Node

func _ready():
	session_node = SessionManager.create_client_session(SCRIPT_PATHS.CLIENT_SESSION)
	#_populate_server_list()
	session_node.server_found.connect(_on_server_found)
	session_node.start_discovery()
	scan_network()

func _process(delta : float):
	if Input.is_action_pressed("debug"):
		Network.join("127.0.0.1", 24565)
func get_local_subnet() -> String:
	var ip = IP.get_local_addresses()
	
	for addr in ip:
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			var parts = addr.split(".")
			return parts[0] + "." + parts[1] + "." + parts[2] + "."
	
	return ""
func scan_network():
	var subnet = get_local_subnet()
	print("SCAN STARTED. Subnet:", subnet)
	
	if subnet == "":
		print("No valid subnet found")
		return
	for i in range(90, 121):   # ✅ 90 → 120
		var ip = subnet + str(i)
		print("Scanning:", ip)
		_try_connect(ip)
		await get_tree().create_timer(0.02).timeout
		
func _try_connect(ip: String):
	Network.probe({
		"ip": ip
	})

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

	# Use the typed IP here:
	session_node.stop_discovery()
	session_node.join(data)
