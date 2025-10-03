extends CharacterBody3D

# --- Tunables (unchanged) ---
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.5
@export var jump_velocity: float = 6.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var air_control: float = 0.4

@export var kick_force: float = 16.0
@export var kick_up: float = 3.0
@export var shoot_cooldown: float = 0.25
@export var cooldown_per_impulse: float = 0.05
@export var jump_cooldownn: float = 0.5

@export var show_aim_arrow: bool = true
@export var aim_min_len: float = 0.3
@export var aim_max_len: float = 3.0
@export var turn_speed: float = 12.0

@export var charge_time_to_max: float = 1.2
@export var charge_decay_speed: float = 1.5
@export var charge_rate_mul: float = 2

@export var charge_min_mul: float = 0.03
@export var charge_max_mul: float = 20
@export var charge_curve: float = 12
@export var charge_knee: float = 0.5
@export var charge_steepness: float = 20.0

@export var dribble_impulse: float = 0.9
@export var dribble_forward_bias: float = 0.35
@export var dribble_up: float = 0.15
@export var dribble_cooldown: float = 0.5
@export var dribble_cone_dot: float = 0.0

@export var vel_influence: float = 0.3
@export var vel_ref_speed: float = 0.0
@export var kick_max_impulse: float = 8.0

@export var fling_up_impulse: float = 8.0
@export var fling_forward_bias: float = 0.0
@export var fling_zero_prev_vel: bool = true

@export var tackle_speed_mul: float = 2
@export var tackle_speed_min: float = 4.0
@export var tackle_speed_max: float = 20.0
@export var tackle_dur_min: float = 0.5
@export var tackle_dur_max: float = 1.85
@export var tackle_decel: float = 9.0
@export var tackle_dur_curve: float = 1.6
@export var tackle_speed_curve: float = 1.2
@export var tackle_require_floor: bool = true
@export var owner_peer_id: int = 1
@export var characters_layer_bit: int = 2
@export var ball_layer_bit: int = 3


# --- Runtime state ---
var current_ball: RigidBody3D = null
var aim_active: bool = false
var aim_dir: Vector3 = Vector3.ZERO
var aim_contact: Vector3 = Vector3.ZERO
var aim_arrow: Node3D = null
var arrow_shaft: MeshInstance3D = null
var arrow_head: MeshInstance3D = null

var _charge: float = 0.0
var _charge_layer: CanvasLayer
var _charge_root: Control
var _charge_bar: ProgressBar
var _ball_prev_parent: Node = null
var _pre_move_vel: Vector3
var tackle_active: bool = false
var tackle_time_left: float = 0.0
var tackle_velocity: Vector3 = Vector3.ZERO

# Latch helpers (no reparenting in netcode—see notes below)
var ball_latched: bool = false
var _latched_offset_local: Vector3 = Vector3.ZERO
var _saved_ball_layer: int = 0
var _saved_ball_mask: int = 0
var _latched_ball: RigidBody3D = null
var cam: Camera3D = null  # local-only reference

@onready var ground_ray: RayCast3D = $GroundRay
@onready var kick_area: Area3D = $KickArea
@onready var tackle_field: Area3D = $TackleField
@onready var ball_latch_anchor: Node3D = Node3D.new()

var _cooldowns := {"shoot": 0.0, "move": 0.0, "jump": 0.0}

# --- Net input state (fed by world.gd on the server) ---
var _net := {
	"mvx": 0.0,          # strafe/right (-1..1)
	"mvz": 0.0,          # forward/back  (-1..1)
	"sprint": false,
	"jump_pressed": false,
	"tackle_pressed": false,
	"dribble": false,
	"stop_ball": false,
	"shoot_down": false,   # held
	"shoot_up": false,     # edge
	# optional (if you later send mouse aim):
	"rmb": false,    # Vector3 or null
	"cam_yaw": 0.0,
}

func apply_net_input(d: Dictionary) -> void:
	# SERVER ONLY: called by world.gd before simulate_server()
	for k in _net.keys():
		if d.has(k):
			_net[k] = d[k]
func attach_camera(c: Camera3D) -> void:
	cam = c
	if cam:
		print("camera has been assigned in player")
	else:
		print("no camera was found to gget assigned in the player")

