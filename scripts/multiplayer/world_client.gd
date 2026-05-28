extends Node
var GameClient := load("res://scripts/multiplayer/game_client.gd")
# --- networking config ---
@export var server_peer_id: int = 1
var _visual_target: Vector3 = Vector3.ZERO
# Name of the RPC on your network endpoint that sends a single input command to the server.
# Change this string to match whatever your server endpoint exposes.
# (Many people use: "receive_network_input" or "receive_client_input" or "sv_receive_input")
@export var input_rpc_name: StringName = &"receive_network_input"
@export var visual_deadzone := 0.05  # try 5–10 cm
# How far "behind" we render remote players for smooth interpolation (ms)
@export var remote_interp_delay_ms: int = 120
@export var remote_buffer_max: int = 10
@export var catchup_speed := 18.0
@export var deadzone := 0.02
@export var snap_dist := 2.5
@export var local_reconcile_deadzone := 0.25
@export var local_reconcile_blend := 0.18
@export var local_reconcile_snap_dist := 3.0
@export var max_prediction_replay_msec: int = 250
@export var max_prediction_replay_inputs: int = 16
@export var show_net_debug_overlay := true
@export var net_debug_ping_interval_sec := 1.0
@export var net_debug_update_interval_sec := 0.25

var proxy : Node3D 
var anchor: Node3D

var _err: Vector3 = Vector3.ZERO
var _t_prev: Transform3D
var _t_curr: Transform3D
var _have := false

# --- assigned/managed externally ---
# You can set this from your World script when players spawn.
var _players: Dictionary[int, Node] = {}  # peer_id -> Player node
# --- local prediction/reconciliation ---
var _pending_inputs: Array[Dictionary] = []   # only for LOCAL player
var _next_input_seq: int = 0

var _latest_local_snapshot: Dictionary = {}   # newest snapshot waiting to reconcile
var _latest_local_snapshot_id: int = -1       # ordering guard (server_tick or last_server_seq)

# --- remote interpolation buffer ---
# peer_id -> Array of { "t": int(ms), "xform": Transform3D, "snap": Dictionary }
var _remote_buf: Dictionary[int, Array] = {}

var _my_id: int = -1
var _fixed_dt: float = 1.0 / 60.0

var _net_debug_layer: CanvasLayer
var _net_debug_root: Control
var _net_debug_label: Label
var _net_debug_ping_accum := 0.0
var _net_debug_ui_accum := 0.0
var _net_debug_ping_ms := -1.0
var _net_debug_last_rtt_ms := -1.0
var _net_debug_jitter_ms := 0.0
var _net_debug_snapshot_jitter_ms := 0.0
var _net_debug_last_snapshot_msec := -1
var _net_debug_pending_inputs := 0
var _net_debug_pending_oldest_ms := 0
var _net_debug_replay_inputs := 0
var _net_debug_correction_m := 0.0
var _net_debug_stale_events := 0
var _net_debug_input_age_ms := 0
var _net_debug_input_stale := false

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
		_view_proxy_setup()
		_camera_setup(ball_path, value.get("joystick_path"))
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

func get_node_track() -> Node3D:
	return _players[multiplayer.get_unique_id()].get_visual_node()

func init(p : Node3D) -> void:
	proxy = p


