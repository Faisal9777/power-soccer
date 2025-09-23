extends CharacterBody3D

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

@export var charge_time_to_max: float = 1.2   # seconds to fill from 0 → 1
@export var charge_decay_speed: float = 1.5   # how fast it drains when released (per second)
@export var charge_rate_mul: float = 2   # >1 faster, <1 slower

@export var charge_min_mul: float = 0.03   # very small at low charge
@export var charge_max_mul: float = 20   # big at full charge
@export var charge_curve:   float = 12   # >1 = slow start, fast finish (try 2–4)
@export var charge_knee: float = 0.5      # where the power takes off (0..1)
@export var charge_steepness: float = 20.0 # how sharp the takeoff is (bigger = sharper)

@export var dribble_impulse: float = 0.9      # base side push
@export var dribble_forward_bias: float = 0.35 # add a bit of forward so you don’t lose the ball
@export var dribble_up: float = 0.15           # tiny lift to avoid ground stick
@export var dribble_cooldown: float = 0.5     # how often nudges can fire (seconds)
@export var dribble_cone_dot: float = 0.0      # require ball roughly in front: -1..1 (0 = 90° cone)


@export var vel_influence:  float = 0.3      # 0..1 how much player speed matters
@export var vel_ref_speed:  float = 0.0      # 0 = auto (uses sprint_speed)
@export var kick_max_impulse: float = 8.0    # safety cap (optional)

# Add near your other exports
@export var fling_up_impulse: float = 8.0      # how hard to launch upward
@export var fling_forward_bias: float = 0.0    # optional extra push forward (0 = straight up)
@export var fling_zero_prev_vel: bool = true   # reset velocity before fling for consistency

# --- Tackle tunables
@export var tackle_speed_mul: float = 2     # how much of your current speed becomes slide speed
@export var tackle_speed_min: float = 4.0
@export var tackle_speed_max: float = 20.0

@export var tackle_dur_min: float = 0.5      # seconds at low speed
@export var tackle_dur_max: float = 1.85      # seconds at sprint speed
@export var tackle_decel:   float = 9.0      # per-second decel for the slide (higher = stops sooner)
@export var tackle_dur_curve: float = 1.6    # >1 = much longer at high speed
@export var tackle_speed_curve: float = 1.2  # >1 = faster at high speed
@export var tackle_require_floor: bool = true # only allow on ground

# Optional: pass-through characters layer during tackle (set to your "characters" layer bit, 1..20; 0 = disabled)
@export var characters_layer_bit: int = 2
@export var ball_layer_bit: int = 3 

var current_ball: RigidBody3D = null
var aim_active: bool = false
var aim_dir: Vector3 = Vector3.ZERO      # direction from player to contact point
var aim_contact: Vector3 = Vector3.ZERO  # world-space contact point on ball surface
var aim_arrow: Node3D = null
var arrow_shaft: MeshInstance3D = null
var arrow_head: MeshInstance3D = null

var _charge: float = 0.0
var _charge_layer: CanvasLayer
var _charge_root: Control
var _charge_bar: ProgressBar
var _pre_move_vel: Vector3
var _tf_was_overlapping: bool = false
# --- State
var tackle_active: bool = false
var tackle_time_left: float = 0.0
var tackle_velocity: Vector3 = Vector3.ZERO

var ball_latched: bool = false
var ball_latch_local: Vector3 = Vector3.ZERO

# Save/restore masks if you enable pass-through
var _saved_player_mask: int = 0
var _saved_ball_mask: int = 0

var _ball_prev_parent: Node = null
var _saved_ball_layer: int = 0
var _latched_ball: RigidBody3D = null

@onready var ball_latch_anchor: Node3D = Node3D.new()

@onready var ground_ray: RayCast3D = $GroundRay
@onready var kick_area: Area3D = $KickArea
@onready var tackle_field: Area3D = $TackleField
		
var _cooldowns := {
	"shoot": 0.0,
	"move": 0.0,
	"jump": 0.0
}

