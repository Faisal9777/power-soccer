# Settings.gd (Autoload)
extends Node

const CFG_PATH := "user://settings.cfg"

var player_name := ""   # shown in lobbies

var fullscreen := false
var vsync := true
var quality := 1          # 0=Low, 1=Med, 2=High (MSAA)
var tex_quality := 2      # 0=Low, 1=Med, 2=High (Textures)

# NEW: 3D render scale (Project Settings -> Rendering -> Scaling 3D -> Scale)
var scale_3d: float = 1.0
var key_bindings: Dictionary = {}
var _default_key_bindings: Dictionary = {}
# Layout state for CanvasLayer UI
var layout_state: Dictionary = {}
func _enter_tree() -> void:
	_capture_default_key_bindings()
	_load()
	_apply()
	_apply_key_bindings()

# UPDATED: add new_scale_3d
func set_and_save(new_fullscreen: bool, new_vsync: bool, new_quality: int, new_tex_quality: int, new_scale_3d: float) -> void:
	fullscreen = new_fullscreen
	vsync = new_vsync
	quality = new_quality
	tex_quality = new_tex_quality
	scale_3d = new_scale_3d
	_apply()
	_save()

func _apply() -> void:
	# Window mode + VSync
	if !OS.has_feature("mobile"):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
	ProjectSettings.set_setting("display/window/vsync/vsync_mode", 1 if vsync else 0)

	# MSAA (3D)
	match quality:
		0: get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		1: get_viewport().msaa_3d = Viewport.MSAA_2X
		2: get_viewport().msaa_3d = Viewport.MSAA_4X

	# Texture "quality"
	match tex_quality:
		0:
			get_viewport().texture_mipmap_bias = 2.0
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		1:
			get_viewport().texture_mipmap_bias = 1.0
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		2:
			get_viewport().texture_mipmap_bias = 0.0
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# NEW: 3D scaling (apply to the root viewport so it matches Project Settings behavior)
	var vp := get_tree().root
	vp.scaling_3d_scale = clampf(scale_3d, 0.25, 2.0)

	# Optional: also keep ProjectSettings in sync (not strictly required for runtime)
	ProjectSettings.set_setting("rendering/scaling_3d/scale", vp.scaling_3d_scale)

	_apply_key_bindings()

func _capture_default_key_bindings() -> void:
	_default_key_bindings = {}
	for action_name in InputMap.get_actions():
		if action_name.begins_with("ui_"):
			continue
		var serialized_events: Array = []
		for event in InputMap.action_get_events(action_name):
			serialized_events.append(_event_to_dict(event))
		if serialized_events.size() > 0:
			_default_key_bindings[action_name] = serialized_events

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		fullscreen  = cfg.get_value("video", "fullscreen", fullscreen)
		vsync       = cfg.get_value("video", "vsync", vsync)
		quality     = cfg.get_value("video", "quality", quality)
		tex_quality = cfg.get_value("video", "texture_quality", tex_quality)

		scale_3d = float(cfg.get_value("video", "scale_3d", scale_3d))

		player_name = cfg.get_value("profile", "name", player_name)

		key_bindings = cfg.get_value("input", "bindings", {})

		layout_state = cfg.get_value("layout", "state", {})
		if typeof(layout_state) != TYPE_DICTIONARY:
			layout_state = {}

func _save() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "texture_quality", tex_quality)

	# NEW:
	cfg.set_value("video", "scale_3d", scale_3d)

	cfg.set_value("profile", "name", player_name)
	cfg.set_value("input", "bindings", key_bindings)
	cfg.set_value("layout", "state", layout_state)


	cfg.save(CFG_PATH)

func ensure_player_name() -> void:
	if player_name.strip_edges() == "":
		player_name = "Player_%d" % randi()
		_save()

func set_player_name_and_save(name: String) -> void:
	player_name = name.strip_edges()
	if player_name == "":
		player_name = "Player_%d" % randi()
	_save()

func get_bindable_actions() -> Array:
	var actions: Array = []

	for action_name in InputMap.get_actions():
		if action_name.begins_with("ui_"):
			continue

		actions.append(action_name)

	actions.sort()
	return actions
	
