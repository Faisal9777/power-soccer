extends Node

# --- Assign in the inspector or hardcode a PackedScene for clients that join ---
@export var player_scene: PackedScene
@onready var spawn_points := $SpawnPoints   # optional, if you have markers named SpawnPoint0/1/2...
@onready var players_root := $Players 
# World.gd


# Keep a typed map of peer-id -> Player node
var _players: Dictionary[int, CharacterBody3D] = {}    # { int: Node }

# Input pump
const NET_INPUT_HZ: float = 30.0
var _input_accum: float = 0.0

func _ready() -> void:
	# Ensure a MultiplayerSpawner exists and knows how to spawn players under /Players
	var spawner := players_root.get_node_or_null("MultiplayerSpawner")
	if spawner == null:
		spawner = MultiplayerSpawner.new()
		spawner.name = "MultiplayerSpawner"
		spawner.spawn_path = players_root.get_path()
		if player_scene == null:
			push_error("World.gd: player_scene not assigned"); # early warning
		else:
			spawner.add_spawnable_scene(player_scene.resource_path)
		players_root.add_child(spawner)

	# Network autoload signals
	Network.server_started.connect(_on_server_started)
	Network.joined_server.connect(_on_joined_server)
	Network.peer_joined.connect(_on_peer_joined)
	Network.peer_left.connect(_on_peer_left)

	# If a preplaced Player exists, register it for the host
	var pre := get_node_or_null("Player")
	if pre != null:
		pre.set_multiplayer_authority(1)   # server-auth: server simulates everyone
		_players[1] = pre
		print("Registered preplaced Player as host player; authority=", pre.get_multiplayer_authority())

	# ---------- CATCH-UP: spawn everyone already connected ----------
	# When we come here from the Lobby, the server is already hosting and clients are already connected,
	# so the 'server_started' / 'peer_joined' signals won't fire again. Do it now.
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		if multiplayer.is_server():
			# Host (peer 1)
			_spawn_player_for(1)
			# All currently connected clients
			for id in multiplayer.get_peers():
				_spawn_player_for(id)
		# Clients don't spawn themselves; they wait for the server to replicate.

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("check_user"):
		_log_pid("in process")
	# Hotkeys (rename actions as you like)
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
	_input_accum += delta
	var step: float = 1.0 / NET_INPUT_HZ
	while _input_accum >= step:
		_input_accum -= step
		_send_local_input()

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
	var sp := spawn_points.get_node_or_null("Marker3D%d" % ((id - 1) % max(1, spawn_points.get_child_count())))
	if sp:
		p.global_transform = sp.global_transform
		print("[spawn] peer", id, "at", sp.global_transform.origin)
	else:
		print("[spawn] peer", id, "NO MARKER, default to", p.global_transform.origin)
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
	# --- Movement from virtual joystick if available/active, else from keyboard ---
	var mvx := 0.0
	var mvz := 0.0

	var js := get_tree().get_first_node_in_group("VirtualJoystick") as JoyStick
	if js:
		# Your JoyStick.gd exposes: vector (x,y) with +y = UP (game-style).
		# Our convention here: +mvz means "forward". So map directly:
		var v: Vector2 = js.vector               # Vector2(x, y)
		mvx = v.x
		mvz = v.y                         # forward = +y on your stick
	else:
		# Fallback: desktop keyboard
		mvx = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		mvz = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")

	# --- Camera yaw (unchanged) ---
	var yaw := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		yaw = cam.global_transform.basis.get_euler().y
	else:
		var me: CharacterBody3D = _players.get(multiplayer.get_unique_id(), null) as CharacterBody3D
		if me:
			yaw = me.rotation.y

	return {
		"mvx": mvx,
		"mvz": mvz,
		"sprint": Input.is_action_pressed("sprint"),
		"jump_pressed": Input.is_action_just_pressed("jump"),
		"tackle_pressed": Input.is_action_just_pressed("tackle"),
		"dribble": Input.is_action_pressed("dribble"),
		"stop_ball": Input.is_action_pressed("stop_ball"),
		"shoot_down": Input.is_action_pressed("shoot"),
		"shoot_up": Input.is_action_just_released("shoot"),
		"rmb": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
		"cam_yaw": yaw
	}

func _send_local_input() -> void:
	# 0) If there is no network peer yet (single-player / not joined / not hosting), do nothing
	if multiplayer.multiplayer_peer == null:
		print("no player has joined yet")
		return
	var d := _gather_input()
	if _players.has(1):
		var p: CharacterBody3D = _players[1]
		if p and p.has_method("apply_net_input"):
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
	if _players.has(from_id):
		var p: CharacterBody3D = _players[from_id]
		if p and p.has_method("apply_net_input"):
			p.apply_net_input(d)
			

func _notify_client_to_attach_camera(p: Node, peer_id: int) -> void:
	print("[notify] attach -> peer=", peer_id, " path=", p.get_path(), " my_id=", multiplayer.get_unique_id())
	if multiplayer.get_unique_id() == peer_id:
		_rpc_attach_cam(p.get_path())
	else:
		rpc_id(peer_id, "_rpc_attach_cam", p.get_path())
#
#@rpc("any_peer", "call_local")
#func _rpc_attach_cam(player_path: NodePath) -> void:
	#var p := get_node_or_null(player_path)
	#if p == null:
		## Player may not be ready yet on this client; try a frame later.
		#await get_tree().process_frame
		#p = get_node_or_null(player_path)
	#if p == null:
		#print("Camera attach: player not found on client")
		#return
#
	## Find your camera (pick whichever suits your project)
	## Option 1: a global camera in the scene tagged by group
	##var cam := get_tree().get_first_node_in_group("Camera3D")
	#var cam := get_node_or_null("/root/World/Scene/Camera3D")
	## Option 2: a camera under the player
	#if cam == null:
		#cam = p.get_node_or_null("Camera3D")
	#if cam:
		#cam.set_target(p)
		#cam.activate()
	## Assign camera variable on the Player and hook it up
	#if p.has_method("attach_camera"):
		#p.attach_camera(cam)
	##if cam and cam.has_method("set_target"):
		##cam.call_deferred("set_target", p)  # use deferred in case camera script isn’t ready yet
	##elif cam:
		### Fallback: just make it current
		##if "current" in cam:
			##cam.current = true
	#else:
		#print("No camera found to attach on client")
@rpc("any_peer", "call_local")
func _rpc_attach_cam(player_path: NodePath) -> void:
	var p := get_node_or_null(player_path)
	if p == null:
		await get_tree().process_frame
		p = get_node_or_null(player_path)
	if p == null:
		print("[cam] player not found for:", player_path); return

	# 1) Prefer world camera tagged MainCamera
	var cam := get_tree().get_first_node_in_group("MainCamera") as Camera3D
	# 2) Fallback: per-player camera if you add one later
	if cam == null:
		cam = p.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		print("[cam] no camera (no MainCamera group and no Player/Camera3D)"); return

	# Wire targets
	if cam.has_method("set_target"):
		cam.call_deferred("set_target", p)
	var ball := get_tree().get_first_node_in_group("Ball") as Node3D
	if cam.has_method("set_ball") and ball:
		cam.call_deferred("set_ball", ball)

	# Make it current
	if cam.has_method("activate"):
		cam.call_deferred("activate")
	else:
		cam.call_deferred("set", "current", true)

	print("[cam] attached on peer", multiplayer.get_unique_id(), " to player:", p.name, " cam:", cam.get_path())
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
