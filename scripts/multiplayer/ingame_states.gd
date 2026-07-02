extends Node

enum WorldPhase { COUNTDOWN, PLAYING, GOAL_CELEBRATION, POST_MATCH }

signal phase_changed(old_phase: WorldPhase, new_phase: WorldPhase)

var current_phase: WorldPhase = WorldPhase.COUNTDOWN :
	set(value):
		var old = current_phase
		current_phase = value
		phase_changed.emit(old, value)

var can_process := false;
var is_paused := true
var countdown_started := false
var time_left_ms: int = 0    # <— this is the ONLY thing we sync
var blue_score: int = 0           # NEW: server writes, clients read
var red_score: int = 0   
var countdown_ms: int = 0
var scene_path_to_load := ""
var game_data = {}
var goal_scored := false    
func _ready() -> void:
	set_multiplayer_authority(1)
	_install_synchronizer()

func _install_synchronizer() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	add_child(sync)

	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath(".:current_phase"))
	cfg.add_property(NodePath(".:time_left_ms"))
	cfg.add_property(NodePath(".:blue_score"))
	cfg.add_property(NodePath(".:red_score"))
	cfg.add_property(NodePath(".:countdown_ms"))
	cfg.add_property(NodePath(".:is_paused"))
	cfg.add_property(NodePath(".:can_process"))
	cfg.add_property(NodePath(".:scene_path_to_load"))
	cfg.add_property(NodePath(".:game_data"))
	cfg.add_property(NodePath(".:goal_scored"))

	cfg.property_set_replication_mode(NodePath(".:time_left_ms"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:blue_score"),   SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.property_set_replication_mode(NodePath(".:red_score"),    SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.property_set_replication_mode(NodePath(".:countdown_ms"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:is_paused"),    SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:can_process"),  SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:scene_path_to_load"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:game_data"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:goal_scored"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:current_phase"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	sync.replication_config = cfg
	sync.replication_interval = 0.0

func set_roster(roster : Dictionary) -> void:
	for peer_id in roster.keys():
		var peer = roster[peer_id]
		var peer_data = {"name" :  peer["name"],
		"team" : peer["team"], "goals" : 0, "assists" : 0, "saves" : 0}
		game_data[peer_id]  = peer_data 

func toggle_process(toggle : bool) -> void:
	can_process = toggle

func add_goal(player_id : int) -> void:
	game_data[player_id]["goals"] += 1

func sub_goal(player_id : int) -> void:
	game_data[player_id]["goals"] -= 1

func add_assist(player_id : int) -> void:
	game_data[player_id]["assists"] += 1

func sub_assist(player_id : int) -> void:
	game_data[player_id]["assists"] -= 1

func get_game_data() -> Dictionary:
	return game_data
