extends RigidBody3D
class_name Ball

var _last_player_hits: Array[int] = [-1, -1]

var latched := false
var latched_to: Node3D = null

func latch_to_keeper(keeper: Node3D) -> void:
	if latched:
		return

	latched = true
	latched_to = keeper

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true

func unlatch() -> void:
	latched = false
	latched_to = null
	sleeping = false

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

func _physics_process(delta: float) -> void:
	if latched and is_instance_valid(latched_to):
		global_transform.origin = latched_to.global_transform.origin + Vector3(0, 1.0, 0)
		return

	# Enable CCD only when the ball is moving fast (prevents tunneling through walls)
	var speed := linear_velocity.length()
	continuous_cd = speed > 18.0  # tune this threshold
