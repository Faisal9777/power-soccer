extends Node

var state: Node
var game : Dictionary = {}
var _scoreboard_instance: Control
# ---------- UI ----------
var _ui_layer: CanvasLayer
var _hud_layer: CanvasLayer
var _time_label: Label
var _score_box: HBoxContainer
var _score_blue_lbl: Label
var _score_sep_lbl: Label
var _score_red_lbl: Label
var _countdown_label: Label
var _is_player_frozen:= true
var _network_endpoint : Node
var _all_player_frozen := true
var p_controllers = []

const BLUE := Color(0.20, 0.60, 1.00)
const RED  := Color(1.00, 0.30, 0.30)  
func set_scoreboard(scoreboard : Control) -> void:
	_scoreboard_instance = scoreboard

	#var stats_array = get_stats_in_array()
	#_scoreboard_instance.set_stats(stats_array)
# ---------- UI helpers ----------
func _create_timer_ui() -> void:
	# Canvas overlay so it’s always on top
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 100
	add_child(_ui_layer)

	var root := Control.new()
	root.name = "HUDRoot"
	root.size = get_viewport().get_visible_rect().size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(root)

	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.text = "00:00"
	_time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 28)
	_time_label.add_theme_color_override("font_color", Color(1,1,1))
	_time_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_time_label.add_theme_constant_override("outline_size", 4)

	# Top-center preset, then nudge down a bit
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(0, 18)
	root.add_child(_time_label)

func _build_hud_ui() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 100
	add_child(_hud_layer)

	var root := Control.new()
	root.size = get_viewport().get_visible_rect().size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)

	# Stack nicely using a VBoxContainer
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vbox.position = Vector2(0, 12)  # nudge down from the very top
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vbox)

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 28)
	_time_label.add_theme_color_override("font_color", Color(1,1,1))
	_time_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_time_label.add_theme_constant_override("outline_size", 4)
	_time_label.text = "00:00"
	vbox.add_child(_time_label)

	_score_box = HBoxContainer.new()
	_score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_score_box)

	_score_blue_lbl = Label.new()
	_score_blue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_blue_lbl.add_theme_font_size_override("font_size", 26)
	_score_blue_lbl.add_theme_color_override("font_color", Color(0.20, 0.60, 1.00))  # BLUE
	_score_blue_lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_score_blue_lbl.add_theme_constant_override("outline_size", 3)
	_score_blue_lbl.text = "BLUE 0"
	_score_box.add_child(_score_blue_lbl)

	_score_sep_lbl = Label.new()
	_score_sep_lbl.add_theme_font_size_override("font_size", 26)
	_score_sep_lbl.add_theme_color_override("font_color", Color(0.85,0.85,0.85))     # separator
	_score_sep_lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.6))
	_score_sep_lbl.add_theme_constant_override("outline_size", 2)
	_score_sep_lbl.text = " : "
	_score_box.add_child(_score_sep_lbl)

	_score_red_lbl = Label.new()
	_score_red_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_red_lbl.add_theme_font_size_override("font_size", 26)
	_score_red_lbl.add_theme_color_override("font_color", Color(1.00, 0.30, 0.30))  # RED
	_score_red_lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_score_red_lbl.add_theme_constant_override("outline_size", 3)
	_score_red_lbl.text = "RED 0"
	_score_box.add_child(_score_red_lbl)
	
	# Big center countdown label (separate, in the middle of the screen)
	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 64)
	_countdown_label.add_theme_color_override("font_color", Color(1,1,1))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.9))
	_countdown_label.add_theme_constant_override("outline_size", 6)
	_countdown_label.visible = false
	root.add_child(_countdown_label)

func _update_label(rem_ms: int) -> void:
	if _time_label == null: return
	var s := int(ceil(rem_ms / 1000.0))
	var m := s / 60
	var sec := s % 60
	_time_label.text = "%02d:%02d" % [m, sec]

func _update_score_label(blue:int, red:int) -> void:
	if _score_blue_lbl: _score_blue_lbl.text = "BLUE %d" % blue
	if _score_red_lbl:  _score_red_lbl.text  = "%d RED" % red