func _ready() -> void:
	_my_id = multiplayer.get_unique_id()
	var hz := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	_fixed_dt = 1.0 / max(1.0, hz)
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)
	show_net_debug_overlay = bool(Settings.net_indicators)
	_ensure_net_debug_overlay()


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
	
	_reconcile_player(me)

	# 2) Local prediction + send input
	var cmd := _gather_local_command(me)
	if cmd.is_empty():
		print("ERROR: could not gather local input")
		return

	cmd["seq"] = _next_input_seq
	cmd["client_msec"] = Time.get_ticks_msec()
	_next_input_seq += 1

	var stored := cmd.duplicate(true)
	_pending_inputs.append(stored)

	if me.has_method("apply_net_input"):
		me.apply_net_input(stored)
	_predict_position(me, stored, _fixed_dt)
	if not multiplayer.is_server():
		if is_instance_valid(_network_endpoint):
			#print("Sending input seq=", int(stored.get("seq", -1)), " to server_peer_id=", server_peer_id)
			_network_endpoint.rpc_id(server_peer_id, input_rpc_name, stored, _my_id)
		else:
			print("ERROR: _network_endpoint is null/invalid, cannot rpc_id")

	if _pending_inputs.size() > 256:
		_pending_inputs = _pending_inputs.slice(_pending_inputs.size() - 256, _pending_inputs.size())
	_trim_pending_inputs()
	if is_instance_valid(_network_endpoint) and _network_endpoint.has_method("_reset_inputs"):
		_network_endpoint.call("_reset_inputs")


func _process(_delta: float) -> void:
	#_smooth_local_visual(_delta)
	_tick_net_debug(_delta)
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
		if not p:
			return

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
	_track_snapshot_jitter(now, snapshots)
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
				_net_debug_stale_events = int(snap.get("stale_input_events", _net_debug_stale_events))
				_net_debug_input_age_ms = int(snap.get("input_age_ms", _net_debug_input_age_ms))
				_net_debug_input_stale = bool(snap.get("input_stale", _net_debug_input_stale))
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
	_trim_pending_inputs()

	# 3) Replay remaining predicted-but-unconfirmed inputs using FIXED dt
	for cmd in _pending_inputs:
		p.update_player_states(cmd, delta)


func _reconcile_local_best_practice(p: Node3D, snap: Dictionary) -> void:
	var predicted_pos := p.global_position

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
	_trim_pending_inputs()

	# --- D) replay remaining inputs using FIXED dt (determinism) ---
	_net_debug_replay_inputs = _pending_inputs.size()
	for cmd in _pending_inputs:
		if p.has_method("apply_net_input"):
			p.apply_net_input(cmd)
		p.update_player_states(cmd, _fixed_dt)
	var corrected_pos := p.global_position
	var reconcile_error := predicted_pos.distance_to(corrected_pos)
	_net_debug_correction_m = reconcile_error
	if reconcile_error <= local_reconcile_deadzone:
		p.global_position = predicted_pos
	elif reconcile_error < local_reconcile_snap_dist:
		p.global_position = predicted_pos.lerp(corrected_pos, clampf(local_reconcile_blend, 0.0, 1.0))
	_calculate_error_after_reconcile()

func _trim_pending_inputs() -> void:
	var now := Time.get_ticks_msec()
	var cutoff := now - max_prediction_replay_msec

	var i := 0
	while i < _pending_inputs.size():
		var cmd := _pending_inputs[i] as Dictionary
		var sent_msec := int(cmd.get("client_msec", now))
		if sent_msec < cutoff:
			_pending_inputs.remove_at(i)
		else:
			i += 1

	while _pending_inputs.size() > max_prediction_replay_inputs:
		_pending_inputs.pop_front()
	_update_pending_input_metrics(now)

func _update_pending_input_metrics(now: int) -> void:
	_net_debug_pending_inputs = _pending_inputs.size()
	if _pending_inputs.is_empty():
		_net_debug_pending_oldest_ms = 0
		return
	var first := _pending_inputs[0] as Dictionary
	_net_debug_pending_oldest_ms = now - int(first.get("client_msec", now))

func _track_snapshot_jitter(now: int, snapshots: Dictionary) -> void:
	if snapshots.is_empty():
		return
	if _net_debug_last_snapshot_msec >= 0:
		var interval := float(now - _net_debug_last_snapshot_msec)
		var expected := 1000.0 / 30.0
		var sample := absf(interval - expected)
		_net_debug_snapshot_jitter_ms = lerpf(_net_debug_snapshot_jitter_ms, sample, 0.12)
	_net_debug_last_snapshot_msec = now

