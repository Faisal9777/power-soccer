extends Node


# --- Assign in the inspector or hardcode a PackedScene for clients that join ---
@export var pause_btn: Button
@export var score_btn: Button
@export var win_scene_path: String = "res://scenes/WinScene.tscn"
@export var defeat_scene_path: String = "res://scenes/DefeatScene.tscn"
@export var scoreboard_scene_path: String = "res://scenes/ScoreboardScene.tscn"
@export var player_scene: PackedScene
@export var bot_player_scene: PackedScene

var _def_tex_ability: Texture2D
var _def_tex_a1: Texture2D
var _def_tex_a2: Texture2D
var _def_tex_a3: Texture2D

func _set_btn_tex(btn: Node, tex: Texture2D, fallback: Texture2D) -> void:
	var use_tex := tex if tex != null else fallback
	if use_tex == null or btn == null:
		return

	if btn is TouchScreenButton:
		(btn as TouchScreenButton).texture_normal = use_tex
	elif btn is TextureButton:
		(btn as TextureButton).texture_normal = use_tex
	elif btn is Button:
		(btn as Button).icon = use_tex


var _grapple_crosshair_layer: CanvasLayer
var _grapple_crosshair_root: Control
var _grapple_crosshair: GrappleCrosshair




@export var ball_packed: PackedScene
@onready var spawn_points := $SpawnPoints   # optional, if you have markers named SpawnPoint0/1/2...
@onready var players_root := $Players
@onready var ball_root: Node = $BallHolder
@onready var is_mobile: bool = OS.has_feature("mobile") 
@export var joystick_path: NodePath
@onready var joystick: Node = get_node(joystick_path) 
@onready var ball_spawn: Node3D = get_node(BALL_SPAWN_PATH) as Node3D
@onready var out_bounds: Area3D = $BallOutOfBounds

# Keep a typed map of peer-id -> Player node
var _players: Dictionary[int, CharacterBody3D] = {}    # { int: Node }

# --- Pause dialog (created at runtime) ---
var _pause_ui: Control
var _gfx_ui: Control
var _btn_resume: Button

# --- Scoreboard popup (shown while holding the "scoreboard" action) ---
var _scoreboard_popup: Control
var _scoreboard_instance: Control
const SCOREBOARD_PAUSES := false  # set true if you want gameplay paused while holding

var _is_server_ready := false
var _is_ready := false
var _peers_ready := 0

# Input pump
const NET_INPUT_HZ: float = 30.0
const TEAM_BLUE_PATH:  NodePath = ^"Teams/TeamBlue/Spawns"
const TEAM_RED_PATH:   NodePath = ^"Teams/TeamRed/Spawns"
const BALL_SPAWN_PATH: NodePath = ^"BallSpawn"
const BALL_PATH: NodePath = ^"Scene/Ball"
# Preload the scripts
var WorldServerScript := load("res://scripts/multiplayer/world_server.gd")
var WorldClientScript := load("res://scripts/multiplayer/world_client.gd")
var GameServer := load("res://scripts/multiplayer/game_server.gd")
var GameClient := load("res://scripts/multiplayer/game_client.gd")
var Ingame := load("res://scripts/multiplayer/ingame_states.gd")
# A reference to whichever net helper we spawned
var net: Node = null
@onready var team_blue: Node3D = get_node(TEAM_BLUE_PATH)
@onready var team_red:  Node3D = get_node(TEAM_RED_PATH)
@onready var local_view_proxy := $LocalViewProxy
var _my_player: Node = null
var _input_accum: float = 0.0
var ball_scene : Node3D = null
var  tackle_edge_latched := false
var  stop_ball_edge_latched := false
var  jump_edge_latched := false
var  shoot_edge_latched := false
var latch_edge_latched := false 
var ability_toggle_edge_latched := false
var ability_a1_edge_latched := false
var ability_a2_edge_latched := false
var ability_a3_edge_latched := false

@onready var tackle_btn: TouchScreenButton = $CanvasLayer/UI/ActionPad/Tackle
var _tackle_cd_label: Label
var _tackle_cd_local: float = 0.0
var _tackle_cd_last_from_player: float = -999.0

var assist_pass_edge_latched := false

@onready var pass_btn: TouchScreenButton = $CanvasLayer/UI/ActionPad/Pass
var _pass_cd_label: Label
var _pass_cd_local: float = 0.0
var _pass_cd_last_from_player: float = -999.0

