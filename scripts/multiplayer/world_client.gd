extends Node
var GameClient := load("res://scripts/multiplayer/game_client.gd")
# --- networking config ---
@export var server_peer_id: int = 1

# Name of the RPC on your network endpoint that sends a single input command to the server.
# Change this string to match whatever your server endpoint exposes.
# (Many people use: "receive_network_input" or "receive_client_input" or "sv_receive_input")
@export var input_rpc_name: StringName = &"receive_network_input"

# How far "behind" we render remote players for smooth interpolation (ms)
@export var remote_interp_delay_ms: int = 120
@export var remote_buffer_max: int = 10
@export var visual_catchup_speed := 18.0
var _visual_offset := Vector3.ZERO

var _view_error_pos: Vector3 = Vector3.ZERO
var _view_error_yaw: float = 0.0
@export var view_catchup_speed := 18.0
@export var teleport_snap_dist := 2.5  # meters; snap if correction is huge

# --- assigned/managed externally ---
# You can set this from your World script when players spawn.
var _players: Dictionary[int, Node] = {}  # peer_id -> Player node
var _visual_nodes : Array 
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
		var ball_path : NodePath = value.get("ball_path")
		var blue_path: NodePath = value.get("blue_path")
		var red_path : NodePath = value.get("red_path")
	
		var game = GameClient.new()
		_network_endpoint.set_game(game)
		game.initialize(roster, _network_endpoint, value.get("state_path"), 
		ball_path, blue_path, red_path)
		_resolve_players_from_roster()
		_network_endpoint.rpc("receive_network_input_dictionary", NetCodes.Msg.INIT_DONE, {})
	if msg == NetCodes.Msg.GAME_BEGIN:
		_network_endpoint.start_game()

# ---------- Public API (call these from your world/spawner) ----------
func set_players(players: Dictionary) -> void:
	_players = players

func register_player(peer_id: int, player: Node) -> void:
	_players[peer_id] = player


# ---------- Snapshot receive entry points ----------
# Your network endpoint can forward server snapshots into either of these.
# I’m providing BOTH names so you can wire it easily.
func process_snapshots(snapshots: Dictionary, server_id: int) -> void:
	
	_store_snapshots(snapshots)

func receive_network_input(snapshots: Dictionary, server_id: int) -> void:
	_store_snapshots(snapshots)


func _ready() -> void:
	_my_id = multiplayer.get_unique_id()
	var hz := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	_fixed_dt = 1.0 / max(1.0, hz)


# ---------- Main loop ----------
func _physics_process(delta: float) -> void:
	_my_id = multiplayer.get_unique_id()

	# ---- DEBUG CHECKS (safe) ----
	#print("\n--- CLIENT _physics_process DEBUG ---")
	#print("_my_id =", _my_id)
	#print("_players has my_id? ", _players.has(_my_id), "  _players size=", _players.size())
	#print("_latest_local_snapshot empty? ", _latest_local_snapshot.is_empty(), "  keys=", _latest_local_snapshot.keys())
	#print("_next_input_seq =", _next_input_seq)
	#print("_pending_inputs size =", _pending_inputs.size())
	#print("_network_endpoint =", _network_endpoint, "  valid? ", is_instance_valid(_network_endpoint))
	#print("server_peer_id =", server_peer_id, "  input_rpc_name =", input_rpc_name)
	#print("is_server? ", multiplayer.is_server())
	#print("--- END DEBUG (pre) ---")
	# -----------------------------

	if not _players.has(_my_id):
		return

	var me = _players.get(_my_id, null)
	#print("me =", me, "  valid? ", is_instance_valid(me))
	if not is_instance_valid(me):
		return

	# 1) Reconcile (if snapshot exists)
	if not _latest_local_snapshot.is_empty():
		var snap := _latest_local_snapshot
		_latest_local_snapshot = {}
		#_reconcile_local(me, snap, delta)
		_reconcile_local_best_practice(me, snap)

	# 2) Local prediction + send input
	var cmd: Dictionary = {}
	if me.has_method("get_input_data"):
		cmd = me.get_input_data() as Dictionary
	else:
		print("ERROR: me has no get_input_data()")
		return

	cmd["seq"] = _next_input_seq
	_next_input_seq += 1

	var stored := cmd.duplicate(true)
	_pending_inputs.append(stored)

	if me.has_method("update_player_states"):
		me.update_player_states(stored, delta)
	else:
		print("ERROR: me has no update_player_states(input, delta)")
		return

	if not multiplayer.is_server():
		if is_instance_valid(_network_endpoint):
			#print("Sending input seq=", int(stored.get("seq", -1)), " to server_peer_id=", server_peer_id)
			_network_endpoint.rpc_id(server_peer_id, input_rpc_name, stored, _my_id)
		else:
			print("ERROR: _network_endpoint is null/invalid, cannot rpc_id")

	if _pending_inputs.size() > 256:
		_pending_inputs = _pending_inputs.slice(_pending_inputs.size() - 256, _pending_inputs.size())