# --- Helpers to read net "buttons" ---
func _btn_down(name: String) -> bool:
	match name:
		"sprint": return bool(_net["sprint"])
		"dribble": return bool(_net["dribble"])
		"stop_ball": return bool(_net["stop_ball"])
		"shoot": return bool(_net["shoot_down"])
		_: return false

func _btn_just_pressed(name: String) -> bool:
	match name:
		"jump": return bool(_net["jump_pressed"])
		"tackle": return bool(_net["tackle_pressed"])
		"shoot": return false
		_: return false

func _btn_just_released(name: String) -> bool:
	match name:
		"shoot": return bool(_net["shoot_up"])
		_: return false

# --- Engine callbacks ---

func _ready() -> void:
	if $KickArea:
		$KickArea.body_entered.connect(_on_kick_area_body_entered)
		$KickArea.body_exited.connect(_on_kick_area_body_exited)
	var my_id := get_tree().get_multiplayer().get_unique_id()
	var is_local := (owner_peer_id == my_id)
	var is_dedicated := OS.has_feature("server")
	#_log_pid("in ready of player.gd: ")
	print("my id: ", my_id)
	print("owner peer id: ", owner_peer_id)
	
	ball_latch_anchor.name = "BallLatchAnchor"
	add_child(ball_latch_anchor)  # or: tackle_field.add_child(ball_latch_anchor)
	#var cam := $Camera3D  # adjust if your camera lives deeper
	
	#if is_dedicated or not is_local:
		#cam.deactivate()
		#return
	
	#if cam and is_local:
		#cam.activate()
	
	_ensure_aim_arrow()
	_init_charge_ui()
func _log_pid(msg : String) -> void:
	print(msg, OS.get_process_id())
func _physics_process(delta: float) -> void:
	# Approach #2: only the SERVER simulates gameplay.
	if !multiplayer.is_server():
		return
	simulate_server(delta)

func _process(delta: float) -> void:
	if not show_aim_arrow or aim_arrow == null:
		return
	if not aim_active:
		_show_arrow(false); return

	var vec := aim_contact - global_transform.origin
	if vec == Vector3.ZERO:
		_show_arrow(false); return

	var dist := maxf(vec.length(), aim_min_len)
	var n := vec.normalized()

	_show_arrow(true)
	aim_arrow.global_transform.origin = global_transform.origin
	aim_arrow.look_at(aim_arrow.global_transform.origin + n, Vector3.UP)
	aim_arrow.scale = Vector3(1.0, 1.0, dist)
# --- Server gameplay loop (moved out of _physics_process for clarity) ---

func simulate_server(delta: float) -> void:
	_update_cooldowns(delta)
	_update_charge_server(delta)
	apply_gravity(delta)
	_face_camera_yaw(delta)

	var input_dir := _get_input_dir_server()
	_pre_move_vel = velocity

	_handle_tackle_input_server()
	if tackle_active:
		_update_tackle_server(delta)
		return

	_handle_action_server(input_dir, delta)
	_update_aim_server(delta)

# --- Server versions of your previous methods (Input → _net) ---

func _update_charge_server(delta: float) -> void:
	var down := _btn_down("shoot")
	if down and charge_time_to_max > 0.0:
		_charge = minf(1.0, _charge + charge_rate_mul * (delta / charge_time_to_max))
	else:
		_charge = maxf(0.0, _charge - charge_decay_speed * delta)
	# Optional: only show UI on host (peer 1). Harmless to leave off on a dedicated server.
	if is_instance_valid(_charge_bar):
		_charge_bar.value = _charge * 100.0
		_charge_bar.visible = down or _charge > 0.001

func _update_cooldowns(delta: float) -> void:
	for k in _cooldowns.keys():
		_cooldowns[k] = max(_cooldowns[k] - delta, 0.0)

func apply_gravity(delta: float) -> void:
	if !is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

func _get_input_dir_server() -> Vector3:
	var yaw := float(_net.get("cam_yaw", rotation.y))
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw); fwd.y = 0.0; fwd = fwd.normalized()
	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw); right.y = 0.0; right = right.normalized()
	var mvx := float(_net["mvx"])
	var mvz := float(_net["mvz"])
	return (right * mvx + fwd * mvz).normalized()

func _handle_action_server(input_dir: Vector3, delta: float) -> void:
	if _cooldowns["move"] == 0.0:
		_move_server(input_dir, delta)
	if _cooldowns["jump"] == 0.0:
		_handle_jump_server()
	_handle_kick_action_server()

