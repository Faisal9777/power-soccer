extends Node
var GameClient := load("res://scripts/multiplayer/game_client.gd")
# --- networking config ---
@export var server_peer_id: int = 1

# Name of the RPC on your network endpoint that sends a single input command to the server.
# Change this string to match whatever your server endpoint exposes.
# (Many people use: "receive_network_input" or "receive_client_input" or "sv_receive_input")
@export var input_rpc_name: StringName = &"receive_network_input"

# How far "behind" we render remote players for smooth interpolation (ms)
@export var deadzone := 0.02
@export var snap_dist := 2.5
const C = preload("res://scripts/shared/scene.gd")
var player_scene:= C.PLAYER
var bot_player_scene:= C.BOT

var init_phase_completed := false
var server_data_completed := false
var _game : Node
var _can_network := true

var p_controller : PlayerController
var controllers : Array = []
var current_snapshots : Dictionary

var blue_sp : Node
var red_sp : Node
var ball : Node
var state : Node
var scoreboard : Control

var proxy : Node
var joystick : Node
var anchor: Node3D

# --- assigned/managed externally ---
# You can set this from your World script when players spawn.
var _players: Dictionary[int, Node] = {}  # peer_id -> Player node
# --- local prediction/reconciliation ---
var _pending_inputs: Array[Dictionary] = []   # only for LOCAL player
var _next_input_seq: int = -1

var _latest_local_snapshot: Dictionary = {}   # newest snapshot waiting to reconcile
var _latest_local_snapshot_id: int = -1       # ordering guard (server_tick or last_server_seq)
var _net_objects : Array
# --- remote interpolation buffer ---
# peer_id -> Array of { "t": int(ms), "xform": Transform3D, "snap": Dictionary }
var _remote_buf: Dictionary[int, Array] = {}

var _my_id: int = -1
var _fixed_dt: float = 1.0 / 60.0

@onready var _network_endpoint: Node = get_parent()

func process_input(cmd: Dictionary, peer_id : int) -> void:
	_store_snapshots(cmd)

func process_input_dictionary(msg : int, value : Dictionary) -> void:
	if msg == NetCodes.Msg.GAME_BEGIN:
		#_game.start_game(value)
		LoadingUI.hide_loading()
		p_controller.start_process()
		_game.start_game(value)
	
	elif msg == NetCodes.Msg.INIT_BEGIN:
		sync_init(value)
	
	elif msg == NetCodes.Msg.GAME_END:
		_game.end_game(value)
	
	elif msg == NetCodes.Msg.SNAPSHOTS:
		_store_snapshots(value)
	elif msg == NetCodes.Msg.ROUND_START:
		_game.start_game(value)
	elif msg == NetCodes.state_message.CHANGE_STATE:
		var state_info = value.get("value")
		StateHandler.change_state(state_info.get("state"), state_info.get("state_data"))

func handle_data(value):
	process_input_dictionary(value.get("message"), value.get("value"))

# ---------- Public API (call these from your world/spawner) ----------
func set_players(players: Dictionary) -> void:
	_players = players

func register_player(peer_id: int, player: Node) -> void:
	_players[peer_id] = player

func submit_input(input):
	_send_network_id(_my_id, NetCodes.Msg.INPUTS, input)

# ---------- Snapshot receive entry points ----------
# Your network endpoint can forward server snapshots into either of these.
# I’m providing BOTH names so you can wire it easily.
func process_snapshots(snapshots: Dictionary, server_id: int) -> void:
	
	_store_snapshots(snapshots)

func receive_network_input(snapshots: Dictionary, server_id: int) -> void:
	_store_snapshots(snapshots)


func init(p : Node3D,
	score_board : Control,
	ingame: Node,
	blue_spawns: Node3D,
	red_spawns: Node3D,
	ball_scene: Node3D,
	net_objects,
	j_stick) -> void:
	proxy = p
	joystick = j_stick
	blue_sp = blue_spawns
	red_sp = red_spawns
	ball = ball_scene
	_net_objects = net_objects
	state = ingame
	scoreboard = score_board 
	
	init_phase_completed = true
	_evaluate_all_phases()

func sync_init(value):
	GameState.roster = value
	server_data_completed = true
	#var ball_path = value.get("ball_path")
	#ball = get_node_or_null(ball_path)
	_evaluate_all_phases()