func _ready() -> void:
	var replication_manager = ReplicationManager.new()
	replication_manager.name = "ReplicationManager"
	add_child(replication_manager)
	LoadingUI.show_loading()
	if multiplayer.is_server():
		out_bounds.body_entered.connect(_on_ball_out_of_bounds)
	if OS.has_feature("mobile"):
		pause_btn.show()
		score_btn.show()
	else:
		pause_btn.hide()
		score_btn.hide()
	if not pause_btn.pressed.is_connected(_on_mobile_pause_pressed):
		print("I RAN")
		pause_btn.pressed.connect(_on_mobile_pause_pressed)

	if not score_btn.button_down.is_connected(_on_mobile_score_down):
		score_btn.button_down.connect(_on_mobile_score_down)
	if not score_btn.button_up.is_connected(_on_mobile_score_up):
		score_btn.button_up.connect(_on_mobile_score_up)
	
	_setup_team_position()
	# If you didn't set the spawner in the editor, do it here:
	var spawner : Node
	if players_root:
		spawner = players_root.get_node_or_null("MultiplayerSpawner")
	if spawner == null:
		spawner = MultiplayerSpawner.new()
		spawner.name = "MultiplayerSpawner"
		players_root.add_child(spawner)
		spawner.spawn_path = players_root.get_path()
		

	# Register ALL player-type scenes that might be spawned
	if player_scene:
		spawner.add_spawnable_scene(player_scene.resource_path)

	if bot_player_scene:
		spawner.add_spawnable_scene(bot_player_scene.resource_path)

	_create_ball_spawner()
	_setup_pause_dialog()
	_tackle_cd_label = _ensure_cd_label(tackle_btn)
	_pass_cd_label = _ensure_cd_label(pass_btn)
	_ensure_grapple_crosshair()
	_cache_default_ability_textures()
	#_initialize_game_setup()
	var game : Node = Ingame.new()
	game.name = "ingame_state"
	
	add_child(game)
	_setup_scoreboard_popup(game)
	var ingame := get_node_or_null("ingame_state")
	var blue_spawns := get_node(TEAM_BLUE_PATH)  as Node3D
	var red_spawns  := get_node(TEAM_RED_PATH)   as Node3D
	var ball_spawn  := get_node(BALL_SPAWN_PATH) as Node3D

	if not multiplayer.is_server():
		net = WorldClientScript.new()
		_initialize_multiplayer("NetClient", net)
		net.init(local_view_proxy, _scoreboard_instance, ingame, blue_spawns, red_spawns, ball_spawn, get_node(joystick_path))
	else:
		_create_ball_server()
		var ids: Array[int] = []
		for k in GameState.roster.keys():
			ids.append(int(k))   # ensure int
			_server_begin_match(ids)
		net = WorldServerScript.new()
		_initialize_multiplayer("NetServer", net)
		net.start_init(_players, _scoreboard_instance, ingame, replication_manager, blue_spawns, red_spawns, ball_spawn,
		ball_scene, GameState.match_len_sec, GameState.goal_limit, GameState.roster, get_node(joystick_path))
		


	# 1) Connect to the Network autoload signals (do it here so it works even if not wired in editor)

	#Network.server_started.connect(_on_server_started)
	#Network.joined_server.connect(_on_joined_server)
	#Network.peer_joined.connect(_on_peer_joined)
	#Network.peer_left.connect(_on_peer_left)
	
	# 2) If a Player is already in the scene (your case), register it for the host
	var pre := get_node_or_null("Player")
	if pre != null and not GameState.is_dedicated_server():
		# Server must own/simulate every player in server-auth
		pre.set_multiplayer_authority(1)
		_players[1] = pre
		print("Registered preplaced Player as host player; authority=", pre.get_multiplayer_authority())

func start_game() -> void:

	LoadingUI.hide_loading()


# Returns [overlay: Control, panel: Panel]
# Returns [overlay: Control, panel: Panel]
# Returns [overlay: Control, panel: Panel]
func _on_mobile_pause_pressed() -> void:
	if _pause_ui and _pause_ui.visible: _on_pause_resume()
	else: _toggle_pause_menu()

func _on_mobile_score_down() -> void: _open_scoreboard()
func _on_mobile_score_up()   -> void: _close_scoreboard()

func _make_centered_overlay(name: String, panel_min_size: Vector2i) -> Array:
	var overlay := Control.new()
	overlay.name = name
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ensure no stale offsets
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_left = 0
	dim.offset_top = 0
	dim.offset_right = 0
	dim.offset_bottom = 0
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	# make sure it truly fills the viewport
	center.offset_left = 0
	center.offset_top = 0
	center.offset_right = 0
	center.offset_bottom = 0
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(center)

	var panel := Panel.new()
	panel.custom_minimum_size = panel_min_size
	# **key:** don’t let children force it to expand; keep it centered
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)

	return [overlay, panel]

func _setup_scoreboard_popup(game_data_holder : Node) -> void:
	var parts := _make_centered_overlay("ScoreboardOverlay", Vector2i(560, 360))
	_scoreboard_popup = parts[0]
	var panel: Panel = parts[1]
	add_child(_scoreboard_popup)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(pad)

