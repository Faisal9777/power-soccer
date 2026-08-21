extends Control

signal icon_selected(icon_path: String)

const ICONS_PATH := "res://Texture/Profile_Icons/"

var _selected_icon_path: String = ""
var _pending_icon_path: String = ""

var _popup: Control
var _grid: GridContainer


func open() -> void:
	_selected_icon_path = Settings.profile_icon_path
	_pending_icon_path = Settings.profile_icon_path

	_create_popup()


func _create_popup() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()

	_popup = Control.new()
	_popup.name = "ProfileIconPopup"
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP

	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.set_offsets_preset(Control.PRESET_FULL_RECT)

	get_viewport().add_child(_popup)

	# --------------------------------------------------
	# Dark background
	# --------------------------------------------------

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	_popup.add_child(dim)

	# --------------------------------------------------
	# Center panel
	# --------------------------------------------------

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	_popup.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 500)

	center.add_child(panel)

	# --------------------------------------------------
	# Padding
	# --------------------------------------------------

	var margin := MarginContainer.new()

	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)

	panel.add_child(margin)

	# --------------------------------------------------
	# Main layout
	# --------------------------------------------------

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)

	margin.add_child(main_vbox)

	# --------------------------------------------------
	# Title
	# --------------------------------------------------

	var title := Label.new()
	title.text = "Select an Profile Icon"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)

	main_vbox.add_child(title)

	# --------------------------------------------------
	# Scroll area
	# --------------------------------------------------

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	main_vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)

	scroll.add_child(_grid)

	# --------------------------------------------------
	# Load SVG icons
	# --------------------------------------------------

	_load_icons()

	# --------------------------------------------------
	# Buttons
	# --------------------------------------------------

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)

	main_vbox.add_child(button_row)

	var ok_button := Button.new()
	ok_button.text = "OK"
	ok_button.custom_minimum_size = Vector2(140, 48)

	button_row.add_child(ok_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(140, 48)

	button_row.add_child(cancel_button)

	ok_button.pressed.connect(_on_ok_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _load_icons() -> void:
	var dir := DirAccess.open(ICONS_PATH)

	if dir == null:
		push_error("Could not open profile icon directory: " + ICONS_PATH)
		return

	var files: Array[String] = []

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()

		if file_name == "":
			break

		if dir.current_is_dir():
			continue

		if file_name.to_lower().ends_with(".svg"):
			files.append(file_name)

	dir.list_dir_end()

	files.sort()

	for file_name in files:
		var path := ICONS_PATH + file_name
		_create_icon_button(path)


func _create_icon_button(icon_path: String) -> void:
	var button := Button.new()

	button.custom_minimum_size = Vector2(75, 75)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var texture := load(icon_path)

	if texture:
		button.icon = texture

	button.expand_icon = true

	button.set_meta("icon_path", icon_path)

	_grid.add_child(button)

	_update_icon_style(button, icon_path)

	button.pressed.connect(
		func():
			_select_icon(icon_path)
	)

func _select_icon(icon_path: String) -> void:
	_pending_icon_path = icon_path

	for child in _grid.get_children():
		if child is Button:
			var button := child as Button
			var path: String = button.get_meta("icon_path", "")

			_update_icon_style(button, path)


func _update_icon_style(
	button: Button,
	icon_path: String
) -> void:

	var is_selected := icon_path == _pending_icon_path

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.10, 1.0)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8

	if is_selected:
		normal.border_width_left = 3
		normal.border_width_right = 3
		normal.border_width_top = 3
		normal.border_width_bottom = 3
		normal.border_color = Color("#3498ff")

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", normal)


func _on_ok_pressed() -> void:
	if _pending_icon_path == "":
		return

	_selected_icon_path = _pending_icon_path

	Settings.set_profile_icon_and_save(_pending_icon_path)

	# Save it using your Settings persistence system.
	Settings._save()

	icon_selected.emit(_selected_icon_path)

	_popup.queue_free()


func _on_cancel_pressed() -> void:
	_popup.queue_free()
