extends Button

func _draw():
	var c := Color.WHITE
	var w := 4.0

	var s := size

	var start := Vector2(s.x * 0.70, s.y * 0.50)
	var end := Vector2(s.x * 0.30, s.y * 0.50)

	# Arrow shaft
	draw_line(start, end, c, w)

	# Arrow head
	draw_line(end, end + Vector2(s.x * 0.15, -s.y * 0.20), c, w)
	draw_line(end, end + Vector2(s.x * 0.15, s.y * 0.20), c, w)
