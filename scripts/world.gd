extends Node


# --- Assign in the inspector or hardcode a PackedScene for clients that join ---
@export var pause_btn: Button
@export var score_btn: Button
@export var win_scene_path: String = "res://WinScene.tscn"
@export var defeat_scene_path: String = "res://DefeatScene.tscn"
@export var scoreboard_scene_path: String = "res://ScoreboardScene.tscn"
@export var player_scene: PackedScene
@export var bot_player_scene: PackedScene

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
var _game : Game
# --- Pause dialog (created at runtime) ---
var _pause_ui: Control
var _gfx_ui: Control
var _btn_resume: Button
# --- Scoreboard popup (shown while holding the "scoreboard" action) ---
var _scoreboard_popup: Control
var _scoreboard_instance: Control
const SCOREBOARD_PAUSES := false  # set true if you want gameplay paused while holding


# Input pump
const NET_INPUT_HZ: float = 30.0
const TEAM_BLUE_PATH:  NodePath = ^"Teams/TeamBlue/Spawns"
const TEAM_RED_PATH:   NodePath = ^"Teams/TeamRed/Spawns"
const BALL_SPAWN_PATH: NodePath = ^"BallSpawn"
const BALL_PATH: NodePath = ^"Scene/Ball"
@onready var team_blue: Node3D = get_node(TEAM_BLUE_PATH)
@onready var team_red:  Node3D = get_node(TEAM_RED_PATH)

var _my_player: Node = null
var _input_accum: float = 0.0
var ball_scene : Node3D = null
var  tackle_edge_latched := false
var  stop_ball_edge_latched := false
var  jump_edge_latched := false
var  shoot_edge_latched := false
var latch_edge_latched := false 
func _ready() -> void:
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
	var spawner := players_root.get_node_or_null("MultiplayerSpawner")
	if spawner == null:
		spawner = MultiplayerSpawner.new()
		spawner.name = "MultiplayerSpawner"
		spawner.spawn_path = players_root.get_path()
		players_root.add_child(spawner)

	# Register ALL player-type scenes that might be spawned
	if player_scene:
		spawner.add_spawnable_scene(player_scene.resource_path)

	if bot_player_scene:
		spawner.add_spawnable_scene(bot_player_scene.resource_path)

	_create_ball_spawner()
	_initialize_game()
	_setup_pause_dialog()
	_setup_scoreboard_popup()
	_game.set_scoreboard(_scoreboard_instance)
	_server_setup()

	# 1) Connect to the Network autoload signals (do it here so it works even if not wired in editor)

	#Network.server_started.connect(_on_server_started)
	#Network.joined_server.connect(_on_joined_server)
	#Network.peer_joined.connect(_on_peer_joined)
	#Network.peer_left.connect(_on_peer_left)
	
	# 2) If a Player is already in the scene (your case), register it for the host
	var pre := get_node_or_null("Player")
	if pre != null:
		# Server must own/simulate every player in server-auth
		pre.set_multiplayer_authority(1)
		_players[1] = pre
		print("Registered preplaced Player as host player; authority=", pre.get_multiplayer_authority())


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

func _setup_scoreboard_popup() -> void:
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
	else:
		push_error("Could not load scoreboard scene at: %s" % scoreboard_scene_path)


func _open_scoreboard() -> void:
	if SCOREBOARD_PAUSES:
		get_tree().paused = true
		# keep mouse as-is (you’re only holding a key)
	_scoreboard_popup.visible = true

