extends Control

var _listening_for_key: StringName = ""
var _pending_action: StringName = ""
var _pending_new_action: StringName = ""
var _pending_event: InputEvent = null
var _pending_conflict_action: StringName = ""
var _row_buttons: Dictionary = {}
var _row_labels: Dictionary = {}
var _scroll: ScrollContainer

func _ready() -> void:
	build_ui()

func build_ui() -> void:
	for child in get_children():
		child.queue_free()

	_row_buttons.clear()
	_row_labels.clear()

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_scroll = ScrollContainer.new()
	var scroll := _scroll

	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	scroll.custom_minimum_size = Vector2(0, 0)

	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_theme_constant_override("separation", 6)

	scroll.add_child(content)
	
	var actions := Settings.get_bindable_actions()

	var hidden_actions := [
		&"debug",
		&"debug_first",
		&"debug_third",
		&"check_user",
		&"join_key",
		&"host_key",
		&"shoot_touch"
	]

	actions = actions.filter(func(action_name):
		return action_name not in hidden_actions
	)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)

	for action_name in actions:

		# Column 1: Action name
		var label := Label.new()
		label.text = _display_name(action_name)
		label.custom_minimum_size = Vector2(220, 48)
		label.size_flags_horizontal = Control.SIZE_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(label)

		# Column 2: Current key
		var current_value := Label.new()
		current_value.text = Settings.get_action_display_text(action_name)
		current_value.custom_minimum_size = Vector2(220, 48)
		current_value.size_flags_horizontal = Control.SIZE_FILL
		current_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		current_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(current_value)

		# Column 3: fixed-width cell
		var button_cell := Control.new()
		button_cell.custom_minimum_size = Vector2(140, 48)
		grid.add_child(button_cell)

		var change_btn := Button.new()
		change_btn.text = "Change"
		change_btn.size = Vector2(140, 44)
		change_btn.position = Vector2(0, 2)
		change_btn.clip_text = true
		change_btn.add_theme_font_size_override("font_size", 16)

		button_cell.add_child(change_btn)

		var current_action = action_name

		_row_labels[current_action] = current_value
		_row_buttons[current_action] = change_btn

		change_btn.pressed.connect(func():
			_start_key_capture(current_action)
		)

	# Reset button
	var reset_btn := Button.new()
	reset_btn.text = "Reset Defaults"
	reset_btn.custom_minimum_size = Vector2(0, 40)
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	root.add_child(reset_btn)

	reset_btn.pressed.connect(func():
		Settings.reset_key_bindings_to_defaults()
		refresh_ui()
	)

func refresh_ui() -> void:
	var scroll_position := 0

	if is_instance_valid(_scroll):
		scroll_position = _scroll.scroll_vertical

	build_ui()

	await get_tree().process_frame

	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = scroll_position


func _start_key_capture(action_name: StringName) -> void:
	_pending_action = action_name
	_listening_for_key = action_name

	set_process_input(true)

	for action in _row_buttons.keys():
		var button: Button = _row_buttons[action]
		button.disabled = true
		button.text = "Change"

	_row_buttons[action_name].disabled = false
	_row_buttons[action_name].text = "Press a key\nESC to cancel"

func _input(event: InputEvent) -> void:
	if _listening_for_key == "":
		return
	# Escape cancels key detection
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_key_capture()
			get_viewport().set_input_as_handled()
			return
			
	var new_event: InputEvent = null

	# Keyboard
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := InputEventKey.new()

		key_event.keycode = event.keycode
		key_event.physical_keycode = event.physical_keycode
		key_event.unicode = event.unicode
		key_event.shift_pressed = event.shift_pressed
		key_event.ctrl_pressed = event.ctrl_pressed
		key_event.alt_pressed = event.alt_pressed
		key_event.meta_pressed = event.meta_pressed
		key_event.pressed = true
		key_event.location = event.location

		new_event = key_event

	# Mouse
	elif event is InputEventMouseButton and event.pressed:
		var mouse_event := InputEventMouseButton.new()

		mouse_event.button_index = event.button_index
		mouse_event.pressed = true

		new_event = mouse_event

	if new_event == null:
		return

	var action := StringName(_pending_action)

	# Check for an existing binding.
	var conflicting_action = Settings.get_binding_conflict(
		action,
		new_event
	)

	if conflicting_action != &"":
		# Remember everything needed until the user answers the popup.
		_pending_new_action = action
		_pending_event = new_event
		_pending_conflict_action = conflicting_action

		_listening_for_key = ""
		_pending_action = ""

		set_process_input(false)


		_show_binding_conflict_popup(
			action,
			conflicting_action,
			new_event
		)

		return
	# No conflict → bind immediately.
	if Settings.set_action_binding(action, new_event):
		_listening_for_key = ""
		_pending_action = ""
		set_process_input(false)


		refresh_ui()
	else:
		print("Binding conflict or invalid event for %s" % action)

		_listening_for_key = ""
		_pending_action = ""
		set_process_input(false)

func _display_name(action_name: StringName) -> String:
	return String(action_name).replace("_", " ").capitalize()

func _show_binding_conflict_popup(
	new_action: StringName,
	old_action: StringName,
	event: InputEvent
) -> void:
	var popup := ConfirmationDialog.new()

	popup.title = "Key Binding Conflict"

	var key_name := Settings._format_event(event)
	var old_action_name := _display_name(old_action)
	var new_action_name := _display_name(new_action)

	popup.dialog_text = "%s is already bound to \"%s\".\n\nDo you want to use %s for \"%s\" instead?\n\nThe old binding will be removed." % [
		key_name,
		old_action_name,
		key_name,
		new_action_name
	]

	add_child(popup)

	popup.confirmed.connect(func():
		_confirm_binding_conflict(popup)
	)

	popup.canceled.connect(func():
		_cancel_binding_conflict(popup)
	)

	popup.close_requested.connect(func():
		_cancel_binding_conflict(popup)
	)

	popup.popup_centered()
	
func _confirm_binding_conflict(popup: ConfirmationDialog) -> void:
	if _pending_event == null or _pending_new_action == &"":
		popup.queue_free()
		return

	var new_action := _pending_new_action
	var event := _pending_event

	# Force the new binding.
	# This removes the same key/mouse binding from the old action.
	var success := Settings.set_action_binding_force(
		new_action,
		event,
		true
	)

	if not success:
		print("Failed to apply forced binding.")

	_pending_event = null
	_pending_new_action = ""
	_pending_conflict_action = ""

	popup.queue_free()

	if success:
		refresh_ui()

func _cancel_binding_conflict(popup: ConfirmationDialog) -> void:
	var action_to_listen := _pending_new_action

	_pending_event = null
	_pending_new_action = ""
	_pending_conflict_action = ""

	popup.queue_free()

	if action_to_listen != &"":
		call_deferred("_start_key_capture", action_to_listen)

func _cancel_key_capture() -> void:
	_listening_for_key = ""
	_pending_action = ""

	set_process_input(false)

	# Restore all Change buttons
	for action in _row_buttons.keys():
		var button: Button = _row_buttons[action]
		button.disabled = false
		button.text = "Change"

	# Hide the Escape hint