func get_action_display_text(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "None"

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey \
		or event is InputEventMouseButton:
			return _format_event(event)

	return "None"
	
func get_action_keyboard_events(action_name: String) -> Array:
	var events: Array = []
	if not InputMap.has_action(action_name):
		return events
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			events.append(event)
	return events

func has_key_binding_conflict(action_name: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action_name):
		return false

	for other_action in InputMap.get_actions():
		if other_action == action_name or other_action.begins_with("ui_"):
			continue

		for other_event in InputMap.action_get_events(other_action):
			if _events_match(other_event, event):
				return true

	return false
	
func set_action_binding(
	action_name: String,
	new_event: InputEvent,
	replace_existing: bool = true
) -> bool:
	if not InputMap.has_action(action_name):
		return false

	if not (
		new_event is InputEventKey
		or new_event is InputEventMouseButton
	):
		return false

	if has_key_binding_conflict(action_name, new_event):
		return false

	var bindable_events: Array[InputEvent] = []

	for current_event in InputMap.action_get_events(action_name):
		if current_event is InputEventKey \
		or current_event is InputEventMouseButton:
			bindable_events.append(current_event)

	if bindable_events.is_empty():
		InputMap.action_add_event(action_name, new_event)
	else:
		if replace_existing:
			var event_to_replace: InputEvent = bindable_events[0]
			InputMap.action_erase_event(action_name, event_to_replace)

		InputMap.action_add_event(action_name, new_event)

	key_bindings[action_name] = _serialize_action_events(action_name)
	_save()
	_apply_key_bindings()

	return true

func reset_key_bindings_to_defaults() -> void:
	key_bindings.clear()
	_save()
	_apply_key_bindings()

func _apply_key_bindings() -> void:
	for action_name in _default_key_bindings.keys():
		_restore_action_events(action_name, _default_key_bindings[action_name])

	for action_name in key_bindings.keys():
		if key_bindings[action_name] is Array:
			_restore_action_events(action_name, key_bindings[action_name])

func _restore_action_events(action_name: String, serialized_events: Array) -> void:
	if not InputMap.has_action(action_name):
		return
	for event in InputMap.action_get_events(action_name):
		InputMap.action_erase_event(action_name, event)
	for data in serialized_events:
		var event := _dict_to_event(data)
		if event != null:
			InputMap.action_add_event(action_name, event)

func _serialize_action_events(action_name: String) -> Array:
	var serialized: Array = []
	for event in InputMap.action_get_events(action_name):
		serialized.append(_event_to_dict(event))
	return serialized

func _has_any_events(action_name: String) -> bool:
	if not InputMap.has_action(action_name):
		return false
	return InputMap.action_get_events(action_name).size() > 0

func _events_match(left: InputEvent, right: InputEvent) -> bool:
	if left is InputEventKey and right is InputEventKey:
		return (
			left.physical_keycode == right.physical_keycode
			and left.keycode == right.keycode
			and left.shift_pressed == right.shift_pressed
			and left.ctrl_pressed == right.ctrl_pressed
			and left.alt_pressed == right.alt_pressed
			and left.meta_pressed == right.meta_pressed
		)

	if left is InputEventMouseButton and right is InputEventMouseButton:
		return left.button_index == right.button_index

	return false
	
func _event_to_dict(event: InputEvent) -> Dictionary:
	var data: Dictionary = {"type": event.get_class()}
	if event is InputEventKey:
		data["keycode"] = int(event.keycode)
		data["physical_keycode"] = int(event.physical_keycode)
		data["unicode"] = int(event.unicode)
		data["shift_pressed"] = event.shift_pressed
		data["ctrl_pressed"] = event.ctrl_pressed
		data["alt_pressed"] = event.alt_pressed
		data["meta_pressed"] = event.meta_pressed
		data["pressed"] = event.pressed
		data["echo"] = event.echo
		data["location"] = int(event.location)
	elif event is InputEventJoypadButton:
		data["device"] = event.device
		data["button_index"] = int(event.button_index)
		data["pressed"] = event.pressed
	elif event is InputEventJoypadMotion:
		data["device"] = event.device
		data["axis"] = int(event.axis)
		data["axis_value"] = event.axis_value
	elif event is InputEventMouseButton:
		data["button_index"] = int(event.button_index)
		data["pressed"] = event.pressed
		data["double_click"] = event.double_click
	return data

func _dict_to_event(data: Dictionary) -> InputEvent:
	var event_type: String = str(data.get("type", ""))
	if event_type == "InputEventKey":
		var event := InputEventKey.new()
		event.keycode = int(data.get("keycode", 0))
		event.physical_keycode = int(data.get("physical_keycode", 0))
		event.unicode = int(data.get("unicode", 0))
		event.shift_pressed = bool(data.get("shift_pressed", false))
		event.ctrl_pressed = bool(data.get("ctrl_pressed", false))
		event.alt_pressed = bool(data.get("alt_pressed", false))
		event.meta_pressed = bool(data.get("meta_pressed", false))
		event.pressed = bool(data.get("pressed", false))
		event.echo = bool(data.get("echo", false))
		event.location = int(data.get("location", 0))
		return event
	elif event_type == "InputEventJoypadButton":
		var event := InputEventJoypadButton.new()
		event.device = int(data.get("device", 0))
		event.button_index = int(data.get("button_index", 0))
		event.pressed = bool(data.get("pressed", false))
		return event
	elif event_type == "InputEventJoypadMotion":
		var event := InputEventJoypadMotion.new()
		event.device = int(data.get("device", 0))
		event.axis = int(data.get("axis", 0))
		event.axis_value = float(data.get("axis_value", 0.0))
		return event
	elif event_type == "InputEventMouseButton":
		var event := InputEventMouseButton.new()
		event.button_index = int(data.get("button_index", 0))
		event.pressed = bool(data.get("pressed", false))
		event.double_click = bool(data.get("double_click", false))
		return event
	return null

func _format_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode)

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				return "Left Mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right Mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP:
				return "Mouse Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Mouse Wheel Down"
			MOUSE_BUTTON_WHEEL_LEFT:
				return "Mouse Wheel Left"
			MOUSE_BUTTON_WHEEL_RIGHT:
				return "Mouse Wheel Right"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2:
				return "Mouse 5"
			_:
				return "Mouse %d" % event.button_index

	if event is InputEventJoypadButton:
		return "Joy %d Button %d" % [event.device, event.button_index]

	if event is InputEventJoypadMotion:
		return "Joy %d Axis %d" % [event.device, event.axis]

	return event.as_text()