func _close_scoreboard() -> void:
	_scoreboard_popup.visible = false
	if SCOREBOARD_PAUSES and get_tree().paused:
		get_tree().paused = false

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
	get_tree().change_scene_to_file("res://title_screen.tscn")

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
	dim.color = Color(0,0,0,0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# centered panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2i(480, 340)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	# Title
	var title := Label.new()
	title.text = "Graphics Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)

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
	quality.add_item("Low (No AA)", 0)
	quality.add_item("Medium (2x AA)", 1)
	quality.add_item("High (4x AA)", 2)
	# pick based on current MSAA
	match get_viewport().msaa_3d:
		Viewport.MSAA_DISABLED: quality.select(0)
		Viewport.MSAA_2X:       quality.select(1)
		Viewport.MSAA_4X:       quality.select(2)
	v.add_child(quality)

	# --- Texture quality dropdown ---
	var tex_label := Label.new()
	tex_label.text = "Texture Quality"
	v.add_child(tex_label)

	var tex_quality := OptionButton.new()
	tex_quality.add_item("Low", 0)
	tex_quality.add_item("Medium", 1)
	tex_quality.add_item("High", 2)
	tex_quality.select(clamp(Settings.tex_quality, 0, 2))
	v.add_child(tex_quality)

	# --- Apply and Back buttons ---
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)

	var apply := Button.new()
	apply.text = "Apply"
	h.add_child(apply)

	var back := Button.new()
	back.text = "Back"
	h.add_child(back)

	# --- Signal handlers ---
	apply.pressed.connect(func ():
		_apply_graphics_settings(fullscreen.button_pressed, vsync.button_pressed, quality.selected,tex_quality.selected)
	)

	back.pressed.connect(func ():
		root.hide()
	)

	return root
func _apply_graphics_settings(fullscreen: bool, vsync: bool, quality: int, tex_quality: int) -> void:
	Settings.set_and_save(fullscreen, vsync, quality, tex_quality)

func _server_setup() -> void:
	if !multiplayer.is_server():
		return
	
	_create_ball_server()

	var ids: Array[int] = []
	for k in GameState.roster.keys():
		var pid := int(k)
		if GameState.is_dedicated_server() and pid == 1:
			continue  # server is not a player in dedicated mode
		ids.append(pid)

	_server_begin_match(ids)

	# Resolve to actual nodes in World context
	var blue_spawns := get_node(TEAM_BLUE_PATH)  as Node3D
	var red_spawns  := get_node(TEAM_RED_PATH)   as Node3D
	var ball_spawn  := get_node(BALL_SPAWN_PATH) as Node3D

	# Give Game everything it needs *before* it's added (so _ready can safely use them)
	_game.setup({
		"duration_sec": GameState.match_len_sec,
		"goal_limit":   GameState.goal_limit,
		"roster":       GameState.roster,
	}, blue_spawns, red_spawns, ball_spawn, ball_scene)
	_game.set_game()

func _initialize_game() -> void:
	var game := Game.new()
	game.name = "Game"
		## Resolve to actual nodes in World context
	#var blue_spawns := get_node(TEAM_BLUE_PATH)  as Node3D
	#var red_spawns  := get_node(TEAM_RED_PATH)   as Node3D
	#var ball_spawn  := get_node(BALL_SPAWN_PATH) as Node3D
	##var ball_scene := get_node(BALL_PATH) as Node3D
#
	## Give Game everything it needs *before* it's added (so _ready can safely use them)
	#game.setup({
			#"duration_sec": GameState.match_len_sec,
			#"goal_limit":   GameState.goal_limit,
			#"roster":       GameState.roster,
		#}, blue_spawns, red_spawns, ball_spawn, ball_scene)

	_game = game
	add_child(game)

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
		ball_spawner.spawn_path = ball_root.get_path()
		ball_root.add_child(ball_spawner)

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
	if Input.is_action_just_pressed("jump") and not jump_edge_latched:
		jump_edge_latched = true
	if Input.is_action_just_pressed("tackle") and not tackle_edge_latched:
		tackle_edge_latched = true			
	if Input.is_action_just_pressed("stop_ball") and not stop_ball_edge_latched:
		stop_ball_edge_latched = true		
	if Input.is_action_just_released(_shoot_action()) and not shoot_edge_latched:
		shoot_edge_latched = true
	# ⬇️ NEW: toggle input (press once = "edge" event)
	if Input.is_action_just_pressed("ball_latch") and not latch_edge_latched:
		 
		latch_edge_latched = true

