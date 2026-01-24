extends AbilityBase
class_name GrappleAbility

@export var grapple_max_dist: float = 250.0
@export var grapple_hit_mask: int = (1 << 0) | (1 << 1) | (1 << 2)
@export var grapple_shot_scene: PackedScene = preload("res://scenes/GrappleShot.tscn")
var latched_point_local := Vector3.ZERO
@export var release_keep_momentum_time: float = 5.0
# server: remember who we were pulling so we can clear it when pull stops
var _last_pulled_victim_path_server: NodePath = NodePath("")
var _player : Node

@export var grapple_pull_speed: float = 10.0
@export var grapple_stop_dist: float = 1.2
@export var grapple_pull_target_speed: float = 7.0
@export var keep_momentum_time := 5.0 # seconds
@export var grapple_icon: Texture2D = preload("res://Texture/Grapple_90x90_big.png")
@export var fire_icon: Texture2D = preload("res://Texture/Fire_90x90_big.png")
@export var pull_icon: Texture2D = preload("res://Texture/Pull_90x90_big.png")
@export var release_icon: Texture2D = preload("res://Texture/Release_90x90_big.png")


# client-only visual state
var shot: GrappleShot = null
var latched_local := false
var target_path_local: NodePath = NodePath("")

# server state
var point_server := Vector3.ZERO
var latched_server := false
var reeling_server := false
var pulling_server := false
var target_path_server: NodePath = NodePath("")
var target_kind_server := 0 # 0 wall, 1 ball, 2 player

func id() -> StringName:
	return &"grapple"

func labels() -> PackedStringArray:
	return PackedStringArray(["Fire", "Pull", "Release"])

func wants_crosshair() -> bool:
	return true


func _ready() -> void:
	ability_icon = grapple_icon
	action1_icon = fire_icon
	action2_icon = pull_icon
	action3_icon = release_icon

func init(net : Node, player : Node) -> void:
	net.subscribe(self)
	_player = player

func handle_action(inputs : Dictionary) -> void:

	# Always keep rope visuals updated (if any)
	if shot and is_instance_valid(shot):
		shot.set_start_world(_player.get_muzzle_from_view())

	if shot and is_instance_valid(shot) and latched_local:
		var end_pos := latched_point_local
		if String(target_path_local) != "":
			var t := _player.get_node_or_null(target_path_local)
			if t is Node3D:
				end_pos = (t as Node3D).global_position
				if t is Player:
					end_pos += Vector3.UP * 0.9
		if shot.has_method("set_end_world"):
			shot.set_end_world(end_pos)

	# ✅ Block ability inputs unless the mode is active
	if !_player.ability_mode_active:
		return

	# Now handle inputs
	if inputs.get("ability_action1"):
		action1_pressed(_player)

	if inputs.get("ability_action2"):
		action2_pressed(_player)
	if inputs.get("ability_action2"):
		action2_released(_player)

	if inputs.get("ability_action3"):
		action3_pressed(_player)

func on_unequipped(player: Player) -> void:
	# cleanup visual if exists on owner
	if player._is_local_owner():
		_client_cleanup(player)

func on_mode_changed(player: Player, enabled: bool) -> void:
	if !enabled and player._is_local_owner():
		_client_cleanup(player)
		player._request_ability_release() # tell server too

func client_tick(player: Player, delta: float) -> void:
	if !player._is_local_owner():
		return

	# Always keep rope visuals updated (if any)
	if shot and is_instance_valid(shot) and player.cam:
		shot.set_start_world(player.get_muzzle_from_camera(player.cam))

	if shot and is_instance_valid(shot) and latched_local:
		var end_pos := latched_point_local
		if String(target_path_local) != "":
			var t := player.get_node_or_null(target_path_local)
			if t is Node3D:
				end_pos = (t as Node3D).global_position
				if t is Player:
					end_pos += Vector3.UP * 0.9
		if shot.has_method("set_end_world"):
			shot.set_end_world(end_pos)

	# ✅ Block ability inputs unless the mode is active
	if !player.ability_mode_active:
		return

	# Now handle inputs
	if Input.is_action_just_pressed("ability_action1"):
		action1_pressed(player)

	if Input.is_action_just_pressed("ability_action2"):
		action2_pressed(player)
	if Input.is_action_just_released("ability_action2"):
		action2_released(player)

	if Input.is_action_just_pressed("ability_action3"):
		action3_pressed(player)

#func action1_pressed(player: Player) -> void:
	## If already latched -> reel
	#if shot and is_instance_valid(shot) and latched_local:
		#player._request_ability_reel(true)
		#return
	#_fire_visual_and_store(player)

func action1_pressed(player: Player) -> void:
	# If already latched -> reel
	if shot and is_instance_valid(shot) and latched_local:
		sv_on_reel(player, true)
		return
	_fire_visual_and_store(player)

func action2_pressed(player: Player) -> void:
	player._request_ability_pull(true)

func action2_released(player: Player) -> void:
	player._request_ability_pull(false)

func action3_pressed(player: Player) -> void:
	_client_cleanup(player)
	player._request_ability_release()

func server_tick(player: Player, delta: float) -> void:
	_sv_update_point_from_target(player)
	_sv_handle_pull_target(player)

