extends Control

@export var game_scene_path: String = "res://scenes/world.tscn"

@onready var vb := $CenterContainer/VBoxContainer
@onready var btn_play: Button = $CenterContainer/VBoxContainer/TestButton
@onready var btn_multi: Button = $CenterContainer/VBoxContainer/MultiPlayerButton
@onready var quit_btn: Button = vb.get_node_or_null("QuitButton")
const HIT_SLOP := 12.0 # pixels of extra touch forgiveness (try 24–40 on mobile)

@onready var popup: Window = $MultiplayerPopup
@onready var btn_find: Button = $MultiplayerPopup/VBox/FindServerButton
@onready var btn_create: Button = $MultiplayerPopup/VBox/CreateServerButton
@onready var ip_line: LineEdit = $MultiplayerPopup/VBox/HBox/IpLine
@onready var btn_connect: Button = $MultiplayerPopup/VBox/HBox/ConnectButton
# (Optional) add a Label under the popup to show status and point this path to it.
@onready var status_label: Label = $MultiplayerPopup/VBox/Label if has_node("MultiplayerPopup/VBox/Label") else null

var _gfx_ui: Control = null
# --- Layout preview drag state ---
var _layout_svc: SubViewportContainer = null
var _layout_sv: SubViewport = null
var _layout_canvas: Node = null
var _layout_candidates: Array[CanvasItem] = []

var _layout_drag_item: CanvasItem = null
var _layout_drag_offset: Vector2 = Vector2.ZERO
var _layout_defaults: Dictionary = {}  # key -> Vector2
var _layout_working: Dictionary = {}   # key -> Vector2


const LOBBY_SCENE := "res://scenes/Lobby.tscn"
@export var world_scene_for_layout: PackedScene = preload("res://scenes/world.tscn")
@export var canvaslayer_path_in_world: NodePath = ^"CanvasLayer"

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
	btn_create.pressed.connect(_on_create_server)
	btn_connect.pressed.connect(_on_connect_to_ip)
	popup.close_requested.connect(_on_close_clicked)
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