func _ready() -> void:
	StateHandler.register_state(self)
	_my_id = multiplayer.get_unique_id()
	var hz := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	_fixed_dt = 1.0 / max(1.0, hz)


# ---------- Main loop ----------
func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("debug"):
		_log_debug_state()
	if p_controller:
		p_controller.physics_tick(delta)


func _process(_delta: float) -> void:
	if controllers and controllers.size() > 0:
		for controller in controllers:
			controller.process_tick(_delta)
	#_smooth_local_visual(_delta)
	

func _evaluate_all_phases() -> void:
	if init_phase_completed and server_data_completed:
		_resolve_players_from_roster(GameState.roster)
		_send_network(NetCodes.Msg.INIT_DONE, {"id" : multiplayer.get_unique_id()})

# ---------- Snapshot storage ----------
func _store_snapshots(snapshots: Dictionary) -> void:
	for net_obj in _net_objects:
		var snap = snapshots.get(net_obj.name)
		if snap:
			net_obj.apply_snapshot(snap)
	current_snapshots = snapshots.get("players")
	_my_id = p_controller.id
	for k in current_snapshots.keys():
		var  entry = current_snapshots[k]
		var node_id = entry.get("node_id")
		var node_id_int := int(node_id)
		var c_id = ArrayUtils.find(controllers, node_id_int)
		var controller = controllers[c_id]
		if not _players.has(node_id_int):
			continue

		var snap: Dictionary = current_snapshots[k]

		# Prefer server_tick if you add it later; fallback to last_server_seq

		controller.store_snapshot(snap)
	#_game.current_state = snapshots.game_state

func _resolve_player(id, rec, scene_to_use) -> Node:
	var world := get_parent()
	if bool(rec.get("is_bot", false)) and bot_player_scene:
		scene_to_use = bot_player_scene

	if scene_to_use == null:
		push_error("No player scene assigned (player_scene / bot_player_scene)")
		return

	var p: Node = load(scene_to_use).instantiate()

	var display_name := String(rec.get("name", GameState.player_name))
	p.name = display_name

	p.set_multiplayer_authority(1)
	p.owner_peer_id = id

	world.players_root.add_child(p, true)

	var ability_id := String(rec.get("ability", "grapple"))  # default
	if p is Player:
		(p as Player).ability_id = StringName(ability_id) 
	return p 

func _resolve_players_from_roster(rosters) -> void:
	# Build unresolved list first
	var scene_to_use := player_scene
	for k in rosters.keys():
		var entry := rosters[k] as Dictionary
		var peer_id = int(k)
		var node_id := int(entry.get("node_id"))
		var ppath: NodePath = entry.get("player_path", NodePath(""))
		var team = entry.get("team")
		var name = entry.get("name")
		if ppath.is_empty():
			print("Roster peer ", node_id, " has EMPTY player_path")
			continue

		var node := _resolve_player(node_id, entry, scene_to_use)
		if peer_id == multiplayer.get_unique_id():
			var scheduler = JobScheduler.new()
			scheduler.name = "JobScheduler"
			add_child(scheduler)
			var cam = get_node_or_null(ObjectPath.CAMERA) as Camera3D
			cam.init(proxy, joystick)
			var input_buffer = LocalInputBuffer.new(NodeUtils.init_input_source(self))
			p_controller = PlayerController.new(node, node_id, name, team, cam, ball, joystick, self, input_buffer, scheduler)
			p_controller.get_body_mesh().visible = false
			proxy.init(node, p_controller)
			controllers.append(p_controller)
		else:
			controllers.append(RemotePlayerReplicator.new(node, name, node_id, team))

		if node != null:
			_players[k] = node
	_game = GameClient.new()
	add_child(_game)
	_game.setup(state, scoreboard, controllers)


func _send_network(msg, value) -> void:
	if _can_network:
		_network_endpoint.rpc(NetCodes.Rpc.INPUT_STREAM, msg, value)

func _send_network_id(sender_id, msg, inputs) -> void:
	var value = {"value": {"inputs" : inputs, "id" : sender_id}, "message" : msg}
	if _can_network:
		StateHandler.send_data(value)

func _log_debug_state() -> void:
	print("[DEBUG] snapshots: ", current_snapshots)
	print("[DEBUG] controller ids: ", controllers.map(func(c): return c.get("id")))
	print("[DEBUG] GameState.roster: ", GameState.roster)
	print("-------------------------------")
