extends RefCounted
class_name AbilityBase

@export var ability_icon: Texture2D = preload("res://Texture/Ability_90x90.png")
@export var action1_icon: Texture2D = preload("res://Texture/Act1_90x90.png")
@export var action2_icon: Texture2D = preload("res://Texture/Act2_90x90.png")
@export var action3_icon: Texture2D = preload("res://Texture/Act3_90x90.png")


func id() -> StringName:
	return &"base"

func labels() -> PackedStringArray:
	# Always 3 labels
	return PackedStringArray(["Action1", "Action2", "Action3"])

func wants_crosshair() -> bool:
	return false

func on_equipped(player: Player) -> void:
	pass

func on_unequipped(player: Player) -> void:
	pass

func on_mode_changed(player: Player, enabled: bool) -> void:
	pass

# Owning client only (visuals + reading Input actions)
func client_tick(player: Player, delta: float) -> void:
	pass

# Server only (authoritative simulation)
func server_tick(player: Player, delta: float) -> void:
	pass

# If this returns true, Player should skip normal movement that tick
func server_movement_override(player: Player, delta: float) -> bool:
	return false

# Ability actions
func action1_pressed(player: Player) -> void:
	pass

func action2_pressed(player: Player) -> void:
	pass

func action2_released(player: Player) -> void:
	pass

func action3_pressed(player: Player) -> void:
	pass

# Optional: handle RPC events routed from Player
func sv_on_latched(player: Player, point: Vector3, target_path: NodePath) -> void:
	pass

func sv_on_reel(player: Player, on: bool) -> void:
	pass

func sv_on_pull(player: Player, on: bool) -> void:
	pass

func sv_on_release(player: Player) -> void:
	pass
