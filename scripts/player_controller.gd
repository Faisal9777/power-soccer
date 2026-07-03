extends LocalController
class_name PlayerController

signal on_reconciled(new_position)
signal on_predicted(new_position)

var network : Node
var _next_input_seq : int = 0
var _latest_local_snapshot: Dictionary = {}   # newest snapshot waiting to reconcile
var _latest_local_snapshot_id: int = -1       # ordering guard (server_tick or last_server_seq)
var _pending_inputs: Array[Dictionary] = []   # only for LOCAL player
var _fixed_dt: float = 1.0 / 60.0

var local_reconcile_deadzone := 0.25
var local_reconcile_blend := 0.18
var local_reconcile_snap_dist := 3.0
var max_prediction_replay_msec: int = 500
var max_prediction_replay_inputs: int = 40

var send_interval := 1.0 / 20.0  # 20 Hz
var send_accumulator := 0.0
var can_process := false
var task_id := 0

func start_process() -> void:
	can_process = true
	task_id = TaskScheduler.schedule(20, _process_interval)

func stop_process() -> void:
	can_process = false
	TaskScheduler.cancel(task_id)

func store_snapshot(snap) -> void:
	if GameState.is_paused:
		return
	var seq = snap.get("seq", snap.get("last_server_seq", -1))
	if not seq:
		return
	var snap_id := int(seq)
	#_calculate_offset_for_local_visual(peer_id, snap)
	# Local player: keep ONLY newest snapshot
	if snap_id >= _latest_local_snapshot_id:
		_latest_local_snapshot_id = snap_id
		_latest_local_snapshot = snap
	

func _init(p_player, pid, p_name, team_name, c_cam, ball, joystick, net, i_buffer : LocalInputBuffer):
	network = net
	super._init(p_player, pid, p_name, team_name, c_cam, ball, joystick, i_buffer)

func _process_interval():
	if GameState.is_paused:
		return
	var value := {"inputs" : _pending_inputs.duplicate()}
	print("SENDING:", value)
	if _pending_inputs.size() > 0:
		_next_input_seq = _pending_inputs.duplicate()[0]["seq"] + 1
	network.submit_input(value)

func physics_tick(delta: float) -> void:
	if Input.is_action_pressed("debug"):
		print("position of the player: ", player.global_position)
	if can_process:
		_reconcile_player(player)
		process_input(delta)

func process_input(delta):
	if GameState.is_paused:
		return
	var input = input_buffer.get_input()
	_apply_inputs(input, delta)
	input["yaw"] = look_yaw
	input["pitch"] = look_pitch
	input["client_msec"] = Time.get_ticks_msec()
	var stored := input.duplicate(true)
	_pending_inputs.append(stored)
	_trim_pending_inputs()
	
	on_predicted.emit(player.global_transform)

func _reconcile_player(me : Node) -> void:
	if GameState.is_paused:
		return
	# 1) Reconcile (if snapshot exists)
	if not _latest_local_snapshot.is_empty():
		var snap := _latest_local_snapshot
		_latest_local_snapshot = {}
		#_reconcile_local(me, snap, delta)
		_reconcile_local_best_practice(me, snap)


func _reconcile_local_best_practice(p: Node3D, snap: Dictionary) -> void:

	# --- B) apply authoritative snap (server state) ---
	var predicted_pos := p.global_position
	if p.has_method("apply_snapshot"):
		
		p.apply_snapshot(snap)
	else:
		p.global_transform = _snap_to_xform(snap, p)
	freeze(snap["is_frozen"])
	# --- C) drop confirmed inputs ---
	var last_server_seq := int(snap.get("seq", -1))
	var i := 0
	while i < _pending_inputs.size():
		var seq := int((_pending_inputs[i] as Dictionary).get("seq", -1))
		if seq <= last_server_seq:
			_pending_inputs.remove_at(i)
		else:
			i += 1
	_trim_pending_inputs()

	# --- D) replay remaining inputs using FIXED dt (determinism) ---
	for cmd in _pending_inputs:
		_apply_inputs(cmd, _fixed_dt)
		
	var corrected_pos := p.global_position
	var reconcile_error := predicted_pos.distance_to(corrected_pos)
	if reconcile_error <= local_reconcile_deadzone:
		p.global_position = predicted_pos
	elif reconcile_error < local_reconcile_snap_dist:
		p.global_position = predicted_pos.lerp(corrected_pos, clampf(local_reconcile_blend, 0.0, 1.0))
		
	on_reconciled.emit(player.global_transform)

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
