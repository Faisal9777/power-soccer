#lobby
extends Control

@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel
@onready var player_list: Tree = $PanelContainer/VBoxContainer/PlayerList  # Tree (not ItemList)
@onready var start_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/StartButton
@onready var leave_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/LeaveButton
@onready var ready_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/ReadyButton
@onready var match_size_opt: OptionButton = $PanelContainer/VBoxContainer/HBoxContainer/MatchSizeOption
@onready var fill_bots_check: CheckButton = $PanelContainer/VBoxContainer/HBoxContainer/FillBotsCheck

const C = preload("res://scripts/shared/scene.gd")
const MIN_TEAM_SIZE := 1
const MAX_TEAM_SIZE := 10

var _server_bots_enabled: bool = false
var _team_size: int = MIN_TEAM_SIZE  # players per team (1..5)
var _next_bot_id: int = 100000  # fake peer ids for bots

# (Optional: if you kept a bottom TeamButton, you can remove it or ignore it.)

var _ui_ids: Array[int] = []  # peer_id order as shown (not needed for Tree, kept for reference)
const WORLD_SCENE := "res://scenes/world.tscn"
const Team = GameState.Team
const TEAM_COLOR := {
	GameState.Team.BLUE: Color(0.2, 0.6, 1.0),
	GameState.Team.RED:  Color(1.0, 0.3, 0.3)
}
# ⬇ NEW: Human-readable role names
var ROLE_NAME := { 
	GameState.Role.GOALKEEPER: "Goalkeeper",
	GameState.Role.MIDFIELDER: "Midfielder",
	GameState.Role.FORWARD: "Forward",
}
# ⬇ NEW: Ability IDs + names
const ABILITY_IDS: Array[String] = ["grapple"]  # add later: ["grapple","dash","blink",...]
var ABILITY_NAME := {
	"grapple": "Grapple",
}

func _get_ability_id(e: Dictionary) -> String:
	return String(e.get("ability", "grapple"))

func _cycle_ability(cur: String) -> String:
	var i := ABILITY_IDS.find(cur)
	if i == -1: i = 0
	return ABILITY_IDS[(i + 1) % ABILITY_IDS.size()]


func _ready() -> void:
	GameState.lobby_size = _team_size*2
	# --- Build the Tree columns + per-row buttons ---
	print("YOU ARE SEEING THE NEW UPDATEE")
	_setup_player_tree()

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
		" is_dedicated2=", GameState.is_dedicated_server(),
		" path=", get_path())

	# --- Ensure host exists and has a team (listen-server only) ---
	if GameState.is_host and not GameState.is_dedicated_server():
		var host_id := multiplayer.get_unique_id() # usually 1
		var host: Dictionary = GameState.roster.get(host_id, {})

		if host.is_empty():
			GameState.roster[host_id] = {
				"name": GameState.player_name,
				"ready": false,
				"team": GameState.pick_balanced_team(),
				"ability": "grapple", # ✅ ADD HERE
			}
		else:
			# Ensure required fields exist even if entry was created earlier
			if !host.has("team"):
				host["team"] = GameState.pick_balanced_team()
			if !host.has("ability"):
				host["ability"] = "grapple" # ✅ BACKFILL HERE

			GameState.roster[host_id] = host

	elif not GameState.is_host:
		# Client announces name to host after Multiplayer is ready
		call_deferred("_submit_name_to_host")
	# (Dedicated server: falls through, no roster entry for id=1)
