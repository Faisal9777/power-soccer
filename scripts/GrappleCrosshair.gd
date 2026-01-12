extends Control
class_name GrappleCrosshair

@export var arm_len: float = 10.0
@export var gap: float = 4.0
@export var thickness: float = 2.0
@export var col: Color = Color(1, 1, 1, 0.9)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2((arm_len + gap) * 2.0 + 2.0, (arm_len + gap) * 2.0 + 2.0)
	queue_redraw()

func _draw() -> void:
	var s := size
	var c := s * 0.5
	var t := thickness

	# left / right
	draw_rect(Rect2(c.x - gap - arm_len, c.y - t * 0.5, arm_len, t), col)
	draw_rect(Rect2(c.x + gap,          c.y - t * 0.5, arm_len, t), col)

	# top / bottom
	draw_rect(Rect2(c.x - t * 0.5, c.y - gap - arm_len, t, arm_len), col)
	draw_rect(Rect2(c.x - t * 0.5, c.y + gap,          t, arm_len), col)