func _face_camera_yaw(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target_yaw: float = cam.global_transform.basis.get_euler().y
	var cur := rotation
	cur.y = lerp_angle(cur.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))
	rotation = cur

func _ready() -> void:
	if $KickArea:
		$KickArea.body_entered.connect(_on_kick_area_body_entered)
		$KickArea.body_exited.connect(_on_kick_area_body_exited)
	ball_latch_anchor.name = "BallLatchAnchor"
	add_child(ball_latch_anchor)  # or: tackle_field.add_child(ball_latch_anchor)
	_ensure_aim_arrow()
	_init_charge_ui()   # <— add this

func _init_charge_ui() -> void:
	_charge_layer = CanvasLayer.new()
	add_child(_charge_layer)  # attach to player; CanvasLayer draws on top of world

	_charge_root = Control.new()
	_charge_root.name = "ChargeUI"
	_charge_layer.add_child(_charge_root)

	# Anchor to bottom-right with 16px margin; size 200x20
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
	_charge_bar.step = 0.1          # smooth enough
	_charge_bar.value = 0.0
	_charge_bar.rounded = true
	_charge_bar.show_percentage = false
	_charge_bar.visible = false
	# Make the bar fill its parent rect
	_charge_bar.anchor_left = 0.0
	_charge_bar.anchor_top = 0.0
	_charge_bar.anchor_right = 1.0
	_charge_bar.anchor_bottom = 1.0
	_charge_bar.offset_left = 0
	_charge_bar.offset_top = 0
	_charge_bar.offset_right = 0
	_charge_bar.offset_bottom = 0
	_charge_root.add_child(_charge_bar)


func _physics_process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_charge(delta)
	apply_gravity(delta)
	_face_camera_yaw(delta)
	var input_dir = _get_input_dir()
	_pre_move_vel = velocity
	_handle_tackle_input()              # <<< start tackle on input
	
	if tackle_active:
		_update_tackle(delta)           # <<< runs its own move_and_slide
		return   
		
	#_latch_ball_to_player()
	#if Input.is_action_just_pressed("stop_ball") and ball_latched:
		#_unlatch_ball_to_player()                       
	
	
	_handle_action(input_dir, delta)
	_update_aim(delta)   # <-- add this
	
func _update_charge(delta: float) -> void:
	var lmb_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if lmb_down:
		# fill toward 1 over charge_time_to_max seconds
		if charge_time_to_max > 0.0:
			#_charge = minf(1.0, _charge + (delta / charge_time_to_max))
			_charge = minf(1.0, _charge + charge_rate_mul * (delta / charge_time_to_max))
	else:
		# drain when released (optional; remove if you want it to snap to 0)
		_charge = maxf(0.0, _charge - charge_decay_speed * delta)
		#_charge = minf(1.0, _charge + charge_rate_mul * (delta / charge_time_to_max))
	# Reflect in UI
	if is_instance_valid(_charge_bar):
		_charge_bar.value = _charge * 100.0
		# Show while charging or if there’s still some value left
		_charge_bar.visible = lmb_down or _charge > 0.001

func _update_cooldowns(delta: float) -> void:
	for k in _cooldowns.keys():
		_cooldowns[k] = max(_cooldowns[k] - delta, 0.0)