# --- Ensure a lobby leader exists (server side) ---
	if multiplayer.is_server():
		_ensure_leader_exists()
		_broadcast_roster()  # so everyone immediately sees leader + roster

	# --- Buttons + initial state ---
	# Start button enabled/disabled will be decided by _update_start_enabled()
	start_btn.disabled = true
	ready_btn.text = "Unready" if _my_ready() else "Ready"

	start_btn.pressed.connect(_on_start)
	leave_btn.pressed.connect(_on_leave)
	ready_btn.pressed.connect(_on_ready_toggle)

	# --- Match-size dropdown (1v1 .. 5v5) ---
	if match_size_opt:
		match_size_opt.clear()
		for s in range(MIN_TEAM_SIZE, MAX_TEAM_SIZE + 1):
			match_size_opt.add_item("%dv%d" % [s, s], s)  # id = team size
		match_size_opt.select(0)  # default 1v1
		# Only the host can change the mode
		match_size_opt.disabled = true
		match_size_opt.item_selected.connect(_on_match_size_selected)

		if GameState.is_host:
			# Make sure clients see the same initial value
			rpc("_rpc_set_team_size", _team_size)
	# --- Fill with bots checkbox ---
	if fill_bots_check:
		fill_bots_check.disabled = true
		fill_bots_check.toggled.connect(_on_fill_bots_toggled)
	
	# --- P2P events: refresh UI & keep roster tidy (host removes leavers) ---
	Network.peer_joined.connect(func(_id):
		_refresh_ui()
		if GameState.is_host and fill_bots_check and fill_bots_check.button_pressed:
			_update_bots_for_team_size()
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

		if multiplayer.is_server() and GameState.roster.has(id):
			GameState.roster.erase(id)
			_ensure_leader_exists()   # ✅ leader might have left
			_broadcast_roster()

			if fill_bots_check and fill_bots_check.button_pressed:
				_update_bots_for_team_size()

		_refresh_ui()
		_update_start_enabled()
	)

	print("before refereshing: ", GameState.roster)
	
	for pid in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[pid]
		print("pid=", pid, " team=", rec.get("team", null))

	# --- First paint ---
	_refresh_ui()
	_update_start_enabled()

func _process(delta) -> void:
	_refresh_ui()

func _on_connected_to_server() -> void:
	# Client: tell server our name right after connect
	#print("CLIENT ID %d" % GameState.)
	rpc_id(1, "_rpc_submit_name", GameState.player_name)


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
	player_list.columns = 4              # ⬅ was 3
	player_list.hide_root = true
	player_list.set_column_titles_visible(true)
	player_list.set_column_title(0, "Player")
	player_list.set_column_title(1, "Team")
	player_list.set_column_title(2, "Swap")
	player_list.set_column_title(3, "Role / Ability") # ⬅ NEW

	player_list.set_column_expand(0, true)   # name expands
	player_list.set_column_expand(1, false)
	player_list.set_column_expand(2, false)
	player_list.set_column_expand(3, false)  # role is compact
	player_list.set_column_custom_minimum_width(3, 140)
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
		ready_btn.text = "Unready" if is_ready else "Ready"
		var team_val  := int(e.get("team", -1))
		var role_val  := int(e.get("role", GameState.Role.MIDFIELDER))  # ⬅ NEW
		var is_bot    := bool(e.get("is_bot", false))                   # ⬅ NEW
		var ability_id := _get_ability_id(e)
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
		if _i_am_leader() and team_val != -1:
			var icon: Texture2D = player_list.get_theme_icon("Reload", "EditorIcons")
			if icon == null:
				# Fallback to a built-in control icon that exists at runtime more reliably
				icon = player_list.get_theme_icon("Reload", "Tree")  # try Tree’s theme
			item.add_button(2, icon, 0, false, "Switch team")
		else:
			item.set_text(2, "")

		# Column 3: Role text + button (bots) OR Ability text + button (humans)
		if is_bot:
			item.set_text(3, ROLE_NAME.get(role_val, "Midfielder"))

			if _i_am_leader():
				var role_icon: Texture2D = player_list.get_theme_icon("Edit", "EditorIcons")
				if role_icon == null:
					role_icon = player_list.get_theme_icon("RightArrow", "Tree")
				item.add_button(3, role_icon, 0, false, "Change role")

		else:
			item.set_text(3, ABILITY_NAME.get(ability_id, ability_id))

			# ✅ allow: player can change their OWN ability
			# (Optional: also allow leader to change others)
			var can_change := (pid == multiplayer.get_unique_id()) or _i_am_leader()
			if can_change:
				var ab_icon: Texture2D = player_list.get_theme_icon("Edit", "EditorIcons")
				if ab_icon == null:
					ab_icon = player_list.get_theme_icon("RightArrow", "Tree")
				item.add_button(3, ab_icon, 0, false, "Change ability")

	status_label.text = "Connected: %d" % int(GameState.roster.size())
	_update_start_enabled()
	_apply_admin_ui_state()


