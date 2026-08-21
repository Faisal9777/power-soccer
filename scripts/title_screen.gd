extends Control

@export var game_scene_path: String = "res://scenes/world.tscn"

@onready var vb := $CenterContainer/VBoxContainer
@onready var btn_play: Button = $CenterContainer/VBoxContainer/TestButton
@onready var btn_multi: Button = $CenterContainer/VBoxContainer/MultiPlayerButton
@onready var quit_btn: Button = vb.get_node_or_null("QuitButton")

#@onready var popup: Window = $MultiplayerPopup
#@onready var btn_find: Button = $MultiplayerPopup/VBox/FindServerButton
#@onready var btn_create: Button = $MultiplayerPopup/VBox/CreateServerButton
#@onready var btn_lan_create: Button = $MultiplayerPopup/VBox/CreateLanButton

@onready var popup: CanvasLayer = $MultiplayerPopup
@onready var btn_find: Button = $MultiplayerPopup/PanelContainer/MarginContainer/VBox/FindServerButton
@onready var btn_create: Button = $MultiplayerPopup/PanelContainer/MarginContainer/VBox/CreateServerButton
@onready var btn_lan_create: Button = $MultiplayerPopup/PanelContainer/MarginContainer/VBox/CreateLanButton

# (Optional) add a Label under the popup to show status and point this path to it.
@onready var status_label: Label = $MultiplayerPopup/VBox/Label if has_node("MultiplayerPopup/VBox/Label") else null
const C = preload("res://scripts/shared/scene.gd")
const SCRIPT_PATHS = preload("res://scripts/shared/script_path.gd")
const PROFILE_UI = preload("res://scripts/ui/ProfileUI.gd")
var _gfx_ui: Control = null
var _login_ui: Control = null
var _login_status_label: Label = null
var _login_btn: Button = null
var _profile_ui: Control = null
var _is_public : bool 

const LOBBY_SCENE := "res://scenes/Lobby.tscn"

func _ready() -> void:
	GameState.player_name = Settings.player_name
	var args := OS.get_cmdline_args()
	# Dedicated headless server mode
	if "--server" in args:
		GameState.is_host = true
		GameState.is_dedicated = true
		Config.load_config()
		
		var id = _get_arg_value2("--id", args)
		var port = _get_arg_value2("--port", args)
		var is_public: bool = _get_arg_value2("--public", args) == "true"
		var player_name = _get_arg_value2("--player_name", args)

		print("Dedicated server args:", args)
		print("Dedicated server lobby ID:", id)
		print("Dedicated server port:", port)
		if id == "" or port == "":
			push_error("Dedicated server missing required --id or --port arguments")
			return
		var session = await SessionManager.create_cloud_server_session(SCRIPT_PATHS.SERVER_SESSION, id, port)
		session.host(player_name, is_public, "Lobby")
		return
	
	# -------- normal client flow below --------
	# (show title screen buttons, etc.)
	
	if !AuthManager.is_authenticated():
		_setup_login_flow()
	else:
		_setup_profile_ui()
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if OS.has_feature("mobile") and quit_btn:
		quit_btn.visible = false
	if GameState.lobby_removal_reason != "":
		var reason = GameState.lobby_removal_reason
		GameState.lobby_removal_reason = ""

		_show_popup("You have been %s from the lobby." % reason)
	# Title buttons
	btn_play.pressed.connect(_start_game)
	btn_multi.pressed.connect(_open_multiplayer_screen)

	# Settings button (auto-create if not in scene)
	var btn_gfx := vb.get_node_or_null("GraphicsButton") as Button
	if btn_gfx == null:
		btn_gfx = Button.new()
		btn_gfx.name = "GraphicsButton"
		btn_gfx.text = "Settings"
		btn_gfx.custom_minimum_size = Vector2i(260, 56)

		# Put it under MultiplayerButton, and above QuitButton if it exists
		vb.add_child(btn_gfx)
		if quit_btn:
			vb.move_child(btn_gfx, quit_btn.get_index())

	btn_gfx.pressed.connect(_open_settings)

	# Popup buttons
	btn_find.pressed.connect(_on_find_server)
	btn_create.pressed.connect(_on_create_cloud_server)
	#btn_connect.pressed.connect(_on_connect_to_ip)
	btn_lan_create.pressed.connect(_on_create_server)
	# Network callbacks while we are on the title screen
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)

