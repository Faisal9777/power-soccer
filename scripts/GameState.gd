# GameState.gd
extends Node

enum Team { BLUE = 0, RED = 1 }
const TEAM_NONE := -1
var player_name: String = ""
var is_host: bool = false
signal player_name_changed(id: int, name: String)
var id:int
var is_dedicated: bool = false 
# { peer_id: { "name": String, "ready": bool, "team": int(Team) } }
var roster: Dictionary = {}
var pending_spawn_ids: Array[int] = []
var match_len_sec = 600
var goal_limit = 50
# --- tie-alternation state ---
var _next_on_tie: int = Team.BLUE
func get_team(peer_id: int) -> int:
	return int(roster.get(peer_id, {}).get("team", TEAM_NONE))

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
