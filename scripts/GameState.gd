extends Node


var player_name: String = "Fardin Eajdani"
var is_host: bool = false
var players: Array[String] = []

func reset_lobby() -> void:
	is_host = false
	players.clear()
