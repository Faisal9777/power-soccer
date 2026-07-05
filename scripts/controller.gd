class_name Controller
extends RefCounted

var is_frozen = true
var look_yaw := 0.0
var look_pitch := 0.0
var player : Node
var id : int = -1
var name : String
var team : int

func freeze(toggle) -> void:
	is_frozen = toggle

func face_at(pos : Vector3) -> void:
	var dir : Vector3 = (pos - player.global_position).normalized()

	look_yaw = atan2(-dir.x, -dir.z)

	var flat_len := Vector2(dir.x, dir.z).length()
	look_pitch = atan2(dir.y, flat_len)

	player.set_look_rotation(look_yaw, look_pitch)

func set_position(gb_transform : Transform3D) -> void:
	player.global_transform = gb_transform

func get_body_mesh() -> MeshInstance3D:
	return player.body_mesh

func process_tick(delta: float) -> void:
	return

func stop_replication():
	player.stop_replication()

func _init(target_player: Node3D, p_name, p_id, team_name) -> void:
	player = target_player
	name = p_name
	id = p_id
	team = team_name

func _snap_to_xform(snap: Dictionary, fallback_node: Node3D) -> Transform3D:
	var pos := snap.get("pos", fallback_node.global_position) as Vector3

	# keep current basis (rotation) so interpolation doesn't touch rotation
	var basis := fallback_node.global_transform.basis

	return Transform3D(basis, pos)