func _get_arg_value2(flag: String, args: Array) -> String:
	var prefix := flag + "="

	for arg in args:
		if arg == flag:
			var idx := args.find(arg)
			if idx + 1 < args.size():
				return args[idx + 1]

		if arg.begins_with(prefix):
			return arg.substr(prefix.length())

	return ""

func _get_arg_value(flag: String, args: Array) -> String:
	var idx = args.find(flag)
	if idx != -1 and idx + 1 < args.size():
		return args[idx + 1]
	return ""

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
	if AuthManager.is_guest():
		btn_find.disabled = false
		btn_find.text = "Find Server"
		btn_create.disabled = true
		btn_create.text = "Create Cloud Server 🔒"
		
		var vbox = btn_find.get_parent()
		var warning_label = vbox.get_node_or_null("GuestWarningLabel")
		if warning_label == null:
			warning_label = Label.new()
			warning_label.name = "GuestWarningLabel"
			warning_label.text = "Cloud multiplayer requires Google Sign-In."
			warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warning_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
			vbox.add_child(warning_label)
			
			var upgrade_btn = Button.new()
			upgrade_btn.name = "GuestUpgradeBtn"
			upgrade_btn.text = "Sign in with Google"
			upgrade_btn.pressed.connect(func():
				popup.hide()
				_setup_login_flow()
			)
			vbox.add_child(upgrade_btn)
	else:
		btn_find.disabled = false
		btn_find.text = "Find Server"
		btn_create.disabled = false
		btn_create.text = "Create Server"
		var vbox = btn_find.get_parent()
		var warning_label = vbox.get_node_or_null("GuestWarningLabel")
		if warning_label: warning_label.queue_free()
		var upgrade_btn = vbox.get_node_or_null("GuestUpgradeBtn")
		if upgrade_btn: upgrade_btn.queue_free()

	#popup.popup_centered(Vector2i(460, 300))
	popup.show()
	await get_tree().process_frame
	btn_find.grab_focus()

# ---------------- Multiplayer ----------------
func _on_find_server() -> void:
	_set_connect_ui_enabled(true)
	get_tree().change_scene_to_file(C.SERVER_LIST)

