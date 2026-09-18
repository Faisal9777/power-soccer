# AimTouchToggle.gd
extends TouchScreenButton

@export var camera_path: NodePath
@export var hold_time: float = 0.5

@export var use_colors: bool = true
@export var color_on: Color = Color(0.8, 1.0, 0.2, 1.0)
@export var color_off: Color = Color(1, 1, 1, 1)
@export var texture_on: Texture2D
@export var texture_off: Texture2D

var _cam: Node = null
var _is_on: bool = false

var _holding := false
var _hold_elapsed := 0.0
var _hold_triggered := false

func _ready() -> void:
	_cam = get_node_or_null(camera_path)

	if _cam == null:
		push_warning("Focus: camera_path not set or invalid.")

	pressed.connect(_on_pressed)
	released.connect(_on_released)

	_update_visual()


func _process(delta: float) -> void:
	if not _holding or _hold_triggered:
		return

	_hold_elapsed += delta

	if _hold_elapsed >= hold_time:
		_hold_triggered = true
		_toggle_third_person()


func _on_pressed() -> void:
	_holding = true
	_hold_elapsed = 0.0
	_hold_triggered = false


func _on_released() -> void:
	_holding = false

	# Short press = existing focus/aim behavior.
	if not _hold_triggered:
		_is_on = !_is_on

		if _cam and _cam.has_method("set_aim_mode"):
			_cam.call("set_aim_mode", _is_on)

		_update_visual()

	_hold_elapsed = 0.0


func _toggle_third_person() -> void:
	if not _cam:
		return

	if _cam.distance <= 0.05:
		if _cam.has_method("set_goal_third_person_view"):
			_cam.call("set_goal_third_person_view")
	else:
		if _cam.has_method("set_first_person_view"):
			_cam.call("set_first_person_view")
func _update_visual() -> void:
	# Persistently show ON/OFF (instead of only while finger is down)
	if use_colors:
		modulate = (color_on if _is_on else color_off)

	# If textures provided, swap the normal texture so it stays
	if texture_on and texture_off:
		texture_normal = (texture_on if _is_on else texture_off)
		# Keep pressed texture same as normal so it doesn't flicker
		texture_pressed = texture_normal
