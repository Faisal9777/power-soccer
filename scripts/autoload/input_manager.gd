# InputManager.gd (autoload)
extends Node

var _mouse_delta := Vector2.ZERO

func _input(event):
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

func get_mouse_delta() -> Vector2:
	return _mouse_delta

func end_frame():
	_mouse_delta = Vector2.ZERO
