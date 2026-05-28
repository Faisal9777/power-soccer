extends LocalController
class_name PlayerController

signal on_reconciled(new_position)
signal on_predicted(new_position)

var network : Node

var _latest_local_snapshot: Dictionary = {}   # newest snapshot waiting to reconcile
var _latest_local_snapshot_id: int = -1       # ordering guard (server_tick or last_server_seq)
var _pending_inputs: Array[Dictionary] = []   # only for LOCAL player
var _fixed_dt: float = 1.0 / 60.0
var _next_input_seq := -1

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
	var snap_id := int(snap.get("server_tick", snap.get("last_server_seq", -1)))
	#_calculate_offset_for_local_visual(peer_id, snap)
	
	# Local player: keep ONLY newest snapshot
	if snap_id > _latest_local_snapshot_id:
		_latest_local_snapshot_id = snap_id
		_latest_local_snapshot = snap

func _init(p_player, pid, p_name, team_name, c_cam, joystick, net, i_buffer : LocalInputBuffer):
	network = net
	super._init(p_player, pid, p_name, team_name, c_cam, joystick, i_buffer)

func _process_interval():
	var value := {"inputs" : _pending_inputs}
	network.submit_input(value)

func physics_tick(delta: float) -> void:
	if can_process:
		_reconcile_player(player)
		process_input(delta)

func process_input(delta):
	if is_frozen:
		return
	var input = input_buffer.get_input()
	_next_input_seq += 1

	var stored := input.duplicate(true)
	stored["seq"] = _next_input_seq
	_pending_inputs.append(stored)
	_apply_inputs(input, delta)
	if _pending_inputs.size() > 256:
		_pending_inputs = _pending_inputs.slice(_pending_inputs.size() - 256, _pending_inputs.size())
	
	on_predicted.emit(player.global_transform)

func _reconcile_player(me : Node) -> void:

	# 1) Reconcile (if snapshot exists)
	if not _latest_local_snapshot.is_empty():
		var snap := _latest_local_snapshot
		_latest_local_snapshot = {}
		#_reconcile_local(me, snap, delta)
		_reconcile_local_best_practice(me, snap)


func _reconcile_local_best_practice(p: Node3D, snap: Dictionary) -> void:

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
		_apply_inputs(cmd, _fixed_dt)
	on_reconciled.emit(player.global_transform)
