extends Control

@export var game_scene_path: String = "res://scenes/world.tscn"

@onready var vb := $CenterContainer/VBoxContainer
@onready var btn_play: Button = $CenterContainer/VBoxContainer/TestButton
@onready var btn_multi: Button = $CenterContainer/VBoxContainer/MultiPlayerButton
@onready var quit_btn: Button = vb.get_node_or_null("QuitButton")

@onready var popup: Window = $MultiplayerPopup
@onready var btn_find: Button = $MultiplayerPopup/VBox/FindServerButton
@onready var btn_create: Button = $MultiplayerPopup/VBox/CreateServerButton
@onready var btn_lan_create: Button = $MultiplayerPopup/VBox/CreateLanButton

# (Optional) add a Label under the popup to show status and point this path to it.
@onready var status_label: Label = $MultiplayerPopup/VBox/Label if has_node("MultiplayerPopup/VBox/Label") else null
const C = preload("res://scripts/shared/scene.gd")
const SCRIPT_PATHS = preload("res://scripts/shared/script_path.gd")
var _gfx_ui: Control = null
var server_info := {"name" : "", 'state': "lobby"}

const LOBBY_SCENE := "res://scenes/Lobby.tscn"

func _ready() -> void:
	GameState.player_name = Settings.player_name
	var args := OS.get_cmdline_args()

	# Dedicated headless server mode
	if "--server" in args:
		GameState.is_host = true
		GameState.is_dedicated = true
		Configuration.load_config()
		var session = SessionManager.create_cloud_server_session(SCRIPT_PATHS.SERVER_SESSION)
		session.host(server_info, C.LOBBY)
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

	# NEW: Graphics Settings button (auto-create if not in scene)
	var btn_gfx := vb.get_node_or_null("GraphicsButton") as Button
	if btn_gfx == null:
		btn_gfx = Button.new()
		btn_gfx.name = "GraphicsButton"
		btn_gfx.text = "Graphics Settings"
		btn_gfx.custom_minimum_size = Vector2i(260, 56)

		# Put it under MultiplayerButton, and above QuitButton if it exists
		vb.add_child(btn_gfx)
		if quit_btn:
			vb.move_child(btn_gfx, quit_btn.get_index())

	btn_gfx.pressed.connect(_open_graphics_settings)

	# Popup buttons
	btn_find.pressed.connect(_on_find_server)
	btn_create.pressed.connect(_on_create_cloud_server)
	#btn_connect.pressed.connect(_on_connect_to_ip)
	btn_lan_create.pressed.connect(_on_create_server)

	# Network callbacks while we are on the title screen
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)


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
	# Enter starts game only when popup AND gfx are closed
	if event.is_action_pressed("ui_accept") and !popup.visible and !(_gfx_ui and _gfx_ui.visible):
		_start_game()

	# Esc / Android Back: close gfx, else close popup, else quit
	if event.is_action_pressed("ui_cancel"):
		if _gfx_ui and _gfx_ui.visible:
			_gfx_ui.hide()
			return
		if popup.visible:
			popup.hide()
			return
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
	_set_connect_ui_enabled(true)
	get_tree().change_scene_to_file(C.SERVER_LIST)

func _on_create_server() -> void:
	print('_on_create_server')
	# Identity
	GameState.reset_lobby()
	if GameState.player_name == "" or GameState.player_name == "Player":
		GameState.player_name = "Fardin Eajdani"  # or make dynamic if you add a name field
	GameState.is_host = true

	# Start ENet server and go to lobby
	GameState.player_name = Settings.player_name
	GameState.id = 1
	GameState.roster[1] = {"name": GameState.player_name, "ready": false, "team": GameState.Team.BLUE} # team optional
	
	server_info.name = GameState.player_name
	server_info['current_scene'] = C.LOBBY
	var lan := get_lan_ip()
	print("Hosting on UDP 24565, LAN IP =", lan)
	# Register host in roster (peer 1) with ready=false
	GameState.roster[1] = {"name": GameState.player_name, "ready": false}
	var session_node = SessionManager.create_lan_server_session(SCRIPT_PATHS.SERVER_SESSION)
	session_node.host(server_info, C.LOBBY)

func _on_create_cloud_server() -> void:
	print('request a backend for a server to host')


#func _on_connect_to_ip() -> void:
#
	#GameState.is_host = false
	#GameState.reset_lobby()
	#GameState.player_name = Settings.player_name
	#GameState.id = randi()
	#GameState.roster[GameState.id] = {"name": GameState.player_name, "ready": false}
#
	#_set_status("Connecting to %s…" % ip)
	#_set_connect_ui_enabled(false)
