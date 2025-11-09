## Lobby.gd (Godot 4.x)
#extends Control
#
#@onready var status_label: Label  = $PanelContainer/VBoxContainer/StatusLabel
#@onready var player_list: ItemList = $PanelContainer/VBoxContainer/PlayerList
#@onready var start_btn: Button    = $PanelContainer/VBoxContainer/HBoxContainer/StartButton
#@onready var leave_btn: Button    = $PanelContainer/VBoxContainer/HBoxContainer/LeaveButton
#@onready var ready_btn: Button    = $PanelContainer/VBoxContainer/HBoxContainer/ReadyButton  # <-- add a Ready button in your scene
#
#const WORLD_SCENE := "res://world.tscn"
#
#func _ready() -> void:
	## If we opened this as host, ensure server is running (idempotent)
	#if GameState.is_host:
		#Network.host()
		## Ensure host entry exists
		#GameState.roster[1] = GameState.roster.get(1, {"name": GameState.player_name, "ready": false})
	#else:
		## As a client, tell the host our name (submit on first frame so multiplayer is ready)
		#call_deferred("_deferred_submit_name")
#
	## UI wiring
	#start_btn.disabled = !GameState.is_host
	#ready_btn.text = "Unready" if _my_ready() else "Ready"
#
	#start_btn.pressed.connect(_on_press_start)
	#leave_btn.pressed.connect(_on_press_leave)
	#ready_btn.pressed.connect(_on_press_ready)
#
	## Update roster display regularly via signals and when RPCs arrive
	#Network.peer_joined.connect(func(_id): _refresh_ui())
	#Network.peer_left.connect(func(id):
		#if GameState.is_host and GameState.roster.has(id):
			#GameState.roster.erase(id)
			#_broadcast_roster()
		#_refresh_ui()
	#)
#
	#_refresh_ui()
#
#func _deferred_submit_name() -> void:
	#if multiplayer.multiplayer_peer == null: return
	## Send name to host (peer 1). Host is authoritative about the roster.
	#rpc_id(1, "_rpc_submit_name", GameState.player_name)
#
#func _on_press_ready() -> void:
	#var new_ready := !_my_ready()
	#_set_my_ready_local(new_ready)  # immediate feedback
	## Tell host to update authoritative roster; host will broadcast back.
	#rpc_id(1, "_rpc_set_ready", multiplayer.get_unique_id(), new_ready)
	#ready_btn.text = "Unready" if new_ready else "Ready"
	#_refresh_ui()
#
#func _on_press_start() -> void:
	#if !GameState.is_host: return
	## Optional: enforce all-ready
	## for id in GameState.roster:
	##     if GameState.roster[id].ready != true:
	##         push_warning("Not everyone is ready.")
	##         return
	## Broadcast start to all peers; everyone switches scene together.
	#rpc("_rpc_start_match", WORLD_SCENE)
#
#func _on_press_leave() -> void:
	## Simple leave: go back to title and nuke local state (you can add disconnect if you want)
	#GameState.reset_lobby()
	#get_tree().change_scene_to_file("res://title_screen.tscn")
#
#func _refresh_ui() -> void:
	#player_list.clear()
#
	## Show connected count from roster (host view) or from what we last received
	#var roster := GameState.roster
	#for id in roster.keys():
		#var entry = roster[id]
		#var host_tag  := " (Host)" if id == 1 else ""
		#var ready_tag := "✓" if entry["ready"] else ""   # use entry.ready if it's an object; entry["ready"] if it's a Dictionary
		#var label := "%s%s %s" % [entry["name"], host_tag, ready_tag]
		#player_list.add_item(label)
#
	#status_label.text = "Connected: %d" % roster.size()
#
## ---------- Ready helpers ----------
#func _my_ready() -> bool:
	#var my_id := multiplayer.get_unique_id()
	#if GameState.is_host and my_id == 1:
		#return GameState.roster[1].ready
	#if GameState.roster.has(my_id):
		#return GameState.roster[my_id].ready
	#return false
#
#func _set_my_ready_local(v: bool) -> void:
	#var my_id := multiplayer.get_unique_id()
	#if !GameState.roster.has(my_id):
		#GameState.roster[my_id] = {"name": GameState.player_name, "ready": v}
	#else:
		#GameState.roster[my_id].ready = v
#
## ---------- RPCs ----------
## Clients → Host: submit name (authoritative add)
#@rpc("any_peer")
#func _rpc_submit_name(name: String) -> void:
	#if !GameState.is_host: return
	#var from := multiplayer.get_remote_sender_id()
	#GameState.roster[from] = {"name": name, "ready": false}
	#_broadcast_roster()
