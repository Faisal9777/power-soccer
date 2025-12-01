# AimTouchToggle.gd
extends TouchScreenButton

@export var camera_path: NodePath

# Optional visuals so you can see ON/OFF state persistently
@export var use_colors: bool = true
@export var color_on: Color = Color(0.8, 1.0, 0.2, 1.0) # TP ON
@export var color_off: Color = Color(1, 1, 1, 1)        # FP OFF
@export var texture_on: Texture2D
@export var texture_off: Texture2D

var _cam: Node = null
var _is_on: bool = false  # false = FP, true = TP

func _ready() -> void:
	_cam = get_node_or_null(camera_path)
	if _cam == null:
		push_warning("AimTouchToggle: camera_path not set or invalid.")

	# Single tap toggles FP/TP
	pressed.connect(_on_pressed)

	# Make sure visuals match current state (starts FP)
	_update_visual()

func _on_pressed() -> void:
	_is_on = !_is_on

	if _cam:
		if _is_on:
			# Turn ON third-person
			if _cam.has_method("set_goal_third_person_view"):
				_cam.call("set_goal_third_person_view")
		else:
			# Turn back to first-person
			if _cam.has_method("set_first_person_view"):
				_cam.call("set_first_person_view")

	_update_visual()

func _update_visual() -> void:
	# Persistently show ON/OFF
	if use_colors:
		modulate = (color_on if _is_on else color_off)

	# If textures provided, swap the normal texture so it stays
	if texture_on and texture_off:
		texture_normal = (texture_on if _is_on else texture_off)
		# Keep pressed texture same as normal so it doesn't flicker
		texture_pressed = texture_normal
