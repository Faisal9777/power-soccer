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

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if OS.has_feature("mobile") and quit_btn:
		quit_btn.visible = false

	# Title buttons
	btn_play.pressed.connect(_start_game)
	btn_multi.pressed.connect(_open_multiplayer_screen)

	# Popup buttons (stubbed for now)
	btn_find.pressed.connect(_on_find_server)
	btn_create.pressed.connect(_on_create_server)
	btn_connect.pressed.connect(_on_connect_to_ip)

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

# ----- Multiplayer stubs (do nothing for now) -----
func _on_find_server() -> void:
	print("TODO: find LAN servers")

func _on_create_server() -> void:
	# For now: just mark host + name and open Lobby
	GameState.player_name = "Fardin Eajdani"
	GameState.is_host = true
	GameState.players = [GameState.player_name]
	get_tree().change_scene_to_file("res://Lobby.tscn")


func _on_connect_to_ip() -> void:
	var ip := ip_line.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	print("TODO: connect to IP: ", ip)

# ----- Quit / fade helpers -----
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