#
## Clients → Host: set ready
#@rpc("any_peer")
#func _rpc_set_ready(peer_id: int, ready: bool) -> void:
	#if !GameState.is_host: return
	## Trust: only accept the caller updating their own state
	#var from := multiplayer.get_remote_sender_id()
	#if from != peer_id: return
	#if GameState.roster.has(peer_id):
		#GameState.roster[peer_id].ready = ready
	#_broadcast_roster()
#
## Host → Everyone: send full roster snapshot
#func _broadcast_roster() -> void:
	#if !GameState.is_host: return
	## Send as array of dicts with id included for stable rehydration
	#var snapshot: Array = []
	#for id in GameState.roster.keys():
		#var e = GameState.roster[id]
		#snapshot.append({"id": id, "name": e.name, "ready": e.ready})
	#rpc("_rpc_set_roster", snapshot)
	#_refresh_ui()
#
#@rpc("any_peer", "call_local")
#func _rpc_set_roster(snapshot: Array) -> void:
	#var dict := {}
	#for e in snapshot:
		#dict[int(e.id)] = {"name": String(e.name), "ready": bool(e.ready)}
	#GameState.roster = dict
	#_refresh_ui()
#
## Host → Everyone: start the match (switch scene)
#@rpc("any_peer", "call_local")
#func _rpc_start_match(scene_path: String) -> void:
	#get_tree().change_scene_to_file(scene_path)
extends Control

@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel
@onready var player_list: Tree = $PanelContainer/VBoxContainer/PlayerList  # Tree (not ItemList)
@onready var start_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/StartButton
@onready var leave_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/LeaveButton
@onready var ready_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/ReadyButton
# (Optional: if you kept a bottom TeamButton, you can remove it or ignore it.)

var _ui_ids: Array[int] = []  # peer_id order as shown (not needed for Tree, kept for reference)
const WORLD_SCENE := "res://world.tscn"
const Team = GameState.Team
const TEAM_COLOR := {
	GameState.Team.BLUE: Color(0.2, 0.6, 1.0),
	GameState.Team.RED:  Color(1.0, 0.3, 0.3)
}

func _ready() -> void:
	# --- Build the Tree columns + per-row buttons ---
	_setup_player_tree()
	# Tree signal (per-row button)
	player_list.button_clicked.connect(_on_tree_button_clicked)

	# --- (Optional but useful) Layout so the list expands properly ---
	var root_ctrl := self as Control
	root_ctrl.anchor_left = 0; root_ctrl.anchor_top = 0
	root_ctrl.anchor_right = 1; root_ctrl.anchor_bottom = 1
	root_ctrl.offset_left = 0; root_ctrl.offset_top = 0
	root_ctrl.offset_right = 0; root_ctrl.offset_bottom = 0

	var panel := $PanelContainer
	var vbox  := $PanelContainer/VBoxContainer
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical    = Control.SIZE_EXPAND_FILL

	player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_list.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	player_list.custom_minimum_size   = Vector2(0, 220)
	status_label.size_flags_vertical  = 0
	$PanelContainer/VBoxContainer/HBoxContainer.size_flags_vertical = 0

	# --- Debug info ---
	print("[lobby] whoami=", multiplayer.get_unique_id(),
		" is_host=", GameState.is_host,
		" path=", get_path())

	# --- Ensure host exists and has a team (host-only) ---
	if GameState.is_host:
		var host: Dictionary = GameState.roster.get(1, {})
		if host.is_empty():
			GameState.roster[1] = {
				"name": GameState.player_name,
				"ready": false,
				"team": GameState.pick_balanced_team()
			}
		elif !host.has("team"):
			GameState.roster[1]["team"] = GameState.pick_balanced_team()
	else:
		# Client announces name to host after Multiplayer is ready
		call_deferred("_submit_name_to_host")

	# --- Buttons + initial state ---
	start_btn.disabled = !GameState.is_host
	ready_btn.text = "Unready" if _my_ready() else "Ready"

	start_btn.pressed.connect(_on_start)
	leave_btn.pressed.connect(_on_leave)
	ready_btn.pressed.connect(_on_ready_toggle)

	# --- P2P events: refresh UI & keep roster tidy (host removes leavers) ---
	Network.peer_joined.connect(func(_id):
		_refresh_ui()
		_update_start_enabled()
	)
	
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.peer_connected.connect(_on_peer_connected)
	
	
	# If the server (host) goes away, clients should bounce to title
	multiplayer.server_disconnected.connect(_on_host_gone)
	multiplayer.connection_failed.connect(_on_host_gone)

	Network.peer_left.connect(func(id):
		# If the host (peer 1) disappears and we are a client, leave lobby
		if id == 1 and !GameState.is_host:
			_on_host_gone()
			return
		if GameState.is_host and GameState.roster.has(id):
			GameState.roster.erase(id)
			_broadcast_roster()
		_refresh_ui()
		_update_start_enabled()
	)

	# --- First paint ---
	_refresh_ui()
	_update_start_enabled()

