class_name RemotePlayerReplicator
extends Controller

# =========================================================
# SERVER-TICK SNAPSHOT BUFFER
# =========================================================

var _snapshot_queue: Array[Dictionary] = []

const REMOTE_INTERP_DELAY_TICKS := 3
const MAX_SNAPSHOT_BUFFER := 12

var _latest_server_tick: int = -1

# Used only for small visual correction.
var _visual_err: Vector3 = Vector3.ZERO

@export var extrapolation_cap_ticks: int = 8
@export var error_catchup_speed: float = 18.0
@export var error_snap_dist: float = 3.0

func _init(target_player: Node3D, p_name, p_id, team_name) -> void:
	super._init(target_player, p_name, p_id, team_name)

# =========================================================
# RECEIVE SERVER SNAPSHOT
# =========================================================

func store_snapshot(snap: Dictionary) -> void:
	var server_tick := int(snap.get("server_tick", -1))

	if server_tick < 0:
		return

	# Never allow old packets to rewind the buffer.
	if server_tick <= _latest_server_tick:
		return

	_latest_server_tick = server_tick

	var xform := _snap_to_xform(snap, player)

	_snapshot_queue.append({
		"tick": server_tick,
		"xform": xform,
		"snap": snap
	})

	# Keep the buffer bounded.
	while _snapshot_queue.size() > MAX_SNAPSHOT_BUFFER:
		_snapshot_queue.pop_front()

# =========================================================
# REMOTE PLAYER RENDERING
# =========================================================

func process_tick(delta: float) -> void:
	if not is_instance_valid(player):
		return

	if _snapshot_queue.is_empty():
		return

	var snapshot : Dictionary= _snapshot_queue.pop_front()

	_apply_snapshot(snapshot, delta)



# =========================================================
# APPLY AUTHORITATIVE STATE
# =========================================================
func _apply_snapshot(snapshot: Dictionary, delta: float) -> void:
	var snap = snapshot.get("snap")
	# Remote interpolation runs every render frame for smoothness
	var now := Time.get_ticks_msec()
	var render_time := now - remote_interp_delay_ms

	if _snapshot_queue.is_empty():
		return
	# Drop snapshots that are definitely older than our render_time
	while _snapshot_queue.size() >= 2 and int(_snapshot_queue[1]["t"]) <= render_time:
		_snapshot_queue.pop_front()

	if _snapshot_queue.size() >= 2:
		var a := _snapshot_queue[0] as Dictionary
		var b := _snapshot_queue[1] as Dictionary

		var tick_a := int(a["tick"])
		var tick_b := int(b["tick"])

		var alpha := 0.0

		if tick_b > tick_a:
			alpha = clampf(
				float(render_tick - tick_a) /
				float(tick_b - tick_a),
				0.0,
				1.0
			)

	var xa := a["xform"] as Transform3D
	var xb := b["xform"] as Transform3D
	#dbg_print_if_moved_xz(p)
	if not player:
		print("client error")
	snap["global_transform"] = xa.interpolate_with(xb, alpha)
	player.apply_snapshot(snap)