func _move_server(input_dir: Vector3, delta: float) -> void:
	var target_speed := sprint_speed if _btn_down("sprint") else walk_speed
	var lateral := velocity; lateral.y = 0.0
	var target_vel := input_dir * target_speed
	var accel := 12.0 if is_on_floor() else 12.0 * air_control
	lateral = lateral.lerp(target_vel, clamp(accel * delta, 0.0, 1.0))
	velocity.x = lateral.x
	velocity.z = lateral.z
	move_and_slide()

func _handle_jump_server() -> void:
	var grounded := is_on_floor() or (ground_ray and ground_ray.is_colliding())
	if grounded and _btn_just_pressed("jump") and _cooldowns["jump"] == 0.0:
		velocity.y = jump_velocity
		_cooldowns["jump"] = jump_cooldownn

func _handle_kick_action_server() -> void:
	if _cooldowns["shoot"] != 0.0:
		return
	_handle_shoot_server()
	_handle_dribble_server()
	_handle_ball_stop_server()

func _handle_ball_stop_server() -> void:
	if _btn_down("stop_ball") and current_ball and is_instance_valid(current_ball):
		current_ball.linear_velocity = Vector3.ZERO
		current_ball.angular_velocity = Vector3.ZERO
		current_ball.sleeping = false
		_cooldowns["shoot"] = dribble_cooldown * 0.5

func _handle_dribble_server() -> void:
	if !_btn_down("dribble") or _cooldowns["shoot"] != 0.0:
		return
	var mvx := float(_net["mvx"])
	var mvz := float(_net["mvz"])
	if mvx < -0.2:
		perform_dribble_server(-1); _cooldowns["shoot"] = dribble_cooldown
	elif mvx > 0.2:
		perform_dribble_server(1);  _cooldowns["shoot"] = dribble_cooldown
	elif mvz > 0.2:
		_fling_ball_server();       _cooldowns["shoot"] = dribble_cooldown

func _fling_ball_server() -> void:
	if current_ball == null or !is_instance_valid(current_ball):
		return
	if fling_zero_prev_vel:
		current_ball.linear_velocity = Vector3.ZERO
		current_ball.angular_velocity = Vector3.ZERO
	var J := Vector3.UP * fling_up_impulse * 0.2
	if fling_forward_bias != 0.0:
		var fwd := -global_transform.basis.z; fwd.y = 0.0
		if fwd.length() > 0.0: J += fwd.normalized() * fling_forward_bias
	current_ball.sleeping = false
	current_ball.apply_impulse(J, Vector3.ZERO)

func perform_dribble_server(direction: int) -> void:
	if current_ball == null or !is_instance_valid(current_ball):
		return
	var player_pos := global_transform.origin
	var ball_pos := current_ball.global_transform.origin
	var to_ball := ball_pos - player_pos
	var to_ball_xz := Vector3(to_ball.x, 0.0, to_ball.z)
	if to_ball_xz == Vector3.ZERO: return
	var fwd := -global_transform.basis.z; fwd.y = 0.0
	if fwd.length() == 0.0: return
	fwd = fwd.normalized()
	if fwd.dot(to_ball_xz.normalized()) < dribble_cone_dot:
		return
	var right_xz := fwd.cross(Vector3.UP).normalized()
	# remove forward drift
	var v := current_ball.linear_velocity
	current_ball.linear_velocity = v - fwd * v.dot(fwd)
	# impulse
	var J := right_xz * float(direction) * dribble_impulse + Vector3.UP * dribble_up
	var radius := _get_ball_radius(current_ball)
	var approx_contact := ball_pos - fwd * radius
	var local_contact := current_ball.to_local(approx_contact).lerp(Vector3.ZERO, 0.4)
	current_ball.sleeping = false
	current_ball.apply_impulse(J, local_contact)

func _handle_shoot_server() -> void:
	# Use edge up for the release shot
	if aim_active and current_ball != null and _btn_just_released("shoot") and _cooldowns["shoot"] == 0.0:
		_kick_at_contact_server()