func _on_connected_to_server() -> void:
	# Client: tell server our name right after connect
	#print("CLIENT ID %d" % GameState.)
	rpc_id(GameState.id, "_rpc_submit_name", GameState.player_name)

func _peer_name(pid: int) -> String:
	return GameState.roster.get(pid, {}).get("name", "Player %d" % pid)



# When any peer connects (server side), you can request their name if you prefer pull:
func _on_peer_connected(pid: int) -> void:
	if multiplayer.is_server():
		# Optionally pre-create an entry to avoid has() failure later
		if !GameState.roster.has(pid):
			GameState.roster[pid] = {"name": "Player %d" % pid, "ready": false}
		# (Then either wait for their _rpc_submit_name, or actively request it)

# -------------------- Tree setup / UI --------------------

func _setup_player_tree() -> void:
	player_list.columns = 3
	player_list.hide_root = true
	player_list.set_column_titles_visible(true)
	player_list.set_column_title(0, "Player")
	player_list.set_column_title(1, "Team")
	player_list.set_column_title(2, "Swap")
	player_list.set_column_expand(0, true)   # name expands
	player_list.set_column_expand(1, false)
	player_list.set_column_expand(2, false)
	# Per-row button signal
	player_list.button_clicked.connect(_on_tree_button_clicked)

func _refresh_ui() -> void:
	player_list.clear()
	var root := player_list.create_item()  # root is hidden (hide_root = true)

	# Stable order
	var ids := GameState.roster.keys()
	ids.sort()

	_ui_ids = []  # not necessary for Tree, but we’ll keep it synced
	for k in ids:
		var pid := int(k)
		_ui_ids.append(pid)

		var e: Dictionary = GameState.roster[pid]
		var name_str  := String(e.get("name", "Player"))
		var is_ready  := bool(e.get("ready", false))
		var team_val  := int(e.get("team", -1))
		var host_tag  := " (Host)" if pid == 1 else ""
		var ready_tag := " ✓" if is_ready else ""

		var item := player_list.create_item(root)
		item.set_metadata(0, pid)  # store peer_id on row

		# Column 0: Player label
		item.set_text(0, "%s%s%s" % [name_str, host_tag, ready_tag])

		# Column 1: Team text + color
		var team_text := "UNASSIGNED" if team_val == -1 else ("BLUE" if team_val == Team.BLUE else "RED")
		item.set_text(1, team_text)

		var col := Color(0.8,0.8,0.8) if team_val == -1 else (TEAM_COLOR[Team.BLUE] if team_val == Team.BLUE else TEAM_COLOR[Team.RED])
		item.set_custom_color(1, col)

		# Column 2: Per-row swap button (host only; show only if assigned)
		if GameState.is_host and team_val != -1:
			var icon: Texture2D = player_list.get_theme_icon("Reload", "EditorIcons")
			if icon == null:
				# Fallback to a built-in control icon that exists at runtime more reliably
				icon = player_list.get_theme_icon("Reload", "Tree")  # try Tree’s theme
			item.add_button(2, icon, 0, false, "Switch team")
		else:
			item.set_text(2, "")

	status_label.text = "Connected: %d" % int(GameState.roster.size())
	_update_start_enabled()

func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if !GameState.is_host: return
	if column != 2: return
	var pid := int(item.get_metadata(0))
	if !GameState.roster.has(pid): return
	var cur := int(GameState.roster[pid].get("team", GameState.Team.BLUE))
	var next := GameState.Team.RED if cur == GameState.Team.BLUE else GameState.Team.BLUE
	GameState.roster[pid]["team"] = next
	_broadcast_roster()
	_update_start_enabled()
# -------------------- Start button enable/disable --------------------
func _all_ready() -> bool:
	for id in GameState.roster.keys():
		var e: Dictionary = GameState.roster[id]
		if !e.get("ready", false):
			return false
	return GameState.roster.size() >= 2

func _everyone_has_a_team() -> bool:
	for id in GameState.roster.keys():
		var e: Dictionary = GameState.roster[id]
		if !e.has("team") or int(e["team"]) == -1:
			return false
	return true

func _teams_equal_nonzero() -> bool:
	var counts := _counts_by_team()
	var blue: int = int(counts[Team.BLUE])
	var red:  int = int(counts[Team.RED])
	return blue == red and blue > 0

func _counts_by_team() -> Dictionary:
	var counts := { Team.BLUE: 0, Team.RED: 0 }
	for id in GameState.roster.keys():
		var e: Dictionary = GameState.roster[id]
		if e.has("team"):
			if e["team"] == Team.BLUE: counts[Team.BLUE] += 1
			elif e["team"] == Team.RED: counts[Team.RED] += 1
	return counts