func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if !_i_am_leader():
		return

	var pid := int(item.get_metadata(0))
	if !GameState.roster.has(pid):
		return

	if multiplayer.is_server():
		# Server can apply immediately (same behavior as before)
		if column == 2:
			var rec: Dictionary = GameState.roster[pid]
			var cur := int(rec.get("team", GameState.Team.BLUE))
			rec["team"] = (GameState.Team.RED if cur == GameState.Team.BLUE else GameState.Team.BLUE)
			GameState.roster[pid] = rec
			_broadcast_roster()
			_update_start_enabled()
		elif column == 3:
			var rec: Dictionary = GameState.roster[pid]

			if bool(rec.get("is_bot", false)):
				# bot => cycle role (your existing behavior)
				var cur_role := int(rec.get("role", GameState.Role.MIDFIELDER))
				rec["role"] = (cur_role + 1) % 3
				GameState.roster[pid] = rec
				_broadcast_roster()
				_update_start_enabled()
			else:
				# human => cycle ability
				rec["ability"] = _cycle_ability(String(rec.get("ability", "grapple")))
				GameState.roster[pid] = rec
				_broadcast_roster()
				_update_start_enabled()

	else:
		# Client leader -> request
		if column == 2:
			rpc_id(1, "_rpc_request_swap_team", pid)
		elif column == 3:
			var rec: Dictionary = GameState.roster[pid]
			if bool(rec.get("is_bot", false)):
				rpc_id(1, "_rpc_request_cycle_role", pid)
			else:
				rpc_id(1, "_rpc_request_cycle_ability", pid)

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
	var enough_players_for_setting := _teams_match_selected_size()

	var can_start := _all_ready() \
		and _everyone_has_a_team() \
		and enough_players_for_setting

	start_btn.disabled = not can_start

	if !_all_ready():
		start_btn.tooltip_text = "Everyone must be Ready."
	elif !_everyone_has_a_team():
		start_btn.tooltip_text = "Everyone needs a team."
	elif !enough_players_for_setting:
		var need := _required_team_size()
		start_btn.tooltip_text = "Lobby must be exactly %dv%d (%d players, balanced teams)." \
			% [need, need, need * 2]
	else:
		start_btn.tooltip_text = ""
	if !_i_am_leader():
		start_btn.disabled = true
		start_btn.tooltip_text = "Only the lobby leader can start."

# -------------------- Lobby flow --------------------

func _submit_name_to_host() -> void:
	if multiplayer.multiplayer_peer == null: return
	print("[client] sending name to host…")
	rpc_id(1, "_rpc_submit_name", GameState.player_name)

func _on_ready_toggle() -> void:
	
	var new_ready = !bool(GameState.roster[multiplayer.get_unique_id()].get("ready"))
	ready_btn.text = "Unready" if new_ready else "Ready"
	SessionManager.session_node.toggle_scene_action("lobby", NetCodes.Lobby_action.READY, 
	new_ready)
	_refresh_ui()
	_update_start_enabled()

func _on_start() -> void:
	if !_i_am_leader():
		return

	if multiplayer.is_server():
		_try_start_match()
	else:
		rpc_id(1, "_rpc_request_start_match")

func _on_leave() -> void:
	if GameState.is_host:
		# Tell everyone we're going away; then close.
		rpc("_rpc_host_is_leaving")
	GameState.reset_lobby()
	SessionManager.exit(C.LOBBY)

