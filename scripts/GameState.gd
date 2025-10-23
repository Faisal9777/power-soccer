# GameState.gd
extends Node

enum Team { BLUE = 0, RED = 1 }

var player_name: String = "Fardin Eajdani"
var is_host: bool = false
# { peer_id: { "name": String, "ready": bool, "team": int(Team) } }
var roster: Dictionary = {}
var pending_spawn_ids: Array[int] = []
var match_len_sec = 600
# --- tie-alternation state ---
var _next_on_tie: int = Team.BLUE

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
