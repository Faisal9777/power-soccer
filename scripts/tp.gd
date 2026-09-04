#extends TouchScreenButton
#
#@export var camera_path: NodePath
#@export var use_colors: bool = true
#@export var color_on: Color = Color(0.8, 1.0, 0.2, 1.0)
#@export var color_off: Color = Color(1, 1, 1, 1)
#@export var texture_on: Texture2D
#@export var texture_off: Texture2D
#
#var _cam: Node = null
#var _is_on := false
#
#
#func _ready() -> void:
	#_cam = get_node_or_null(camera_path)
#
	#if _cam == null:
		#push_error("TP: camera_path is invalid: " + str(camera_path))
#
	#pressed.connect(_on_pressed)
	#_update_visual()
#
#
#func _input(event: InputEvent) -> void:
	#if not OS.has_feature("mobile"):
		#return
#
	#if event is InputEventScreenTouch:
		#var touch := event as InputEventScreenTouch
#
		#if touch.pressed and _is_touch_inside(touch.position):
			#_on_pressed()
			#get_viewport().set_input_as_handled()
#
#
#func _is_touch_inside(screen_pos: Vector2) -> bool:
	#var texture := texture_normal
#
	#if texture == null:
		#return false
#
	#var button_size := texture.get_size()
#
	#var rect := Rect2(
		#global_position - button_size * 0.5,
		#button_size
	#)
#
	#return rect.has_point(screen_pos)
	#
#func _on_pressed() -> void:
	#_is_on = !_is_on
#
	#if _cam:
		#if _is_on:
			#if _cam.has_method("set_goal_third_person_view"):
				#_cam.call("set_goal_third_person_view")
		#else:
			#if _cam.has_method("set_first_person_view"):
				#_cam.call("set_first_person_view")
#
	#_update_visual()
#
#
#func _update_visual() -> void:
	#if use_colors:
		#modulate = color_on if _is_on else color_off
#
	#if texture_on and texture_off:
		#texture_normal = texture_on if _is_on else texture_off
		#texture_pressed = texture_normal
extends TouchScreenButton

@export var camera_path: NodePath
@export var use_colors: bool = true
@export var color_on: Color = Color(0.8, 1.0, 0.2, 1.0)
@export var color_off: Color = Color(1, 1, 1, 1)
@export var texture_on: Texture2D
@export var texture_off: Texture2D

var _cam: Node = null
var _is_on := false


func _ready() -> void:
	_cam = get_node_or_null(camera_path)

	if _cam == null:
		push_error("TP: camera_path is invalid: " + str(camera_path))

	pressed.connect(_on_pressed)
	_update_visual()


func _on_pressed() -> void:
	_is_on = !_is_on

	if _cam:
		if _is_on:
			if _cam.has_method("set_goal_third_person_view"):
				_cam.call("set_goal_third_person_view")
		else:
			if _cam.has_method("set_first_person_view"):
				_cam.call("set_first_person_view")

	_update_visual()


func _update_visual() -> void:
	if use_colors:
		modulate = color_on if _is_on else color_off

	if texture_on and texture_off:
		texture_normal = texture_on if _is_on else texture_off
		texture_pressed = texture_normal