func _on_host_gone() -> void:
	print("[lobby] host disconnected or left")
	status_label.text = "Host left. Returning to title..."
	# Clear local state and return to title
	GameState.reset_lobby()
	Network.close_connection()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

# -------------------- Helpers --------------------

func _apply_admin_ui_state() -> void:
	var admin := _i_am_leader()
	if match_size_opt: match_size_opt.disabled = !admin
	if fill_bots_check: fill_bots_check.disabled = !admin


func _i_am_leader() -> bool:
	return multiplayer.get_unique_id() == GameState.lobby_leader_id

func _sender_is_leader() -> bool:
	return multiplayer.get_remote_sender_id() == GameState.lobby_leader_id

func _pick_next_leader() -> int:
	var best := 0
	for k in GameState.roster.keys():
		var pid := int(k)
		var rec: Dictionary = GameState.roster[pid]
		if bool(rec.get("is_bot", false)):
			continue
		if best == 0 or pid < best:
			best = pid
	return best

func _ensure_leader_exists() -> void:
	if !multiplayer.is_server():
		return

	# Keep current if valid
	if GameState.lobby_leader_id != 0 and GameState.roster.has(GameState.lobby_leader_id):
		var rec: Dictionary = GameState.roster[GameState.lobby_leader_id]
		if !bool(rec.get("is_bot", false)):
			return

	var next := _pick_next_leader() 
	GameState.lobby_leader_id = next
	
	# CHANGE: Call a local RPC in this script, not GameState
	rpc("_rpc_set_lobby_leader", next)

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
	if !multiplayer.is_server(): return

	var from := multiplayer.get_remote_sender_id()
	var team := GameState.pick_balanced_team()
	GameState.roster[from] = {"name": name, "ready": false, "team": team, "ability": "grapple"}

	_ensure_leader_exists()   # ✅ IMPORTANT
	_broadcast_roster()

@rpc("any_peer", "call_local")
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
	if !GameState.is_host:
		return

	var snapshot: Array = []
	for id in GameState.roster.keys():
		var e = GameState.roster[id]
		snapshot.append({
			"id": id,
			"name": e.get("name", "Player"),
			"ready": e.get("ready", false),
			"team": e.get("team", Team.BLUE),
			"is_bot": e.get("is_bot", false),  # <--- keep bot flag
			"role": e.get("role", GameState.Role.MIDFIELDER),  # ⬅ NEW
			"ability": e.get("ability", "grapple"),  # ✅ NEW
		})


	rpc("_rpc_set_roster", snapshot)
	_refresh_ui()

@rpc("authority", "call_local", "reliable")
func _rpc_set_roster(snapshot: Array) -> void:
	var dict := {}
	for e in snapshot:
		dict[int(e["id"])] = {
			"name": String(e["name"]),
			"ready": bool(e["ready"]),
			"team": int(e.get("team", Team.BLUE)),
			"is_bot": bool(e.get("is_bot", false)),
			"role": int(e.get("role", GameState.Role.MIDFIELDER)),  # ⬅ NEW
			"ability": String(e.get("ability", "grapple")), # ✅ NEW
		}

	print("ROSTERRRRRR")
	print("new update yea")
	GameState.roster = dict
	print(GameState.roster)
	_refresh_ui()
	_update_start_enabled()

@rpc("authority", "call_local", "reliable")
func _rpc_start_match(scene_path: String) -> void:
	SessionManager.session_node.change_state(WORLD_SCENE)
@rpc("any_peer", "reliable")
func _rpc_set_my_name(name: String) -> void:
	if multiplayer.is_server():
		var pid := multiplayer.get_remote_sender_id()
		if GameState.roster.has(pid):
			GameState.roster[pid]["name"] = name
		# optionally broadcast a lobby refresh to everyone here
# ---------- SERVER SIDE ----------