func record_ping_pong(client_msec: int, _server_msec: int) -> void:
	var now := Time.get_ticks_msec()
	var rtt := maxf(0.0, float(now - client_msec))
	if _net_debug_last_rtt_ms >= 0.0:
		var sample_jitter := absf(rtt - _net_debug_last_rtt_ms)
		_net_debug_jitter_ms = lerpf(_net_debug_jitter_ms, sample_jitter, 0.2)
	_net_debug_last_rtt_ms = rtt
	_net_debug_ping_ms = rtt if _net_debug_ping_ms < 0.0 else lerpf(_net_debug_ping_ms, rtt, 0.25)

func _tick_net_debug(delta: float) -> void:
	var desired_overlay := bool(Settings.net_indicators)
	if show_net_debug_overlay != desired_overlay:
		show_net_debug_overlay = desired_overlay

	if not show_net_debug_overlay:
		if is_instance_valid(_net_debug_root):
			_net_debug_root.visible = false
		return

	_ensure_net_debug_overlay()
	if is_instance_valid(_net_debug_root):
		_net_debug_root.visible = true

	_net_debug_ping_accum += delta
	if _net_debug_ping_accum >= net_debug_ping_interval_sec:
		_net_debug_ping_accum = 0.0
		if not multiplayer.is_server() and is_instance_valid(_network_endpoint):
			_network_endpoint.rpc_id(server_peer_id, "_rpc_net_ping", Time.get_ticks_msec())

	_net_debug_ui_accum += delta
	if _net_debug_ui_accum >= net_debug_update_interval_sec:
		_net_debug_ui_accum = 0.0
		_update_net_debug_overlay()