func _update_countdown_ui(ms:int) -> void:
	if ms > 0:
		#var s := int(ceil(ms / 1000.0))
		_countdown_label.text = str(ms)     # "3", "2", "1"
		_countdown_label.show()
	
	elif ms == 0:
		_countdown_label.text = "GO!"
		_countdown_label.show()

	elif ms == -1:
		_countdown_label.hide()

func _color_all_players(controllers : Array) -> void:
	for controller in controllers:
		var team : int = controller.team
		#print("about to calll _cl_init_entry: ", multiplayer.get_unique_id())
		# initialize only if missing
		var p = controller.player
		if team == GameState.Team.BLUE:
			_tint_recursive(p, BLUE)
		else:
			_tint_recursive(p, RED)

func _tint_recursive(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			var sc: int = mesh.get_surface_count()
			var s: int = 0
			while s < sc:
				var base_mat: Material = mi.get_surface_override_material(s)
				if base_mat == null:
					base_mat = mesh.surface_get_material(s)

				var new_mat: Material
				if base_mat != null:
					new_mat = base_mat.duplicate(true)
				else:
					new_mat = StandardMaterial3D.new()

				if new_mat is StandardMaterial3D:
					var sm: StandardMaterial3D = new_mat as StandardMaterial3D
					sm.albedo_color = col
				elif new_mat is ShaderMaterial:
					var sh: ShaderMaterial = new_mat as ShaderMaterial
					# your shader must have a 'tint_color' uniform (change name if different)
					sh.set_shader_parameter("tint_color", col)

				mi.set_surface_override_material(s, new_mat)
				s += 1

	# recurse children
	var children: Array = n.get_children()
	for i in children.size():
		var child: Node = children[i] as Node
		_tint_recursive(child, col)

func setup(ingame : Node, scoreboard, controllers) -> void:

	state = ingame
	state.phase_changed.connect(_on_phase_changed)
	_scoreboard_instance = scoreboard
	p_controllers = controllers
	for controller in p_controllers:
		_init_entry(controller.id, controller.name, controller.team)
	_color_all_players(controllers)

func _ready() -> void:
	
	_build_hud_ui()
	set_multiplayer_authority(1)

func _physics_process(delta: float) -> void:
	#if _is_player_frozen and not state.is_paused:
		#_toggle_player_process(true)
		#_is_player_frozen = false

	if state and state.can_process:
		if not state.is_paused:
			# Everyone (server + clients) renders from replicated time_left_ms
			_update_label(state.time_left_ms)
		if state.goal_scored:
			_countdown_label.text = "Goal!"     # "3", "2", "1"
			_countdown_label.show()
		else:
			_update_countdown_ui(state.countdown_ms)
			_update_score_label(state.blue_score, state.red_score)

func _position_players() -> void:
	return


func start_game(game_data) -> void:
	_position_players2(game_data)

func end_game(value : Dictionary) -> void:
	var scene := value.get(multiplayer.get_unique_id(), NodePath("")) as NodePath
	GameState.game_results = state.game_data
	_end_match(scene)

func _position_players2(game_data) -> void:
	var ball_position : Vector3 = game_data["ball_position"]
	for controller in p_controllers:
		controller.set_position(game_data[controller.id]["position"])
		
		_init_entry(controller.id, controller.name, controller.team)
		controller.face_at(ball_position)
		controller.freeze(game_data[controller.id]["freeze"])
	

func _init_entry(pid: int, name: String, team: int) -> void:
	# Each peer (and the caller) runs this locally
	game.get_or_add(pid, {
		"name": name,
		"goals": 0,
		"team": team,
		"assists": 0,
		"saves": 0,
	}) as Dictionary
	#if _scoreboard_instance:
		#var stats_array = get_stats_in_array()
		#_scoreboard_instance.set_stats(stats_array)
func _end_match(scene_path_to_load: String) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(scene_path_to_load)

func _show_banner_for(text: String, seconds: float) -> void:
	if _countdown_label == null:  # or is_instance_valid(_countdown_label)
		return
	_countdown_label.text = text
	_countdown_label.show()
	var t := get_tree().create_timer(seconds)  # local, per-client
	await t.timeout
	_countdown_label.hide()

func _on_phase_changed(old, new) -> void:
	if state.WorldPhase.POST_MATCH:
		_countdown_label.text = "End!"
		_countdown_label.show()