@rpc("any_peer")
func _sv_register_player(name: String) -> void:
	if not multiplayer.is_server():
		return

	var from_id := multiplayer.get_remote_sender_id()

	# Dedicated server: never register itself as a player
	if GameState.is_dedicated_server() and from_id == 1:
		return

	var rec: Dictionary = GameState.roster.get(from_id, {})
	rec["name"] = name
	rec["ready"] = false
	# balanced team using your helpers
	rec["team"] = GameState.pick_balanced_team()
	GameState.roster[from_id] = rec

	_broadcast_lobby_state()

@rpc("any_peer")
func _sv_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var from_id := multiplayer.get_remote_sender_id()
	if !GameState.roster.has(from_id):
		return
	GameState.roster[from_id]["ready"] = ready
	_broadcast_lobby_state()

@rpc("any_peer")
func _sv_request_start_match() -> void:
	if not multiplayer.is_server():
		return
	_try_start_match()
func _all_players_ready() -> bool:
	for id in GameState.roster.keys():
		var rec: Dictionary = GameState.roster[id]
		if !rec.get("ready", false):
			return false
	return true

func _try_start_match() -> void:
	if !_all_players_ready():
		print("Not all players ready yet")
		return

	if !_everyone_has_a_team():
		print("Not everyone has a team")
		return

	if !_teams_match_selected_size():
		var need := _required_team_size()
		print("Need exactly %d players per team for %dv%d before starting." % [need, need])
		return
	for pid in GameState.roster.keys():
		GameState.roster[pid]["ready"] = false
	rpc("_rpc_start_match", WORLD_SCENE)
	SessionManager.session_node.change_state(WORLD_SCENE)


func _broadcast_lobby_state() -> void:
	# server -> all
	rpc("_rpc_lobby_state", GameState.roster)
	_refresh_ui()

@rpc("any_peer", "call_local")
func _rpc_lobby_state(new_roster: Dictionary) -> void:
	# Keep everyone in sync
	GameState.roster = new_roster.duplicate(true)
	_refresh_ui()

@rpc("any_peer", "reliable")
func _rpc_request_team_size(size: int) -> void:
	if !multiplayer.is_server(): return
	if !_sender_is_leader(): return
	_team_size = clamp(size, MIN_TEAM_SIZE, MAX_TEAM_SIZE)
	rpc("_rpc_set_team_size", _team_size)
	_update_bots_for_team_size()
	_broadcast_roster()

@rpc("any_peer", "reliable")
func _rpc_request_swap_team(pid: int) -> void:
	if !multiplayer.is_server(): return
	if !_sender_is_leader(): return
	if !GameState.roster.has(pid): return

	var rec: Dictionary = GameState.roster[pid]
	var cur := int(rec.get("team", GameState.Team.BLUE))
	rec["team"] = (GameState.Team.RED if cur == GameState.Team.BLUE else GameState.Team.BLUE)
	GameState.roster[pid] = rec
	_broadcast_roster()

@rpc("any_peer", "reliable")
func _rpc_request_cycle_role(pid: int) -> void:
	if !multiplayer.is_server(): return
	if !_sender_is_leader(): return
	if !GameState.roster.has(pid): return

	var rec: Dictionary = GameState.roster[pid]
	if !bool(rec.get("is_bot", false)): return

	var cur_role := int(rec.get("role", GameState.Role.MIDFIELDER))
	rec["role"] = (cur_role + 1) % 3
	GameState.roster[pid] = rec
	_broadcast_roster()

@rpc("any_peer", "reliable")
func _rpc_request_start_match() -> void:
	if !multiplayer.is_server(): return
	if !_sender_is_leader(): return
	_try_start_match()

