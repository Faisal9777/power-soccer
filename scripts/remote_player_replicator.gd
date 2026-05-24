class_name RemotePlayerReplicator
extends Controller

# =========================================================
# SNAPSHOT BUFFER
# =========================================================
var _snapshot_queue: Array[Dictionary] = []
var remote_buffer_max: int = 10
var remote_interp_delay_ms: int = 120

# =========================================================
# INIT
# =========================================================
func _init(target_player: Node3D, p_name, p_id, team_name) -> void:
	super._init(target_player, p_name, p_id, team_name)



# =========================================================
# SERVER PUSHES SNAPSHOTS HERE
# =========================================================
func store_snapshot(snap: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var xform := _snap_to_xform(snap, player)

	_snapshot_queue.append({
		"t": now,
		"xform": xform,
		"snap": snap
	})

	# Optional: update internal state too (animations, etc.) if apply_snapshot exists.
	# We'll still override transform in interpolation, but internal vars can be useful.
	if player.has_method("apply_snapshot"):
		player.apply_snapshot(snap)

	while _snapshot_queue.size() > remote_buffer_max:
		_snapshot_queue.pop_front()



# =========================================================
# CALLED EVERY FRAME/TICK
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

	# Remote interpolation runs every render frame for smoothness
	var now := Time.get_ticks_msec()
	var render_time := now - remote_interp_delay_ms

	if _snapshot_queue.is_empty():
		return
	# Drop snapshots that are definitely older than our render_time
	while _snapshot_queue.size() >= 2 and int(_snapshot_queue[1]["t"]) <= render_time:
		_snapshot_queue.pop_front()

	if _snapshot_queue.size() == 1:
		# Not enough points to interpolate; just snap to the only sample we have.
		player.global_transform = _snapshot_queue[0]["xform"]
		return

	var a := _snapshot_queue[0] as Dictionary
	var b := _snapshot_queue[1] as Dictionary
	var ta := int(a["t"])
	var tb := int(b["t"])

	var alpha := 0.0
	if tb > ta:
		alpha = clamp(float(render_time - ta) / float(tb - ta), 0.0, 1.0)

	var xa := a["xform"] as Transform3D
	var xb := b["xform"] as Transform3D
	#dbg_print_if_moved_xz(p)
	if not player:
		print("client error")
	player.global_transform = xa.interpolate_with(xb, alpha)
