# res://autoloads/level_container.gd
extends Node

signal world_ready(node: Node)   # local, per-peer

@onready var spawner := MultiplayerSpawner.new()

func _ready():
	add_child(spawner)
	spawner.spawn_path = get_path()
	spawner.add_spawnable_scene("res://world.tscn")
	spawner.spawned.connect(func(n): world_ready.emit(n))
