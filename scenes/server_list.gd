extends Control

# Reference to the VBoxContainer
@onready var filter_box = $FilterBox
@onready var filter_button = $FilterBox/FilterBar/FilterServers

@onready var filter_options = $FilterBox/FilterOptions

@onready var lan_cb = $FilterBox/FilterOptions/LAN
@onready var cloud_cb = $FilterBox/FilterOptions/Cloud
@onready var has_players_cb = $FilterBox/FilterOptions/HasPlayers
@onready var private_cb = $FilterBox/FilterOptions/Private
@onready var public_cb = $FilterBox/FilterOptions/Public
@onready var server_list = $ScrollContainer/ServerListContainer
const C = preload("res://scripts/shared/scene.gd")
const SCRIPT_PATHS = preload("res://scripts/shared/script_path.gd")
var known_servers := {}
var cleanup_timer := 0.0
var session_node : Node
var pending_join_data = null
var discovery_times := {}
var _probe_udp := PacketPeerUDP.new()
var filter_lan := true
var filter_cloud := true

var filter_private := true
var filter_public := true

var filter_has_players := false

func _ready():
	session_node = await SessionManager.create_client_session(SCRIPT_PATHS.CLIENT_SESSION)
	#_populate_server_list()
	session_node.server_found.connect(_on_server_found)
	session_node.auth_failed.connect(_on_auth_failed)
	session_node.start_discovery()
	scan_network()
	filter_options.visible = false

	lan_cb.button_pressed = true
	cloud_cb.button_pressed = true

	private_cb.button_pressed = true
	public_cb.button_pressed = true

	has_players_cb.button_pressed = false

	filter_button.pressed.connect(_on_filter_button_pressed)

	lan_cb.toggled.connect(_on_filter_changed)
	cloud_cb.toggled.connect(_on_filter_changed)
	private_cb.toggled.connect(_on_filter_changed)
	public_cb.toggled.connect(_on_filter_changed)
	has_players_cb.toggled.connect(_on_filter_changed)

func _process(delta : float):
	_check_server_status()
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
	for i in range(90, 121):
		var ip = subnet + str(i)
		print("Scanning:", ip)
		discovery_times[ip] = Time.get_ticks_msec()
		_try_connect(ip)
		await get_tree().create_timer(0.02).timeout
		
func _try_connect(ip: String):
	# Send a small UDP probe packet directly to the target IP on the LAN discovery port.
	# If a hosted game server is running there it will reply via its UDP broadcast,
	# which the existing _poll_discovery loop in Network.gd will pick up.
	var probe_data := JSON.stringify({"probe": true}).to_utf8_buffer()
	_probe_udp.set_dest_address(ip, NetConfig.DISCOVERY_PORT)
	_probe_udp.put_packet(probe_data)

func _on_server_found(data):
	if not data.has("ip") or not data.has("port"):
		return  # invalid packet

	var ping := int(data.get("ping", -1))
	var ip := String(data.get("ip", ""))

	if discovery_times.has(ip):
		ping = Time.get_ticks_msec() - discovery_times[ip]

	data["ping"] = ping
	var key = str(data.id)
	#print("data: ", data) 
	#print("known_servers: ", known_servers)
	# Server is fresh
	if known_servers.has(key):
		known_servers[key]["entry"].update_status(data)
		known_servers[key]["entry"].visible = _passes_filters(data)
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
		entry.visible = _passes_filters(data)
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

	# If server is private → ask password first
	if not data.get("is_public", true):
		pending_join_data = data
		_show_password_popup()
		return

	# Public server → join immediately
	_join_server(data, 0)
		
func _join_server(data, password):
	session_node.stop_discovery()
	session_node.join(data, password)

	# wait for connection, then send password

	
func _show_password_popup():
	var popup := Window.new()
	popup.title = "Enter Password"
	popup.size = Vector2i(350, 180)
	popup.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(popup)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(vbox)

	var input := LineEdit.new()
	input.placeholder_text = "Password"
	input.secret = true
	input.max_length = 6
	input.text_changed.connect(func(new_text):
		var filtered := ""

		for ch in new_text:
			if ch >= "0" and ch <= "9":
				filtered += ch

		if filtered != new_text:
			input.text = filtered
			input.caret_column = filtered.length()
)
	vbox.add_child(input)

	var error_label := Label.new()
	error_label.text = ""
	vbox.add_child(error_label)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)

	var cancel := Button.new()
	cancel.text = "Cancel"
	btn_row.add_child(cancel)

	var join := Button.new()
	join.text = "Join"
	btn_row.add_child(join)

	# Cancel
	cancel.pressed.connect(func():
		popup.queue_free()
		pending_join_data = null
		session_node.start_discovery()

	)

	# JOIN → no validation here anymore
	join.pressed.connect(func():
		var password := int(input.text)
		popup.queue_free()

		# Pass password to secure join flow
		_join_server(pending_join_data, password)
		
	)

	popup.popup_centered()
func _on_auth_failed():
	session_node.close_connection()
	_show_auth_failed_popup()
	
func _show_auth_failed_popup():
	var popup := Window.new()
	popup.title = "Authentication Failed"
	popup.size = Vector2i(350, 180)
	popup.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	popup.unresizable = true

	add_child(popup)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	popup.add_child(vbox)

	var label := Label.new()
	label.text = "Wrong password. Please try again."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2i(100, 40)
	btn_row.add_child(ok_btn)

	ok_btn.pressed.connect(func():
		popup.queue_free()
		_show_password_popup()
		session_node.start_discovery()
	)

	popup.popup_centered()
func _passes_filters(data) -> bool:
	# LAN / Cloud
	if data.get("is_lan", true):
		if !filter_lan:
			return false
	else:
		if !filter_cloud:
			return false
	# Private / Public
	if data.get("is_public", true):
		if !filter_public:
			return false
	else:
		if !filter_private:
			return false

	# Has Players
	if filter_has_players and data.get("players", 0) <= 0:
		return false

	return true
func _refresh_filters():
	for key in known_servers:
		var entry = known_servers[key]["entry"]
		var data = entry.server_data

		entry.visible = _passes_filters(data)
func _on_filter_button_pressed():
	filter_options.visible = !filter_options.visible


func _on_filter_changed(_pressed: bool):
	filter_lan = lan_cb.button_pressed
	filter_cloud = cloud_cb.button_pressed

	filter_private = private_cb.button_pressed
	filter_public = public_cb.button_pressed

	filter_has_players = has_players_cb.button_pressed

	_refresh_filters()
