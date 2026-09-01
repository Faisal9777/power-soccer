extends RigidBody3D
class_name Ball

var _last_player_hits: Array[int] = [-1, -1]

func apply_hit(J: Vector3, position: Vector3, player_id: int) -> void:
	if _last_player_hits.size() > 1 and _last_player_hits[0] != player_id:
		var last_player_id = _last_player_hits[0]
		_last_player_hits[1] = last_player_id

	_last_player_hits[0] = player_id

	# ✅ ADD META HERE (last kicker info)
	# Best practice: only server sets it (bots run on server anyway)
	if multiplayer.is_server():
		set_meta("last_kicker_id", player_id)
		set_meta("last_kicker_team", GameState.get_team(player_id))
		set_meta("last_kick_time_sec", Time.get_ticks_msec() / 1000.0)

	apply_impulse(J, position)

func get_player(last_hit_index: int) -> int:
	if _last_player_hits.size() < 1 or (_last_player_hits.size() < 2 and last_hit_index == 1):
		return -1
	return _last_player_hits[last_hit_index]

func get_snapshot() -> Dictionary:
	return {"global_transform" : global_transform}

func apply_snapshot(snap):
	global_transform = snap.get("global_transform")

func stop_replication() -> void:
	$MultiplayerSynchronizer.public_visibility = false

func _physics_process(delta: float) -> void:
	# Enable CCD only when the ball is moving fast (prevents tunneling through walls)
	var speed := linear_velocity.length()
	continuous_cd = speed > 18.0  # tune this threshold
	


# --- DEBUG: sync test, remove after diagnosing reconnect issue ---
var debug_counter: int = 0:
	set(value):
		debug_counter = value
		if not multiplayer.is_server():
			print("[sync test] peer_id=", multiplayer.get_unique_id(),
				" debug_counter arrived: ", value, " at t=", Time.get_ticks_msec())

func _debug_tick_counter() -> void:
	print("[sync test] peer_id=", multiplayer.get_unique_id(),
				" path of the ball is: ", get_path())
	if multiplayer.is_server():
		debug_counter += 1
# --- END DEBUG ---