func _process(_delta: float) -> void:
	#_smooth_local_visual(_delta)
	_smooth_local_view(_delta)
	# Remote interpolation runs every render frame for smoothness
	var now := Time.get_ticks_msec()
	var render_time := now - remote_interp_delay_ms
	for peer_id in _remote_buf.keys():
		
		if peer_id == _my_id:
			continue
		if not _players.has(peer_id):
			
			continue

		var buf: Array = _remote_buf[peer_id]
		if buf.is_empty():
			continue
		# Drop snapshots that are definitely older than our render_time
		while buf.size() >= 2 and int(buf[1]["t"]) <= render_time:
			buf.pop_front()

		var p := _players[peer_id]

		if buf.size() == 1:
			# Not enough points to interpolate; just snap to the only sample we have.
			p.global_transform = buf[0]["xform"]
			continue

		var a := buf[0] as Dictionary
		var b := buf[1] as Dictionary
		var ta := int(a["t"])
		var tb := int(b["t"])

		var alpha := 0.0
		if tb > ta:
			alpha = clamp(float(render_time - ta) / float(tb - ta), 0.0, 1.0)

		var xa := a["xform"] as Transform3D
		var xb := b["xform"] as Transform3D
		#dbg_print_if_moved_xz(p)
		if not p:
			print("client error")
		p.global_transform = xa.interpolate_with(xb, alpha)