func _kick_at_contact_server() -> void:
	if !is_instance_valid(current_ball):
		return

	var C := current_ball.global_transform.origin
	var R := _get_ball_radius(current_ball)

	# --- NEW: build hit_point from latest input, clamped to ball surface ---
	var hit_point: Vector3
	var target: Variant = _net.get("aim_contact", null)  # may be Vector3 or null
	if target is Vector3:
		var dir := (target as Vector3) - C
		if dir.length() < 1e-5:
			dir = C - global_transform.origin  # fallback: from player toward ball
		dir = dir.normalized()
		hit_point = C - dir * R              # clamp onto sphere surface
	else:
		var dir2 := C - global_transform.origin
		if dir2.length() < 1e-5:
			dir2 = Vector3.FORWARD
		hit_point = C - dir2.normalized() * R

	# (optional) keep visuals in sync
	aim_contact = hit_point
	# ----------------------------------------------------------------------

	var impulse_dir := (C - hit_point).normalized()

	var linear := impulse_dir * kick_force
	var lift := Vector3.UP * kick_up

	var q := clampf(_charge, 0.0, 1.0)
	var m := clampf(charge_knee, 0.05, 0.95)
	var s := maxf(0.001, charge_steepness)
	var f0 := 1.0 / (1.0 + exp(-s * (0.0 - m)))
	var f1 := 1.0 / (1.0 + exp(-s * (1.0 - m)))
	var f  := 1.0 / (1.0 + exp(-s * (q - m)))
	var q_eased := (f - f0) / maxf(1e-6, (f1 - f0))
	var charge_mul := lerpf(charge_min_mul, charge_max_mul, q_eased)

	var v_player := (_pre_move_vel if _pre_move_vel != Vector3.ZERO else velocity)
	var v_along := maxf(v_player.dot(impulse_dir), 0.0)
	var v_ref := (vel_ref_speed if vel_ref_speed > 0.0 else maxf(0.001, sprint_speed))
	var v_norm := clampf(v_along / v_ref, 0.0, 1.0)
	var vel_mul := lerpf(1.0 - vel_influence, 1.0 + vel_influence, v_norm)

	var J := (linear + lift) * (charge_mul * vel_mul)
	if kick_max_impulse > 0.0:
		var Jlen := J.length()
		if Jlen > kick_max_impulse:
			J *= kick_max_impulse / Jlen

	current_ball.sleeping = false
	var local_contact := current_ball.to_local(hit_point)
	current_ball.apply_impulse(J, local_contact)

	_cooldowns["shoot"] = shoot_cooldown + J.length() * cooldown_per_impulse
	_charge = 0.0
	if is_instance_valid(_charge_bar):
		_charge_bar.value = 0.0

# --- Tackle / latch (server) ---

func _handle_tackle_input_server() -> void:
	if tackle_active: return
	if !_btn_just_pressed("tackle"): return
	if tackle_require_floor and !is_on_floor(): return
	_start_tackle_server()

func _start_tackle_server() -> void:
	var fwd := -global_transform.basis.z; fwd.y = 0.0
	if fwd.length() == 0.0: return
	fwd = fwd.normalized()

	var v0_xz := Vector3(_pre_move_vel.x, 0.0, _pre_move_vel.z)
	var speed0 := v0_xz.length()
	var s_norm := clampf(speed0 / maxf(0.001, sprint_speed), 0.0, 1.0)

	var w_dur := pow(s_norm, maxf(1.0, tackle_dur_curve))
	tackle_time_left = lerpf(tackle_dur_min, tackle_dur_max, w_dur)

	var slide_speed := clampf(speed0 * tackle_speed_mul, tackle_speed_min, tackle_speed_max)
	var w_spd := pow(s_norm, maxf(1.0, tackle_speed_curve))
	slide_speed = lerpf(slide_speed, tackle_speed_max, 0.25 * w_spd)
	tackle_velocity = fwd * slide_speed

	tackle_active = true

	# Begin latch attempt; no reparent—server will tick-snap ball (see _tick_latch_ball_server)
	if current_ball and tackle_field and tackle_field.overlaps_body(current_ball) and current_ball.is_in_group("ball"):
		var C := current_ball.global_transform.origin
		var F := tackle_field.global_transform.origin
		var dir := (C - F).normalized()
		var r := _get_ball_radius(current_ball)
		var contact_world := C - dir * r
		_latched_offset_local = to_local(contact_world)
		ball_latched = true
		current_ball.freeze = true
		current_ball.linear_velocity = Vector3.ZERO
		current_ball.angular_velocity = Vector3.ZERO

