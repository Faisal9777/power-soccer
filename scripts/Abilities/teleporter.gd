extends AbilityBase
class_name Teleporter

@export var gadget_scene: PackedScene = preload("res://scenes/TeleportGadget.tscn")
@export var throw_speed: float = 6.0

@export var teleporter_ready_icon: Texture2D = preload("res://Texture/Teleport_90x90.png")
@export var teleporter_icon: Texture2D = preload("res://Texture/Teleporter_90x90.png")
@export var throw_icon: Texture2D = preload("res://Texture/Throw_90x90.png")
@export var switch_icon: Texture2D = preload("res://Texture/Switch_90x90.png")
@export var destroy_icon: Texture2D = preload("res://Texture/Destroy_90x90.png")

var _enabled := false
var _gadget_thrown := false

# ✅ server-only: where the thrown gadget is
var _gadget_path_server: NodePath = NodePath("")

func id() -> StringName:
	return &"teleporter"

func labels() -> PackedStringArray:
	return PackedStringArray(["Throw", "Switch", "Destroy"])

func on_equipped(player: Player) -> void:
	_gadget_thrown = false
	_gadget_path_server = NodePath("")

	ability_icon = teleporter_icon
	action1_icon = throw_icon
	action2_icon = switch_icon
	action3_icon = destroy_icon

func on_mode_changed(player: Player, enabled: bool) -> void:
	_enabled = enabled

func client_tick(player: Player, _delta: float) -> void:
	if !player._is_local_owner():
		return
	if !player.ability_mode_active or !_enabled:
		return

	if Input.is_action_just_pressed("ability_action1"):
		var target := player._get_crosshair_target_world(200.0) # layer 1 walls
		player._request_teleporter_action1(target)
  # ✅ server decides: throw or teleport
	if Input.is_action_just_pressed("ability_action2"):
		player._request_teleporter_action2()
	if Input.is_action_just_pressed("ability_action3"):
		player._request_teleporter_action3()

func cl_set_thrown_state(player: Player, thrown: bool) -> void:
	_gadget_thrown = thrown
	action1_icon = teleporter_ready_icon if _gadget_thrown else throw_icon
	if player and is_instance_valid(player):
		player.call_deferred("_emit_ability_ui")

# -------------------------
# SERVER: Action1 handler
# -------------------------
func sv_action1(player: Player, target_world: Vector3) -> void:
	# If gadget exists -> teleport to it
	if String(_gadget_path_server) != "":
		var g := player.get_node_or_null(_gadget_path_server)
		if g is Node3D and is_instance_valid(g):
			_sv_teleport_to_gadget(player, g as Node3D)
			return
		else:
			_gadget_path_server = NodePath("")
			player._sv_set_teleporter_thrown(false)

	# Otherwise -> throw toward target_world
	sv_throw(player, target_world)

func sv_action2(player: Player) -> void:
	# ✅ HARD BLOCK: cannot switch while player is inside layer 9 zone
	if player.is_in_layer9_zone():
		return
	if String(_gadget_path_server) == "":
		return

	var g := player.get_node_or_null(_gadget_path_server)
	if !(g is TeleportGadget) or !is_instance_valid(g):
		_gadget_path_server = NodePath("")
		player._sv_set_teleporter_thrown(false)
		return

	var tg := g as TeleportGadget
	if String(tg.swap_target_path) == "":
		# gadget stuck to wall or something not in layer2/3 -> no swap allowed
		return

	var target := player.get_tree().root.get_node_or_null(tg.swap_target_path)
	if !(target is Node3D) or !is_instance_valid(target):
		return

	# Safety: refuse swapping with layer1 or any other layer
	if target is CollisionObject3D:
		var allowed := (1 << 1) | (1 << 2)
		if ((target as CollisionObject3D).collision_layer & allowed) == 0:
			return

	# Optional: refuse swapping with static bodies (if you only want movable stuff)
	if target is StaticBody3D:
		return

	_sv_swap_positions(player, target as Node3D, tg.stuck_normal_world)

	# Consume gadget after swap (recommended)
	(target as Node3D) # no-op; just clarity
	tg.queue_free()
	_gadget_path_server = NodePath("")
	player._sv_set_teleporter_thrown(false)

func sv_action3(player: Player) -> void:
	# Destroy gadget if it exists
	if String(_gadget_path_server) == "":
		return

	var g := player.get_node_or_null(_gadget_path_server)
	_gadget_path_server = NodePath("") # clear first (safe)
	player._sv_set_teleporter_thrown(false)

	if g is Node and is_instance_valid(g):
		(g as Node).queue_free()


