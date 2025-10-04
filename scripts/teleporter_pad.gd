extends Area3D

@export var teleport_id: int = 1          # pads with the same id link together
@export var raise_y: float = 1.0          # lift player a bit at destination
@export var cooldown: float = 0.35        # brief pause to prevent ping-pong

var _cooling_down := false

func _ready() -> void:
	add_to_group("TeleporterPad")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _cooling_down:
		return
	if not body.is_in_group("player"):
		return

	var dest = _find_destination()
	if dest == null:
		return

	# temporarily disable the destination so we don't immediately teleport back
	dest._start_cooldown(cooldown)

	# move the player
	var target = dest.global_transform.origin + Vector3(0, raise_y, 0)
	if body.has_method("set_global_position"):
		body.global_position = target
	else:
		var t = body.global_transform
		t.origin = target
		body.global_transform = t

	# optional: cancel any current motion so landing is stable
	if "velocity" in body:
		body.velocity = Vector3.ZERO

func _start_cooldown(t: float) -> void:
	_cooling_down = true
	monitoring = false
	await get_tree().create_timer(t).timeout
	monitoring = true
	_cooling_down = false

func _find_destination() -> Node:
	# search for another TeleporterPad with the same id
	var pads = get_tree().get_nodes_in_group("TeleporterPad")
	for p in pads:
		if p != self and p.teleport_id == teleport_id:
			return p
	return null
