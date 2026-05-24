extends InputBuffer
class_name LocalInputBuffer

var _mouse_delta := Vector2.ZERO
var should_listen := true

func _input(event):
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

func get_input() -> Dictionary:
	var input = {'mouse_delta' : get_mouse_delta(), 'move_right': get_action_strength("move_right"),
	'move_left': get_action_strength("move_left"), 'move_forward': get_action_strength("move_forward"),
	'move_back': get_action_strength("move_back"), 'sprint' : is_action_pressed("sprint")}

	return input

func get_mouse_delta() -> Vector2:
	
	var m_delta = _mouse_delta
	end_frame()
	return m_delta

func end_frame():
	_mouse_delta = Vector2.ZERO

func get_action_strength(action) -> float:
	if should_listen:
		return Input.get_action_strength(action)
	return 0

func is_action_pressed(action) -> bool:
	if should_listen:
		return Input.is_action_pressed(action)
	return false
