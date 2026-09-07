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

	# Render a few server ticks behind the newest authoritative state.
	var render_tick := _latest_server_tick - REMOTE_INTERP_DELAY_TICKS

	# -----------------------------------------------------
	# Remove snapshots that are definitely behind us.
	# Keep one snapshot before render_tick.
	# -----------------------------------------------------

	while _snapshot_queue.size() >= 2:
		var next_tick := int(_snapshot_queue[1]["tick"])

		if next_tick <= render_tick:
			_snapshot_queue.pop_front()
		else:
			break

	# -----------------------------------------------------
	# We have two snapshots -> interpolate.
	# -----------------------------------------------------

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

		var target_transform := xa.interpolate_with(xb, alpha)

		_apply_visual_position(target_transform.origin, delta)

		# Rotation is also interpolated using server state.
		var snap_a: Dictionary = a["snap"]
		var snap_b: Dictionary = b["snap"]

		var yaw_a := float(snap_a.get("yaw", 0.0))
		var yaw_b := float(snap_b.get("yaw", yaw_a))

		var pitch_a := float(snap_a.get("pitch", 0.0))
		var pitch_b := float(snap_b.get("pitch", pitch_a))

		look_yaw = lerp_angle(yaw_a, yaw_b, alpha)
		look_pitch = lerp(pitch_a, pitch_b, alpha)

		player.set_look_rotation(look_yaw, look_pitch)

		if snap_b.has("vel"):
			player.velocity = snap_b["vel"]

		return

	# -----------------------------------------------------
	# Only one snapshot available.
	#
	# Don't immediately teleport to it.
	# Use a very short server-tick extrapolation.
	# -----------------------------------------------------

	var s := _snapshot_queue[0] as Dictionary
	var snap: Dictionary = s["snap"]

	var snapshot_tick := int(s["tick"])
	var ticks_since_snapshot = max(
		0,
		_latest_server_tick - snapshot_tick
	)

	var ideal_pos := (s["xform"] as Transform3D).origin

	if (
		not bool(snap.get("is_frozen", false))
		and ticks_since_snapshot <= extrapolation_cap_ticks
		and snap.has("vel")
	):
		var physics_hz := float(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second"
			)
		)

		var dt := 1.0 / maxf(physics_hz, 1.0)

		ideal_pos += (
			snap["vel"] as Vector3
		) * (ticks_since_snapshot * dt)

	_apply_visual_position(ideal_pos, delta)

# =========================================================
# SMALL VISUAL CORRECTION
# =========================================================

func _apply_visual_position(
	ideal_pos: Vector3,
	delta: float
) -> void:

	var a := 1.0 - pow(
		0.001,
		delta * error_catchup_speed
	)

	_visual_err = _visual_err.lerp(
		Vector3.ZERO,
		a
	)

	player.global_position = ideal_pos + _visual_err