func server_movement_override(player: Player, delta: float) -> bool:
	if !reeling_server or !latched_server:
		return false

	var to := point_server - player.global_position
	var dist := to.length()
	if dist <= grapple_stop_dist:
		reeling_server = false
		player.velocity = Vector3.ZERO
		return true

	var dir = to / max(dist, 0.001)
	player.velocity = dir * grapple_pull_speed
	player.move_and_slide()
	return true

# --- Server events routed from Player RPCs ---
func sv_on_latched(player: Player, point: Vector3, target_path: NodePath) -> void:
	point_server = point
	latched_server = true
	reeling_server = false
	pulling_server = false

	target_kind_server = 0
	target_path_server = NodePath("")

	if String(target_path) != "":
		var n := player.get_node_or_null(target_path)
		if n is RigidBody3D and (n as RigidBody3D).is_in_group("ball"):
			target_kind_server = 1
			target_path_server = target_path
		elif n is Player:
			target_kind_server = 2
			target_path_server = target_path

func sv_on_reel(player: Player, on: bool) -> void:
	reeling_server = on and latched_server

func sv_on_pull(player: Player, on: bool) -> void:
	pulling_server = on

func sv_on_release(player: Player) -> void:
	# ✅ clear any victim we were pulling
	if String(_last_pulled_victim_path_server) != "":
		var old_victim := player.get_node_or_null(_last_pulled_victim_path_server) as Player
		if old_victim and is_instance_valid(old_victim):
			old_victim.clear_external_pull()
		_last_pulled_victim_path_server = NodePath("")
	reeling_server = false
	latched_server = false
	pulling_server = false
	point_server = Vector3.ZERO
	target_kind_server = 0
	target_path_server = NodePath("")

	# ✅ keep momentum after release (generic player helper)
	player.start_air_momentum_keep(release_keep_momentum_time)

# --- internals ---
func _client_cleanup(player: Player) -> void:
	if shot and is_instance_valid(shot):
		shot.queue_free()
	shot = null
	latched_local = false
	target_path_local = NodePath("")

func _fire_visual_and_store(player: Player) -> void:
	if player.cam == null or grapple_shot_scene == null:
		return

	_client_cleanup(player)

	var vp := player.get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	var ro := player.cam.project_ray_origin(center)
	var rd := player.cam.project_ray_normal(center).normalized()
	var to := ro + rd * grapple_max_dist

	var q := PhysicsRayQueryParameters3D.create(ro, to)
	q.collision_mask = grapple_hit_mask
	q.exclude = [player.get_rid()]
	q.collide_with_bodies = true
	q.collide_with_areas = true
	q.hit_from_inside = true
	q.hit_back_faces = true

	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var end_pos: Vector3 = hit.position if !hit.is_empty() else to

	var target_path := NodePath("")
	if !hit.is_empty():
		var col = hit.get("collider")
		if col is Node:
			if (col is RigidBody3D and (col as RigidBody3D).is_in_group("ball")) or (col is Player):
				target_path = (col as Node).get_path()

	var start_pos := player.get_muzzle_from_camera(player.cam)

	var s := grapple_shot_scene.instantiate() as GrappleShot
	player.get_tree().current_scene.add_child(s)
	s.start(start_pos, end_pos)

	s.latched.connect(func(p: Vector3):
		latched_local = true
		latched_point_local = p            # ✅ store latch point
		target_path_local = target_path
		player._request_ability_latched(p, target_path)
	)


	shot = s

func _sv_update_point_from_target(player: Player) -> void:
	if !latched_server:
		return

	if target_kind_server == 1:
		var ball := player.get_node_or_null(target_path_server) as Node3D
		if ball:
			point_server = ball.global_position
		else:
			target_kind_server = 0
			target_path_server = NodePath("")
	elif target_kind_server == 2:
		var p := player.get_node_or_null(target_path_server) as Player
		if p:
			point_server = p.global_position + Vector3.UP * 0.9
		else:
			target_kind_server = 0
			target_path_server = NodePath("")

func _sv_handle_pull_target(player: Player) -> void:
	# ✅ If pull is NOT active anymore, clear old victim pull (if any) and exit
	if !pulling_server or !latched_server:
		if String(_last_pulled_victim_path_server) != "":
			var old_victim := player.get_node_or_null(_last_pulled_victim_path_server) as Player
			if old_victim and is_instance_valid(old_victim):
				old_victim.clear_external_pull()
			_last_pulled_victim_path_server = NodePath("")
		return

	if target_kind_server == 1:
		var ball := player.get_node_or_null(target_path_server) as RigidBody3D
		if ball == null:
			return
		ball.freeze = false
		ball.sleeping = false
		var to_me := (player.global_position + Vector3.UP * 0.6) - ball.global_position
		var dist := to_me.length()
		if dist <= grapple_stop_dist:
			ball.linear_velocity = Vector3.ZERO
			return
		ball.linear_velocity = (to_me / max(dist, 0.001)) * grapple_pull_target_speed

	elif target_kind_server == 2:
		var victim := player.get_node_or_null(target_path_server) as Player
		if victim and is_instance_valid(victim):
			_last_pulled_victim_path_server = target_path_server
			victim.apply_external_pull(player.global_position, grapple_pull_target_speed, grapple_stop_dist)