func _open_create_server_popup(is_lan: bool) -> void:
	popup.hide()
	var root := Control.new()
	root.name = "CreateServerPopup"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# dark background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# center panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2i(420, 320)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# ---------------- Server Name ----------------
	var name_label := Label.new()
	name_label.text = "Server Name"
	vbox.add_child(name_label)

	var name_input := LineEdit.new()
	name_input.max_length = 100
	name_input.placeholder_text = "My Server"
	vbox.add_child(name_input)

	# ---------------- Public / Private ----------------
	var public_check := CheckBox.new()
	public_check.text = "Public Server"
	public_check.button_pressed = true
	vbox.add_child(public_check)

	var private_check := CheckBox.new()
	private_check.text = "Private Server"
	vbox.add_child(private_check)


	# mutual exclusivity
	public_check.toggled.connect(func(v):
		if v:
			private_check.button_pressed = false

		else:
			if not private_check.button_pressed:
				public_check.button_pressed = true
	)

	private_check.toggled.connect(func(v):
		if v:
			public_check.button_pressed = false

		else:

			if not public_check.button_pressed:
				public_check.button_pressed = true
	)

	# ---------------- Buttons ----------------
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var create_btn := Button.new()
	create_btn.text = "Create"
	btn_row.add_child(create_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	btn_row.add_child(cancel_btn)

	# ---------------- Actions ----------------
	cancel_btn.pressed.connect(func():
		root.queue_free()
	)

	create_btn.pressed.connect(func():
		var server_name = name_input.text.strip_edges()
		var is_public = public_check.button_pressed


		if server_name == "":
			server_name = "Server"

		if is_lan:
			_on_create_server_with_data(server_name, is_public)
		else:
			_on_create_cloud_server_with_data(server_name, is_public)

		root.queue_free()
	)


func _on_create_server_with_data(name: String, is_public: bool) -> void:
	print("LAN SERVER:", name, is_public)
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
	
	var lan := get_lan_ip()
	print("Hosting on UDP 24565, LAN IP =", lan)
	# Register host in roster (peer 1) with ready=false
	GameState.roster[1] = {"name": GameState.player_name, "ready": false}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var session_node = await SessionManager.create_lan_server_session(SCRIPT_PATHS.SERVER_SESSION, id)
	session_node.host(name, is_public, "Lobby")

func _on_create_cloud_server_with_data(name: String, is_public: bool) -> void:
	print("CLOUD SERVER:", name, is_public)
	_is_public = is_public
	var session_node = await SessionManager.create_client_session(SCRIPT_PATHS.CLIENT_SESSION)
	session_node.host_cloud_server(name, is_public)



func _on_create_server() -> void:
	_open_create_server_popup(true)
func _on_create_cloud_server() -> void:
	_open_create_server_popup(false)
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
func _open_settings() -> void:
	if _gfx_ui and _gfx_ui.visible:
		_gfx_ui.hide()
		return

	if _gfx_ui == null:
		_gfx_ui = _create_settings_ui()
		add_child(_gfx_ui)

	_gfx_ui.visible = true


func _create_settings_ui() -> Control:
	var root := Control.new()
	root.name = "SettingsWindow"
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := Panel.new()
	var vp := get_viewport_rect().size
	var w := int(min(640.0, vp.x - 40.0))
	var h := int(min(620.0, vp.y - 40.0))
	panel.custom_minimum_size = Vector2i(max(420, w), max(360, h))
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 12)
	pad.add_child(main_v)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_child(header)

	var title := Label.new()
	title.text = "Settings"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2i(44, 44)
	header.add_child(close_btn)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_child(tabs)

	var graphics_page := Control.new()
	graphics_page.name = "Graphics"
	graphics_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(graphics_page)

	var graphics_margin := MarginContainer.new()
	graphics_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	graphics_margin.add_theme_constant_override("margin_left", 8)
	graphics_margin.add_theme_constant_override("margin_right", 8)
	graphics_margin.add_theme_constant_override("margin_top", 8)
	graphics_margin.add_theme_constant_override("margin_bottom", 8)
	graphics_page.add_child(graphics_margin)

	var graphics_v := VBoxContainer.new()
	graphics_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graphics_v.add_theme_constant_override("separation", 10)
	graphics_margin.add_child(graphics_v)

	# ============================================================
	# Scrollable graphics options
	# ============================================================

	var graphics_scroll := ScrollContainer.new()
	graphics_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graphics_scroll.size_flags_stretch_ratio = 1.0
	graphics_v.add_child(graphics_scroll)

	var graphics_content := VBoxContainer.new()
	graphics_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_content.add_theme_constant_override("separation", 14)
	graphics_scroll.add_child(graphics_content)

	# ---------------- Fullscreen ----------------

	var fullscreen := CheckBox.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	graphics_content.add_child(fullscreen)

	# ---------------- VSync ----------------

	var vsync := CheckBox.new()
	vsync.text = "VSync"
	vsync.button_pressed = (
		ProjectSettings.get_setting(
			"display/window/vsync/vsync_mode"
		) != 0
	)
	graphics_content.add_child(vsync)

	# ---------------- MSAA Quality ----------------

	var quality_label := Label.new()
	quality_label.text = "Quality (MSAA)"
	graphics_content.add_child(quality_label)

	var quality := OptionButton.new()
	quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	quality.add_item("Low (No AA)", 0)
	quality.add_item("Medium (2x AA)", 1)
	quality.add_item("High (4x AA)", 2)

	match get_viewport().msaa_3d:
		Viewport.MSAA_DISABLED:
			quality.select(0)
		Viewport.MSAA_2X:
			quality.select(1)
		Viewport.MSAA_4X:
			quality.select(2)
		_:
			quality.select(clamp(Settings.quality, 0, 2))

	graphics_content.add_child(quality)

	# ---------------- Texture Quality ----------------

	var tex_label := Label.new()
	tex_label.text = "Texture Quality"
	graphics_content.add_child(tex_label)

	var tex_quality := OptionButton.new()
	tex_quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	tex_quality.add_item("Low", 0)
	tex_quality.add_item("Medium", 1)
	tex_quality.add_item("High", 2)

	tex_quality.select(clamp(Settings.tex_quality, 0, 2))

	graphics_content.add_child(tex_quality)

	# ---------------- 3D Render Scale ----------------

	var scale_label := Label.new()
	scale_label.text = "3D Render Scale"
	graphics_content.add_child(scale_label)

	var scale_row := HBoxContainer.new()
	scale_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_theme_constant_override("separation", 12)
	graphics_content.add_child(scale_row)

	var scale_slider := HSlider.new()
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.min_value = 0.25
	scale_slider.max_value = 2.0
	scale_slider.step = 0.05
	scale_slider.value = clampf(
		Settings.scale_3d,
		float(scale_slider.min_value),
		float(scale_slider.max_value)
	)
	scale_row.add_child(scale_slider)

	var scale_value := Label.new()
	scale_value.custom_minimum_size = Vector2i(70, 0)
	scale_row.add_child(scale_value)

	var update_scale_text := func():
		scale_value.text = "%d%%" % int(round(scale_slider.value * 100.0))

	update_scale_text.call()

	scale_slider.value_changed.connect(func(_v):
		update_scale_text.call()
	)

	# ============================================================
	# Bottom buttons
	# IMPORTANT: These are OUTSIDE the ScrollContainer
	# ============================================================

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.size_flags_vertical = Control.SIZE_SHRINK_END
	button_row.add_theme_constant_override("separation", 16)

	graphics_v.add_child(button_row)

	var apply := Button.new()
	apply.name = "ApplyButton"
	apply.text = "Apply"
	apply.custom_minimum_size = Vector2i(160, 48)
	apply.focus_mode = Control.FOCUS_ALL
	button_row.add_child(apply)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "Back"
	back.custom_minimum_size = Vector2i(160, 48)
	back.focus_mode = Control.FOCUS_ALL
	button_row.add_child(back)

	# ============================================================
	# Close
	# ============================================================

	var _close := func():
		root.hide()

	close_btn.pressed.connect(_close)
	back.pressed.connect(_close)

	# ============================================================
	# APPLY GRAPHICS SETTINGS
	# ============================================================

	apply.pressed.connect(func():
		print("SETTINGS: Apply pressed")

		_apply_graphics_settings(
			fullscreen.button_pressed,
			vsync.button_pressed,
			quality.selected,
			tex_quality.selected,
			float(scale_slider.value)
		)
	)
	if not OS.has_feature("mobile"):
		var key_page := Control.new()
		key_page.name = "Key Bindings"
		key_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tabs.add_child(key_page)

		var key_margin := MarginContainer.new()
		key_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		key_margin.add_theme_constant_override("margin_left", 8)
		key_margin.add_theme_constant_override("margin_right", 8)
		key_margin.add_theme_constant_override("margin_top", 8)
		key_margin.add_theme_constant_override("margin_bottom", 8)
		key_page.add_child(key_margin)

		var key_bindings_ui := preload("res://scripts/KeyBindingsUI.gd").new()
		key_bindings_ui.name = "KeyBindingsUI"
		key_bindings_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		key_margin.add_child(key_bindings_ui)

	if OS.has_feature("mobile"):
		var layout_page := preload(
			"res://scripts/LayoutEditor.gd"
		).new()

		layout_page.name = "Layout"

		layout_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout_page.size_flags_vertical = Control.SIZE_EXPAND_FILL

		tabs.add_child(layout_page)

	var tab_names := ["Graphics"]

	if OS.has_feature("mobile"):
		tab_names.append("Layout")
	else:
		tab_names.append("Key Bindings")

	for index in range(tab_names.size()):
		tabs.set_tab_title(index, tab_names[index])

	return root


