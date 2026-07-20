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

var init_phase_completed := false
var server_data_completed := false
var _game : Node
var _can_network := true

var p_controller : PlayerController
var controllers : Array = []

var blue_sp : Node
var red_sp : Node
var ball : Node
var ball_sp : Node
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

# --- remote interpolation buffer ---
# peer_id -> Array of { "t": int(ms), "xform": Transform3D, "snap": Dictionary }
var _remote_buf: Dictionary[int, Array] = {}

var _my_id: int = -1
var _fixed_dt: float = 1.0 / 60.0

@onready var _network_endpoint: Node = get_parent()

func process_input(cmd: Dictionary, peer_id : int) -> void:
	_store_snapshots(cmd)

func process_input_dictionary(msg : int, value : Dictionary) -> void:
	if msg == NetCodes.Msg.INIT_BEGIN:
		var roster := value.get("roster") as Dictionary
		GameState.roster = roster
		server_data_completed = true
		var ball_path = value.get("ball_path")
		ball = get_node_or_null(ball_path)
		_evaluate_all_phases()

	if msg == NetCodes.Msg.GAME_BEGIN:
		#_game.start_game(value)
		LoadingUI.hide_loading()
		p_controller.start_process()
		_game.start_game(value)
	elif msg == NetCodes.Msg.GAME_END:
		_game.end_game(value)
	
	elif msg == NetCodes.Msg.SNAPSHOTS:
		_store_snapshots(value)
	elif msg == NetCodes.Msg.ROUND_START:
		_game.start_game(value)

func handle_data(msg, value):
	process_input_dictionary(msg, value)

# ---------- Public API (call these from your world/spawner) ----------
func set_players(players: Dictionary) -> void:
	_players = players

func register_player(peer_id: int, player: Node) -> void:
	_players[peer_id] = player

func submit_input(input):
	_send_network_id(server_peer_id, _my_id, NetCodes.Msg.INPUTS, input)

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
	ball_spawn: Node3D,
	j_stick) -> void:
	proxy = p
	joystick = j_stick
	blue_sp = blue_spawns
	red_sp = red_spawns
	ball_sp = ball_spawn
	state = ingame
	scoreboard = score_board 
	
	init_phase_completed = true
	_evaluate_all_phases()


func _ready() -> void:
	StateHandler.register_state(self)
	_my_id = multiplayer.get_unique_id()
	var hz := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	_fixed_dt = 1.0 / max(1.0, hz)


# ---------- Main loop ----------
func _physics_process(delta: float) -> void:
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
		_send_network(NetCodes.Msg.INIT_DONE, {})

# ---------- Snapshot storage ----------
func _store_snapshots(snapshots: Dictionary) -> void:
	_my_id = p_controller.id
	for k in snapshots.keys():
		var peer_id := int(k)
		var c_id = ArrayUtils.find(controllers, peer_id)
		var controller = controllers[c_id]
		if not _players.has(peer_id):
			continue

		var snap: Dictionary = snapshots[k]

		# Prefer server_tick if you add it later; fallback to last_server_seq

		controller.store_snapshot(snap)
	#_game.current_state = snapshots.game_state

func _resolve_players_from_roster(rosters) -> void:
	# Build unresolved list first
	for k in rosters.keys():
		var peer_id := int(k)
		var entry := rosters[k] as Dictionary
		var ppath: NodePath = entry.get("player_path", NodePath(""))
		var team = entry.get("team")
		var name = entry.get("name")
		if ppath.is_empty():
			print("Roster peer ", peer_id, " has EMPTY player_path")
			continue

		var node := get_node_or_null(ppath)
		if peer_id == multiplayer.get_unique_id():
			var scheduler = JobScheduler.new()
			scheduler.name = "JobScheduler"
			add_child(scheduler)
			var cam = get_node_or_null("/root/World/Scene/Camera3D") as Camera3D
			cam.init(proxy, joystick)
			var input_buffer = LocalInputBuffer.new(NodeUtils.init_input_source(self))
			p_controller = PlayerController.new(node, peer_id, name, team, cam, ball, joystick, self, input_buffer, scheduler)
			p_controller.get_body_mesh().visible = false
			proxy.init(node, p_controller)
			controllers.append(p_controller)
		else:
			controllers.append(RemotePlayerReplicator.new(node, name, peer_id, team))

		if node != null:
			_players[k] = node
	_game = GameClient.new()
	add_child(_game)
	_game.setup(state, scoreboard, controllers)

func _send_network(msg, value) -> void:
	if _can_network:
		_network_endpoint.rpc(NetCodes.Rpc.INPUT_STREAM, msg, {})

func _send_network_id(target_id, sender_id, msg, value) -> void:
	value["id"] = sender_id
	if _can_network:
		SessionManager.send_data_id(target_id, msg, value)
	
