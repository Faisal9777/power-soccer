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

@onready var status_label: Label   = $PanelContainer/VBoxContainer/StatusLabel
@onready var player_list: ItemList = $PanelContainer/VBoxContainer/PlayerList
@onready var start_btn: Button     = $PanelContainer/VBoxContainer/HBoxContainer/StartButton
@onready var leave_btn: Button     = $PanelContainer/VBoxContainer/HBoxContainer/LeaveButton
@onready var ready_btn: Button     = $PanelContainer/VBoxContainer/HBoxContainer/ReadyButton
var _player_ids: Array[int] = []
const WORLD_SCENE := "res://World.tscn"
enum Team { BLUE = 0, RED = 1 }
const TEAM_COLOR := {
	GameState.Team.BLUE: Color(0.2, 0.6, 1.0),
	GameState.Team.RED:  Color(1.0, 0.3, 0.3)
}
func _ready() -> void:
	# If you opened via Create Server, ensure host record exists
	print("[lobby] whoami=", multiplayer.get_unique_id(),
	  " is_host=", GameState.is_host,
	  " path=", get_path())

	if GameState.is_host:
		var host: Dictionary = GameState.roster.get(1, {})
		if host.is_empty():
			GameState.roster[1] = {
				"name": GameState.player_name,
				"ready": false,
				"team": GameState.pick_balanced_team()
			}
		else:
			if !host.has("team"):
				GameState.roster[1]["team"] = GameState.pick_balanced_team()
	else:
		call_deferred("_submit_name_to_host")

	# Buttons
	start_btn.disabled = !GameState.is_host
	ready_btn.text = "Unready" if _my_ready() else "Ready"

	start_btn.pressed.connect(_on_start)
	leave_btn.pressed.connect(_on_leave)
	ready_btn.pressed.connect(_on_ready_toggle)
	GameState.pending_spawn_ids.append(1)
	# Keep UI fresh on joins/leaves (host mainly)
	Network.peer_joined.connect(func(_id): _refresh_ui(); _add_players(_id))
	Network.peer_left.connect(func(id):
		if GameState.is_host and GameState.roster.has(id):
			GameState.roster.erase(id)
			_broadcast_roster()
		_refresh_ui()
	)

	_refresh_ui()

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

func _on_start() -> void:
	if !GameState.is_host: return
	# Optional: enforce all-ready here
	# for id in GameState.roster.keys():
	# 	if !GameState.roster[id]["ready"]:
	# 		push_warning("Not everyone is ready."); return
	rpc("_rpc_start_match", WORLD_SCENE)

func _on_leave() -> void:
	GameState.reset_lobby()
	Network.close_connection()
	get_tree().change_scene_to_file("res://title_screen.tscn")

func _refresh_ui() -> void:
	player_list.clear()

	# Stable order so indices match colors
	var ids := GameState.roster.keys()  # plain Array is fine
	ids.sort()

	var i := 0
	for id in ids:
		var e: Dictionary = GameState.roster[id]

		var host_tag  := " (Host)" if int(id) == 1 else ""
		var ready_tag := " ✓" if bool(e.get("ready", false)) else ""
		var name_str  := String(e.get("name", "Player"))
		var label := "%s%s%s" % [name_str, host_tag, ready_tag]

		# Team handling: -1 means unassigned (don’t default to BLUE)
		var team_val := int(e.get("team", -1))

		if team_val == -1:
			label += " [UNASSIGNED]"
			player_list.add_item(label)
			player_list.set_item_custom_fg_color(i, Color(0.8, 0.8, 0.8))  # neutral gray
		else:
			label += (" [BLUE]" if team_val == Team.BLUE else " [RED]")
			player_list.add_item(label)
			player_list.set_item_custom_fg_color(i, TEAM_COLOR.get(team_val, TEAM_COLOR[Team.BLUE]))

		i += 1

	status_label.text = "Connected: %d" % int(GameState.roster.size())

func _add_players(id:int) -> void:
	GameState.pending_spawn_ids.append(id)

func _assign_team_for_new_peer(peer_id: int) -> int:
	var blue_count := 0
	var red_count  := 0
	for id in GameState.roster.keys():
		if GameState.roster[id].has("team"):
			if GameState.roster[id]["team"] == Team.BLUE: blue_count += 1
			elif GameState.roster[id]["team"] == Team.RED: red_count += 1
	return Team.BLUE if blue_count <= red_count else Team.RED

func _my_ready() -> bool:
	var me := multiplayer.get_unique_id()
	return GameState.roster.has(me) and GameState.roster[me]["ready"]
 
func _set_my_ready_local(v: bool) -> void:
	var me := multiplayer.get_unique_id()
	if !GameState.roster.has(me):
		GameState.roster[me] = {"name": GameState.player_name, "ready": v}
	else:
		GameState.roster[me]["ready"] = v

# ---------- RPCs ----------
@rpc("any_peer")
func _rpc_submit_name(name: String) -> void:
	if !GameState.is_host:
		return
	var from := multiplayer.get_remote_sender_id()
	var team := GameState.pick_balanced_team()   # <-- call here
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

func _broadcast_roster() -> void:
	if !GameState.is_host: return
	var snapshot: Array = []
	for id in GameState.roster.keys():
		var e = GameState.roster[id]
		snapshot.append({
			"id": id,
			"name": e["name"],
			"ready": e["ready"],
			"team": e.get("team", Team.BLUE)  # default if missing
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
	GameState.roster = dict
	_refresh_ui()

@rpc("any_peer", "call_local")
func _rpc_start_match(scene_path: String) -> void:     # now valid
	get_tree().change_scene_to_file(scene_path)