func _apply_graphics_settings(fullscreen: bool, vsync: bool, quality: int, tex_quality: int, scale_3d: float) -> void:
	Settings.set_and_save(fullscreen, vsync, quality, tex_quality, scale_3d)


func _on_center_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		popup.hide()

func _setup_login_flow() -> void:
	if _login_ui != null and is_instance_valid(_login_ui):
		_login_ui.queue_free()
		_login_ui = null
		
	# Hide main UI
	$CenterContainer.visible = false
	
	# Create login overlay
	_login_ui = Control.new()
	_login_ui.name = "LoginOverlay"
	_login_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_login_ui)
	
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_login_ui.add_child(bg)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_login_ui.add_child(center)
	
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 250)
	center.add_child(card)
	
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	var title := Label.new()
	title.text = "Soccer Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "Please sign in with Google to continue."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)
	
	_login_btn = Button.new()
	_login_btn.text = "Sign in with Google"
	_login_btn.custom_minimum_size = Vector2(250, 50)
	vbox.add_child(_login_btn)
	
	var separator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(separator)
	
	var guest_btn = Button.new()
	guest_btn.text = "Play as Guest"
	guest_btn.custom_minimum_size = Vector2(250, 50)
	vbox.add_child(guest_btn)
	
	var guest_desc = Label.new()
	guest_desc.text = "Guests can only join or host LAN matches. Cloud multiplayer requires a Google account."
	guest_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guest_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guest_desc.add_theme_font_size_override("font_size", 14)
	vbox.add_child(guest_desc)
	
	_login_btn.pressed.connect(func():
		_login_btn.disabled = true
		guest_btn.disabled = true
		AuthManager.login()
	)
	guest_btn.pressed.connect(func():
		_login_btn.disabled = true
		guest_btn.disabled = true
		AuthManager.login_as_guest()
	)
	
	_login_status_label = Label.new()
	_login_status_label.text = ""
	_login_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_login_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_login_status_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_login_status_label)
	
	# Connect to AuthManager signals
	AuthManager.auth_status_changed.connect(_on_auth_status_changed)
	AuthManager.auth_completed.connect(_on_auth_completed)
	
	# Auto-login check
	if AuthManager.load_session_token():
		_login_btn.disabled = true
		AuthManager.verify_session_token(AuthManager.session_token)