func _update_tackle(delta: float) -> void:
	_latch_ball_to_player()
	# Horizontal decel
	var v_xz: Vector3 = Vector3(tackle_velocity.x, 0.0, tackle_velocity.z)
	var dec: float = tackle_decel * delta
	var new_len: float = maxf(v_xz.length() - dec, 0.0)
	var dir: Vector3 = v_xz.normalized()
	if v_xz == Vector3.ZERO:
		dir = Vector3.ZERO
	tackle_velocity = Vector3(dir.x * new_len, velocity.y, dir.z * new_len)

	# Apply gravity to vertical component separately
	if not is_on_floor():
		tackle_velocity.y = velocity.y - gravity * delta
	else:
		if tackle_velocity.y < 0.0:
			tackle_velocity.y = 0.0

	# Move the character with the tackle velocity
	velocity = tackle_velocity
	move_and_slide()

	## If ball latched, carry it at the saved local point
	#if ball_latched and is_instance_valid(current_ball) and is_instance_valid(tackle_field):
		#var anchor_world: Vector3 = tackle_field.to_global(ball_latch_local)
		#current_ball.freeze = true
		#current_ball.global_transform.origin = anchor_world
		#current_ball.linear_velocity  = Vector3.ZERO
		#current_ball.angular_velocity = Vector3.ZERO

	# End conditions
	tackle_time_left -= delta
	if tackle_time_left <= 0.0 or Vector3(velocity.x,0.0,velocity.z).length() < 0.1:
		_end_tackle()

func _end_tackle() -> void:
	tackle_active = false

	## Release ball if latched
	#if ball_latched and is_instance_valid(current_ball):
		#current_ball.freeze = false
		#current_ball.sleeping = false
	#ball_latched = false
#
	# Restore masks if pass-through used
	if characters_layer_bit > 0:
		collision_mask = _saved_player_mask
		#if is_instance_valid(current_ball):
			#current_ball.collision_mask = _saved_ball_mask
	_unlatch_ball_to_player()

func _latch_ball_to_player() -> void:
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
		
		

func _unlatch_ball_to_player() -> void:
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

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Small stick-to-ground if needed
		if velocity.y < 0.0:
			velocity.y = 0.0

func _get_input_dir() -> Vector3:
	var dir = Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	# Use camera-relative movement if you have a Camera3D in the scene
	var forward := (cam.basis * Vector3.FORWARD)
	forward.y = 0
	forward = forward.normalized()
	var right := (cam.basis * Vector3.RIGHT)
	right.y = 0
	right = right.normalized()

	if Input.is_action_pressed("move_forward"): dir += forward
	if Input.is_action_pressed("move_back"):    dir -= forward
	if Input.is_action_pressed("move_right"):   dir += right
	if Input.is_action_pressed("move_left"):    dir -= right

	return dir.normalized()
func _handle_action(input_dir: Vector3, delta: float) -> void:
	if _cooldowns["move"] == 0:
		_move(input_dir, delta)
	if _cooldowns["jump"] == 0:
		_handle_jump()
	_handle_kick_action()


func _handle_kick_action() -> void:
	if _cooldowns["shoot"] == 0:
		_handle_shoot()
		_handle_dribble()
		_handle_ball_stop()

func _move(input_dir: Vector3, delta: float) -> void:
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	var lateral_vel := velocity
	lateral_vel.y = 0.0

	var target_vel = input_dir * target_speed

	# Ground vs air control
	var accel := 12.0 if is_on_floor() else 12.0 * air_control

	lateral_vel = lateral_vel.lerp(target_vel, clamp(accel * delta, 0.0, 1.0))

	velocity.x = lateral_vel.x
	velocity.z = lateral_vel.z

	# Rotate towards movement direction (optional)
	#if input_dir.length() > 0.1:
		#look_at(global_transform.origin + input_dir, Vector3.UP)

	move_and_slide()
func _handle_ball_stop() -> void:
	if Input.is_action_pressed("stop_ball") and current_ball != null and is_instance_valid(current_ball): 
		print("performing kick action")
		current_ball.linear_velocity = Vector3.ZERO 
		current_ball.angular_velocity = Vector3.ZERO 
		_cooldowns["shoot"] = dribble_cooldown*0.5

func _handle_dribble() -> void:
	if Input.is_action_pressed("dribble") and _cooldowns["shoot"] == 0.0:
		print("performing kick action")
		if Input.is_action_pressed("move_left"):
			
			perform_dribble(-1)
			_cooldowns["shoot"] = dribble_cooldown
		elif Input.is_action_pressed("move_right"):
			
			perform_dribble(1)
			_cooldowns["shoot"] = dribble_cooldown
		elif Input.is_action_pressed("move_forward"):
			_fling_ball()
			_cooldowns["shoot"] = dribble_cooldown

