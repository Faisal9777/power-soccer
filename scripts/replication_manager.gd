# replication_manager.gd
class_name ReplicationManager
extends Node

func stop() -> void:
	if not multiplayer.is_server():
		return
	for sync in _get_synchronizers():
		sync.public_visibility = false

func resume() -> void:
	if not multiplayer.is_server():
		return
	for sync in _get_synchronizers():
		sync.public_visibility = true

func _get_synchronizers() -> Array:
	return get_tree().current_scene.find_children("*", "MultiplayerSynchronizer", true, false)
