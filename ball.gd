extends RigidBody3D
class_name Ball
#
#func _ready() -> void:
	#contact_monitor = true
	#max_contacts_reported = 16
	#print("[Ball] ready; contact monitor on.")
#
var _last_player_hits: Array[int] = [-1, -1]
func apply_hit(J : Vector3, position : Vector3, player_id : int) -> void:
	if _last_player_hits.size() > 1:
		var last_player_id = _last_player_hits[0]
		_last_player_hits[1] = last_player_id

	_last_player_hits[0] = player_id
	apply_impulse(J,  position)

func get_player(last_hit_index : int) -> int:
	if _last_player_hits.size() < 1 or _last_player_hits.size() < 2 and last_hit_index == 1:
		return -1
	return _last_player_hits[last_hit_index]