func _fling_ball() -> void:
	if current_ball == null or not is_instance_valid(current_ball):
		return

	current_ball.sleeping = false

	# Optional: clear existing velocity so the fling is deterministic
	if fling_zero_prev_vel:
		current_ball.linear_velocity  = Vector3.ZERO
		current_ball.angular_velocity = Vector3.ZERO

	# Upward impulse (+ optional forward bias)
	var J: Vector3 = Vector3.UP * fling_up_impulse
	J*=0.2
	if fling_forward_bias != 0.0:
		var fwd: Vector3 = -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.0:
			fwd = fwd.normalized()
			J += fwd * fling_forward_bias

	# Apply at center (no spin)
	current_ball.apply_impulse(J, Vector3.ZERO)
			
func perform_dribble(direction: int) -> void:
	
	if current_ball == null or not is_instance_valid(current_ball):
		return

	var player_pos: Vector3 = global_transform.origin
	var ball_pos: Vector3 = current_ball.global_transform.origin
	var to_ball: Vector3 = (ball_pos - player_pos)
	var to_ball_xz := Vector3(to_ball.x, 0.0, to_ball.z)
	if to_ball_xz == Vector3.ZERO:
		return

	# Facing (horizontal)
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() == 0.0:
		return
	fwd = fwd.normalized()

	var facing_dot: float = fwd.dot(to_ball_xz.normalized())
	if facing_dot < dribble_cone_dot:
		return

	# Pure left/right (no forward bias)
	var right_xz: Vector3 = fwd.cross(Vector3.UP).normalized()
	var push_xz: Vector3 = (right_xz * float(direction)).normalized()

	# >>> ADD THIS HERE: remove any existing forward drift <<<
	var v: Vector3 = current_ball.linear_velocity
	var v_no_fwd: Vector3 = v - fwd * v.dot(fwd)   # project out forward component
	current_ball.linear_velocity = v_no_fwd

	# Impulse (side only + tiny lift)
	var J: Vector3 = push_xz * dribble_impulse + Vector3.UP * dribble_up

	# Apply at contact (slightly toward COM to reduce spin)
	var radius: float = _get_ball_radius(current_ball)
	var approx_contact: Vector3 = ball_pos - fwd * radius
	var local_contact: Vector3 = current_ball.to_local(approx_contact).lerp(Vector3.ZERO, 0.4)

	current_ball.sleeping = false
	current_ball.apply_impulse(J, local_contact)


	
func _handle_jump() -> void:
	# Use ray or is_on_floor() for robust ground check
	var grounded = is_on_floor() or (ground_ray and ground_ray.is_colliding())
	if grounded and Input.is_action_just_pressed("jump") and _cooldowns["jump"] == 0.0:
		velocity.y = jump_velocity
		_cooldowns["jump"] = jump_cooldownn

func _handle_shoot() -> void:
	if aim_active and current_ball != null and Input.is_action_just_released("shoot") and _cooldowns["shoot"] == 0.0:

		_kick_at_contact()

func _perform_kick() -> void:
	if not is_instance_valid(kick_area):
		return
	var fwd := -global_transform.basis.z.normalized()

	# pick the nearest ball in the area (avoids double-kicking multiple balls)
	var nearest: RigidBody3D = null
	var best_d := INF

	for body in kick_area.get_overlapping_bodies():
		print("  •", body.name, "groups:", body.get_groups())
		if body is RigidBody3D and body.is_in_group("ball"):
			print("the ball is found")
			var d := global_transform.origin.distance_to(body.global_transform.origin)
			if d < best_d:
				best_d = d
				nearest = body

	if nearest:
		# optional: only kick if roughly in front of the player
		var to_ball := (nearest.global_transform.origin - global_transform.origin).normalized()
		if fwd.dot(to_ball) >= 0.2:  # -1..1; >0 means in front cone
			var impulse := fwd * kick_force + Vector3.UP * kick_up
			nearest.apply_impulse(impulse)
			
