extends LocalController
class_name PlayerController

signal on_reconciled(error_delta, new_position)
signal on_predicted(new_position)

var network : Node
var _next_input_seq : int = 0
var _latest_local_snapshot: Dictionary = {}   # newest snapshot waiting to reconcile
var _latest_local_snapshot_id: int = -1       # ordering guard (server_tick or last_server_seq)
var _pending_inputs: Array[Dictionary] = []   # only for LOCAL player
var _fixed_dt: float = 1.0 / 60.0
var _scheduler : JobScheduler
var _task : Node
var send_interval := 1.0 / 20.0  # 20 Hz
var send_accumulator := 0.0
var can_process := false
var task_id := 0

func start_process() -> void:
	can_process = true
	_task = _scheduler.schedule_repeating(_process_interval, 1.0 / 20.0)

func stop_process() -> void:
	can_process = false
	_scheduler.cancel(_task)

func store_snapshot(snap) -> void:
	if not snap.has("server_tick") or not snap.has("ack_input_seq"):
		return
	var server_tick := int(snap["server_tick"])
	# Strict ordering prevents late or duplicate authoritative state from rewinding us.
	if server_tick > _latest_local_snapshot_id:
		_latest_local_snapshot_id = server_tick
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
	var value := {"inputs" : _pending_inputs.duplicate()}
	network.submit_input(value)

func physics_tick(delta: float) -> void:
	if Input.is_action_pressed("debug"):
		print("position of the player: ", player.global_position)
	if can_process:
		if is_instance_valid(player):
			_reconcile_player(player)
			process_input(_fixed_dt)

func process_input(delta):
	if GameState.is_paused:
		return
	var input = input_buffer.get_input()
	if is_mobile and is_instance_valid(joystick):
		input["mvx"] = joystick.vector.x
		input["mvz"] = joystick.vector.y
		input["move_magnitude"] = joystick.mag
	else:
		input["move_magnitude"] = 1.0
	_apply_inputs(input, delta)
	# On mobile, _yaw/_pitch live on the camera (touch drag writes there directly,
	# safe from reconciliation). Read them back so the server gets the real orientation.
	if is_mobile and is_instance_valid(cam):
		look_yaw = cam.get_cam_yaw()
		look_pitch = cam.get_cam_pitch()
	input["yaw"] = look_yaw
	input["pitch"] = look_pitch
	_next_input_seq = int(input["seq"]) + 1
	var stored := input.duplicate(true)
	_pending_inputs.append(stored)
	if _pending_inputs.size() > 256:
		_pending_inputs = _pending_inputs.slice(_pending_inputs.size() - 256, _pending_inputs.size())

	on_predicted.emit(player.global_transform)

func _reconcile_player(me : Node) -> void:
	if not _latest_local_snapshot.is_empty():
		var snap := _latest_local_snapshot
		_latest_local_snapshot = {}
		_reconcile_local_best_practice(me, snap)


# player_controller.gd — in _reconcile_local_best_practice(), right after freeze(snap["is_frozen"])
func _reconcile_local_best_practice(p: Node3D, snap: Dictionary) -> void:
	var pre_reconcile_origin: Vector3 = p.global_position

	if p.has_method("apply_snapshot"):
		p.apply_snapshot(snap)
	else:
		p.global_transform = _snap_to_xform(snap, p)
	freeze(snap["is_frozen"])

	# look_yaw/pitch drive the facing replay below — reset
	# them to the server's authoritative value here, same as position above.
	look_yaw = snap.get("yaw", look_yaw)
	look_pitch = snap.get("pitch", look_pitch)

	var ack_input_seq := int(snap.get("ack_input_seq", -1))
	var i := 0
	while i < _pending_inputs.size():
		var seq := int((_pending_inputs[i] as Dictionary).get("seq", -1))
		if seq <= ack_input_seq:
			_pending_inputs.remove_at(i)
		else:
			i += 1
	_pending_inputs.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["seq"]) < int(b["seq"]))
	for cmd in _pending_inputs:
		_apply_inputs(cmd, _fixed_dt)

	# After replaying stored inputs, look_yaw/look_pitch reflect the last stored snapshot value.
	# On mobile, the camera owns the live orientation — restore it so the next process_input
	# records the correct current camera direction, not a stale replayed one.
	if is_mobile and is_instance_valid(cam):
		look_yaw = cam.get_cam_yaw()
		look_pitch = cam.get_cam_pitch()

	var post_reconcile_origin: Vector3 = p.global_position
	var error_delta: Vector3 = pre_reconcile_origin - post_reconcile_origin
	on_reconciled.emit(error_delta, player.global_transform)
	
func set_paused(state: bool) -> void:
	super.set_paused(state)