func _ensure_net_debug_overlay() -> void:
	if not show_net_debug_overlay:
		return
	if is_instance_valid(_net_debug_label):
		return

	_net_debug_layer = CanvasLayer.new()
	_net_debug_layer.name = "NetDebugLayer"
	_net_debug_layer.layer = 500
	add_child(_net_debug_layer)

	_net_debug_root = MarginContainer.new()
	_net_debug_root.name = "NetDebugRoot"
	_net_debug_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_debug_root.anchor_left = 0.0
	_net_debug_root.anchor_top = 0.0
	_net_debug_root.anchor_right = 0.0
	_net_debug_root.anchor_bottom = 0.0
	_net_debug_root.offset_left = 10
	_net_debug_root.offset_top = 10
	_net_debug_root.offset_right = 320
	_net_debug_root.offset_bottom = 150
	_net_debug_layer.add_child(_net_debug_root)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_debug_root.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.72)
	style.border_color = Color(1, 1, 1, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(pad)

	_net_debug_label = Label.new()
	_net_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_debug_label.add_theme_font_size_override("font_size", 13)
	_net_debug_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	_net_debug_label.custom_minimum_size = Vector2(280, 0)
	pad.add_child(_net_debug_label)
	_update_net_debug_overlay()

func _update_net_debug_overlay() -> void:
	if not is_instance_valid(_net_debug_label):
		return

	var ping_text := "--" if _net_debug_ping_ms < 0.0 else "%.0f" % _net_debug_ping_ms
	var stale_text := "yes" if _net_debug_input_stale else "no"
	_net_debug_label.text = "NET TEST\nPing: %s ms | Jitter: %.0f ms\nPending replay: %d (%d ms)\nCorrection: %.2f m | Replayed: %d\nStale input: %d | active: %s | age: %d ms\nSnapshot jitter: %.0f ms" % [
		ping_text,
		_net_debug_jitter_ms,
		_net_debug_pending_inputs,
		_net_debug_pending_oldest_ms,
		_net_debug_correction_m,
		_net_debug_replay_inputs,
		_net_debug_stale_events,
		stale_text,
		_net_debug_input_age_ms,
		_net_debug_snapshot_jitter_ms,
	]

func _calculate_error_after_reconcile() -> void:

	# Call ONCE per reconcile event, after apply snapshot + replay
	if not _have: return

	var base := anchor.global_transform
	var corr := proxy.global_position - base.origin
	var d := corr.length()

	if d < visual_deadzone:
		return
	if d > snap_dist:
		_err = Vector3.ZERO
	else:
		_err += corr * 0.25   # 0.1–0.3 works well
		#_err += corr

func _update_visual_position() -> void:
	# Call from netcode _physics_process
	if not _have: return
	_t_prev = _t_curr
	_t_curr = anchor.global_transform

func _reconcile_player(me : Node) -> void:

	# 1) Reconcile (if snapshot exists)
	if not _latest_local_snapshot.is_empty():
		var snap := _latest_local_snapshot
		_latest_local_snapshot = {}
		#_reconcile_local(me, snap, delta)
		_reconcile_local_best_practice(me, snap)

func _predict_position(me : Node, stored : Dictionary, delta : float) -> void:

	if me.has_method("update_player_states"):
		me.update_player_states(stored, delta)
	else:
		print("ERROR: me has no update_player_states(input, delta)")
		return
	_update_visual_position()

func _gather_local_command(me: Node) -> Dictionary:
	if is_instance_valid(_network_endpoint) and _network_endpoint.has_method("_gather_input"):
		return _network_endpoint.call("_gather_input") as Dictionary
	if me.has_method("get_input_data"):
		return me.get_input_data() as Dictionary
	return {}

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

func _camera_setup(ball_path : NodePath, joystick_path : NodePath) -> void:
	var cam: Camera3D = get_node_or_null("/root/World/Scene/Camera3D") as Camera3D
	var p := _players[multiplayer.get_unique_id()] 
	if cam == null:
		cam = p.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	# Wire camera (existing)
	cam.current = true
	
	if cam.has_method("set_target"): cam.call_deferred("set_target", proxy)
	if cam.has_method("activate"):   cam.call_deferred("activate")
	if cam.has_method("set_ball"):   cam.call_deferred("set_ball", ball_path)

	var joystick : Node = get_node("/root/World/CanvasLayer/UI/JoyStick") 
	# NEW: give the camera its joystick
	if joystick and cam.has_method("set_joystick"):
		cam.call_deferred("set_joystick", joystick)

	# Hand joystick to player (as you already do)
	if p.has_method("attach_camera"):
		p.call_deferred("attach_camera", cam, joystick)

func _view_proxy_setup() -> void:
	anchor = _players[multiplayer.get_unique_id()].get_visual_node()

	if not is_instance_valid(anchor) or not is_instance_valid(proxy):
		_have = false
		return
	_t_prev = anchor.global_transform
	_t_curr = anchor.global_transform
	_visual_target = anchor.global_position
	proxy.global_transform = anchor.global_transform
	_have = true

func _smooth_local_view(delta: float) -> void:
	if not _have:
		return

	var frac := Engine.get_physics_interpolation_fraction()
	var base := _t_prev.interpolate_with(_t_curr, frac)

	var raw_target := base.origin

	# 🔥 Smooth the TARGET itself (this is the missing piece)
	var target_lerp := 1.0 - pow(0.001, delta * 8.0)
	_visual_target = _visual_target.lerp(raw_target, target_lerp)

	var current := proxy.global_transform.origin
	var dist := current.distance_to(_visual_target)

	if dist < visual_deadzone:
		return

	var move_lerp := 1.0 - pow(0.001, delta * catchup_speed)
	var new_pos := current.lerp(_visual_target, move_lerp)

	proxy.global_transform.origin = new_pos
	proxy.global_transform.basis = base.basis
	
func _on_server_disconnected() -> void:
	if get_tree():
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

func _on_connection_failed() -> void:
	if get_tree():
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