func _on_close_clicked() -> void:	
	popup.visible = false

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
	var w := int(min(vp.x, vp.x - 40.0))
	var h := int(min(vp.y, vp.y - 40.0))
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

	# main layout: Header + Tabs + Buttons
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
	# Tabs (Graphics / Layout)
	# --------------------
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_child(tabs)

	# ===== Graphics Tab (your existing settings) =====
	var tab_graphics := Control.new()
	tab_graphics.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_graphics.name = "Graphics"
	tab_graphics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_graphics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(tab_graphics)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_graphics.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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

	# --- 3D Render Scale ---
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

	# ===== Layout Tab (EMPTY) =====
	var tab_layout := Control.new()
	tab_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_layout.name = "Layout"
	tab_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(tab_layout)

	var base_w := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var base_h := int(ProjectSettings.get_setting("display/window/size/viewport_height"))

	var ar := AspectRatioContainer.new()
	ar.set_anchors_preset(Control.PRESET_FULL_RECT)
	ar.ratio = float(base_w) / float(base_h)
	ar.stretch_mode = AspectRatioContainer.STRETCH_FIT
	tab_layout.add_child(ar)

	# ✅ Frame that will be resized by AspectRatioContainer to the "real preview" size
	var preview_frame := PanelContainer.new()
	preview_frame.name = "PreviewFrame"
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't block input to svc
	ar.add_child(preview_frame)

	# ✅ Red border style (no padding so border matches exact area)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)      # transparent background
	sb.border_color = Color(1, 0, 0, 1)  # red
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	preview_frame.add_theme_stylebox_override("panel", sb)

	# --- Layout preview area (SubViewportContainer) ---
	var svc := SubViewportContainer.new()
	svc.name = "LayoutSVC"
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	svc.gui_input.connect(_on_layout_preview_gui_input)
	_layout_svc = svc

	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_frame.add_child(svc)



	var sv := SubViewport.new()
	# keep UI buttons from actually clicking/working
	sv.gui_disable_input = true

	_layout_sv = sv

	sv.gui_disable_input = true
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = Vector2i(base_w, base_h)
	sv.size_2d_override = Vector2i(base_w, base_h)
	sv.size_2d_override_stretch = true
	svc.stretch = true

	svc.add_child(sv)

	# Keep SubViewport size matched to the blue area
	var _sync_sv_size := func():
		var base_ww := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
		var base_hh := int(ProjectSettings.get_setting("display/window/size/viewport_height"))
		sv.size = Vector2i(max(1, base_ww), max(1, base_hh))

	_sync_sv_size.call()
	_layout_debug_print_sizes("after _sync_sv_size")
	svc.resized.connect(func():
		#_sync_sv_size.call()
		_layout_debug_print_sizes("svc.resized")
)
	# Spawn CanvasLayer branch from World inside the SubViewport (no separate scene needed)
	if world_scene_for_layout:
		var wd := world_scene_for_layout.instantiate()
		var cl := wd.get_node_or_null(canvaslayer_path_in_world)
		if cl:
			wd.remove_child(cl)     # detach from World instance
			sv.add_child(cl) 
			cl.process_mode = Node.PROCESS_MODE_DISABLED
			_layout_canvas = cl
			_layout_rebuild_candidates()

	 # attach to SubViewport
			wd.queue_free()         # free the rest of World
	call_deferred("_layout_finalize_defaults")


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

	var save_layout := Button.new()
	save_layout.text = "Save Layout"
	save_layout.custom_minimum_size = Vector2i(160, 48)
	hrow.add_child(save_layout)

	var reset_layout := Button.new()
	reset_layout.text = "Reset Layout"
	reset_layout.custom_minimum_size = Vector2i(160, 48)
	hrow.add_child(reset_layout)


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

	# Disable Apply when Layout tab is selected
	tabs.tab_changed.connect(func(tab_idx: int):
		var on_graphics := (tab_idx == 0)
		var on_layout := (tab_idx == 1)

		# Graphics tab
		apply.visible = on_graphics
		apply.disabled = not on_graphics
		back.visible = true

		# Layout tab
		save_layout.visible = on_layout
		reset_layout.visible = on_layout
)

	apply.disabled = false
	save_layout.visible = false
	reset_layout.visible = false
	# Save current working layout into Settings.cfg
	save_layout.pressed.connect(func():
		Settings.set_layout_state_and_save(_layout_working)
	)


	# Reset = restore from Settings if available, otherwise fallback to captured defaults
	reset_layout.pressed.connect(func():
		_layout_working = _layout_defaults.duplicate(true) # factory/original
		_layout_apply_positions(_layout_working)
	)



	return root


func _apply_graphics_settings(fullscreen: bool, vsync: bool, quality: int, tex_quality: int, scale_3d: float) -> void:
	Settings.set_and_save(fullscreen, vsync, quality, tex_quality, scale_3d)

func _layout_virtual_size() -> Vector2:
	if _layout_sv == null:
		return Vector2.ONE
	# If you use 2D override (you do), THAT is the coordinate space your UI uses.
	if _layout_sv.size_2d_override != Vector2i.ZERO and _layout_sv.size_2d_override_stretch:
		return Vector2(_layout_sv.size_2d_override)
	return Vector2(_layout_sv.size)

func _layout_svc_to_vp(p: Vector2) -> Vector2:
	if _layout_svc == null or _layout_sv == null:
		return p
	if _layout_svc.size.x <= 0.0 or _layout_svc.size.y <= 0.0:
		return p

	var virt := _layout_virtual_size()
	var sx := virt.x / _layout_svc.size.x
	var sy := virt.y / _layout_svc.size.y
	return Vector2(p.x * sx, p.y * sy)

func _layout_rebuild_candidates() -> void:
	_layout_candidates.clear()
	if _layout_canvas == null:
		return

	# Prefer CanvasLayer/UI branch if it exists
	var ui := _layout_canvas.get_node_or_null(^"UI")
	var root := ui if ui != null else _layout_canvas
	_layout_collect_candidates(root)

func _layout_collect_candidates(n: Node) -> void:
	for c in n.get_children():
		# If we reached JoyStick, add ONLY JoyStick and DO NOT recurse into it.
		if c is CanvasItem and c.name == "JoyStick":
			_layout_candidates.append(c)
			continue

		# Skip joystick internals if they ever appear (extra safety)
		if c.get_parent() and c.get_parent().name == "JoyStick":
			continue

		if c is CanvasItem:
			if c.name != "UI":
				_layout_candidates.append(c)

		_layout_collect_candidates(c)