func _update_tackle_server(delta: float) -> void:
	# keep the ball glued while latched (server-side tick snap)
	_tick_latch_ball_server()

	# slide & gravity
	var v_xz := Vector3(tackle_velocity.x, 0.0, tackle_velocity.z)
	var dec := tackle_decel * delta
	var new_len := maxf(v_xz.length() - dec, 0.0)
	var dir := (v_xz if v_xz != Vector3.ZERO else Vector3.FORWARD).normalized()
	tackle_velocity = Vector3(dir.x * new_len, velocity.y, dir.z * new_len)

	if !is_on_floor():
		tackle_velocity.y = velocity.y - gravity * delta
	elif tackle_velocity.y < 0.0:
		tackle_velocity.y = 0.0

	velocity = tackle_velocity
	move_and_slide()

	tackle_time_left -= delta
	if tackle_time_left <= 0.0 or Vector3(velocity.x,0.0,velocity.z).length() < 0.1:
		_end_tackle_server()

func _tick_latch_ball_server() -> void:
	if current_ball and tackle_field.overlaps_body(current_ball) and current_ball is RigidBody3D and current_ball.is_in_group("ball"):
		print("latching the ball")
		var ball := current_ball
		var C: Vector3 = ball.global_transform.origin
		var F: Vector3 = tackle_field.global_transform.origin
		var dir: Vector3 = (C - F).normalized()
		var r: float = _get_ball_radius(ball)
		var contact_world: Vector3 = C - dir * r

		# Position the anchor at the contact point in world space
		ball_latch_anchor.global_transform.origin = contact_world

		# Save parent & collisions
		_ball_prev_parent = current_ball.get_parent()
		_saved_ball_layer = current_ball.collision_layer
		_saved_ball_mask  = current_ball.collision_mask

		# Freeze so physics won’t fight the parenting, and avoid blocking
		current_ball.freeze = true
		current_ball.linear_velocity  = Vector3.ZERO
		current_ball.angular_velocity = Vector3.ZERO
		current_ball.collision_layer = 0
		current_ball.collision_mask  = 0
		_latched_ball = current_ball
		# Reparent under the anchor, keeping world transform
		current_ball.reparent(ball_latch_anchor, true)  # keep_global = true
		ball_latched = true

func _end_tackle_server() -> void:
	tackle_active = false
	if characters_layer_bit > 0:
		collision_mask = collision_mask # (restore if you modify it elsewhere)
	if ball_latched:
		_unlatch_ball_server()

func _unlatch_ball_server() -> void:
	if _latched_ball:
		print("unlatching the ball")
	current_ball = _latched_ball
	_latched_ball = null
	if _ball_prev_parent != null and is_instance_valid(_ball_prev_parent):
		# Keep world transform when restoring parent
		current_ball.reparent(_ball_prev_parent, true)
	current_ball.freeze = false
	current_ball.sleeping = false
	current_ball.collision_layer = _saved_ball_layer
	current_ball.collision_mask  = _saved_ball_mask
	_ball_prev_parent = null
	ball_latched = false

# --- Misc / UI / aim ---

func _face_camera_yaw(delta: float) -> void:
	var target_yaw := float(_net.get("cam_yaw", rotation.y))
	var cur := rotation
	cur.y = lerp_angle(cur.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))
	rotation = cur

func _ensure_aim_arrow() -> void:
	# purely visual; clients render it. Server won't show UI.
	if !show_aim_arrow: return
	aim_arrow = Node3D.new()
	aim_arrow.name = "AimArrow"
	add_child(aim_arrow)
	arrow_shaft = MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.08, 0.08, 1.0)
	arrow_shaft.mesh = shaft_mesh
	arrow_shaft.position = Vector3(0, 0, -0.5)
	aim_arrow.add_child(arrow_shaft)
	arrow_head = MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.12
	head_mesh.height = 0.24
	arrow_head.mesh = head_mesh
	arrow_head.rotation_degrees.x = 90.0
	arrow_head.position = Vector3(0, 0, -1.0)
	aim_arrow.add_child(arrow_head)
	_show_arrow(false)