# Load the scoreboard scene
	var ps := load(scoreboard_scene_path)
	if ps is PackedScene:
		var inst: Node = ps.instantiate()
		# If root is CanvasLayer, unwrap the first Control child
		var root_ctrl: Control = null
		if inst is CanvasLayer:
			var layer := inst as CanvasLayer
			if layer.get_child_count() > 0 and layer.get_child(0) is Control:
				root_ctrl = layer.get_child(0) as Control
				layer.remove_child(root_ctrl)
				layer.queue_free()
			else:
				push_error("ScoreboardScene CanvasLayer must contain a Control as first child"); return
		elif inst is Control:
			root_ctrl = inst as Control
		else:
			push_error("ScoreboardScene root must be Control or CanvasLayer"); return

		# Normalize
		root_ctrl.top_level = false
		# IMPORTANT: do NOT full-rect this; let CenterContainer center it
		root_ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root_ctrl.offset_left = 0
		root_ctrl.offset_top = 0
		root_ctrl.offset_right = 0
		root_ctrl.offset_bottom = 0
		root_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		root_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# Wrap in a CenterContainer so it's truly centered in the panel
		var inner_center := CenterContainer.new()
		inner_center.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner_center.offset_left = 0
		inner_center.offset_top = 0
		inner_center.offset_right = 0
		inner_center.offset_bottom = 0
		inner_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pad.add_child(inner_center)

		# If the scoreboard has no inherent min size, give one so it has something to center
		if root_ctrl.get_minimum_size() == Vector2.ZERO:
			root_ctrl.custom_minimum_size = Vector2i(560, 360)  # tweak as you like

		inner_center.add_child(root_ctrl)
		_scoreboard_instance = root_ctrl
		_scoreboard_instance.set_game_data_holder(game_data_holder, _scoreboard_popup)
	else:
		push_error("Could not load scoreboard scene at: %s" % scoreboard_scene_path)


func _open_scoreboard() -> void:
	if SCOREBOARD_PAUSES:
		get_tree().paused = true
		# keep mouse as-is (you’re only holding a key)
	_scoreboard_instance.show_score(true)

func _close_scoreboard() -> void:
	_scoreboard_popup.visible = false
	if SCOREBOARD_PAUSES and get_tree().paused:
		_scoreboard_instance.show_score(false)

func _setup_pause_dialog() -> void:
	# Root overlay that still works while paused
	_pause_ui = Control.new()
	_pause_ui.name = "PauseOverlay"
	_pause_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_pause_ui.visible = false
	_pause_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pause_ui)  # or add to your CanvasLayer

	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_ui.add_child(dim)

	# Center the panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pause_ui.add_child(center)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2i(420, 260)
	center.add_child(panel)

	# Vertical stack
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(v)

	# Title
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)

	# --- Buttons (centered, comfy touch sizes) ---
	_btn_resume = Button.new()
	_btn_resume.text = "Resume"
	_btn_resume.custom_minimum_size = Vector2i(260, 56)
	_btn_resume.pressed.connect(_on_pause_resume)
	v.add_child(_btn_resume)

	var btn_gfx := Button.new()
	btn_gfx.text = "Graphics Settings"
	btn_gfx.custom_minimum_size = Vector2i(260, 56)
	btn_gfx.pressed.connect(_open_graphics_settings)
	v.add_child(btn_gfx)

	var btn_exit := Button.new()
	btn_exit.text = "Exit Game"
	btn_exit.custom_minimum_size = Vector2i(260, 56)
	btn_exit.pressed.connect(_on_pause_exit)
	v.add_child(btn_exit)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# ✅ If graphics menu is open, close it first (don’t unpause)
		if _gfx_ui and _gfx_ui.visible:
			_gfx_ui.hide()
			return
		_toggle_pause_menu()

	# SHOW while holding
	if event.is_action_pressed("scoreboard"):
		_open_scoreboard()

	# HIDE on release
	if event.is_action_released("scoreboard"):
		_close_scoreboard()

