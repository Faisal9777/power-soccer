# res://ui/Scoreboard.gd
extends Control

@export var tree_path: NodePath   # assign in Inspector (to your Tree)
var _tree: Tree

enum Team { BLUE, RED }

const TEAM_NAME := { Team.BLUE: "BLUE", Team.RED: "RED" }

# ---- Fake data (replace later) ----
# snapshot = [{id, name, team, goals, assists, saves}, ...]
var _fake_stats := [
	{"id": 1, "name": "Ayaan",  "team": Team.BLUE, "goals": 3, "assists": 1, "saves": 0},
	{"id": 2, "name": "Fardin", "team": Team.BLUE, "goals": 1, "assists": 2, "saves": 1},
	{"id": 3, "name": "Nabil", "team": Team.BLUE, "goals": 0, "assists": 1, "saves": 3},
	{"id": 4, "name": "Rafi",   "team": Team.RED,  "goals": 2, "assists": 0, "saves": 1},
	{"id": 5, "name": "Ahsan",   "team": Team.RED,  "goals": 1, "assists": 3, "saves": 0},
	{"id": 6, "name": "Hamza",  "team": Team.RED,  "goals": 0, "assists": 1, "saves": 2},
]

func _ready() -> void:
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
	set_stats(_fake_stats)

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
