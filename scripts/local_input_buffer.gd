extends InputBuffer
class_name LocalInputBuffer

var should_listen := true
var _mouse_input : InputSource

func get_input() -> Dictionary:
	var input = {'mouse_delta' : _mouse_input.get_mouse_delta(), 'move_right': get_action_strength("move_right"),
	'move_left': get_action_strength("move_left"), 'move_forward': get_action_strength("move_forward"),
	'move_back': get_action_strength("move_back"), 'sprint' : is_action_pressed("sprint")}

	return input

func get_action_strength(action) -> float:
	if should_listen:
		return Input.get_action_strength(action)
	return 0

func is_action_pressed(action) -> bool:
	if should_listen:
		return Input.is_action_pressed(action)
	return false

func _init(mouse_input : InputSource):
	_mouse_input = mouse_input
