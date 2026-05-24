# GameInitializer.gd
class_name GameInitializer
extends RefCounted

static func setup_match(player: Node3D, proxy: Node3D, camera: Node3D, spawn_pos: Vector3) -> void:
	player.global_position = spawn_pos

	proxy.global_transform = player.global_transform

	if proxy.has_method("snap_to"):
		proxy.snap_to(player.global_transform)

	camera.global_position = proxy.global_position