func _joy_knob_hit(joy: CanvasItem, vp_pos: Vector2) -> bool:
	var knob := joy.get_node_or_null(^"Knob")
	if knob == null:
		return false

	# TouchScreenButton knob (most common)
	if knob is TouchScreenButton:
		var ts := knob as TouchScreenButton
		var tex: Texture2D = ts.texture_normal
		if tex:
			var size := tex.get_size() * ts.global_scale
			var rect := Rect2(ts.global_position - size * 0.5, size)
			return rect.has_point(vp_pos)
		return ts.global_position.distance_to(vp_pos) <= 48.0

	# TextureRect / Button / other Control knob
	if knob is Control:
		return (knob as Control).get_global_rect().has_point(vp_pos)

	# Fallback: distance pick
	var origin := (knob as CanvasItem).get_global_transform_with_canvas().origin
	return origin.distance_to(vp_pos) <= 32.0


func _layout_pick_at(vp_pos: Vector2) -> CanvasItem:
	# Iterate reverse so later items are preferred (roughly topmost)
	for i in range(_layout_candidates.size() - 1, -1, -1):
		var item := _layout_candidates[i]
		if not is_instance_valid(item) or not item.visible:
			continue

		# ✅ ADD THIS BLOCK HERE
		# JoyStick: ONLY allow dragging when the Knob is hit (not the big blank area)
		if item.name == "JoyStick":
			if _joy_knob_hit(item, vp_pos):
				return item   # drag the JoyStick node
			continue
		# Focus container: DO NOT drag the blank parent area.
		# Only its child TouchScreenButtons should be draggable.
		if item.name == "Focus button" and item.get_child_count() > 0:
			continue

		# Controls: use rect hit test
		if item is Control:
			var r := (item as Control).get_global_rect().grow(HIT_SLOP)
			if r.has_point(vp_pos):
				return item
			continue

		# TouchScreenButton / Node2D: approximate using texture size if possible, else radius
		if item is TouchScreenButton:
			var ts := item as TouchScreenButton
			var tex: Texture2D = ts.texture_normal
			if tex:
				var size := tex.get_size() * ts.global_scale
				var rect := Rect2(ts.global_position - size * 0.5, size)
				rect = rect.grow(HIT_SLOP)
				if rect.has_point(vp_pos):
					return item
			else:
				if ts.global_position.distance_to(vp_pos) <= (48.0 + HIT_SLOP):
					return item
			continue

		# Generic Node2D-like items: pick by distance to origin
		var origin := item.get_global_transform_with_canvas().origin
		if origin.distance_to(vp_pos) <= 32.0:
			return item

	return null

func _on_layout_preview_gui_input(event: InputEvent) -> void:
	
	if _layout_svc == null:
		return

	# -------------------------
	# MOUSE (desktop)
	# -------------------------
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var vp_pos := _layout_svc_to_vp(mb.position)

		if mb.pressed:
			var picked := _layout_pick_at(vp_pos)
			if picked != null:
				_layout_drag_item = picked
				_layout_drag_offset = vp_pos - _layout_drag_item.global_position
		else:
			_layout_drag_item = null

		_layout_svc.accept_event()
		return

	if event is InputEventMouseMotion and _layout_drag_item != null:
		var mm := event as InputEventMouseMotion
		var vp_pos2 := _layout_svc_to_vp(mm.position)

		if is_instance_valid(_layout_drag_item):
			_layout_drag_item.global_position = vp_pos2 - _layout_drag_offset
			_layout_working[_layout_key(_layout_drag_item)] = _layout_read_state(_layout_drag_item)

		_layout_svc.accept_event()
		return

	# -------------------------
	# TOUCH (mobile)
	# -------------------------
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var vp_pos_t := _layout_svc_to_vp(st.position)

		if st.pressed:
			var picked_t := _layout_pick_at(vp_pos_t)
			if picked_t != null:
				_layout_drag_item = picked_t
				_layout_drag_offset = vp_pos_t - _layout_drag_item.global_position
		else:
			_layout_drag_item = null

		_layout_svc.accept_event()
		return

	if event is InputEventScreenDrag and _layout_drag_item != null:
		var sd := event as InputEventScreenDrag
		var vp_pos3 := _layout_svc_to_vp(sd.position)

		if is_instance_valid(_layout_drag_item):
			_layout_drag_item.global_position = vp_pos3 - _layout_drag_offset
			_layout_working[_layout_key(_layout_drag_item)] = _layout_read_state(_layout_drag_item)

		_layout_svc.accept_event()
		return