func _init_charge_ui() -> void:
	_charge_layer = CanvasLayer.new()
	add_child(_charge_layer)
	_charge_root = Control.new()
	_charge_root.name = "ChargeUI"
	_charge_layer.add_child(_charge_root)
	_charge_root.anchor_left = 1.0
	_charge_root.anchor_top = 1.0
	_charge_root.anchor_right = 1.0
	_charge_root.anchor_bottom = 1.0
	_charge_root.offset_right = -16
	_charge_root.offset_bottom = -16
	_charge_root.offset_left = _charge_root.offset_right - 200
	_charge_root.offset_top = _charge_root.offset_bottom - 20
	_charge_bar = ProgressBar.new()
	_charge_bar.min_value = 0.0
	_charge_bar.max_value = 100.0
	_charge_bar.step = 0.1
	_charge_bar.value = 0.0
	_charge_bar.rounded = true
	_charge_bar.show_percentage = false
	_charge_bar.visible = false
	_charge_bar.anchor_left = 0.0
	_charge_bar.anchor_top = 0.0
	_charge_bar.anchor_right = 1.0
	_charge_bar.anchor_bottom = 1.0
	_charge_bar.offset_left = 0
	_charge_bar.offset_top = 0
	_charge_bar.offset_right = 0
	_charge_bar.offset_bottom = 0
	_charge_root.add_child(_charge_bar)

func _show_arrow(v: bool) -> void:
	if arrow_shaft: arrow_shaft.visible = v
	if arrow_head: arrow_head.visible = v

func _get_ball_radius(ball: RigidBody3D) -> float:
	var r := 0.12
	for child in ball.get_children():
		if child is CollisionShape3D and child.shape is SphereShape3D:
			r = child.shape.radius
			break
	return r

# Server uses a simple, camera-forward contact if no aim sent.
func _update_aim_server(delta: float) -> void:
	# Arrow only exists while a ball is in the KickArea
	if not aim_active or current_ball == null:
		_show_arrow(false)
		return

	var C: Vector3 = current_ball.global_transform.origin
	var R: float = _get_ball_radius(current_ball)

	if _is_aiming():
		# --- Mouse-driven contact (ray -> sphere)
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			_show_arrow(false)
			return
		var mp: Vector2 = get_viewport().get_mouse_position()
		var ro: Vector3 = cam.project_ray_origin(mp)
		var rd: Vector3 = cam.project_ray_normal(mp).normalized()

		var oc: Vector3 = ro - C
		var b: float = 2.0 * rd.dot(oc)
		var c: float = oc.dot(oc) - R * R
		var disc: float = b * b - 4.0 * c
		var contact: Vector3 = Vector3.ZERO
		if disc >= 0.0:
			var sd: float = sqrt(disc)
			var t1: float = (-b - sd) * 0.5
			var t2: float = (-b + sd) * 0.5
			var t: float = -1.0
			if t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2
			if t > 0.0:
				contact = ro + rd * t
		if contact == Vector3.ZERO:
			var t_closest: float = -rd.dot(oc)
			var closest: Vector3 = ro + rd * maxf(t_closest, 0.0)
			var dir_to: Vector3 = closest - C
			if dir_to == Vector3.ZERO:
				dir_to = global_transform.origin - C
			contact = C + dir_to.normalized() * R
		aim_contact = contact
	else:
		# --- Fixed contact: front-facing surface toward the player (no mouse)
		var dir := (C - global_transform.origin).normalized()
		aim_contact = C - dir * R

	# Common: drive the arrow from player -> contact
	var vec: Vector3 = aim_contact - global_transform.origin
	if vec == Vector3.ZERO:
		_show_arrow(false)
		return
	var dist: float = maxf(vec.length(), aim_min_len)  # no upper clamp
	aim_dir = vec.normalized()

	_show_arrow(true)
	aim_arrow.global_transform.origin = global_transform.origin
	aim_arrow.look_at(aim_arrow.global_transform.origin + aim_dir, Vector3.UP)
	aim_arrow.scale = Vector3(1.0, 1.0, dist)
func _is_aiming() -> bool:
	return aim_active and _net["rmb"]
# KickArea hooks
func _on_kick_area_body_entered(body: Node) -> void:
	if not multiplayer.is_server(): return
	if body is RigidBody3D and body.is_in_group("ball"):
		current_ball = body
		aim_active = true
		var C := current_ball.global_transform.origin
		var R := _get_ball_radius(current_ball)
		var dir := (C - global_transform.origin).normalized()
		aim_contact = C - dir * R
		aim_dir = (aim_contact - global_transform.origin).normalized()

func _on_kick_area_body_exited(body: Node) -> void:
	if not multiplayer.is_server(): return
	if body == current_ball:
		current_ball = null
		aim_active = false
		_show_arrow(false)