func _sv_swap_positions(player: Player, other: Node3D, n: Vector3) -> void:
	var p_pos := player.global_position
	var o_pos := other.global_position

	# Better push direction for balls: away from ball center -> player
	var push := (p_pos - o_pos)
	if push.length() < 0.001:
		push = n
	if push == Vector3.ZERO:
		push = Vector3.UP
	push = push.normalized()

	# ✅ bigger separation (player capsule ~0.3–0.4 radius, ball ~0.12)
	var sep := 0.75  # start here; can tune 0.6..1.0

	# keep each one's own momentum
	var p_vel := player.velocity
	var o_rb_vel := Vector3.ZERO
	var o_rb_ang := Vector3.ZERO
	var o_cb_vel := Vector3.ZERO

	var other_rb := other as RigidBody3D
	var other_cb := other as CharacterBody3D

	if other_rb:
		o_rb_vel = other_rb.linear_velocity
		o_rb_ang = other_rb.angular_velocity
	elif other_cb:
		o_cb_vel = other_cb.velocity

	# ✅ prevent physics from "exploding" the ball due to penetration
	if other_rb:
		_temp_no_collide(player, player, other_rb, 0.20)

	player.global_position = o_pos + push * sep
	other.global_position  = p_pos - push * sep

	player.velocity = p_vel
	if other_rb:
		other_rb.linear_velocity = o_rb_vel
		other_rb.angular_velocity = o_rb_ang
		other_rb.sleeping = false
	elif other_cb:
		other_cb.velocity = o_cb_vel


func sv_throw(player: Player, target_world: Vector3) -> void:
	if gadget_scene == null:
		return

	var gadget := _throw_gadget(player, target_world)
	if gadget == null:
		return

	_gadget_path_server = gadget.get_path()

	gadget.tree_exited.connect(func():
		_gadget_path_server = NodePath("")
		if is_instance_valid(player):
			player._sv_set_teleporter_thrown(false)
	)

	player._sv_set_teleporter_thrown(true)
func _throw_gadget(player: Player, target_world: Vector3) -> Node3D:
	var gadget := gadget_scene.instantiate() as Node3D
	if gadget == null:
		return null

	# Spawn point (feel free to tweak)
	var muzzle := player.global_position + Vector3.UP * 1.2

	var dir := (target_world - muzzle)
	if dir.length() < 0.05:
		dir = -player.global_transform.basis.z
	dir = dir.normalized()

	gadget.global_position = muzzle + dir * 1.2

	if gadget is RigidBody3D:
		var rb := gadget as RigidBody3D
		rb.add_collision_exception_with(player)
		rb.linear_velocity = dir * throw_speed
		rb.sleeping = false

	var world := player.get_tree().current_scene
	var root := world.get_node_or_null(^"Teleporters/Gadgets")
	if root == null:
		root = world # fallback

	root.add_child(gadget, true) # ✅ now clients will see it spawn

	return gadget

func _sv_teleport_to_gadget(player: Player, gadget: Node3D) -> void:
	# --- momentum ---
	# Option A (most common): keep PLAYER momentum
	var keep_v := player.velocity

	# Option B (if you meant "inherit gadget momentum"): uncomment these 2 lines:
	if gadget is RigidBody3D:
		keep_v = (gadget as RigidBody3D).linear_velocity
	var n := Vector3.ZERO
	if gadget is TeleportGadget:
		n = (gadget as TeleportGadget).stuck_normal_world

	if n == Vector3.ZERO:
		n = -player.global_transform.basis.z

	# ✅ push player away from the wall BEFORE setting position
	var target := gadget.global_position + n * 0.9 #+ Vector3.UP * 0.2

	player.global_position = target
	player.velocity = keep_v
	# ✅ slide / gradually lose inherited momentum
	player.start_teleport_glide(0.9, 0.22, 1.0)

	gadget.queue_free()
	_gadget_path_server = NodePath("")
	player._sv_set_teleporter_thrown(false)
func wants_crosshair() -> bool:
	return true
func _temp_no_collide(ctx: Node, a: PhysicsBody3D, b: PhysicsBody3D, sec: float = 0.20) -> void:
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)

	var t := ctx.get_tree().create_timer(sec)
	t.timeout.connect(func():
		if is_instance_valid(a):
			a.remove_collision_exception_with(b)
		if is_instance_valid(b):
			b.remove_collision_exception_with(a)
	)