@rpc("any_peer", "reliable")
func _rpc_request_fill_bots(pressed: bool) -> void:
	if !multiplayer.is_server(): return
	if !_sender_is_leader(): return

	# 1. Update the logic variable
	_server_bots_enabled = pressed
	
	# 2. Update the UI visually (if this is a host/listen server)
	if fill_bots_check:
		# ✅ FIX: Use set_pressed_no_signal to avoid loops
		fill_bots_check.set_pressed_no_signal(pressed)

	# 3. Run logic
	_update_bots_for_team_size()
	_broadcast_roster()
# ---------- CLIENT BUTTON HANDLERS ----------

func _on_ready_pressed() -> void:
	if multiplayer.is_server():
		# listen-server testing; not used in dedicated mode
		var my_id := multiplayer.get_unique_id()
		var current = GameState.roster.get(my_id, {}).get("ready", false)
		GameState.roster[my_id]["ready"] = !current
		_broadcast_lobby_state()
	else:
		var my_id := multiplayer.get_unique_id()
		var current = GameState.roster.get(my_id, {}).get("ready", false)

		rpc_id(1, "_sv_set_ready", !current)

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		_try_start_match()
	else:
		rpc_id(1, "_sv_request_start_match")

func _on_leave_pressed() -> void:
	GameState.reset_lobby()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")  # or wherever
func _update_status() -> void:
	if multiplayer.is_server():
		status_label.text = "HOST (dedicated)" if GameState.is_dedicated_server() else "HOST"
	else:
		status_label.text = "CLIENT"
func _on_server_started() -> void:
	print("Lobby: server started")
	_update_status()

func _on_joined_server() -> void:
	print("Lobby: joined server")
	_update_status()

func _on_peer_joined(id: int) -> void:
	print("Lobby: peer joined ", id)

func _on_peer_left(id: int) -> void:
	print("Lobby: peer left ", id)
	GameState.roster.erase(id)
	_broadcast_lobby_state()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed"
	return
	#get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

func _on_server_disconnected() -> void:
	status_label.text = "Server disconnected"
	return
	#get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
func _required_team_size() -> int:
	# Rely on the variable, not the UI node. 
	# The variable is synced via _rpc_set_team_size already.
	return clamp(_team_size, MIN_TEAM_SIZE, MAX_TEAM_SIZE)
	
func _teams_match_selected_size() -> bool:
	var counts := _counts_by_team()
	var need := _required_team_size()
	var blue: int = int(counts[Team.BLUE])
	var red:  int = int(counts[Team.RED])
	
	# Strict equality check
	return blue == need and red == need and need > 0
	
func _on_match_size_selected(index: int) -> void:
	if !_i_am_leader():
		_apply_admin_ui_state()
		return

	if match_size_opt == null:
		return

	var new_size := match_size_opt.get_item_id(index)
	if new_size <= 0:
		new_size = MIN_TEAM_SIZE

	if multiplayer.is_server():
		_team_size = clamp(new_size, MIN_TEAM_SIZE, MAX_TEAM_SIZE)
		rpc("_rpc_set_team_size", _team_size)
		if fill_bots_check and fill_bots_check.button_pressed:
			_update_bots_for_team_size()
		_broadcast_roster()
	else:
		rpc_id(1, "_rpc_request_team_size", new_size)

@rpc("authority", "call_local", "reliable")
func _rpc_set_team_size(size: int) -> void:
	_team_size = clamp(size, MIN_TEAM_SIZE, MAX_TEAM_SIZE)

	if match_size_opt:
		var idx := match_size_opt.get_item_index(_team_size)
		if idx != -1:
			match_size_opt.select(idx)
	GameState.lobby_size = _team_size*2
	# Only host manages bots
	if GameState.is_host and fill_bots_check and fill_bots_check.button_pressed:
		_update_bots_for_team_size()

	_update_start_enabled()

func _is_bot_entry(e: Dictionary) -> bool:
	return bool(e.get("is_bot", false))

func _alloc_bot_id() -> int:
	var id := _next_bot_id
	_next_bot_id += 1
	return id