func _handle_tackle_input() -> void:
	if tackle_active:
		return
	if not Input.is_action_just_pressed("tackle"):
		return
	if tackle_require_floor and not is_on_floor():
		return
	_start_tackle()

func _start_tackle() -> void:
	# Facing (XZ)
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() == 0.0:
		return
	fwd = fwd.normalized()

	# Use horizontal pre-move speed to scale duration & slide speed
	var v0: Vector3 = _pre_move_vel
	var v0_xz: Vector3 = Vector3(v0.x, 0.0, v0.z)
	var speed0: float = v0_xz.length()

	# Map speed to duration in [tackle_dur_min .. tackle_dur_max]
	var s_norm: float = clampf(speed0 / maxf(0.001, sprint_speed), 0.0, 1.0)

	# Duration: bias toward long at high speeds
	var w_dur: float = pow(s_norm, maxf(1.0, tackle_dur_curve))
	tackle_time_left = lerpf(tackle_dur_min, tackle_dur_max, w_dur)

	# Speed: bias toward fast at high speeds
	var slide_speed: float = clampf(speed0 * tackle_speed_mul, tackle_speed_min, tackle_speed_max)
	var w_spd: float = pow(s_norm, maxf(1.0, tackle_speed_curve))
	slide_speed = lerpf(slide_speed, tackle_speed_max, 0.25 * w_spd)  # small extra kick up top
	tackle_velocity = fwd * slide_speed

	# Latch state
	tackle_active = true
	#ball_latched = false

	# Optional: pass through characters layer during tackle
	if characters_layer_bit > 0:
		_saved_player_mask = collision_mask
		set_collision_mask_value(characters_layer_bit, false)
		set_collision_mask_value(ball_layer_bit, false)
		#if is_instance_valid(current_ball):
			#_saved_ball_mask = current_ball.collision_mask
			#current_ball.set_collision_mask_value(characters_layer_bit, false)
			
func _ensure_aim_arrow() -> void:
	if not show_aim_arrow:
		return
	aim_arrow = Node3D.new()
	aim_arrow.name = "AimArrow"
	add_child(aim_arrow)

	# ---- Shaft: Box aligned with local Z so we can just scale Z for length
	arrow_shaft = MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.08, 0.08, 1.0)  # 1.0 long along Z
	arrow_shaft.mesh = shaft_mesh
	# Put the box so its back is at z = 0 and tip is at z = -1 (center at -0.5)
	arrow_shaft.position = Vector3(0, 0, -0.5)
	aim_arrow.add_child(arrow_shaft)

	# ---- Head: small cone at the tip. CylinderMesh with top_radius=0 = cone.
	arrow_head = MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0   # cone
	head_mesh.bottom_radius = 0.12
	head_mesh.height = 0.24
	arrow_head.mesh = head_mesh
	# Cylinders point along Y; rotate so it points along -Z
	arrow_head.rotation_degrees.x = 90.0
	# Place at the tip (local -Z). After scaling Z, this will move with the tip.
	arrow_head.position = Vector3(0, 0, -1.0)
	aim_arrow.add_child(arrow_head)

	_show_arrow(false)

func _show_arrow(v: bool) -> void:
	if arrow_shaft: arrow_shaft.visible = v
	if arrow_head: arrow_head.visible = v

func _get_ball_radius(ball: RigidBody3D) -> float:
	# Try to find a SphereShape3D radius; fallback to ~0.12m
	var r := 0.12
	for child in ball.get_children():
		if child is CollisionShape3D and child.shape is SphereShape3D:
			r = child.shape.radius
			break
	return r