#
	## Use the typed IP here:
	#Network.join(ip)

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
func _open_graphics_settings() -> void:
	if _gfx_ui and _gfx_ui.visible:
		_gfx_ui.hide()
		return

	if _gfx_ui == null:
		_gfx_ui = _create_graphics_settings_ui()
		add_child(_gfx_ui)

	_gfx_ui.visible = true


func _create_graphics_settings_ui() -> Control:
	var root := Control.new()
	root.name = "GraphicsSettings"
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	# background dim
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# centered panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := Panel.new()

	# ✅ Make panel fit the screen (avoid going off-screen on small displays)
	var vp := get_viewport_rect().size
	var w := int(min(520.0, vp.x - 40.0))
	var h := int(min(520.0, vp.y - 40.0))
	panel.custom_minimum_size = Vector2i(max(360, w), max(300, h))
	center.add_child(panel)

	# padding inside panel
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	# main layout: Header + Scroll + Buttons
	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 12)
	pad.add_child(main_v)

	# --------------------
	# Header row (Title + X)
	# --------------------
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_child(header)

	var title := Label.new()
	title.text = "Graphics Settings"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2i(44, 44)
	header.add_child(close_btn)

	# --------------------
	# Scrollable content
	# --------------------
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)

	# --- Fullscreen toggle ---
	var fullscreen := CheckBox.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	v.add_child(fullscreen)

	# --- VSync toggle ---
	var vsync := CheckBox.new()
	vsync.text = "VSync"
	vsync.button_pressed = ProjectSettings.get_setting("display/window/vsync/vsync_mode") != 0
	v.add_child(vsync)

	# --- Quality dropdown ---
	var quality_label := Label.new()
	quality_label.text = "Quality (MSAA)"
	v.add_child(quality_label)

	var quality := OptionButton.new()
	quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality.add_item("Low (No AA)", 0)
	quality.add_item("Medium (2x AA)", 1)
	quality.add_item("High (4x AA)", 2)

	match get_viewport().msaa_3d:
		Viewport.MSAA_DISABLED: quality.select(0)
		Viewport.MSAA_2X:       quality.select(1)
		Viewport.MSAA_4X:       quality.select(2)
		_:                      quality.select(clamp(Settings.quality, 0, 2))
	v.add_child(quality)

	# --- Texture quality dropdown ---
	var tex_label := Label.new()
	tex_label.text = "Texture Quality"
	v.add_child(tex_label)

	var tex_quality := OptionButton.new()
	tex_quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tex_quality.add_item("Low", 0)
	tex_quality.add_item("Medium", 1)
	tex_quality.add_item("High", 2)
	tex_quality.select(clamp(Settings.tex_quality, 0, 2))
	v.add_child(tex_quality)

	# --- 3D Render Scale (Scaling 3D -> Scale) ---
	var scale_label := Label.new()
	scale_label.text = "3D Render Scale"
	v.add_child(scale_label)

	var scale_row := HBoxContainer.new()
	scale_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_theme_constant_override("separation", 12)
	v.add_child(scale_row)

	var scale_slider := HSlider.new()
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.min_value = 0.25
	scale_slider.max_value = 2.0
	scale_slider.step = 0.05
	scale_slider.value = clampf(Settings.scale_3d, float(scale_slider.min_value), float(scale_slider.max_value))
	scale_row.add_child(scale_slider)

	var scale_value := Label.new()
	scale_value.custom_minimum_size = Vector2i(70, 0)
	scale_row.add_child(scale_value)

	var _update_scale_text := func():
		scale_value.text = "%d%%" % int(round(scale_slider.value * 100.0))
	_update_scale_text.call()

	scale_slider.value_changed.connect(func(_v):
		_update_scale_text.call()
	)

	# --------------------
	# Bottom buttons (always visible)
	# --------------------
	var hrow := HBoxContainer.new()
	hrow.alignment = BoxContainer.ALIGNMENT_CENTER
	hrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_theme_constant_override("separation", 16)
	main_v.add_child(hrow)

	var apply := Button.new()
	apply.text = "Apply"
	apply.custom_minimum_size = Vector2i(160, 48)
	hrow.add_child(apply)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2i(160, 48)
	hrow.add_child(back)

	# --- handlers ---
	var _close := func():
		root.hide()

	close_btn.pressed.connect(_close)
	back.pressed.connect(_close)

	apply.pressed.connect(func():
		_apply_graphics_settings(
			fullscreen.button_pressed,
			vsync.button_pressed,
			quality.selected,
			tex_quality.selected,
			float(scale_slider.value)
		)
	)

	return root


func _apply_graphics_settings(fullscreen: bool, vsync: bool, quality: int, tex_quality: int, scale_3d: float) -> void:
	Settings.set_and_save(fullscreen, vsync, quality, tex_quality, scale_3d)
