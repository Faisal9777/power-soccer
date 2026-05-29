extends Node
class_name AbilityVisualController

var active_visuals := {}


@rpc("authority", "call_local", "reliable")
func rpc_spawn_visual(
	visual_id: String,
	scene_path: String,
	data := {}
):
	_remove_visual_internal(visual_id)

	var scene: PackedScene = load(scene_path)

	if scene == null:
		push_error("Failed to load visual scene: " + scene_path)
		return

	var visual = scene.instantiate()

	get_tree().current_scene.add_child(visual)

	active_visuals[visual_id] = visual

	if visual.has_method("setup"):
		visual.setup(data)


@rpc("authority", "call_local", "reliable")
func rpc_remove_visual(visual_id: String):
	_remove_visual_internal(visual_id)


func _remove_visual_internal(visual_id: String):
	if !active_visuals.has(visual_id):
		return

	var visual = active_visuals[visual_id]

	if is_instance_valid(visual):
		visual.queue_free()

	active_visuals.erase(visual_id)