func _reset_inputs() -> void:
	jump_edge_latched = false
	tackle_edge_latched = false
	stop_ball_edge_latched = false
	shoot_edge_latched = false
	latch_edge_latched = false     # ⬅️ NEW


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("host_key"):
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
			print("Already hosting (ENet)")
		else:
			Network.host()              # start hosting
	#var fps := Engine.get_frames_per_second()
	##if fmod(fps, 10.0) < 0.001:
		##print(int(round(fps)))
	#print("MSAA Level:", get_viewport().msaa_3d)

	if Input.is_action_just_pressed("join_key"):
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			print("Already connected (ENet)")
		else:
			Network.join("127.0.0.1")
	if Input.is_action_just_pressed("debug_third") and is_instance_valid(_game):
		_game._rpc_set_goal_camera_third_person()  # direct local call

	if Input.is_action_just_pressed("debug_first") and is_instance_valid(_game):
		_game._rpc_set_camera_first_person()       # direct local call
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

	# Avoid duplicates
	if _players.has(id) and is_instance_valid(_players[id]):
		return

	# ----------------------------
	# Choose bot scene or player scene
	# ----------------------------
	var scene_to_use: PackedScene = player_scene

	if GameState.roster.has(id):
		var rec: Dictionary = GameState.roster[id]
		if rec.get("is_bot", false) and bot_player_scene:
			scene_to_use = bot_player_scene

	if scene_to_use == null:
		push_error("No player scene assigned (player_scene / bot_player_scene)")
		return

	var p: Node = scene_to_use.instantiate()

	# Use the name from roster if present (so bots show “Bot1”, etc.)
	var display_name := GameState.player_name
	if GameState.roster.has(id):
		display_name = String(GameState.roster[id].get("name", display_name))
	p.name = display_name

	p.set_multiplayer_authority(1)        # SERVER owns/simulates in server-auth
	p.owner_peer_id = id                  # who should see/control this player locally
	_players[id] = p
	players_root.add_child(p, true)
	GameState.roster[id]["player_path"] = p.get_path()

	print("Spawned/registered player for peer ", id,
		" (bot=", GameState.roster.get(id, {}).get("is_bot", false),
		") authority=", p.get_multiplayer_authority())

	# Tell only that client to attach their camera to this player
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
	return {
	"mvx": mvx,
	"mvz": mvz,
	"sprint": Input.is_action_pressed("sprint"),
	"jump_pressed": jump_edge_latched,
	"tackle_pressed": tackle_edge_latched,
	"dribble": Input.is_action_pressed("dribble"),
	"stop_ball": stop_ball_edge_latched,
	"shoot_down": Input.is_action_pressed(_shoot_action()),
	"shoot_up": shoot_edge_latched,
	"rmb": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
	"facing": facing,
	"aim_position": _my_player.get_aim_arrow_position() if _my_player and shoot_edge_latched else null,
	"cam_yaw": yaw,
	"latch_toggle": latch_edge_latched   # ⬅️ NEW
}

func _send_local_input() -> void:
	# 0) If there is no network peer yet (single-player / not joined / not hosting), do nothing
	if multiplayer.multiplayer_peer == null:
		print("no player has joined yet")
		return
	var d := _gather_input()
	if _players.has(1):
		#print("_players.has(1)")
		var p: CharacterBody3D = _players[1]
		if p and p.has_method("apply_net_input"):
			#print("_players.has(1)2")
			p.apply_net_input(d)
	else:
		# Client: only send if we’re actually connected to the server (peer 1)
		if multiplayer.get_peers().has(1):
			rpc_id(1, "_rpc_client_input", multiplayer.get_unique_id(), d)
		else:
			#print("Client not connected yet; dropping input")
			pass

@rpc("any_peer")
func _rpc_client_input(from_id: int, d: Dictionary) -> void:
	#print("the input is coming from the player: ", from_id)
	#print("_rpc_client_input")
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

	# Resolve joystick on THIS client
	#var joystick: Control = null
	#if OS.has_feature("mobile"):
		#joystick = get_node_or_null("/root/World/CanvasLayer/UI/JoyStick") as Control
		#if joystick == null:
			#var world := get_node_or_null("/root/World")
			#if world:
				#joystick = world.find_child("JoyStick", true, false) as Control

	# Resolve camera
	var cam: Camera3D = get_node_or_null("/root/World/Scene/Camera3D") as Camera3D
	if cam == null:
		cam = p.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return

	# Wire camera (existing)
	cam.current = true
	if cam.has_method("set_target"): cam.call_deferred("set_target", p)
	if cam.has_method("activate"):   cam.call_deferred("activate")
	if cam.has_method("set_ball"):   cam.call_deferred("set_ball", ball_path)

	# NEW: give the camera its joystick
	if joystick and cam.has_method("set_joystick"):
		cam.call_deferred("set_joystick", joystick)

	# Hand joystick to player (as you already do)
	if p.has_method("attach_camera"):
		p.call_deferred("attach_camera", cam, joystick)
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
