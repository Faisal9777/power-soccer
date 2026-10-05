extends InputBuffer
class_name LocalInputBuffer
var should_listen := true
var _source_input : InputSource

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

func _init(source_input) -> void:
	_source_input= source_input

func _get_input() -> Dictionary:
	
	var shoot_action := "shoot_touch" if OS.has_feature("mobile") else "shoot"
	var input = _source_input.get_inputs()

	return {
		"mouse_delta":          _source_input.get_mouse_delta(),
		"move_right":           get_action_strength("move_right"),
		"move_left":            get_action_strength("move_left"),
		"move_forward":         get_action_strength("move_forward"),
		"move_back":            get_action_strength("move_back"),
		"sprint":               is_action_pressed("sprint"),
		"rmb":                  is_action_pressed("aim"),
		"dribble":              is_action_pressed("dribble"),

		"shoot_down":           Input.is_action_pressed(shoot_action),
		"jump_pressed": input.get("jump_pressed"),
		"tackle_pressed": input.get("tackle_pressed"),
		"stop_ball": input.get("stop_ball"),
		"shoot_up": input.get("shoot_up"),
		"latch_toggle": input.get("latch_toggle"),
		"assist_pass_pressed": input.get("assist_pass_pressed"),
		"ability_toggle": input.get("ability_toggle"),
		"ability_action1": input.get("ability_action1"),
		"ability_action3": input.get("ability_action3"),
	}
