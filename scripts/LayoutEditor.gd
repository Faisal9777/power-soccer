extends Control

const HIT_SLOP := 12.0

@export var world_scene_for_layout: PackedScene = preload("res://scenes/world.tscn")
@export var canvaslayer_path_in_world: NodePath = ^"CanvasLayer"

var world_root: Node = null
var _layout_svc: SubViewportContainer = null
var _layout_sv: SubViewport = null
var _layout_canvas: Node = null
var _layout_candidates: Array[CanvasItem] = []

var _layout_drag_item: CanvasItem = null
var _layout_drag_offset: Vector2 = Vector2.ZERO

var _layout_defaults: Dictionary = {}
var _layout_working: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout_editor()


func _build_layout_editor() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)

	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	add_child(margin)

	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 10)

	margin.add_child(main_v)

	var base_w := int(
		ProjectSettings.get_setting(
			"display/window/size/viewport_width"
		)
	)

	var base_h := int(
		ProjectSettings.get_setting(
			"display/window/size/viewport_height"
		)
	)

	var ar := AspectRatioContainer.new()
	ar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ar.ratio = float(base_w) / float(base_h)
	ar.stretch_mode = AspectRatioContainer.STRETCH_FIT

	main_v.add_child(ar)

	var preview_frame := PanelContainer.new()
	preview_frame.name = "PreviewFrame"
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	ar.add_child(preview_frame)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1, 0, 0, 1)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3

	preview_frame.add_theme_stylebox_override(
		"panel",
		sb
	)

	var svc := SubViewportContainer.new()
	svc.name = "LayoutSVC"
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)

	svc.gui_input.connect(
		_on_layout_preview_gui_input
	)

	_layout_svc = svc

	preview_frame.add_child(svc)

	var sv := SubViewport.new()

	sv.gui_disable_input = true
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	sv.size = Vector2i(base_w, base_h)
	sv.size_2d_override = Vector2i(base_w, base_h)
	sv.size_2d_override_stretch = true

	_layout_sv = sv

	svc.stretch = true
	svc.add_child(sv)

	if world_scene_for_layout:
		var wd := world_scene_for_layout.instantiate()

		var cl := wd.get_node_or_null(
			canvaslayer_path_in_world
		)

		if cl:
			var goal_markers := cl.get_node_or_null("UI/GoalMarkers")
			if goal_markers:
				goal_markers.visible = false

			var ball_marker := cl.get_node_or_null("UI/BallMarker")
			if ball_marker:
				ball_marker.visible = false

			wd.remove_child(cl)
			sv.add_child(cl)

			cl.process_mode = Node.PROCESS_MODE_DISABLED

			_layout_canvas = cl

			_layout_rebuild_candidates()

		wd.queue_free()


	var button_row := HBoxContainer.new()

	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_theme_constant_override("separation", 16)

	main_v.add_child(button_row)

	var save_layout := Button.new()
	save_layout.text = "Save Layout"
	save_layout.custom_minimum_size = Vector2i(160, 48)

	button_row.add_child(save_layout)

	var reset_layout := Button.new()
	reset_layout.text = "Reset Layout"
	reset_layout.custom_minimum_size = Vector2i(160, 48)

	button_row.add_child(reset_layout)

	save_layout.pressed.connect(func():
		Settings.set_layout_state_and_save(
			_layout_working
		)
		if world_root != null and world_root.has_method("_apply_saved_layout_to_world_ui"):
			world_root.call_deferred("_apply_saved_layout_to_world_ui")
	)

	reset_layout.pressed.connect(func():
		_layout_working = _layout_defaults.duplicate(true)
		_layout_apply_positions(_layout_working)
	)

	call_deferred("_layout_finalize_defaults")


func _layout_virtual_size() -> Vector2:
	if _layout_sv == null:
		return Vector2.ONE

	if _layout_sv.size_2d_override != Vector2i.ZERO \
	and _layout_sv.size_2d_override_stretch:

		return Vector2(
			_layout_sv.size_2d_override
		)

	return Vector2(
		_layout_sv.size
	)


func _layout_svc_to_vp(p: Vector2) -> Vector2:
	if _layout_svc == null or _layout_sv == null:
		return p

	if _layout_svc.size.x <= 0.0 \
	or _layout_svc.size.y <= 0.0:

		return p

	var virt := _layout_virtual_size()

	return Vector2(
		p.x * virt.x / _layout_svc.size.x,
		p.y * virt.y / _layout_svc.size.y
	)


func _layout_rebuild_candidates() -> void:
	_layout_candidates.clear()

	if _layout_canvas == null:
		return

	var ui := _layout_canvas.get_node_or_null(^"UI")

	var root := ui if ui != null else _layout_canvas

	_layout_collect_candidates(root)


func _layout_collect_candidates(n: Node) -> void:
	for c in n.get_children():

		if c is CanvasItem and c.name == "JoyStick":
			_layout_candidates.append(c)
			continue

		if c.get_parent() \
		and c.get_parent().name == "JoyStick":

			continue

		if c is CanvasItem:
			if c.name != "UI":
				_layout_candidates.append(c)

		_layout_collect_candidates(c)


func _joy_knob_hit(
	joy: CanvasItem,
	vp_pos: Vector2
) -> bool:

	var knob := joy.get_node_or_null(^"Knob")

	if knob == null:
		return false

	if knob is TouchScreenButton:

		var ts := knob as TouchScreenButton
		var tex: Texture2D = ts.texture_normal

		if tex:

			var size := tex.get_size() * ts.global_scale

			var rect := Rect2(
				ts.global_position - size * 0.5,
				size
			)

			return rect.has_point(vp_pos)

		return (
			ts.global_position.distance_to(vp_pos)
			<= 48.0
		)

	if knob is Control:
		return (
			knob as Control
		).get_global_rect().has_point(vp_pos)

	var origin := (
		knob as CanvasItem
	).get_global_transform_with_canvas().origin

	return origin.distance_to(vp_pos) <= 32.0