func _update_start_enabled() -> void:
	var ok := GameState.is_host \
		and _all_ready() \
		and _everyone_has_a_team() \
		and _teams_equal_nonzero()

	start_btn.disabled = not ok

	# (Nice UX) show why it's disabled
	if !GameState.is_host:
		start_btn.tooltip_text = "Only the host can start."
	elif !_all_ready():
		start_btn.tooltip_text = "Everyone must be Ready."
	elif !_everyone_has_a_team():
		start_btn.tooltip_text = "Everyone needs a team."
	elif !_teams_equal_nonzero():
		start_btn.tooltip_text = "Teams must be equal (e.g., 1v1, 2v2…)."
	else:
		start_btn.tooltip_text = ""

# -------------------- Lobby flow --------------------

func _submit_name_to_host() -> void:
	if multiplayer.multiplayer_peer == null: return
	print("[client] sending name to host…")
	rpc_id(1, "_rpc_submit_name", GameState.player_name)

func _on_ready_toggle() -> void:
	var new_ready := !_my_ready()
	_set_my_ready_local(new_ready)
	ready_btn.text = "Unready" if new_ready else "Ready"
	# Tell host (authoritative) to update and broadcast
	rpc_id(1, "_rpc_set_ready", multiplayer.get_unique_id(), new_ready)
	_refresh_ui()
	_update_start_enabled()

func _on_start() -> void:
	if !GameState.is_host: return
	rpc("_rpc_start_match", WORLD_SCENE)

func _on_leave() -> void:
	if GameState.is_host:
		# Tell everyone we're going away; then close.
		rpc("_rpc_host_is_leaving")
	GameState.reset_lobby()
	Network.close_connection()
	get_tree().change_scene_to_file("res://title_screen.tscn")

func _on_host_gone() -> void:
	print("[lobby] host disconnected or left")
	status_label.text = "Host left. Returning to title..."
	# Clear local state and return to title
	GameState.reset_lobby()
	Network.close_connection()
	get_tree().change_scene_to_file("res://title_screen.tscn")

# -------------------- Helpers --------------------

func _my_ready() -> bool:
	var me := multiplayer.get_unique_id()
	return GameState.roster.has(me) and GameState.roster[me]["ready"]

func _set_my_ready_local(v: bool) -> void:
	var me := multiplayer.get_unique_id()
	if !GameState.roster.has(me):
		GameState.roster[me] = {"name": GameState.player_name, "ready": v}
	else:
		GameState.roster[me]["ready"] = v


# -------------------- RPCs --------------------

@rpc("any_peer")
func _rpc_submit_name(name: String) -> void:
	if !GameState.is_host: return
	var from := multiplayer.get_remote_sender_id()
	var team := GameState.pick_balanced_team()
	GameState.roster[from] = {
		"name": name,
		"ready": false,
		"team": team
	}
	_broadcast_roster()

@rpc("any_peer")
func _rpc_set_ready(peer_id: int, ready: bool) -> void:
	if !GameState.is_host: return
	var from := multiplayer.get_remote_sender_id()
	if from != peer_id: return
	if GameState.roster.has(peer_id):
		GameState.roster[peer_id]["ready"] = ready
	_broadcast_roster()

@rpc("any_peer", "call_local")
func _rpc_host_is_leaving() -> void:
	if !GameState.is_host:
		_on_host_gone()

func _broadcast_roster() -> void:
	if !GameState.is_host: return
	var snapshot: Array = []
	for id in GameState.roster.keys():
		var e = GameState.roster[id]
		snapshot.append({
			"id": id,
			"name": e["name"],
			"ready": e["ready"],
			"team": e.get("team", Team.BLUE)
		})
	rpc("_rpc_set_roster", snapshot)
	_refresh_ui()

@rpc("any_peer", "call_local")
func _rpc_set_roster(snapshot: Array) -> void:
	var dict := {}
	for e in snapshot:
		dict[int(e["id"])] = {
			"name": String(e["name"]),
			"ready": bool(e["ready"]),
			"team":  int(e.get("team", Team.BLUE))
		}
	print("ROSTERRRRRR")
	GameState.roster = dict
	print(GameState.roster)
	_refresh_ui()
	_update_start_enabled()

@rpc("any_peer", "call_local")
func _rpc_start_match(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
@rpc("any_peer", "reliable")
func _rpc_set_my_name(name: String) -> void:
	if multiplayer.is_server():
		var pid := multiplayer.get_remote_sender_id()
		if GameState.roster.has(pid):
			GameState.roster[pid]["name"] = name
		# optionally broadcast a lobby refresh to everyone here
