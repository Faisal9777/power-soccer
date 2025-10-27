extends Node


# --- Assign in the inspector or hardcode a PackedScene for clients that join ---
@export var player_scene: PackedScene
@export var ball_packed: PackedScene
@onready var spawn_points := $SpawnPoints   # optional, if you have markers named SpawnPoint0/1/2...
@onready var players_root := $Players
@onready var ball_root: Node = $BallHolder
@onready var is_mobile: bool = OS.has_feature("mobile") 
@export var joystick_path: NodePath
@onready var joystick: Node = get_node(joystick_path) 
# Keep a typed map of peer-id -> Player node
var _players: Dictionary[int, CharacterBody3D] = {}    # { int: Node }

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

func _ready() -> void:
	
	_setup_team_position()
	# If you didn't set the spawner in the editor, do it here:
	var spawner := players_root.get_node_or_null("MultiplayerSpawner")
	if spawner == null:
		spawner = MultiplayerSpawner.new()
		spawner.name = "MultiplayerSpawner"
		spawner.spawn_path = players_root.get_path()
		spawner.add_spawnable_scene(player_scene.resource_path)
		players_root.add_child(spawner)
	_create_ball_spawner()
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


func _server_setup() -> void:
	if !multiplayer.is_server():
		return
	_create_ball_server()
	var ids: Array[int] = []
	for k in GameState.roster.keys():
		ids.append(int(k))   # ensure int
		_server_begin_match(ids)
	var game := Game.new()

	# Resolve to actual nodes in World context
	var blue_spawns := get_node(TEAM_BLUE_PATH)  as Node3D
	var red_spawns  := get_node(TEAM_RED_PATH)   as Node3D
	var ball_spawn  := get_node(BALL_SPAWN_PATH) as Node3D
	#var ball_scene := get_node(BALL_PATH) as Node3D

	# Give Game everything it needs *before* it's added (so _ready can safely use them)
	game.setup({
		"duration_sec": GameState.match_len_sec,
		"goal_limit":   GameState.goal_limit,
		"roster":       GameState.roster,
	}, blue_spawns, red_spawns, ball_spawn, ball_scene)

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

func _reset_inputs() -> void:
	jump_edge_latched = false
	tackle_edge_latched = false
	stop_ball_edge_latched = false
	shoot_edge_latched = false


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("host_key"):
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
			print("Already hosting (ENet)")
		else:
			Network.host()              # start hosting

	if Input.is_action_just_pressed("join_key"):
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			print("Already connected (ENet)")
		else:
			Network.join("127.0.0.1")
	#print("am i connected? ", multiplayer.multiplayer_peer != null and multiplayer.is_server())
	#print("total numbers of players joined: ", multiplayer.get_peers())
	# Input pump
	#_input_accum += delta
	#var step: float = 1.0 / NET_INPUT_HZ
	#while _input_accum >= step:
		#_input_accum -= step
		#_send_local_input()

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
	# If you *don’t* have a preplaced Player, spawn one here for the host:
	_spawn_player_for(1)

func _on_joined_server() -> void:
	print("Client joined server.")

func _on_peer_joined(id: int) -> void:
	print("Peer joined: ", id)
	if multiplayer.is_server():
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
	p.name = "Player_%d" % id
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
	p.name = "Player_%d" % id

	p.set_multiplayer_authority(1)  # SERVER owns/simulates in server-auth
	#print("the id bbeofre setting owner peer id: ", id)
	p.owner_peer_id = id  # who should see/control this player locally
	_players[id] = p
	players_root.add_child(p, true)
	GameState.roster[id]["player_path"] = p.get_path()
	print("Spawned/registered player for peer ", id, " authority=", p.get_multiplayer_authority())
		# Tell only that client to attach their camera to this player
	_notify_client_to_attach_camera(p, id)
		# Focus camera if this is *our* player on this machine
		#_focus_camera_on_player(p, id)


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
		# Fallback to local player rotation if camera not ready
		var me: CharacterBody3D = _players.get(multiplayer.get_unique_id(), null) as CharacterBody3D
		if me:
			yaw = me.rotation.y
	
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
		"cam_yaw": yaw,
		"aim_position": _my_player.get_aim_arrow_position() if shoot_edge_latched else null
	}
#
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
func _rpc_attach_cam(player_path: NodePath, joystick_path: NodePath, ball_path: NodePath) -> void:
	var joystick := get_node_or_null(joystick_path)
	_my_player = get_node_or_null(player_path)
	var p := get_node_or_null(player_path)
	if p == null:
		# Player may not be ready yet on this client; try a frame later.
		await get_tree().process_frame
		p = get_node_or_null(player_path)
	if p == null:
		print("Camera attach: player not found on client")
		return
	# Find your camera (pick whichever suits your project)
	# Option 1: a global camera in the scene tagged by group
	#var cam := get_tree().get_first_node_in_group("Camera3D")
	var cam := get_node_or_null("/root/World/Scene/Camera3D")
	# Option 2: a camera under the player
	if cam == null:
		cam = p.get_node_or_null("Camera3D")
	if cam:
		cam.set_target(p)
		cam.activate()
	cam.set_ball(ball_path)
	# Assign camera variable on the Player and hook it up
	if p.has_method("attach_camera"):
		p.attach_camera(cam, joystick)
	#if cam and cam.has_method("set_target"):
		#cam.call_deferred("set_target", p)  # use deferred in case camera script isn’t ready yet
	#elif cam:
		## Fallback: just make it current
		#if "current" in cam:
			#cam.current = true
	else:
		print("No camera found to attach on client")

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
