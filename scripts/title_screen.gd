extends Control

@export var game_scene_path: String = "res://world.tscn"

@onready var vb := $CenterContainer/VBoxContainer
@onready var btn_play: Button = $CenterContainer/VBoxContainer/TestButton
@onready var btn_multi: Button = $CenterContainer/VBoxContainer/MultiPlayerButton
@onready var quit_btn: Button = vb.get_node_or_null("QuitButton")

@onready var popup: Window = $MultiplayerPopup
@onready var btn_find: Button = $MultiplayerPopup/VBox/FindServerButton
@onready var btn_create: Button = $MultiplayerPopup/VBox/CreateServerButton
@onready var ip_line: LineEdit = $MultiplayerPopup/VBox/HBox/IpLine
@onready var btn_connect: Button = $MultiplayerPopup/VBox/HBox/ConnectButton
# (Optional) add a Label under the popup to show status and point this path to it.
@onready var status_label: Label = $MultiplayerPopup/VBox/Label if has_node("MultiplayerPopup/VBox/Label") else null

const LOBBY_SCENE := "res://Lobby.tscn"

func _ready() -> void:
	
	var args := OS.get_cmdline_args()

	# Dedicated headless server mode
	if "--server" in args:
		GameState.is_host = true
		GameState.is_dedicated = true

		Network.host()  # your ENet create_server()

		# go straight to lobby; no UI, no camera
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return

	# -------- normal client flow below --------
	# (show title screen buttons, etc.)
	
	
	Settings.ensure_player_name()
	if Settings.player_name == "" or Settings.player_name.begins_with("Player_"):
		await _prompt_for_player_name()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if OS.has_feature("mobile") and quit_btn:
		quit_btn.visible = false

	# Title buttons
	btn_play.pressed.connect(_start_game)
	btn_multi.pressed.connect(_open_multiplayer_screen)

	# Popup buttons
	btn_find.pressed.connect(_on_find_server)
	btn_create.pressed.connect(_on_create_server)
	btn_connect.pressed.connect(_on_connect_to_ip)

	# Network callbacks while we are on the title screen
	Network.joined_server.connect(_on_joined_server)
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)

	# Convenience default for local tests
	if ip_line.text.strip_edges() == "":
		ip_line.text = "127.0.0.1"

func _prompt_for_player_name() -> void:
	var win := Window.new()
	win.title = "Set Your Player Name"
	win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	win.size = Vector2i(800,400)
	win.unresizable = true
	add_child(win)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 16; vb.offset_right = -16
	vb.offset_top  = 16; vb.offset_bottom = -16
	win.add_child(vb)

	var label := Label.new()
	label.text = "Enter the name to show in lobbies:"
	vb.add_child(label)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "e.g., Ayaan"
	name_edit.text = Settings.player_name
	vb.add_child(name_edit)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(row)

	var cancel := Button.new(); cancel.text = "Cancel"
	var ok := Button.new();     ok.text = "Save"
	row.add_child(cancel); row.add_child(ok)

	ok.pressed.connect(func():
		Settings.set_player_name_and_save(name_edit.text)
		win.queue_free()
	)
	cancel.pressed.connect(func():
		if Settings.player_name == "" or Settings.player_name.begins_with("Player_"):
			Settings.ensure_player_name()
		win.queue_free()
	)

	win.popup_centered()
	await win.tree_exited


func _unhandled_input(event: InputEvent) -> void:
	# Enter starts game only when popup is closed
	if event.is_action_pressed("ui_accept") and !popup.visible:
		_start_game()

	# Esc / Android Back: close popup or exit
	if event.is_action_pressed("ui_cancel"):
		if popup.visible:
			popup.hide()
		else:
			_show_quit_confirm_or_exit()

func _start_game() -> void:
	if has_node("Fade"):
		_fade_then_change()
	else:
		get_tree().change_scene_to_file(game_scene_path)

func _open_multiplayer_screen() -> void:
	popup.popup_centered(Vector2i(460, 300))
	await get_tree().process_frame
	btn_find.grab_focus()

# ---------------- Multiplayer ----------------

func _on_find_server() -> void:
	print("TODO: find LAN servers")

func _on_create_server() -> void:
	# Identity
	GameState.reset_lobby()
	if GameState.player_name == "" or GameState.player_name == "Player":
		GameState.player_name = "Fardin Eajdani"  # or make dynamic if you add a name field
	GameState.is_host = true
	

	# Start ENet server and go to lobby
	Network.host()
	GameState.player_name = Settings.player_name
	GameState.id = 1
	GameState.roster[1] = {"name": GameState.player_name, "ready": false, "team": GameState.Team.BLUE} # team optional
	var lan := get_lan_ip()
	print("Hosting on UDP 24565, LAN IP =", lan)
	# Register host in roster (peer 1) with ready=false
	GameState.roster[1] = {"name": GameState.player_name, "ready": false}

	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_connect_to_ip() -> void:
	var ip := ip_line.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"

	GameState.is_host = false
	GameState.reset_lobby()
	GameState.player_name = Settings.player_name
	GameState.id = randi()
	GameState.roster[GameState.id] = {"name": GameState.player_name, "ready": false}

	_set_status("Connecting to %s…" % ip)
	_set_connect_ui_enabled(false)

	# Use the typed IP here:
	Network.join(ip)

func get_lan_ip() -> String:
	for addr in IP.get_local_addresses():  # PackedStringArray of addresses
		var is_ipv6 := String(addr).find(":") != -1
		if not addr.begins_with("127.") and not addr.begins_with("169.254.") and not is_ipv6:
			return addr
	return ""

func _on_joined_server() -> void:
	_set_status("Connected! Entering lobby…")
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_connection_failed() -> void:
	_set_status("Connection failed. Check IP/port and try again.")
	_set_connect_ui_enabled(true)

func _on_server_disconnected() -> void:
	_set_status("Disconnected from server.")
	_set_connect_ui_enabled(true)

func _set_connect_ui_enabled(v: bool) -> void:
	btn_connect.disabled = not v
	btn_create.disabled = not v

func _set_status(t: String) -> void:
	if status_label:
		status_label.text = t
	print(t)

# ---------------- Quit / fade helpers ----------------

func _quit() -> void:
	get_tree().quit()

func _show_quit_confirm_or_exit() -> void:
	if OS.has_feature("mobile"):
		get_tree().quit()

func _fade_then_change() -> void:
	var fade := $Fade as ColorRect
	fade.visible = true
	fade.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(fade, "modulate:a", 1.0, 0.35)
	await t.finished
	get_tree().change_scene_to_file(game_scene_path)