func get_binding_conflict(action_name: String, event: InputEvent) -> StringName:
	if not InputMap.has_action(action_name):
		return &""

	for other_action in InputMap.get_actions():
		if other_action == action_name or other_action.begins_with("ui_"):
			continue

		for other_event in InputMap.action_get_events(other_action):
			if _events_match(other_event, event):
				return StringName(other_action)

	return &""

func set_action_binding_force(
	action_name: String,
	new_event: InputEvent,
	replace_existing: bool = true
) -> bool:
	if not InputMap.has_action(action_name):
		return false

	if not (
		new_event is InputEventKey
		or new_event is InputEventMouseButton
	):
		return false

	# Remove this binding from every other action.
	for other_action in InputMap.get_actions():
		if other_action == action_name or other_action.begins_with("ui_"):
			continue

		var events_to_remove: Array[InputEvent] = []

		for other_event in InputMap.action_get_events(other_action):
			if _events_match(other_event, new_event):
				events_to_remove.append(other_event)

		for other_event in events_to_remove:
			InputMap.action_erase_event(other_action, other_event)

		# Save the changed conflicting action.
		if not events_to_remove.is_empty():
			key_bindings[other_action] = _serialize_action_events(other_action)

	# Remove the current action's old keyboard/mouse binding.
	var bindable_events: Array[InputEvent] = []

	for current_event in InputMap.action_get_events(action_name):
		if current_event is InputEventKey \
		or current_event is InputEventMouseButton:
			bindable_events.append(current_event)

	if replace_existing:
		for current_event in bindable_events:
			InputMap.action_erase_event(action_name, current_event)

	InputMap.action_add_event(action_name, new_event)

	key_bindings[action_name] = _serialize_action_events(action_name)

	_save()
	_apply_key_bindings()

	return true

func set_layout_state_and_save(state: Dictionary) -> void:
	layout_state = state.duplicate(true)
	_save()


func clear_layout_state_and_save() -> void:
	layout_state.clear()
	_save()


func has_layout_state() -> bool:
	return not layout_state.is_empty()
