class_name RemotePlayerReplicator
extends Controller

# =========================================================
# SNAPSHOT BUFFER
# =========================================================
var _snapshot_queue: Array[Dictionary] = []
var remote_buffer_max: int = 10
var remote_interp_delay_ms: int = 120
var _latest_server_tick: int = -1

# =========================================================
# INIT
# =========================================================
func _init(target_player: Node3D, p_name, p_id, team_name) -> void:
	super._init(target_player, p_name, p_id, team_name)



# =========================================================
# SERVER PUSHES SNAPSHOTS HERE
# =========================================================
func store_snapshot(snap: Dictionary) -> void:
	var server_tick := int(snap.get("server_tick", -1))
	if server_tick <= _latest_server_tick:
		return
	_latest_server_tick = server_tick
	var now := Time.get_ticks_msec()
	var xform := _snap_to_xform(snap, player)

	_snapshot_queue.append({
		"t": now,
		"xform": xform,
		"snap": snap
	})

	# Optional: update internal state too (animations, etc.) if apply_snapshot exists.
	# We'll still override transform in interpolation, but internal vars can be useful.
	while _snapshot_queue.size() > remote_buffer_max:
		_snapshot_queue.pop_front()



# =========================================================
# CALLED EVERY FRAME/TICK
# =========================================================
func process_tick(delta: float) -> void:
	if not is_instance_valid(player) or _snapshot_queue.is_empty():
		return

	var now := Time.get_ticks_msec()
	var render_time := now - remote_interp_delay_ms

	# Drop snapshots that are older than render_time, keeping the bounding pair
	while _snapshot_queue.size() >= 2 and int(_snapshot_queue[1]["t"]) <= render_time:
		_snapshot_queue.pop_front()

	if _snapshot_queue.size() == 1:
		var s := _snapshot_queue[0]
		player.global_transform = s["xform"]
		var snap: Dictionary = s["snap"]
		look_yaw = snap.get("yaw", look_yaw)
		look_pitch = snap.get("pitch", look_pitch)
		player.set_look_rotation(look_yaw, look_pitch)
		if snap.has("vel"):
			player.velocity = snap["vel"]
		return

	var a := _snapshot_queue[0] as Dictionary
	var b := _snapshot_queue[1] as Dictionary
	var ta := int(a["t"])
	var tb := int(b["t"])
	var alpha := 0.0
	if tb > ta:
		alpha = clampf(float(render_time - ta) / float(tb - ta), 0.0, 1.0)
	else:
		alpha = 1.0

	var xa := a["xform"] as Transform3D
	var xb := b["xform"] as Transform3D
	player.global_transform = xa.interpolate_with(xb, alpha)

	var snap_a: Dictionary = a["snap"]
	var snap_b: Dictionary = b["snap"]
	var yaw_a: float = snap_a.get("yaw", 0.0)
	var yaw_b: float = snap_b.get("yaw", 0.0)
	var pitch_a: float = snap_a.get("pitch", 0.0)
	var pitch_b: float = snap_b.get("pitch", 0.0)

	look_yaw = lerp_angle(yaw_a, yaw_b, alpha)
	look_pitch = lerp(pitch_a, pitch_b, alpha)
	player.set_look_rotation(look_yaw, look_pitch)

	if snap_b.has("vel"):
		player.velocity = snap_b["vel"]
