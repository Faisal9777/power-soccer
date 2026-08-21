extends Control


const PROFILE_ICON_PICKER = preload(
	"res://scripts/ui/ProfileIconPicker.gd"
)

var _icon_picker: Control
var _icon_rect: TextureRect
var _profile_menu: PopupMenu
var _profile_overlay: Button

func setup() -> void:
	name = "ProfileUI"
	var ui_scale := clampf(
		get_viewport_rect().size.x / 1920.0,
		0.75,
		1.25
	)
	# Position in top-right
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	
	offset_top = 20
	offset_right = -20


	# --------------------------------------------------
	# Background panel
	# --------------------------------------------------

	var panel := PanelContainer.new()
	panel.name = "ProfilePanel"

	# Responsive size
	var viewport_size := get_viewport_rect().size

	var panel_width := clampf(
		viewport_size.x * 0.18,
		200.0,
		300.0
	)

	var panel_height := clampf(
		viewport_size.y * 0.09,
		80.0,
		110.0
	)

	panel.custom_minimum_size = Vector2(
		panel_width,
		panel_height
	)
	offset_left = offset_right - panel_width
	offset_bottom = offset_top + panel_height

	add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#202129")
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10

	panel.add_theme_stylebox_override("panel", panel_style)

	# --------------------------------------------------
	# Padding
	# --------------------------------------------------

	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		int(20.0 * ui_scale)
	)

	margin.add_theme_constant_override(
		"margin_right",
		int(20.0 * ui_scale)
	)

	margin.add_theme_constant_override(
		"margin_top",
		int(15.0 * ui_scale)
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		int(15.0 * ui_scale)
	)
	panel.add_child(margin)

	# --------------------------------------------------
	# Profile contents
	# --------------------------------------------------

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(15.0 * ui_scale))

	margin.add_child(hbox)

	# --------------------------------------------------
	# Profile icon
	# --------------------------------------------------
	_icon_rect = TextureRect.new()
	_icon_rect.name = "ProfileIcon"
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_icon_rect.custom_minimum_size = Vector2(
		40.0 * ui_scale,
		40.0 * ui_scale
	)

	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture = load(Settings.profile_icon_path)

	hbox.add_child(_icon_rect)
	_icon_picker = PROFILE_ICON_PICKER.new()
	_icon_picker.name = "ProfileIconPicker"

	add_child(_icon_picker)

	_icon_picker.icon_selected.connect(_on_icon_selected)
		# --------------------------------------------------
	# Profile popup menu
	# --------------------------------------------------

	_profile_menu = PopupMenu.new()
	_profile_menu.add_theme_font_size_override("font_size", 16)
	_profile_menu.add_theme_constant_override("item_start_padding", 8)
	_profile_menu.add_theme_constant_override("item_end_padding", 8)
	_profile_menu.add_theme_constant_override("item_icon_max_width", 0)
	_profile_menu.add_theme_constant_override("item_vertical_padding", 4)

	_profile_menu.add_item("Change Profile Icon", 1)
	_profile_menu.add_item("Logout", 2)
	_profile_menu.id_pressed.connect(_on_profile_menu_option_pressed)

	add_child(_profile_menu)
	# --------------------------------------------------
	# Player name
	# --------------------------------------------------

	var name_label := Label.new()

	if GameState.player_name != "":
		name_label.text = GameState.player_name
	else:
		name_label.text = "Player"

	name_label.add_theme_font_size_override("font_size", int(24.0 * ui_scale))
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	hbox.add_child(name_label)

	# --------------------------------------------------
	# Clickable overlay
	# --------------------------------------------------

	_profile_overlay = Button.new()

	_profile_overlay.name = "ProfileButton"

	# Make it fill the panel
	_profile_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	_profile_overlay.flat = true
	_profile_overlay.focus_mode = Control.FOCUS_NONE
	_profile_overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Transparent button
	var transparent_style := StyleBoxFlat.new()
	transparent_style.bg_color = Color(0, 0, 0, 0)

	_profile_overlay.add_theme_stylebox_override(
		"normal",
		transparent_style
	)

	_profile_overlay.add_theme_stylebox_override(
		"hover",
		transparent_style
	)

	_profile_overlay.add_theme_stylebox_override(
		"pressed",
		transparent_style
	)

	panel.add_child(_profile_overlay)

	# --------------------------------------------------
	# Click signal
	# --------------------------------------------------

	_profile_overlay.pressed.connect(_on_profile_clicked)

	# --------------------------------------------------
	# Logout Confirmation Dialog
	# --------------------------------------------------
	var logout_dialog := ConfirmationDialog.new()
	logout_dialog.name = "LogoutDialog"
	logout_dialog.dialog_text = "Are you sure you want to log out?"
	logout_dialog.confirmed.connect(_do_logout)
	add_child(logout_dialog)

func _on_profile_clicked() -> void:
	print("PROFILE BUTTON CLICKED")

	var overlay_rect := _profile_overlay.get_global_rect()

	_profile_menu.position = Vector2i(
		overlay_rect.position.x,
		overlay_rect.position.y + overlay_rect.size.y
	)

	_profile_menu.popup()
func _on_profile_icon_clicked() -> void:
	_icon_picker.open()
	
func _on_icon_selected(icon_path: String) -> void:
	_icon_rect.texture = load(icon_path)

func _on_profile_menu_option_pressed(id: int) -> void:
	match id:
		1:
			# Change Profile Icon
			_icon_picker.open()

		2:
			# Logout
			var dialog := get_node_or_null("LogoutDialog")
			if dialog:
				dialog.popup_centered()

func _do_logout() -> void:
	# 1. Cleanly leave active lobby/match
	if multiplayer.multiplayer_peer != null:
		Network.close_connection()

	# 2. Reset player-specific state
	GameState.player_name = ""
	GameState.clear()
	Settings.set_player_name_and_save("")
	Settings.set_profile_icon_and_save("res://Texture/Profile_Icons/Apple.svg")

	# 3. Log out via AuthManager (handles Google & Guest)
	AuthManager.logout()

	# 4. Return to title screen (which handles the login overlay when no session exists)
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
