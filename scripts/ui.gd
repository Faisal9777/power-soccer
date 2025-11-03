# UI.gd  (attach to: CanvasLayer/UI)
extends Control

# Reference design resolution you layouted against
@export var design_size: Vector2 = Vector2(1280.0, 720.0)

# How big the joystick travel should be relative to its own box
@export var joystick_radius_pct: float = 0.45  # 0..0.5 of the smaller side

# Button sizing parameters
@export var button_cell_pct: float = 0.45      # fraction of ActionPad's smaller side per button
@export var base_button_font_px: int = 18      # font size at design_size

@onready var _joy_stick: Control   = $JoyStick
@onready var _action_pad: Control  = $ActionPad

func _ready() -> void:
	# Defer so children (buttons) are ready
	call_deferred("_rescale_all")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rescale_all()

func _rescale_all() -> void:
	# --- Compute screen scale relative to your design ---
	var vp: Vector2 = get_viewport_rect().size
	var scale_factor: float = min(vp.x / design_size.x, vp.y / design_size.y)

	# --- Scale ActionPad subtree (keeps existing manual layout) ---
	if _action_pad:
		# scale the whole pad
		_action_pad.scale = Vector2(scale_factor, scale_factor)

		# derive a reasonable button size from ActionPad box and scale
		var pad_box: Vector2 = _action_pad.size * scale_factor
		var cell: float = min(pad_box.x, pad_box.y) * clamp(button_cell_pct, 0.2, 0.9)

		# scale tap targets + labels for each direct child button
		for child in _action_pad.get_children():
			if child is BaseButton:
				var btn := child as BaseButton
				btn.custom_minimum_size = Vector2(cell, cell)

				var font_px: int = max(12, int(round(float(base_button_font_px) * scale_factor)))
				btn.add_theme_font_size_override("font_size", font_px)

	# --- Recompute joystick radius from its own box ---
	if _joy_stick:
		var box: Vector2 = _joy_stick.size          # pre-scale; joystick uses its own local size
		var r_px: float = min(box.x, box.y) * clamp(joystick_radius_pct, 0.05, 0.49)

		# If your joystick script exports `radius`, update it:
		if _joy_stick.has_method("set") and _joy_stick.has_meta(""):
			# 'set' always exists; this branch just silences analyzers
			pass
		_joy_stick.set("radius", r_px)

		# (optional) recenter knob if present
		var knob := _joy_stick.get_node_or_null("Knob") as Control
		if knob:
			knob.pivot_offset = knob.size * 0.5
			knob.position = _joy_stick.size * 0.5