func _toggle_pause_menu() -> void:
	if _pause_ui and _pause_ui.visible:
		_on_pause_resume()
		return
	get_tree().paused = true
	if !OS.has_feature("mobile"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pause_ui.visible = true
	if _btn_resume:
		_btn_resume.grab_focus()  # keyboard/controller friendly

func _on_pause_resume() -> void:
	if _pause_ui:
		_pause_ui.visible = false
	get_tree().paused = false
	if !OS.has_feature("mobile"):  # don’t hide mouse on touch devices
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
func _on_pause_exit() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if !OS.has_feature("mobile"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Quit or go to title:
	# get_tree().quit()
	SessionManager.session_node.disconnect_connection()

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
	root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
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

	# ✅ Fit panel to screen (so it never goes off-screen)
	var vp := get_viewport().get_visible_rect().size
	var w := int(min(520.0, vp.x - 40.0))
	var h := int(min(520.0, vp.y - 40.0))
	panel.custom_minimum_size = Vector2i(max(360, w), max(300, h))
	center.add_child(panel)

	# padding
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	# main layout: header + scroll + bottom buttons
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

	# handlers
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

func _initialize_multiplayer(name: String, net : Node) -> void:
	net.name = name
	add_child(net)

func _create_ball_server() -> void:
	# Instance a **fresh** rigid body
	var ball := ball_packed.instantiate() as RigidBody3D
	ball.name = "Ball"  # stable name helps other scripts find it
	ball.add_to_group("ball")
	# Make it inert before adding/placing (prevents the "rocket" issue)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO

	# Add under the spawner's path so it replicates to clients
	ball_root.add_child(ball)
	ball_scene = ball

func _create_ball_spawner() -> void:
	# Set up once
	var ball_spawner := ball_root.get_node_or_null("MultiplayerSpawner") as MultiplayerSpawner
	if ball_spawner == null:
		ball_spawner = MultiplayerSpawner.new()
		ball_spawner.name = "MultiplayerSpawner"
		ball_root.add_child(ball_spawner)
		ball_spawner.spawn_path = ball_root.get_path()

	# register the ball scene so the spawner knows how to recreate it on clients
	if ball_packed:
		ball_spawner.add_spawnable_scene(ball_packed.resource_path)


func _setup_team_position(plane_z: float = 0.0) -> void:
# If Blue/Red share parent, local position is fine:
	var p := team_blue.position

	# Mirror across Z = plane_z (default midfield = 0)
	team_red.position = Vector3(p.x, p.y, 2.0 * plane_z - p.z)

	# Face opposite direction (yaw 180°)
	team_red.rotation_degrees.y = fposmod(team_blue.rotation_degrees.y + 180.0, 360.0)

func _server_begin_match(peer_ids: Array[int]) -> void:
	for id in peer_ids:
		_on_peer_joined(id)  # your existing spawn path

func _physics_process(delta: float) -> void:
	#if  Input.is_action_just_pressed("tackle"): print("tackle input was detected in physics process")
	#var inputs := _gather_input()
	#_send_local_input(inputs)
	#_perf_tick(delta)
	_update_inputs() 
	_input_accum += delta
	var step: float = 1.0 / NET_INPUT_HZ
	while _input_accum >= step:
		_input_accum -= step
		_send_local_input()
		_reset_inputs()
func _shoot_action() -> String:
	return "shoot_touch" if is_mobile else "shoot"
func _update_inputs() -> void:
	var gm := false
	if Input.is_action_just_pressed("jump") and not jump_edge_latched:
		jump_edge_latched = true
	if Input.is_action_just_pressed("tackle") and not tackle_edge_latched:
		if _tackle_cd_local <= 0.0:
			tackle_edge_latched = true
	if Input.is_action_just_pressed("stop_ball") and not stop_ball_edge_latched:
		stop_ball_edge_latched = true		
	# Only allow shoot edge when NOT grappling
	if !gm and Input.is_action_just_released(_shoot_action()) and not shoot_edge_latched:
		shoot_edge_latched = true
	# ⬇️ NEW: toggle input (press once = "edge" event)
	if Input.is_action_just_pressed("ball_latch") and not latch_edge_latched:
		 
		latch_edge_latched = true
	if Input.is_action_just_pressed("assist_pass") and not assist_pass_edge_latched:
		
		if _pass_cd_local <= 0.0:
			print("CAPPPPPPPPPPP!!!!!!+")
			assist_pass_edge_latched = true

		# --- Ability inputs (edge-latched like everything else) ---
	if Input.is_action_just_pressed("ability_toggle") and not ability_toggle_edge_latched:
		ability_toggle_edge_latched = true

	if Input.is_action_just_pressed("ability_action1") and not ability_a1_edge_latched:
		ability_a1_edge_latched = true	
		print("WORLD: ability_action1 pressed")

	if Input.is_action_just_pressed("ability_action3") and not ability_a3_edge_latched:
		ability_a3_edge_latched = true

func _reset_inputs() -> void:
	jump_edge_latched = false
	tackle_edge_latched = false
	stop_ball_edge_latched = false
	shoot_edge_latched = false
	latch_edge_latched = false     # ⬅️ NEW
	assist_pass_edge_latched = false
	ability_toggle_edge_latched = false
	ability_a1_edge_latched = false
	ability_a3_edge_latched = false


func _process(delta: float) -> void:
		#_all_players_positions()
	if Input.is_action_just_pressed("host_key"):
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
			print("Already hosting (ENet)")        # start hosting
	#var fps := Engine.get_frames_per_second()
	##if fmod(fps, 10.0) < 0.001:
		##print(int(round(fps)))
	#print("MSAA Level:", get_viewport().msaa_3d)

	if Input.is_action_just_pressed("join_key"):
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			print("Already connected (ENet)")
	
	_update_tackle_cooldown_ui(delta)
	_update_pass_cooldown_ui(delta)


	
func _is_really_hosting() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server()

func _is_really_client() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and not multiplayer.is_server()
	
func _role_tag() -> String:
	if multiplayer.multiplayer_peer == null:
		return "offline"
	return "host" if multiplayer.is_server() else "client_%d" % multiplayer.get_unique_id()

#func _log_pid() -> void:
	#print("os id is: ", OS.get_process_id())
func _log_pid(msg : String) -> void:
	print(msg, OS.get_process_id())
	
func _whoami() -> String:
	if multiplayer.multiplayer_peer == null:
		return "offline"
	return "HOST" if multiplayer.is_server() else "CLIENT_%d" % multiplayer.get_unique_id()
# -------------------------
# Spawning & lifecycle
# -------------------------

func _on_server_started() -> void:
	print("Server started (signal).")
	# In listen-server mode (editor host), we want a local player.
	# In dedicated mode, server is NOT a player.
	if not GameState.is_dedicated_server():
		_spawn_player_for(1)


func _on_joined_server() -> void:
	print("Client joined server.")
	
func _on_peer_joined(id: int) -> void:
	print("Peer joined: ", id)
	if multiplayer.is_server():
		if GameState.is_dedicated_server() and id == 1:
			return  # never spawn the dedicated server as a player
		_spawn_player_for2(id)


func on_peer_joined(id: int) -> void:
	print("Peer joined: ", id)
	if multiplayer.is_server():
		_spawn_player_for(id)


func _on_peer_left(id: int) -> void:
	print("Peer left: ", id)
	if _players.has(id):
		var p: CharacterBody3D = _players[id]
		if p:
			_players.erase(id)
			p.queue_free()

func _spawn_player_for(id: int) -> void:
	#print("spawining player for id: ", id)
	if not multiplayer.is_server():
		return
	# Avoid duplicates
	if _players.has(id) and is_instance_valid(_players[id]):
		return

	var p: Node = null
	if player_scene == null:
		push_error("player_scene not assigned"); return
	p = player_scene.instantiate()
	p.name = GameState.player_name
	# Put at a spawn point if you have one
	#var sp := spawn_points.get_node_or_null("Marker3D%d" % ((id - 1) % max(1, spawn_points.get_child_count())))
	var sp := spawn_points.get_node_or_null("Marker3D")
	if sp: p.global_transform = sp.global_transform

		

	p.set_multiplayer_authority(1)  # SERVER owns/simulates in server-auth
	#print("the id bbeofre setting owner peer id: ", id)
	p.owner_peer_id = id  # who should see/control this player locally
	_players[id] = p
	players_root.add_child(p, true)
	print("Spawned/registered player for peer ", id, " authority=", p.get_multiplayer_authority())
		# Tell only that client to attach their camera to this player
	_notify_client_to_attach_camera(p, id)
		# Focus camera if this is *our* player on this machine
		#_focus_camera_on_player(p, id)

func _spawn_player_for2(id: int) -> void:
	if !multiplayer.is_server():
		return

	if _players.has(id) and is_instance_valid(_players[id]):
		return

	var scene_to_use: PackedScene = player_scene
	var rec: Dictionary = GameState.roster.get(id, {})

	if bool(rec.get("is_bot", false)) and bot_player_scene:
		scene_to_use = bot_player_scene

	if scene_to_use == null:
		push_error("No player scene assigned (player_scene / bot_player_scene)")
		return

	var p: Node = scene_to_use.instantiate()

	var display_name := String(rec.get("name", GameState.player_name))
	p.name = display_name

	p.set_multiplayer_authority(1)
	p.owner_peer_id = id

	_players[id] = p
	players_root.add_child(p, true)

	var ability_id := String(rec.get("ability", "grapple"))  # default
	if p is Player:
		(p as Player).ability_id = StringName(ability_id)  

	# store player_path back into roster (server-side)
	if GameState.roster.has(id):
		GameState.roster[id]["player_path"] = p.get_path()

	print("Spawned/registered player for peer ", id,
		" (bot=", rec.get("is_bot", false),
		") authority=", p.get_multiplayer_authority())

	_notify_client_to_attach_camera(p, id)

func _spawn_players() -> void:
	#print("spawining player for id: ", id)
	var blue_placed := 1
	var red_placed := 1
	for k in GameState.roster:
		var v: Dictionary = GameState.roster[k]
		var id: int = k
		if not multiplayer.is_server():
			return
		# Avoid duplicates
		if _players.has(id) and is_instance_valid(_players[id]):
			return

		var p: Node = null
		if player_scene == null:
			push_error("player_scene not assigned"); return
		p = player_scene.instantiate()
		p.name = "Player_%d" % id
		# Put at a spawn point if you have one
		#var sp := spawn_points.get_node_or_null("Marker3D%d" % ((id - 1) % max(1, spawn_points.get_child_count())))
		if v.get("team") == "Blue":
			var sp := spawn_points.get_node_or_null("Spawn%d" % blue_placed)
			blue_placed += 1
			if sp: p.global_transform = sp.global_transform
		else:
			var sp := spawn_points.get_node_or_null("Spawn%d"% red_placed)
			red_placed += 1
			if sp: p.global_transform = sp.global_transform

		p.set_multiplayer_authority(1)  # SERVER owns/simulates in server-auth
		#print("the id bbeofre setting owner peer id: ", id)
		p.owner_peer_id = id  # who should see/control this player locally
		_players[id] = p
		players_root.add_child(p, true)
		print("Spawned/registered player for peer ", id, " authority=", p.get_multiplayer_authority())
			# Tell only that client to attach their camera to this player
		_notify_client_to_attach_camera(p, id)
			# Focus camera if this is *our* player on this machine
			#_focus_camera_on_player(p, id)

# -------------------------
# Input → server
# -------------------------

func _gather_input() -> Dictionary:
	var mvx : float = 0.0
	var mvz : float = 0.0
	if is_mobile and is_instance_valid(joystick):
		var v2: Vector2 = joystick.vector
		if v2.length() > 0.01:
			mvx = v2.x
			mvz = v2.y
	else:
		mvx = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		mvz = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")

	var yaw := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		yaw = cam.global_transform.basis.get_euler().y
	else:
		var me: CharacterBody3D = _players.get(multiplayer.get_unique_id(), null) as CharacterBody3D
		if me:
			yaw = me.rotation.y
	
	var facing: Dictionary
	if OS.has_feature("mobile"):
		cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("consume_facing_delta"):
			facing = cam.consume_facing_delta()
		else:
			facing = Dictionary()
	else:
		facing = (_my_player.get_yaw() if _my_player else Dictionary())
	var gm := false

	var shoot_down := Input.is_action_pressed(_shoot_action())
	var shoot_up := shoot_edge_latched

	if gm:
		shoot_down = false
		shoot_up = false
	return {
	"mvx": mvx,
	"mvz": mvz,
	"sprint": Input.is_action_pressed("sprint"),
	"jump_pressed": jump_edge_latched,
	"tackle_pressed": tackle_edge_latched,
	"dribble": Input.is_action_pressed("dribble"),
	"stop_ball": stop_ball_edge_latched,
	"shoot_down": shoot_down,
	"shoot_up": shoot_up,
	"rmb": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
	"facing": facing,
	"aim_position": _my_player.get_aim_arrow_position() if _my_player and shoot_edge_latched else null,
	"cam_yaw": yaw,
	"assist_pass_pressed": assist_pass_edge_latched,
	"latch_toggle": latch_edge_latched,
	"ability_toggle": ability_toggle_edge_latched,
	"ability_action1": ability_a1_edge_latched,
	"ability_action2": Input.is_action_pressed("ability_action2"),
	"ability_action3": ability_a3_edge_latched,  
	}


func _send_local_input() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	var d := _gather_input()
	d["id"] = multiplayer.get_unique_id()

	# ✅ IMPORTANT: also feed local player immediately on this machine
	# so client-side code (_ability.client_tick, UI, etc.) can react instantly.
	if is_instance_valid(_my_player) and _my_player.has_method("apply_net_input"):
		_my_player.apply_net_input(d)

	if multiplayer.is_server():
		if _players.has(1):
			var p: CharacterBody3D = _players[1]
			if p and p.has_method("apply_net_input"):
				p.apply_net_input(d)
				if d.get("ability_action1", false):
					print("PLAYER: got ability_action1 (server=", multiplayer.is_server(), ")")

	else:
		StateHandler.send_data_id(NetCodes.Msg.DISCRETE_INPUTS, d)

@rpc("any_peer")
func _rpc_client_input(from_id: int, d: Dictionary) -> void:
	if d.get("grapple_toggle", false):
		print("World got grapple toggle from ", from_id)
	if _players.has(from_id):
		#print("_rpc_client_input2")
		var p: CharacterBody3D = _players[from_id]
		if p and p.has_method("apply_net_input"):
			#print("_rpc_client_input3")
			p.apply_net_input(d)
			

func _notify_client_to_attach_camera(p: Node, peer_id: int) -> void:
	# If this machine IS the owner (e.g., listen server’s own player), just do it locally.
	var joystick_path = NodePath("")
	if joystick: joystick_path = joystick.get_path()
	if multiplayer.get_unique_id() == peer_id:
		_rpc_attach_cam(p.get_path(), joystick_path, ball_scene.get_path())
	else:
		rpc_id(peer_id, "_rpc_attach_cam", p.get_path(), joystick_path, ball_scene.get_path())

@rpc("any_peer", "reliable", "call_local")
func _rpc_attach_cam(player_path: NodePath, _unused_joystick_path: NodePath, ball_path: NodePath) -> void:
	_my_player = get_node_or_null(player_path)
	var p := _my_player
	if p == null:
		await get_tree().process_frame
		p = get_node_or_null(player_path)
	if p == null:
		return

	# Connect ONCE (avoid double connect on respawn)
	if not _my_player.ability_ui_changed.is_connected(_on_ability_ui_changed):
		_my_player.ability_ui_changed.connect(_on_ability_ui_changed)

	# ✅ FORCE INITIAL UI UPDATE (so textures set on game start)
	if _my_player.has_method("refresh_ability_ui"):
		_my_player.call_deferred("refresh_ability_ui")

	# Resolve joystick on THIS client
	#var joystick: Control = null
	#if OS.has_feature("mobile"):
		#joystick = get_node_or_null("/root/World/CanvasLayer/UI/JoyStick") as Control
		#if joystick == null:
			#var world := get_node_or_null("/root/World")
			#if world:
				#joystick = world.find_child("JoyStick", true, false) as Control
	
	
	## Resolve camera
	#var cam: Camera3D = get_node_or_null("/root/World/Scene/Camera3D") as Camera3D
	#if cam == null:
		#cam = p.get_node_or_null("Camera3D") as Camera3D
	#if cam == null:
		#return
#
	## Wire camera (existing)
	#cam.current = true
	#if cam.has_method("set_target"): cam.call_deferred("set_target", p)
	#if cam.has_method("activate"):   cam.call_deferred("activate")
	#if cam.has_method("set_ball"):   cam.call_deferred("set_ball", ball_path)
#
	## NEW: give the camera its joystick
	#if joystick and cam.has_method("set_joystick"):
		#cam.call_deferred("set_joystick", joystick)
#
	## Hand joystick to player (as you already do)
	#if p.has_method("attach_camera"):
		#p.call_deferred("attach_camera", cam, joystick)


func _focus_camera_on_player(p: Node, peer_id: int) -> void:
	# Find your camera (adjust the path/group/name to your project)
	var my_id := multiplayer.get_unique_id()
	# If this world.gd is running on the same machine that should see the camera,
	# do it locally; otherwise, tell that specific client to do it.
	if my_id == peer_id:
		_enable_local_view_now(p)
	else:
		rpc_id(peer_id, "_rpc_enable_local_view", p.get_path())
func _enable_local_view_now(p: Node) -> void:
	# mark for convenience if you want in Player.gd
	p.add_to_group("LocalPlayer")

	var cam := p.get_node_or_null("Camera3D") # adjust path if your camera is elsewhere
	if cam:
		cam.current = true
		cam.visible = true

		# Optional: wire the ball target (if your Camera script uses it)
		var ball := get_tree().get_first_node_in_group("Ball")
		if ball:
			cam.call_deferred("set", "ball_target_path", ball.get_path())

@rpc("any_peer", "unreliable_ordered")
func receive_network_input_by_id(peer_id : int, msg, cmd : Dictionary) -> void:
	net.process_input_by_id(peer_id, msg, cmd)
	

@rpc("any_peer", "reliable")
func receive_network_input_dictionary(msg: int, value : Dictionary) -> void:
	net.process_input_dictionary(msg, value)

@rpc("authority", "unreliable_ordered")
func _rpc_client_receive_facing_snapshots(snapshots: Dictionary) -> void:
	# Forward to client-only helper
	net.on_recieving_snapshots(snapshots)

@rpc("any_peer", "call_local")
func _rpc_enable_local_view(player_path: NodePath) -> void:
	#_log_pid("in rpc enabble local view now")
	var p := get_node_or_null(player_path)
	if p:
		_enable_local_view_now(p)
	else:
		print("there is no player scene attached in the player_path when in rpc enable local view now")
func _on_ball_out_of_bounds(body: Node) -> void:
	if !multiplayer.is_server():
		return
	if body == null or !body.is_in_group("ball"):
		return

	_respawn_ball(body as RigidBody3D)
func _respawn_ball(ball: RigidBody3D) -> void:
	if ball == null:
		return

	# stop all motion
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.sleeping = true  # pause it a moment so it doesn't instantly re-fall

	# move it back to spawn
	if ball_spawn:
		ball.global_transform = ball_spawn.global_transform
	else:
		# fallback: BallHolder origin
		ball.global_position = ball_root.global_position

	# wake next frame
	ball.call_deferred("_wake_ball")

# helper method on the ball (or inline with deferred lambda)
func _ensure_cd_label(btn: TouchScreenButton) -> Label:
	var lbl := btn.get_node_or_null("CooldownLabel") as Label
	if lbl:
		return lbl

	lbl = Label.new()
	lbl.name = "CooldownLabel"
	lbl.visible = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.z_index = 1000
	lbl.z_as_relative = true

	# Match the texture rect (TouchScreenButton texture starts at local (0,0))
	var tex := btn.texture_normal
	var size := Vector2(120, 120)
	if tex:
		size = tex.get_size()

	lbl.size = size
	lbl.position = Vector2.ZERO  # ✅ key change: align to textured rect

	# Make countdown text black
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.add_theme_font_size_override("font_size", 48)

	btn.add_child(lbl)
	return lbl

func _update_tackle_cooldown_ui(delta: float) -> void:
	if not OS.has_feature("mobile"):
		return
	if _tackle_cd_label == null:
		return

	# Pull last replicated cooldown start value from player (server → owner)
	var from_player := 0.0
	if _my_player and is_instance_valid(_my_player):
		# tackle_cd_ui is replicated to the owning client
		from_player = float(_my_player.get("tackle_cd_ui"))

	# If server pushed a new cooldown (or reset), sync local timer
	if absf(from_player - _tackle_cd_last_from_player) > 0.001:
		_tackle_cd_last_from_player = from_player
		_tackle_cd_local = from_player

	# Count down locally for smooth UI
	if _tackle_cd_local > 0.0:
		_tackle_cd_local = maxf(0.0, _tackle_cd_local - delta)

	if _tackle_cd_local > 0.0:
		_tackle_cd_label.visible = true
		_tackle_cd_label.text = str(int(ceil(_tackle_cd_local)))

		# Optional: visually “disable” button
		# tackle_btn.modulate.a = 0.55
	else:
		_tackle_cd_label.visible = false
		_tackle_cd_label.text = ""
		# tackle_btn.modulate.a = 1.0

func _update_pass_cooldown_ui(delta: float) -> void:
	if not OS.has_feature("mobile"):
		return
	if _pass_cd_label == null:
		return

	var from_player := 0.0
	if _my_player and is_instance_valid(_my_player):
		from_player = float(_my_player.get("assist_pass_cd_ui"))

	if absf(from_player - _pass_cd_last_from_player) > 0.001:
		_pass_cd_last_from_player = from_player
		_pass_cd_local = from_player

	if _pass_cd_local > 0.0:
		_pass_cd_local = maxf(0.0, _pass_cd_local - delta)

	if _pass_cd_local > 0.0:
		_pass_cd_label.visible = true
		_pass_cd_label.text = str(int(ceil(_pass_cd_local)))
	else:
		_pass_cd_label.visible = false
		_pass_cd_label.text = ""




func _ensure_grapple_crosshair() -> void:
	if _grapple_crosshair_layer != null:
		return

	_grapple_crosshair_layer = CanvasLayer.new()
	_grapple_crosshair_layer.name = "GrappleCrosshairLayer"
	_grapple_crosshair_layer.layer = 200  # draw above most UI
	add_child(_grapple_crosshair_layer)

	# full-screen root
	_grapple_crosshair_root = Control.new()
	_grapple_crosshair_root.name = "GrappleCrosshairRoot"
	_grapple_crosshair_root.anchor_left = 0.0
	_grapple_crosshair_root.anchor_top = 0.0
	_grapple_crosshair_root.anchor_right = 1.0
	_grapple_crosshair_root.anchor_bottom = 1.0
	_grapple_crosshair_root.offset_left = 0
	_grapple_crosshair_root.offset_top = 0
	_grapple_crosshair_root.offset_right = 0
	_grapple_crosshair_root.offset_bottom = 0
	_grapple_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grapple_crosshair_layer.add_child(_grapple_crosshair_root)

	# center container
	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = 0
	center.offset_top = 0
	center.offset_right = 0
	center.offset_bottom = 0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grapple_crosshair_root.add_child(center)

	_grapple_crosshair = GrappleCrosshair.new()
	_grapple_crosshair.visible = false
	center.add_child(_grapple_crosshair)


func _update_grapple_crosshair() -> void:
	if _grapple_crosshair == null:
		return

	var show := false
	if is_instance_valid(_my_player):
		# show only when grapple mode is enabled
		show = _my_player.grapple_mode_active

	_grapple_crosshair.visible = show




func ui_release_grapple() -> void:
	pass # Replace with function body.
func _on_ability_ui_changed(labels: PackedStringArray, visible: bool, wants_crosshair: bool) -> void:
	var pad := $CanvasLayer/UI/ActionPad

	var ability_btn := pad.get_node_or_null("Ability") # ability toggle button
	var a1 := pad.get_node_or_null("AbilityAction1")
	var a2 := pad.get_node_or_null("AbilityAction2")
	var a3 := pad.get_node_or_null("AbilityAction3")

	# show/hide
	if a1: a1.visible = visible
	if a2: a2.visible = visible
	if a3: a3.visible = visible
	if ability_btn: ability_btn.visible = true  # your choice

	# (optional) labels on top of textures
	# _set_btn_label(a1, labels.size() > 0 ? labels[0] : "")
	# _set_btn_label(a2, labels.size() > 1 ? labels[1] : "")
	# _set_btn_label(a3, labels.size() > 2 ? labels[2] : "")

	# ✅ swap textures based on currently equipped ability
	var icons := {}
	if is_instance_valid(_my_player) and _my_player.has_method("get_ability_icons"):
		icons = _my_player.get_ability_icons()

	_set_btn_tex(ability_btn, icons.get("ability", null), _def_tex_ability)
	_set_btn_tex(a1, icons.get("a1", null), _def_tex_a1)
	_set_btn_tex(a2, icons.get("a2", null), _def_tex_a2)
	_set_btn_tex(a3, icons.get("a3", null), _def_tex_a3)

	# crosshair
	if is_instance_valid(_grapple_crosshair):
		_grapple_crosshair.visible = visible and wants_crosshair

func _set_btn_label(btn: Node, t: String) -> void:
	if btn == null: return
	var lbl := btn.get_node_or_null("Label") as Label
	if lbl:
		lbl.text = t
		return
	for c in btn.get_children():
		if c is Label:
			(c as Label).text = t
			return
func _cache_default_ability_textures() -> void:
	var pad := $CanvasLayer/UI/ActionPad

	var ability_btn := pad.get_node_or_null("Ability") # <- your "Ability toggle" button node name
	var a1 := pad.get_node_or_null("AbilityAction1")
	var a2 := pad.get_node_or_null("AbilityAction2")
	var a3 := pad.get_node_or_null("AbilityAction3")

	if ability_btn is TouchScreenButton: _def_tex_ability = (ability_btn as TouchScreenButton).texture_normal
	if a1 is TouchScreenButton: _def_tex_a1 = (a1 as TouchScreenButton).texture_normal
	if a2 is TouchScreenButton: _def_tex_a2 = (a2 as TouchScreenButton).texture_normal
	if a3 is TouchScreenButton: _def_tex_a3 = (a3 as TouchScreenButton).texture_normal

func _all_players_positions() -> void:
	for k in GameState.roster.keys():
		var p := get_node(GameState.roster[k]["player_path"]) as Node3D
		#print("the player's id is: ", pid)
		if p == null or int(k) ==1:
			continue
		print("player ", p.name)
		print("position: ", p.global_position)

var _perf_acc := 0.0
var _perf_frames := 0

func _perf_tick(delta: float) -> void:
	_perf_acc += delta
	_perf_frames += 1

	if _perf_acc >= 1.0:
		var phys_s := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		var proc_s := float(Performance.get_monitor(Performance.TIME_PROCESS))
		var phys_ms := phys_s * 1000.0
		var proc_ms := proc_s * 1000.0
		var avg_delta : float= _perf_acc / max(1, _perf_frames)

		print("SERVER PERF | phys_ms=", phys_ms,
			" proc_ms=", proc_ms,
			" physics_fps≈", _perf_frames,
			" avg_delta=", avg_delta)

		_perf_acc = 0.0
		_perf_frames = 0