func _on_auth_status_changed(msg: String) -> void:
	if _login_status_label:
		_login_status_label.text = msg

func _on_auth_completed(success: bool, player_info: Dictionary) -> void:
	if success:
		AuthManager.authenticated = true
		# Update Settings & GameState player name
		Settings.set_player_name_and_save(player_info["player_name"])
		GameState.player_name = player_info["player_name"]
		GameState.user_id = int(player_info.get("player_id", 0))
		# Disconnect signals to prevent double-connects on scene reload
		if AuthManager.auth_status_changed.is_connected(_on_auth_status_changed):
			AuthManager.auth_status_changed.disconnect(_on_auth_status_changed)
		if AuthManager.auth_completed.is_connected(_on_auth_completed):
			AuthManager.auth_completed.disconnect(_on_auth_completed)
			
		# Clean up login UI and show main menu
		if _login_ui:
			_login_ui.queue_free()
		$CenterContainer.visible = true
		_setup_profile_ui()
	else:
		if _login_btn:
			_login_btn.disabled = false
		# The specific error was already printed to the label via auth_status_changed
		# just leave it there so the player knows what actually went wrong!

func _show_popup(message: String) -> void:
	var popup := Window.new()
	popup.title = "Disconnected"
	popup.size = Vector2i(420, 220)
	popup.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	popup.unresizable = true

	add_child(popup)

	# Main container
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# Message
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	vbox.add_child(label)

	# OK button
	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(0, 48)
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.add_theme_font_size_override("font_size", 20)

	vbox.add_child(ok_btn)

	ok_btn.pressed.connect(func() -> void:
		popup.queue_free()
	)

	popup.popup_centered()

func _setup_profile_ui() -> void:
	if _profile_ui != null and is_instance_valid(_profile_ui):
		return

	_profile_ui = PROFILE_UI.new()
	_profile_ui.name = "ProfileUI"

	add_child(_profile_ui)

	_profile_ui.setup()