func _current_bot_count() -> int:
	var c := 0
	for id in GameState.roster.keys():
		var e: Dictionary = GameState.roster[id]
		if _is_bot_entry(e):
			c += 1
	return c

func _remove_all_bots() -> void:
	var to_remove: Array[int] = []
	for id in GameState.roster.keys():
		var e: Dictionary = GameState.roster[id]
		if _is_bot_entry(e):
			to_remove.append(int(id))
	for id in to_remove:
		GameState.roster.erase(id)
func _update_bots_for_team_size() -> void:
	if !GameState.is_host:
		return
# CHANGE: Check the variable, not the UI element
	if !_server_bots_enabled:
		_remove_all_bots()
		_broadcast_roster()
		_refresh_ui()
		_update_start_enabled()
		return

	var need := _required_team_size()
	if need <= 0:
		return

	# Count current players + bots on each team, and track bot ids per team
	var counts := { Team.BLUE: 0, Team.RED: 0 }
	var bot_ids_blue: Array[int] = []
	var bot_ids_red: Array[int] = []

	for k in GameState.roster.keys():
		var pid := int(k)
		var e: Dictionary = GameState.roster[pid]
		var team_val := int(e.get("team", GameState.TEAM_NONE))
		if team_val == Team.BLUE:
			counts[Team.BLUE] += 1
			if _is_bot_entry(e):
				bot_ids_blue.append(pid)
		elif team_val == Team.RED:
			counts[Team.RED] += 1
			if _is_bot_entry(e):
				bot_ids_red.append(pid)

	# 1) Remove extra bots if team has more than 'need'
	for team in [Team.BLUE, Team.RED]:
		var bot_list := bot_ids_blue if team == Team.BLUE else bot_ids_red
		while counts[team] > need and bot_list.size() > 0:
			var remove_id: int = bot_list.pop_back()
			GameState.roster.erase(remove_id)
			counts[team] -= 1

	# 2) Add bots until each team reaches 'need'
	for team in [Team.BLUE, Team.RED]:
		while counts[team] < need:
			var new_id := _alloc_bot_id()
			var bot_index := _current_bot_count() + 1
			var bot_name := "Bot%d" % bot_index
			GameState.roster[new_id] = {
				"name": bot_name,
				"ready": true,
				"team": team,
				"is_bot": true,
				"role": GameState.Role.MIDFIELDER,  # default; host can change
				"ability": "grapple",
			}

			counts[team] += 1

	_broadcast_roster()
	_refresh_ui()
	_update_start_enabled()

func _on_fill_bots_toggled(pressed: bool) -> void:
	if !_i_am_leader():
		if fill_bots_check:
			fill_bots_check.set_pressed_no_signal(false)
		return

	if multiplayer.is_server():
		# ✅ FIX: You must update the variable here!
		_server_bots_enabled = pressed 
		
		_update_bots_for_team_size()
		_broadcast_roster()
	else:
		rpc_id(1, "_rpc_request_fill_bots", pressed)
@rpc("authority", "call_local", "reliable")
func _rpc_set_lobby_leader(id: int) -> void:
	GameState.lobby_leader_id = id
	print("[Lobby] Leader updated to: ", id)
	# CRITICAL: Force UI to re-check if "I am leader" is now true
	_refresh_ui()
	_apply_admin_ui_state()
	_update_start_enabled()
@rpc("any_peer", "reliable")
func _rpc_request_cycle_ability(pid: int) -> void:
	if !multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()

	# ✅ allow the player to change their OWN ability
	# (Optional) also allow leader to change others
	if sender != pid and sender != GameState.lobby_leader_id:
		return

	if !GameState.roster.has(pid):
		return

	var rec: Dictionary = GameState.roster[pid]
	if bool(rec.get("is_bot", false)):
		return # bots use role cycling, not this

	var cur := String(rec.get("ability", "grapple"))
	rec["ability"] = _cycle_ability(cur)
	GameState.roster[pid] = rec

	_broadcast_roster()
