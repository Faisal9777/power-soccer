# GameState.gd
extends Node

enum Team { BLUE = 0, RED = 1 }
enum Role { GOALKEEPER = 0, MIDFIELDER = 1, FORWARD = 2 }  # ⬅ NEW
const TEAM_NONE := -1
var player_name: String = ""
var is_host: bool = false
signal player_name_changed(id: int, name: String)
var id:int
var is_dedicated: bool = false 
var lobby_leader_id: int = 0
signal lobby_leader_changed(id: int)
# { peer_id: { "name": String, "ready": bool, "team": int(Team) } }
var roster: Dictionary = {}
var game_results: Dictionary = {}
var lobby_data := {"lobby_size" : 0, "players_connected" : 0}
var pending_spawn_ids: Array[int] = []
var match_len_sec = 500
var goal_limit = 10
# --- tie-alternation state ---
var _next_on_tie: int = Team.BLUE
func get_team(peer_id: int) -> int:
	return int(roster.get(peer_id, {}).get("team", TEAM_NONE))

func get_role(peer_id: int) -> int:
	return int(roster.get(peer_id, {}).get("role", Role.MIDFIELDER))

func set_role(peer_id: int, role: int) -> void:
	var rec: Dictionary = roster.get(peer_id, {})
	rec["role"] = role
	roster[peer_id] = rec

func is_dedicated_server() -> bool:
	return is_dedicated and multiplayer.is_server()

func is_team(peer_id: int, team_id: int) -> bool:
	return get_team(peer_id) == team_id

func is_blue(peer_id: int) -> bool:
	return get_team(peer_id) == Team.BLUE

func is_red(peer_id: int) -> bool:
	return get_team(peer_id) == Team.RED
	
func is_in_the_same_team(peer_id: int, team : String) -> bool:
	if team == "blue":
		return is_team(peer_id, 0)
	return is_team(peer_id, 1)
func reset_lobby() -> void:
	is_host = false
	roster.clear()
	pending_spawn_ids.clear()
	_next_on_tie = Team.BLUE

func clear() -> void:
	roster.clear()
	pending_spawn_ids.clear()
	_next_on_tie = Team.BLUE

func _counts_by_team() -> Dictionary:
	var counts := { Team.BLUE: 0, Team.RED: 0 }
	for id in roster.keys():
		var e = roster[id]
		if e.has("team"):
			if e["team"] == Team.BLUE: counts[Team.BLUE] += 1
			elif e["team"] == Team.RED: counts[Team.RED] += 1
	return counts

func pick_balanced_team() -> int:
	var c := _counts_by_team()
	if c[Team.BLUE] < c[Team.RED]: return Team.BLUE
	if c[Team.RED] < c[Team.BLUE]: return Team.RED
	# tie → alternate
	var t := _next_on_tie
	_next_on_tie = Team.RED if _next_on_tie == Team.BLUE else Team.BLUE
	return t

func get_player_name(id: int) -> String:
	# Prefer roster[id]["name"], fall back to the single player_name, else a default.
	var rec: Dictionary = roster.get(id, {})
	if rec != null and rec.has("name") and String(rec["name"]) != "":
		return String(rec["name"])
	if player_name != "":
		return player_name
	return "Player %d" % id

func set_player_name_for(id: int, name: String) -> void:
	var rec: Dictionary = roster.get(id, {})
	rec["name"] = name
	roster[id] = rec
	player_name_changed.emit(id, name)
@rpc("authority", "call_local", "reliable")
func _rpc_set_lobby_leader(id: int) -> void:
	lobby_leader_id = id
	lobby_leader_changed.emit(id)
func is_same_team(a: int, b: int) -> bool:
	var ta := get_team(a)
	return ta != TEAM_NONE and ta == get_team(b)