func _layout_key(item: CanvasItem) -> String:
	if _layout_canvas == null:
		return item.name
	# unique + stable within the preview tree
	return String(_layout_canvas.get_path_to(item))

func _layout_read_state(item: CanvasItem) -> Dictionary:
	# Save a stable "layout state"
	if item is Control:
		var c := item as Control
		return {
			"t": "c",
			"al": c.anchor_left, "at": c.anchor_top, "ar": c.anchor_right, "ab": c.anchor_bottom,
			"ol": c.offset_left, "ot": c.offset_top, "or": c.offset_right, "ob": c.offset_bottom
		}
	else:
		# Node2D / TouchScreenButton etc.
		return {"t": "n", "p": item.position}

func _layout_apply_state(item: CanvasItem, state: Dictionary) -> void:
	if not state.has("t"):
		return

	if state["t"] == "c" and item is Control:
		var c := item as Control
		# Restore anchors first, then offsets
		c.anchor_left = state["al"]; c.anchor_top = state["at"]
		c.anchor_right = state["ar"]; c.anchor_bottom = state["ab"]
		c.offset_left = state["ol"]; c.offset_top = state["ot"]
		c.offset_right = state["or"]; c.offset_bottom = state["ob"]
	else:
		# Node2D path
		if state.has("p"):
			item.position = state["p"]

func _layout_finalize_defaults() -> void:
	# Run after 1 frame so the SubViewport + UI have valid layout
	if _layout_canvas == null:
		return

	_layout_rebuild_candidates()

	# "Factory default" from the scene
	_layout_capture_defaults()

	# If user saved layout exists, use it as the current working layout
	if Settings.has_layout_state():
		_layout_working = Settings.layout_state.duplicate(true)
	else:
		_layout_working = _layout_defaults.duplicate(true)

	_layout_apply_positions(_layout_working)
	_layout_debug_print_sizes("after finalize/apply")


func _layout_capture_defaults() -> void:
	_layout_defaults.clear()
	if _layout_candidates.is_empty():
		return
	for item in _layout_candidates:
		if is_instance_valid(item):
			_layout_defaults[_layout_key(item)] = _layout_read_state(item)

func _layout_apply_working_from_defaults() -> void:
	_layout_working = _layout_defaults.duplicate(true)

func _layout_apply_positions(dict: Dictionary) -> void:
	if _layout_candidates.is_empty():
		return
	for item in _layout_candidates:
		if not is_instance_valid(item):
			continue
		var k := _layout_key(item)
		if dict.has(k):
			_layout_apply_state(item, dict[k])

func _layout_debug_print_sizes(tag: String = "") -> void:
	if _layout_svc:
		print("[LayoutPreview]", tag,
			" svc_w=", _layout_svc.size.x, " svc_h=", _layout_svc.size.y)

	if _layout_sv:
		print("[LayoutPreview]", tag,
			" sv_w=", _layout_sv.size.x, " sv_h=", _layout_sv.size.y)

	if _layout_canvas:
		var ui := _layout_canvas.get_node_or_null(^"UI")
		if ui is Control:
			var c := ui as Control
			print("[LayoutPreview]", tag,
				" world_ui_w=", c.size.x, " world_ui_h=", c.size.y,
				" world_ui_global_rect=", c.get_global_rect())
	if _layout_svc and _layout_sv:
		var virt := _layout_virtual_size()
		print("[LayoutPreview]", tag, " virt=", virt, " svc=", _layout_svc.size,
			" scale=", Vector2(virt.x/_layout_svc.size.x, virt.y/_layout_svc.size.y))
