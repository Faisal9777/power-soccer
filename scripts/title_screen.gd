
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
	var lan := get_lan_ip()
	print("Hosting on UDP 24565, LAN IP =", lan)
	# Register host in roster (peer 1) with ready=false
	GameState.roster[1] = {"name": GameState.player_name, "ready": false}

	get_tree().change_scene_to_file(LOBBY_SCENE)

func _on_connect_to_ip() -> void:
	var ip := ip_line.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"

	# Set a client name if you don't already have one
	if GameState.player_name == "" or GameState.player_name == "Fardin Eajdani":
		GameState.player_name = "Guest_%d" % randi()

	GameState.is_host = false
	GameState.reset_lobby()

	# UI feedback
	_set_status("Connecting to %s…" % ip)
	_set_connect_ui_enabled(false)

	# Join server; on success we'll get _on_joined_server()
	Network.join("photos-personality.gl.at.ply.gg",11341)
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
