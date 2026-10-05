extends LocalController
class_name PlayerController

signal on_reconciled(error_delta, new_position, is_bursting)
signal on_predicted(new_position)

var network : Node
var _latest_local_snapshot: Dictionary = {}   # newest snapshot waiting to reconcile
var _latest_local_snapshot_id: int = -1       # ordering guard (server_tick or last_server_seq)
var _fixed_dt: float = 1.0 / 60.0
var _scheduler : JobScheduler
var _task : Node

const INPUT_SEND_HZ := 60.0
var send_interval := 1.0 / INPUT_SEND_HZ

var send_accumulator := 0.0
var task_id := 0
var _truncated_up_to_seq: int = -1   # last seq WE discarded via the size cap (not server-skipped)

func start_process() -> void:
	can_process = true
	_task = _scheduler.schedule_repeating(_process_interval, send_interval)

func stop_process() -> void:
	can_process = false
	_scheduler.cancel(_task)

func store_snapshot(snap) -> void:
	var seq = snap.get("seq", snap.get("last_server_seq", -1))
	if not seq:
		return
	var snap_id := int(seq)
	#_calculate_offset_for_local_visual(peer_id, snap)
	# Local player: keep ONLY newest snapshot
	if snap_id >= _latest_local_snapshot_id:
		_latest_local_snapshot_id = snap_id
		_latest_local_snapshot = snap
	

func _init(p_player, pid, p_name, team_name, c_cam, ball, joystick, net, i_buffer : LocalInputBuffer, 
scheduler : JobScheduler):
	_scheduler = scheduler
	network = net
	var hz := float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	_fixed_dt = 1.0 / maxf(hz, 1.0)
	super._init(p_player, pid, p_name, team_name, c_cam, ball, joystick, i_buffer)

func _process_interval():
	if GameState.is_paused:
		return
	#print("[pending] size=", _pending_inputs.size(), " t=", Time.get_ticks_msec())
	network.submit_input(_pending_inputs.duplicate())

func physics_tick(delta: float) -> void:
	if can_process:
		if is_instance_valid(player):
			_reconcile_player(player)
			super.physics_tick(delta)


func process_input(delta):
	if GameState.is_paused:
		return

	var input = input_buffer.get_input()

	if is_mobile and is_instance_valid(joystick):
		input["mvx"] = joystick.vector.x
		input["mvz"] = joystick.vector.y
		input["move_magnitude"] = joystick.mag

		# Get camera orientation BEFORE movement prediction.
		if is_instance_valid(cam):
			look_yaw = cam.get_cam_yaw()
			look_pitch = cam.get_cam_pitch()

		input["yaw"] = look_yaw
		input["pitch"] = look_pitch
	else:
		input["move_magnitude"] = 1.0

	_apply_inputs(input, delta)

	if not input.has("yaw"):
		input["yaw"] = look_yaw
		input["pitch"] = look_pitch

	_next_input_seq = int(input["seq"]) + 1
	var stored := input.duplicate(true)
	_pending_inputs.append(stored)

	if _pending_inputs.size() > 100:
		var cutoff := _pending_inputs.size() - 100
		_truncated_up_to_seq = int((_pending_inputs[cutoff - 1] as Dictionary).get("seq", _truncated_up_to_seq))
		_pending_inputs = _pending_inputs.slice(cutoff, _pending_inputs.size())

	on_predicted.emit(player.global_transform)

func _reconcile_player(me : Node) -> void:
	if not _latest_local_snapshot.is_empty():
		var snap := _latest_local_snapshot
		_latest_local_snapshot = {}
		_reconcile_local_best_practice(me, snap)


# player_controller.gd — in _reconcile_local_best_practice(), right after freeze(snap["is_frozen"])
func _reconcile_local_best_practice(p: Node3D, snap: Dictionary) -> void:
	# --- B) apply authoritative snap (server state) ---
	if p.has_method("apply_snapshot"):
		p.apply_snapshot(snap)
	else:
		p.global_transform = _snap_to_xform(snap, p)
	freeze(snap["is_frozen"])

	look_yaw = snap.get("yaw", look_yaw)
	look_pitch = snap.get("pitch", look_pitch)

	var last_server_seq := int(snap.get("seq", -1))

	var i := 0
	while i < _pending_inputs.size():
		var seq := int((_pending_inputs[i] as Dictionary).get("seq", -1))
		if seq <= last_server_seq:
			_pending_inputs.remove_at(i)
		else:
			i += 1
	for cmd in _pending_inputs:
		_apply_inputs(cmd, _fixed_dt)

	if is_mobile and is_instance_valid(cam):
		look_yaw = cam.get_cam_yaw()
		look_pitch = cam.get_cam_pitch()

	#on_reconciled.emit(player.global_transform)
func set_paused(state: bool) -> void:
	super.set_paused(state)
