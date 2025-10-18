extends Node


var player_name: String = "Fardin Eajdani"
var is_host: bool = false
# Roster is host-authoritative. We’ll keep it as {peer_id: {name, ready}}
var roster: Dictionary = {}   # example: { 1: { "name": "Fardin", "ready": false }, 7: {...} }
var pending_spawn_ids: Array[int] = []  
func reset_lobby() -> void:
	is_host = false
	roster.clear()
