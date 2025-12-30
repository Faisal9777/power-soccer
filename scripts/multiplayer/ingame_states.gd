extends Node
var can_process := false;
var is_paused := true
var countdown_started := false
var time_left_ms: int = 0    # <— this is the ONLY thing we sync
var blue_score: int = 0           # NEW: server writes, clients read
var red_score: int = 0   
var countdown_ms: int = 0
var scene_path_to_load := ""    
func _ready() -> void:
	_install_synchronizer()

func _install_synchronizer() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	add_child(sync)

	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath(".:time_left_ms"))
	cfg.add_property(NodePath(".:blue_score"))
	cfg.add_property(NodePath(".:red_score"))
	cfg.add_property(NodePath(".:countdown_ms"))
	cfg.add_property(NodePath(".:is_paused"))
	cfg.add_property(NodePath(".:can_process"))
	cfg.add_property(NodePath(".:scene_path_to_load"))

	cfg.property_set_replication_mode(NodePath(".:time_left_ms"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:blue_score"),   SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.property_set_replication_mode(NodePath(".:red_score"),    SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.property_set_replication_mode(NodePath(".:countdown_ms"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:is_paused"),    SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:can_process"),  SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(".:scene_path_to_load"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	sync.replication_config = cfg
	sync.replication_interval = 0.0

func toggle_process(toggle : bool) -> void:
	can_process = toggle