# ---------- Snapshot storage ----------
func _store_snapshots(snapshots: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	_my_id = multiplayer.get_unique_id()
	for k in snapshots.keys():
		var peer_id := int(k)
		if not _players.has(peer_id):
			continue

		var snap: Dictionary = snapshots[k]

		# Prefer server_tick if you add it later; fallback to last_server_seq
		var snap_id := int(snap.get("server_tick", snap.get("last_server_seq", -1)))

		if peer_id == _my_id:
			#_calculate_offset_for_local_visual(peer_id, snap)
			
			# Local player: keep ONLY newest snapshot
			if snap_id > _latest_local_snapshot_id:
				_latest_local_snapshot_id = snap_id
				_latest_local_snapshot = snap
		else:
			# Remote players: push into a small buffer for interpolation
			if not _remote_buf.has(peer_id):
				_remote_buf[peer_id] = []

			var p := _players[peer_id]
			var xform := _snap_to_xform(snap, p)

			_remote_buf[peer_id].append({
				"t": now,
				"xform": xform,
				"snap": snap
			})

			# Optional: update internal state too (animations, etc.) if apply_snapshot exists.
			# We'll still override transform in interpolation, but internal vars can be useful.
			if p.has_method("apply_snapshot"):
				p.apply_snapshot(snap)

			while _remote_buf[peer_id].size() > remote_buffer_max:
				_remote_buf[peer_id].pop_front()

# ---------- Local reconcile ----------
func _reconcile_local(p: Node, snap: Dictionary, delta : float) -> void:
	# 1) Apply authoritative server state
	if p.has_method("apply_snapshot"):
		p.apply_snapshot(snap)
	else:
		# fallback if you don't have apply_snapshot yet
		p.global_transform = _snap_to_xform(snap, p)

	# 2) Remove inputs server already processed
	var last_server_seq := int(snap.get("last_server_seq", -1))

	var i := 0
	while i < _pending_inputs.size():
		var cmd := _pending_inputs[i] as Dictionary
		var seq := int(cmd.get("seq", -1))

		if seq <= last_server_seq:
			_pending_inputs.remove_at(i)
		else:
			i += 1

	# 3) Replay remaining predicted-but-unconfirmed inputs using FIXED dt
	for cmd in _pending_inputs:
		p.update_player_states(cmd, delta)


func _reconcile_local_best_practice(p: Node3D, snap: Dictionary) -> void:
	# --- A) capture the CURRENT VIEW (what camera should keep seeing) ---
	var old_view_pos := p.global_position + _view_error_pos
	var old_view_yaw := p.rotation.y + _view_error_yaw

	# --- B) apply authoritative snap (server state) ---
	if p.has_method("apply_snapshot"):
		p.apply_snapshot(snap)
	else:
		p.global_transform = _snap_to_xform(snap, p)

	# --- C) drop confirmed inputs ---
	var last_server_seq := int(snap.get("last_server_seq", -1))

	var i := 0
	while i < _pending_inputs.size():
		var seq := int((_pending_inputs[i] as Dictionary).get("seq", -1))
		if seq <= last_server_seq:
			_pending_inputs.remove_at(i)
		else:
			i += 1

	# --- D) replay remaining inputs using FIXED dt (determinism) ---
	for cmd in _pending_inputs:
		p.update_player_states(cmd, _fixed_dt)

	# --- E) set error so the VIEW stays continuous (no snapback) ---
	var new_pred_pos := p.global_position
	var new_pred_yaw := p.rotation.y

	_view_error_pos = old_view_pos - new_pred_pos
	_view_error_yaw = wrapf(old_view_yaw - new_pred_yaw, -PI, PI)

	# Optional: if correction is enormous, snap view too (prevents “rubber band tail”)
	if _view_error_pos.length() > teleport_snap_dist:
		_view_error_pos = Vector3.ZERO
		_view_error_yaw = 0.0

# ---------- Helpers ----------
#func _snap_to_xform(snap: Dictionary, fallback_node: Node) -> Transform3D:
	## Best-case: snapshot already contains a Transform3D
	#if snap.has("global_transform"):
		#return snap["global_transform"] as Transform3D
	#if snap.has("xform"):
		#return snap["xform"] as Transform3D
#
	## Common pattern: pos + basis
	#if snap.has("pos") and snap.has("basis"):
		#return Transform3D(snap["basis"] as Basis, snap["pos"] as Vector3)
#
	## Fallback: keep whatever the node currently has (prevents crashing)
	#if fallback_node != null:
		#return fallback_node.global_transform
#
	#return Transform3D.IDENTITY

func _snap_to_xform(snap: Dictionary, fallback_node: Node3D) -> Transform3D:
	var pos := snap.get("pos", fallback_node.global_position) as Vector3

	# keep current basis (rotation) so interpolation doesn't touch rotation
	var basis := fallback_node.global_transform.basis

	return Transform3D(basis, pos)

func _resolve_players_from_roster() -> void:
	# Build unresolved list first
	for k in GameState.roster.keys():
		var peer_id := int(k)
		var entry := GameState.roster[k] as Dictionary
		var ppath: NodePath = entry.get("player_path", NodePath(""))

		if ppath.is_empty():
			print("Roster peer ", peer_id, " has EMPTY player_path")
			continue

		var node := get_node_or_null(ppath)

		if node != null:
			_players[k] = node

func _calculate_offset_for_local_visual(peer_id : int, snap : Dictionary) -> void:
	var p := _players[peer_id]
	var new_pos : Vector3 = snap["pos"]
	var old_pos : Vector3 = p.global_position
	# 3) compute the correction delta in GLOBAL space
	var delta_global := old_pos - new_pos

	# 4) convert that delta into PLAYER-LOCAL space and accumulate it
	#    (so it behaves correctly even if player rotates)
	var delta_local : Vector3  = p.global_transform.basis.inverse() * delta_global
	_visual_offset += delta_local

func _smooth_local_visual(delta : float) -> void:
	if not _players.has(multiplayer.get_unique_id()):
		return
	# Smoothly remove the local offset back to 0
	var a := 1.0 - pow(0.001, delta * visual_catchup_speed)
	_visual_offset = _visual_offset.lerp(Vector3.ZERO, a)

	# Apply ONLY the local offset to the visual
	var visual : Node = _players[multiplayer.get_unique_id()].get_view_node()
	
	visual.position = _visual_offset

func _smooth_local_view(delta: float) -> void:
	if not _players.has(_my_id):
		return
	var p: Node3D = _players[_my_id]
	if not is_instance_valid(p):
		return

	var view: Node3D = p.get_view_node() # should return Visual/ViewRoot for local owner
	if not is_instance_valid(view):
		return

	# Exponential decay toward 0
	var a := 1.0 - pow(0.001, delta * view_catchup_speed)
	_view_error_pos = _view_error_pos.lerp(Vector3.ZERO, a)
	_view_error_yaw = lerp_angle(_view_error_yaw, 0.0, a)

	# Apply error in GLOBAL space (robust under rotation changes)
	view.global_position = p.global_position + _view_error_pos

	# If your camera uses yaw from the body and you want yaw smoothing too:
	# (only do this if your view node is meant to rotate independently)
	# var r := view.global_rotation
	# r.y = p.global_rotation.y + _view_error_yaw
	# view.global_rotation = r