func _update_aim(delta: float) -> void:
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
func _kick_at_contact() -> void:
	if not is_instance_valid(current_ball):
		return

	# Geometry
	var C: Vector3 = current_ball.global_transform.origin
	var hit_point: Vector3 = aim_contact
	var impulse_dir: Vector3 = (C - hit_point).normalized()

	# Base (your tunables)
	var linear: Vector3 = impulse_dir * kick_force
	var lift: Vector3 = Vector3.UP * kick_up

	# --- 1) Charge scaling: logistic ease-in (tiny start, huge end)
	var q: float = clampf(_charge, 0.0, 1.0)

	# Logistic with knee at charge_knee and steepness charge_steepness, normalized to [0,1]
	var m: float = clampf(charge_knee, 0.05, 0.95)               # knee (midpoint) of the curve
	var s: float = maxf(0.001, charge_steepness)                 # slope

	# Compute logistic and normalize so f(0)=0, f(1)=1
	var f0: float = 1.0 / (1.0 + exp(-s * (0.0 - m)))
	var f1: float = 1.0 / (1.0 + exp(-s * (1.0 - m)))
	var f:  float = 1.0 / (1.0 + exp(-s * (q - m)))
	var q_eased: float = (f - f0) / maxf(1e-6, (f1 - f0))        # normalized 0..1

	var charge_mul: float = lerpf(charge_min_mul, charge_max_mul, q_eased)

	# --- 2) Velocity influence (use pre-move vel if captured)
	var v_player: Vector3 = _pre_move_vel
	if v_player == Vector3.ZERO:
		v_player = velocity
	var v_along: float = maxf(v_player.dot(impulse_dir), 0.0)
	var v_ref: float = vel_ref_speed
	if v_ref <= 0.0:
		v_ref = maxf(0.001, sprint_speed)
	var v_norm: float = clampf(v_along / v_ref, 0.0, 1.0)
	var vel_mul: float = lerpf(1.0 - vel_influence, 1.0 + vel_influence, v_norm)
	# --- Final impulse (+ optional cap)
	var J: Vector3 = (linear + lift) * (charge_mul * vel_mul)
	print("the force is: ", J)
	if kick_max_impulse > 0.0:
		var Jlen: float = J.length()
		if Jlen > kick_max_impulse:
			J = J * (kick_max_impulse / Jlen)

	# Apply at contact (adds spin). Lerp toward center to reduce spin if desired:
	current_ball.sleeping = false
	var local_contact: Vector3 = current_ball.to_local(hit_point)
	# local_contact = local_contact.lerp(Vector3.ZERO, 0.5)  # uncomment to reduce spin
	current_ball.apply_impulse(J, local_contact)
	var Jlen: float = J.length()
	_cooldowns["shoot"] = shoot_cooldown + Jlen * cooldown_per_impulse
	# Reset charge (optional)
	_charge = 0.0
	if is_instance_valid(_charge_bar):
		_charge_bar.value = 0.0

func _on_kick_area_body_entered(body: Node) -> void:
	if body is RigidBody3D and body.is_in_group("ball"):
		current_ball = body
		aim_active = true
		var C := current_ball.global_transform.origin
		var R := _get_ball_radius(current_ball)
		var dir := (C - global_transform.origin).normalized()
		aim_contact = C - dir * R
		aim_dir = (aim_contact - global_transform.origin).normalized()

func _on_kick_area_body_exited(body: Node) -> void:
	if body == current_ball:
		current_ball = null
		aim_active = false
		_show_arrow(false)
		
func _is_aiming() -> bool:
	return aim_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	#return aim_active and current_ball != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
func _face_ball_yaw(delta: float) -> void:
	if current_ball == null: return
	var to_ball: Vector3 = current_ball.global_transform.origin - global_transform.origin
	to_ball.y = 0.0
	if to_ball == Vector3.ZERO: return
	var target_yaw: float = atan2(-to_ball.x, -to_ball.z) # -Z is forward
	var cur := rotation
	cur.y = lerp_angle(cur.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))
	rotation = cur
