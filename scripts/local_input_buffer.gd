extends InputBuffer
class_name LocalInputBuffer
var should_listen := true
var _mouse_input : InputSource

## Reference to the World node so we can consume edge-latch action flags.
## Set this from world_client.gd (or wherever PlayerController is created)
## right after constructing LocalInputBuffer.
var world_node : Node = null

func get_action_strength(action) -> float:
	if should_listen:
		return Input.get_action_strength(action)
	return 0

func is_action_pressed(action) -> bool:
	if should_listen:
		return Input.is_action_pressed(action)
	return false

func _init(mouse_input) -> void:
	_mouse_input = mouse_input

func _get_input() -> Dictionary:
	var shoot_action := "shoot_touch" if OS.has_feature("mobile") else "shoot"

	# --- Read and consume edge-latched action flags from World ---
	# These are set by world.gd::_update_inputs() each physics tick.
	# We must clear them here so each edge event is only sent once.
	var jump_pressed       := false
	var tackle_pressed     := false
	var stop_ball_pressed  := false
	var shoot_up           := false
	var latch_toggle       := false
	var assist_pass        := false
	var ability_toggle     := false
	var ability_a1         := false
	var ability_a2         := false
	var ability_a3         := false
	var cam_yaw            := 0.0

	if is_instance_valid(world_node):
		jump_pressed       = bool(world_node.get("jump_edge_latched"))
		tackle_pressed     = bool(world_node.get("tackle_edge_latched"))
		stop_ball_pressed  = bool(world_node.get("stop_ball_edge_latched"))
		shoot_up           = bool(world_node.get("shoot_edge_latched"))
		latch_toggle       = bool(world_node.get("latch_edge_latched"))
		assist_pass        = bool(world_node.get("assist_pass_edge_latched"))
		ability_toggle     = bool(world_node.get("ability_toggle_edge_latched"))
		ability_a1         = bool(world_node.get("ability_a1_edge_latched"))
		ability_a2         = bool(world_node.get("ability_a2_edge_latched"))
		ability_a3         = bool(world_node.get("ability_a3_edge_latched"))

		# Consume all edge latches so they fire exactly once per press
		world_node.set("jump_edge_latched",           false)
		world_node.set("tackle_edge_latched",         false)
		world_node.set("stop_ball_edge_latched",      false)
		world_node.set("shoot_edge_latched",          false)
		world_node.set("latch_edge_latched",          false)
		world_node.set("assist_pass_edge_latched",    false)
		world_node.set("ability_toggle_edge_latched", false)
		world_node.set("ability_a1_edge_latched",     false)
		world_node.set("ability_a2_edge_latched",     false)
		world_node.set("ability_a3_edge_latched",     false)

		# Camera yaw for server-side shoot/movement direction
		var viewport_cam := world_node.get_viewport().get_camera_3d() if world_node.get_viewport() else null
		if viewport_cam:
			cam_yaw = viewport_cam.global_transform.basis.get_euler().y

	return {
		"mouse_delta":          _mouse_input.get_mouse_delta(),
		"move_right":           get_action_strength("move_right"),
		"move_left":            get_action_strength("move_left"),
		"move_forward":         get_action_strength("move_forward"),
		"move_back":            get_action_strength("move_back"),
		"sprint":               is_action_pressed("sprint"),
		"rmb":                  is_action_pressed("aim"),
		"dribble":              is_action_pressed("dribble"),

		"shoot_down":           Input.is_action_pressed(shoot_action),
		"shoot_up":             shoot_up,
		"jump_pressed":         jump_pressed,
		"tackle_pressed":       tackle_pressed,
		"stop_ball":            stop_ball_pressed,
		"latch_toggle":         latch_toggle,
		"assist_pass_pressed":  assist_pass,
		"ability_toggle":       ability_toggle,
		"ability_action1":      ability_a1,
		"ability_action2":      ability_a2,
		"ability_action3":      ability_a3,
		"cam_yaw":              cam_yaw,
	}
