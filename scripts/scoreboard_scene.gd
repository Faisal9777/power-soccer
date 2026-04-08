# res://ui/Scoreboard.gd
extends Control

@export var tree_path: NodePath   # assign in Inspector (to your Tree)
var _tree: Tree
var _game_data_holder : Node
var _sc_popup : Control
enum Team { BLUE, RED }
var _lobby_scene_path := NodePath('')
var _back_btn: Button
var _status: Label

const TEAM_NAME := { Team.BLUE: "BLUE", Team.RED: "RED" }

func _add_back_to_lobby_ui() -> void:
	_back_btn = Button.new()
	_back_btn.text = "Back to Lobby"
	add_child(_back_btn)

	# Bottom-center with padding
	_back_btn.custom_minimum_size = Vector2(240, 44)
	_back_btn.anchor_left = 0.5
	_back_btn.anchor_right = 0.5
	_back_btn.anchor_top = 1.0
	_back_btn.anchor_bottom = 1.0
	_back_btn.offset_left = -120
	_back_btn.offset_right = 120
	_back_btn.offset_top = -60
	_back_btn.offset_bottom = -16

	_status = Label.new()
	_status.text = ""
	add_child(_status)
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = -200
	_status.offset_right = 200
	_status.offset_top = -95
	_status.offset_bottom = -70
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if not _back_btn.pressed.is_connected(_on_back_pressed):
		_back_btn.pressed.connect(_on_back_pressed)

func _ready() -> void:
	_add_back_to_lobby_ui()
	var result = _get_stats_in_array(GameState.game_results)
	# Resolve the Tree node (via exported path, or auto-find by name)
	_tree = get_node_or_null(tree_path) as Tree
	if _tree == null:
		_tree = find_child("Tree", true, false) as Tree
	if _tree == null:
		push_error("Scoreboard: Tree not found. Assign 'tree_path' in the Inspector or name a child 'Tree'.")
		return

	# (Nice defaults so Containers don't squash it)
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size   = Vector2(680, 360)

	_setup_columns()
	# Render the fake data now
	set_stats(result)


func set_game_data_holder(holder: Node, sc_popup : Control) -> void:

	_game_data_holder = holder
	_sc_popup = sc_popup
	# Team he

func show_score(toggle : bool) -> void:
	var data : Dictionary = _game_data_holder.get_game_data()
	var stats : Array = _get_stats_in_array(data)
	set_stats(stats)
	_sc_popup.visible = toggle

# -------- Public API: call later with real data --------
# snapshot = [{id, name, team (0/1), goals, assists, saves}, ...]
func set_stats(snapshot: Array) -> void:

	_tree.clear()
	var root := _tree.create_item()

	# Team headers
	var blue := _tree.create_item(root)
	blue.set_text(0, TEAM_NAME[Team.BLUE])

	var red  := _tree.create_item(root)
	red.set_text(0, TEAM_NAME[Team.RED])

	# Sort by name (optional)
	var rows := snapshot.duplicate(true)
	rows.sort_custom(Callable(self, "_cmp_by_name"))

	# Add rows
	for r in rows:
		var team := int(r.get("team", Team.BLUE))
		var parent := (blue if team == Team.BLUE else red)
		var it := _tree.create_item(parent)
		it.set_text(0, String(r.get("name", "Player")))
		it.set_text(1, str(int(r.get("goals", 0))))
		it.set_text(2, str(int(r.get("assists", 0))))
		it.set_text(3, str(int(r.get("saves", 0))))

# Comparator used by sort_custom
func _cmp_by_name(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("name", "")) < String(b.get("name", ""))

func _setup_columns() -> void:
	_tree.columns = 4
	_tree.hide_root = true
	_tree.set_column_titles_visible(true)
	_tree.set_column_title(0, "Player")
	_tree.set_column_title(1, "G")
	_tree.set_column_title(2, "A")
	_tree.set_column_title(3, "S")

	# Player column expands; G/A/S stay tight
	_tree.set_column_expand(0, true)
	for c in range(1, 4):
		_tree.set_column_expand(c, false)
		_tree.set_column_custom_minimum_width(c, 48)

# (Optional) close if used as a standalone popup and user hits ESC
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and !e.echo and (e.keycode == KEY_ESCAPE or e.physical_keycode == KEY_ESCAPE):
		queue_free()

func _get_stats_in_array(game: Dictionary) -> Array[Dictionary]:
	var stats: Array[Dictionary] = []

	for k in game.keys():
		var pid: int = int(k)
		var e := game[k] as Dictionary

		# name: prefer _game entry; fall back to GameState.roster
		var name_val: String = ""
		if e.has("name"):
			name_val = String(e["name"])

		# team: derive from your helper
		var team_val := e["team"] as int


		# build one row
		var row: Dictionary = {
			"id": k,
			"name": name_val,
			"team": team_val,
			"goals": int(e.get("goals", 0)),
			"assists": int(e.get("assists", 0)),
			"saves": int(e.get("saves", 0)),  # default to 0 if you don't track it
		}
		stats.append(row)

	# (Optional) stable ordering by id
	stats.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return stats

func _on_back_pressed() -> void:
	_back_btn.disabled = true
	_status.text = "Waiting for other players..."

	SessionManager.session_node.change_state(_lobby_scene_path)
