class_name RemotePlayerReplicator
extends Controller

# =========================================================
# SNAPSHOT BUFFER
# =========================================================
var _snapshot_queue: Array[Dictionary] = []
var remote_buffer_max: int = 10
var remote_interp_delay_ms: int = 33
var _latest_server_tick: int = -1

var _visual_err: Vector3 = Vector3.ZERO
var _was_extrapolating: bool = false

@export var extrapolation_cap_ms: int = 200   # freeze, don't guess forever
@export var error_catchup_speed: float = 18.0 # same idea as proxy_follower's catchup_speed
@export var error_snap_dist: float = 3.0      # beyond this, hard snap (goal reset, respawn, etc.)

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
		#var s := _snapshot_queue[0]
		#player.global_transform = s["xform"]
		#var snap: Dictionary = s["snap"]
		#look_yaw = snap.get("yaw", look_yaw)
		#look_pitch = snap.get("pitch", look_pitch)
		#player.set_look_rotation(look_yaw, look_pitch)
		#if snap.has("vel"):
			#player.velocity = snap["vel"]
		#return
		var s := _snapshot_queue[0]
		var snap: Dictionary = s["snap"]
		var elapsed_ms := now - int(s["t"])
		var ideal_pos := (s["xform"] as Transform3D).origin

		if not bool(snap.get("is_frozen", false)) and elapsed_ms <= extrapolation_cap_ms and snap.has("vel"):
			var t := elapsed_ms / 1000.0
			ideal_pos += (snap["vel"] as Vector3) * t
			
			# optional refinement, see below
		# past the cap, or frozen, or no vel → ideal_pos just stays at the last known point (same as today)

		_apply_visual_position(ideal_pos, delta)
		_was_extrapolating = true
		# rotation: no angular velocity is sent, so just hold last known yaw/pitch as you do today
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

func _apply_visual_position(ideal_pos: Vector3, delta: float) -> void:
	var a := 1.0 - pow(0.001, delta * error_catchup_speed)
	_visual_err = _visual_err.lerp(Vector3.ZERO, a)
	player.global_position = ideal_pos + _visual_err
