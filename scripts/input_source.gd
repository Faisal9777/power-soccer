extends Node
class_name InputSource

var _mouse_delta := Vector2.ZERO

func _input(event):
	if event is InputEventMouseMotion:
		if not GameState.is_paused:
			_mouse_delta += event.relative

func get_mouse_delta() -> Vector2:
	var m_delta = _mouse_delta
	end_frame()
	return m_delta

func end_frame():
	_mouse_delta = Vector2.ZERO