func _layout_pick_at(
	vp_pos: Vector2
) -> CanvasItem:

	for i in range(
		_layout_candidates.size() - 1,
		-1,
		-1
	):

		var item := _layout_candidates[i]

		if not is_instance_valid(item):
			continue

		if not item.visible:
			continue

		if item.name == "JoyStick":

			if _joy_knob_hit(
				item,
				vp_pos
			):
				return item

			continue

		if item.name == "Focus button" \
		and item.get_child_count() > 0:

			continue

		if item is Control:

			var rect := (
				item as Control
			).get_global_rect().grow(HIT_SLOP)

			if rect.has_point(vp_pos):
				return item

			continue

		if item is TouchScreenButton:

			var ts := item as TouchScreenButton
			var tex: Texture2D = ts.texture_normal

			if tex:

				var size := (
					tex.get_size()
					* ts.global_scale
				)

				var rect := Rect2(
					ts.global_position - size * 0.5,
					size
				).grow(HIT_SLOP)

				if rect.has_point(vp_pos):
					return item

			else:

				if ts.global_position.distance_to(
					vp_pos
				) <= 48.0 + HIT_SLOP:

					return item

			continue

		var origin := (
			item
			.get_global_transform_with_canvas()
			.origin
		)

		if origin.distance_to(vp_pos) <= 32.0:
			return item

	return null


func _on_layout_preview_gui_input(
	event: InputEvent
) -> void:

	if _layout_svc == null:
		return

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT:

		var mb := event as InputEventMouseButton

		var vp_pos := _layout_svc_to_vp(
			mb.position
		)

		if mb.pressed:

			var picked := _layout_pick_at(
				vp_pos
			)

			if picked != null:

				_layout_drag_item = picked

				_layout_drag_offset = (
					vp_pos
					- _layout_drag_item.global_position
				)

		else:

			_layout_drag_item = null

		_layout_svc.accept_event()
		return

	if event is InputEventMouseMotion \
	and _layout_drag_item != null:

		var mm := event as InputEventMouseMotion

		var vp_pos := _layout_svc_to_vp(
			mm.position
		)

		if is_instance_valid(
			_layout_drag_item
		):

			_layout_drag_item.global_position = (
				vp_pos
				- _layout_drag_offset
			)

			_layout_working[
				_layout_key(_layout_drag_item)
			] = _layout_read_state(
				_layout_drag_item
			)

		_layout_svc.accept_event()
		return

	if event is InputEventScreenTouch:

		var st := event as InputEventScreenTouch

		var vp_pos := _layout_svc_to_vp(
			st.position
		)

		if st.pressed:

			var picked := _layout_pick_at(
				vp_pos
			)

			if picked != null:

				_layout_drag_item = picked

				_layout_drag_offset = (
					vp_pos
					- _layout_drag_item.global_position
				)

		else:

			_layout_drag_item = null

		_layout_svc.accept_event()
		return

	if event is InputEventScreenDrag \
	and _layout_drag_item != null:

		var sd := event as InputEventScreenDrag

		var vp_pos := _layout_svc_to_vp(
			sd.position
		)

		if is_instance_valid(
			_layout_drag_item
		):

			_layout_drag_item.global_position = (
				vp_pos
				- _layout_drag_offset
			)

			_layout_working[
				_layout_key(_layout_drag_item)
			] = _layout_read_state(
				_layout_drag_item
			)

		_layout_svc.accept_event()


func _layout_key(item: CanvasItem) -> String:
	if _layout_canvas == null:
		return item.name

	return String(
		_layout_canvas.get_path_to(item)
	)


func _layout_read_state(
	item: CanvasItem
) -> Dictionary:

	if item is Control:

		var c := item as Control

		return {
			"t": "c",
			"al": c.anchor_left,
			"at": c.anchor_top,
			"ar": c.anchor_right,
			"ab": c.anchor_bottom,
			"ol": c.offset_left,
			"ot": c.offset_top,
			"or": c.offset_right,
			"ob": c.offset_bottom
		}

	return {
		"t": "n",
		"p": item.position
	}


func _layout_apply_state(
	item: CanvasItem,
	state: Dictionary
) -> void:

	if not state.has("t"):
		return

	if state["t"] == "c" \
	and item is Control:

		var c := item as Control

		c.anchor_left = state["al"]
		c.anchor_top = state["at"]
		c.anchor_right = state["ar"]
		c.anchor_bottom = state["ab"]

		c.offset_left = state["ol"]
		c.offset_top = state["ot"]
		c.offset_right = state["or"]
		c.offset_bottom = state["ob"]

	elif state["t"] == "n":

		if state.has("p"):
			item.position = state["p"]


func _layout_finalize_defaults() -> void:
	if _layout_canvas == null:
		return

	_layout_rebuild_candidates()

	_layout_capture_defaults()

	if Settings.has_layout_state():

		_layout_working = (
			Settings.layout_state
			.duplicate(true)
		)

	else:

		_layout_working = (
			_layout_defaults
			.duplicate(true)
		)

	_layout_apply_positions(
		_layout_working
	)


func _layout_capture_defaults() -> void:
	_layout_defaults.clear()

	for item in _layout_candidates:

		if is_instance_valid(item):

			_layout_defaults[
				_layout_key(item)
			] = _layout_read_state(item)


func _layout_apply_positions(
	dict: Dictionary
) -> void:

	for item in _layout_candidates:

		if not is_instance_valid(item):
			continue

		var key := _layout_key(item)

		if dict.has(key):

			_layout_apply_state(
				item,
				dict[key]
			)
