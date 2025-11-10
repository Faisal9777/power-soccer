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

@export var shoot_cost_mul: float = 0.2

@export var charge_min_mul: float = 0.03
@export var charge_max_mul: float = 20
@export var charge_curve: float = 12
@export var charge_knee: float = 0.5
@export var charge_steepness: float = 20.0

@export var dribble_impulse: float = 0.9
@export var dribble_forward_bias: float = 0.35
@export var dribble_up: float = 0.15
@export var dribble_cooldown: float = 1
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
@export var tackle_cost_mul: float = 0.5
@export var tackle_require_floor: bool = true
@export var owner_peer_id: int = 1
@export var characters_layer_bit: int = 2
@export var ball_layer_bit: int = 3
# --- Stamina config ---
@export var stamina_max: float = 100.0
@export var stamina_regen_rate: float = 15.0      # per second
@export var stamina_sprint_drain: float = 25.0    # per second while sprinting
@export var stamina_tackle_cost: float = 20.0     # one-time cost on tackle start
@export var stamina_min_to_sprint: float = 5.0 
@export var stamina_min_to_shoot: float = 10    # must be above this to sprint
@export var stamina_min_to_jump: float = 15
@export var stamina_min_to_dribble: float = 10
@export var stamina_min_to_stop_ball: float = 10    
@export var mouse_sens: float = 0.008
@onready var aim_pivot: Node3D = $AimPivot
@export var min_pitch := deg_to_rad(-60)
@export var max_pitch := deg_to_rad( 60)
# --- Aiming/orbit state (client-local) ---
@export var aim_sens_x := 0.010   # radians per pixel (tune)
@export var aim_sens_y := 0.010
@export var aim_pitch_min := deg_to_rad(-80)
@export var aim_pitch_max := deg_to_rad( 80)

var _aim_az := 0.0      # yaw around the ball (left/right)
var _aim_el := 0.0      # pitch around the ball (up/down)
var _captured := true
var _yaw_delta_accum: float = 0.0  # collected since last send
var _pitch_delta_accum := 0.0
var _is_frozen := true
const SELF_LAYER_UI := 19                     # the checkbox number in the inspector
const SELF_LAYER_MASK := 1 << (SELF_LAYER_UI - 1)  # convert 1..20 -> bit 0..19
const WORLD_LAYER_MASK := 1 << 0   # Layer 1 (default / visible to camera)
const EPS := 1e-6
# --- Stamina runtime (authoritative on server; replicated to owner) ---
var _stamina: float = 100.0

# UI nodes (client-local)
var _stam_layer: CanvasLayer
var _stam_root: Control
var _stam_bar: ProgressBar
var _can_stamina_regen : bool = true

# --- Runtime state ---
var current_ball_path: NodePath = NodePath("")
var current_ball: RigidBody3D = null

var aim_active: bool = false
var aim_dir: Vector3 = Vector3.ZERO
var aim_contact: Vector3 = Vector3.ZERO
#var arrow_position: Vector3 = Vector3.ZERO
var aim_arrow: Node3D = null
var arrow_shaft: MeshInstance3D = null
var arrow_head: MeshInstance3D = null

var _charge: float = 0.0
var _charge_layer: CanvasLayer
var _charge_root: Control
var _charge_bar: ProgressBar
var _ball_prev_parent: Node = null
var _ball_offset: Transform3D = Transform3D.IDENTITY  # ball in anchor space
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
var _ui_charge := 0.0  # client-only visual charge
@onready var name_tag: Label3D = $NameTag if has_node("NameTag") else null
@onready var ground_ray: RayCast3D = $GroundRay
@onready var kick_area: Area3D = $KickArea
@onready var tackle_field: Area3D = $TackleField
@onready var ball_latch_anchor: Node3D = Node3D.new()
@onready var is_mobile: bool = OS.has_feature("mobile")
@onready var joystick: Node = null
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
	"facing": {"yaw_delta" : _yaw_delta_accum, "pitch_delta" : _pitch_delta_accum},
	"aim_position": null
}

func apply_net_input(d: Dictionary) -> void:
	# SERVER ONLY: called by world.gd before simulate_server()
	for k in _net.keys():
		if d.has(k):
			_net[k] = d[k]
			#if k == "tackle_pressed":
				##print("net[k]: ", _net[k])
				##print("d[k]: ", d[k])
				#_net[k] = _net[k] + d[k]
			#else:
				#_net[k] = d[k]
func attach_camera(c: Camera3D, j : Node) -> void:

	joystick = j
	cam = c
	if cam and _is_local_owner():
		#print("hiding mesh for player: ", owner_peer_id)
		#_log_pid("done in: ")
	# Tag ONLY this player's visuals with the extra bit (additive!)
		_mark_self_layer_recursive(self)
		#_disable_self_shadows_recursive(self)
		# Cull only this extra bit on this camera
		cam.cull_mask &= ~SELF_LAYER_MASK
		cam.current = true
		cam.near = max(cam.near, 0.12) # small near-plane helps

# Aim the camera at a world position.
# yaw_only=true keeps the camera level (no pitch); set false to let it tilt up/down.
@rpc("any_peer", "reliable", "call_local")
func rpc_aim_camera_at(target_world: Vector3, from : Vector3) -> void:
	cam.face_towards(target_world, from)

func get_yaw() -> Dictionary:
	# Consume yaw delta accumulated since the last send (desktop)
	var yaw_delta := _yaw_delta_accum
	var pitch_delta := _pitch_delta_accum
	_yaw_delta_accum = 0.0
	_pitch_delta_accum = 0.0
	return {"yaw_delta" : yaw_delta, "pitch_delta" : pitch_delta}
#func _debug_list_visible_to_cam():
	#if cam == null: return
	#for ch in get_tree().get_nodes_in_group("**unused**"): pass # no group? do recursive walk
	#_debug_walk(self)
#
#func _debug_walk(n: Node) -> void:
	#for ch in n.get_children():
		#if ch is VisualInstance3D:
			#var vi := ch as VisualInstance3D
			#if (vi.layers & cam.cull_mask) != 0:
				#print("Still visible: ", vi.get_path(), " layers=", vi.layers)
		#_debug_walk(ch)

func _mark_self_layer_recursive(n: Node) -> void:
	for ch in n.get_children():
		# Skip the aim arrow and the name tag (and its subtree)
		if (aim_arrow and (ch == aim_arrow or aim_arrow.is_ancestor_of(ch))) \
		or (name_tag and (ch == name_tag or name_tag.is_ancestor_of(ch))) \
		or (ch is Label3D):   # extra safeguard
			continue

		if ch is VisualInstance3D:
			var v := ch as VisualInstance3D
			v.layers = (v.layers | SELF_LAYER_MASK) & ~WORLD_LAYER_MASK
			v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		_mark_self_layer_recursive(ch)
func _disable_self_shadows_recursive(n: Node) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D and (ch.layers & SELF_LAYER_MASK) != 0:
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_disable_self_shadows_recursive(ch)

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
	if tackle_field:
		tackle_field.body_entered.connect(_on_tackle_field_body_entered)
	if $KickArea:
		$KickArea.body_entered.connect(_on_kick_area_body_entered)
		$KickArea.body_exited.connect(_on_kick_area_body_exited)
	var my_id := get_tree().get_multiplayer().get_unique_id()
	var is_local := (owner_peer_id == my_id)
	var is_dedicated := OS.has_feature("server")
	
	ball_latch_anchor.name = "BallLatchAnchor"
	add_child(ball_latch_anchor)  # or: tackle_field.add_child(ball_latch_anchor)
	
	_ensure_aim_arrow()
	if is_local:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_captured = true
		_client_side_setup()
	# ⬇️ prevent taps-anywhere from triggering 'shoot'
	if is_mobile:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_erase_event("shoot", ev)   # remove mouse-left binding at runtime
	_ensure_name_tag()

func _ensure_name_tag() -> void:
	if name_tag == null:
		name_tag = Label3D.new()
		name_tag.name = "NameTag"
		name_tag.position = Vector3(0, 1.9, 0)   # hover above head
		add_child(name_tag)

	# Visual tuning
	name_tag.fixed_size = true
	name_tag.pixel_size = 0.002          # 0.004..0.010; tweak to taste
	name_tag.outline_size = 12           # optional readability
	name_tag.no_depth_test = false       # set true to draw through walls
	name_tag.visible = true

	# IMPORTANT: keep it on a camera-visible layer (default layer 1 is fine)
	name_tag.layers = 1

	# Text from your GameState (adapt if you use a different getter)
	if "get_player_name" in GameState:
		name_tag.text = GameState.get_player_name(owner_peer_id)
	elif GameState.player_name != "":
		name_tag.text = GameState.player_name
	else:
		name_tag.text = "Player %d" % owner_peer_id


func _log_pid(msg : String) -> void:
	print(msg, OS.get_process_id())

func _client_side_setup() -> void:
	_init_charge_ui()
	_init_stamina_ui()
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON

func _physics_process(delta: float) -> void:
	_local_physics_process(delta)
		# Approach #2: only the SERVER simulates gameplay.
	if !multiplayer.is_server():
		return
	simulate_server(delta)


func _process(delta: float) -> void:

	if get_tree().get_multiplayer().get_unique_id() == owner_peer_id: 
		_local_process(delta)
	if name_tag:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to_cam := cam.global_transform.origin - name_tag.global_transform.origin
			to_cam.y = 0.0
			if to_cam.length() > 0.001:
				name_tag.look_at(name_tag.global_transform.origin + to_cam, Vector3.UP)
				name_tag.rotate_y(PI)  # Label3D front faces -Z; flip it
				
func _local_physics_process(delta: float) -> void:
	if get_tree().get_multiplayer().get_unique_id() == owner_peer_id: 
		#request_arrow_calculation()
		_update_arrow_position(delta)


func _update_arrow_position(delta: float) -> void:
	var ball := _resolve_ball() as RigidBody3D
	if aim_arrow == null or ball == null or !is_instance_valid(ball) or !aim_active:
		_show_arrow(false)
		return

	# Live for owner, interpolated for others
	var is_owner := (multiplayer.get_unique_id() == owner_peer_id)
	var pxf: Transform3D = (global_transform if is_owner else get_global_transform_interpolated())
	var bxf: Transform3D = ball.get_global_transform_interpolated()

	var P: Vector3 = pxf.origin
	var C: Vector3 = bxf.origin
	var R: float   = _get_ball_radius(ball)

	var contact: Vector3 = C  # RMB not held => center of ball

	if _is_aiming():
		# RMB held: orbit on sphere via local azimuth/elevation (no camera rays)
		var pivot := get_node_or_null("AimPivot") as Node3D
		var pivot_pos: Vector3 = pxf.origin
		if is_instance_valid(pivot):
			pivot_pos = (pivot.global_transform.origin if is_owner else pivot.get_global_transform_interpolated().origin)

		# Orthonormal frame at ball, pointing toward player
		var front: Vector3 = (pivot_pos - C).normalized()   # from ball → player
		var up_ref: Vector3 = Vector3.UP
		if abs(front.dot(up_ref)) > 0.98:
			up_ref = Vector3(0, 0, 1)                       # fallback if almost parallel
		var right: Vector3 = up_ref.cross(front).normalized()
		var up_s: Vector3 = front.cross(right).normalized()

		# Rotate 'front' by azimuth around up_s, then elevation around right
		var basis_az: Basis = Basis(up_s, _aim_az)
		var basis_el: Basis = Basis(right, _aim_el)
		var dir: Vector3 = ((basis_el * basis_az) * front).normalized()

		contact = C + dir * R

	# Smooth & draw
	var smooth: float = 1.0 - pow(1.0 - 0.14, maxf(delta * 60.0, 0.0))
	aim_contact = aim_contact.lerp(contact, clamp(smooth, 0.0, 1.0))

	var vec: Vector3 = aim_contact - P
	if vec == Vector3.ZERO:
		_show_arrow(false)
		return

	_show_arrow(is_owner)
	aim_arrow.global_position = P
	aim_arrow.look_at(P + vec.normalized(), Vector3.UP)
	aim_arrow.scale = Vector3(1.0, 1.0, maxf(vec.length(), aim_min_len))

func _resolve_ball() -> RigidBody3D:
	if String(current_ball_path) == "":
		current_ball = null
		return null
	# If cached and still valid, reuse
	if current_ball != null and is_instance_valid(current_ball):
		if current_ball.get_path() == current_ball_path:
			return current_ball
	# Resolve fresh
	current_ball = get_node_or_null(current_ball_path) as RigidBody3D
	return current_ball

# --- Server gameplay loop (moved out of _physics_process for clarity) ---
func _is_local_owner() -> bool:
	return get_tree().get_multiplayer().get_unique_id() == owner_peer_id
func _local_process(delta: float) -> void:
	if _charge_bar :
		_update_charge_ui_from_replication()
	if _stam_bar:
		_update_stamina_ui_from_replication()

func _update_charge_ui_from_replication() -> void:
	# _charge here is replicated from the server via MultiplayerSynchronizer
	_charge_bar.value = _charge * 100.0
	_charge_bar.visible = _charge > 0.001 or _net["shoot_down"]

func simulate_server(delta: float) -> void:
	#if is_instance_valid(current_ball) and current_ball.linear_velocity.length() > 0.1:
		#log_ball_velocity()
	if not _is_frozen:
		if current_ball_path:
			_resolve_ball() 
		_update_cooldowns(delta)
		_update_charge_server(delta)
		apply_gravity(delta)
		#_face_camera_yaw(delta)
		_update_player_facing_server(delta)
		#_calculate_arrow_position(delta)
		var input_dir := _get_input_dir_server()
		_pre_move_vel = velocity
		_handle_tackle_input_server(delta)
		_handle_action_server(input_dir, delta)
		_update_stamina_server(delta)

func _can_perform(action: String, stamina_required : float) -> bool:
	
	if _is_valid_action(action) and _stamina > stamina_min_to_sprint:
		_stamina = maxf(0.0, _stamina - stamina_required)
		return true
	if action == "stamina_regen":
		if not tackle_active and is_on_floor():
			return true
	return false	

func _is_valid_action(action: String) -> bool:
	return ["sprint", "tackle", "shoot", "dribble", "jump", "stop"].has(action)


func _unhandled_input(event: InputEvent) -> void:
	if !_is_local_owner():
		return
	# Optional aim toggle you already had...
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_captured = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			# initialize arrow orbit from current facing: point to frontmost spot
			if not current_ball:
				_resolve_ball()
			if current_ball and is_instance_valid(current_ball):
				var C := current_ball.global_transform.origin
				var pivot := get_node_or_null("AimPivot") as Node3D
				var P := (pivot.global_transform.origin if is_instance_valid(pivot) else global_transform.origin)
				# front = from center toward player; start az=0, el=0 -> frontmost point
				_aim_az = 0.0
				_aim_el = 0.0
		else:
			_captured = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

		return

	# Mouse move → just accumulate yaw delta; no local rotation
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		
		if _is_aiming():
			# Arrow-only orbit control (do NOT rotate character)
			_aim_az +=  mm.relative.x * aim_sens_x
			_aim_el += mm.relative.y * aim_sens_y   # invert for typical feel
			# keep angles reasonable
			_aim_az = wrapf(_aim_az, -PI, PI)
			_aim_el = clamp(_aim_el, aim_pitch_min, aim_pitch_max)
		else:
			# Normal mode: accumulate facing deltas (character will rotate on server)
			_yaw_delta_accum   += -mm.relative.x * mouse_sens
			_pitch_delta_accum += -mm.relative.y * mouse_sens
		# (If you track local camera pitch, you can still update that here; it’s local-only)
func _update_stamina_ui_from_replication() -> void:
	# _stamina is replicated from server → owner via MultiplayerSynchronizer
	var pct := 100.0 * (_stamina / maxf(1e-6, stamina_max))
	_stam_bar.value = clampf(pct, 0.0, 100.0)
	# Optionally hide when full
	# _stam_bar.visible = pct < 99.9

func _update_stamina_server(delta: float) -> void:
	# Drain while actually sprinting & moving
	if _can_perform("stamina_regen", 0.0): 
		_stamina = minf(stamina_max, _stamina + stamina_regen_rate * delta)	
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
	#else:
		#_log_pid("")
		#print("charge bar does not exist for the player with id: ", owner_peer_id)

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
	var mag := 1.0
	if is_mobile and is_instance_valid(joystick):
		mag = joystick.mag
		walk_speed = walk_speed + (sprint_speed - walk_speed) * mag

	var target_speed := sprint_speed if _btn_down("sprint") and _can_perform("sprint", stamina_sprint_drain * delta) else walk_speed
	var lateral := velocity; lateral.y = 0.0
	var target_vel := input_dir * target_speed
	var accel := 12.0 if is_on_floor() else 12.0 * air_control
	lateral = lateral.lerp(target_vel, clamp(accel * delta, 0.0, 1.0))
	velocity.x = lateral.x
	velocity.z = lateral.z
	move_and_slide()

func _handle_jump_server() -> void:
	var grounded := is_on_floor() or (ground_ray and ground_ray.is_colliding())
	if grounded and _btn_just_pressed("jump") and _cooldowns["jump"] == 0.0 and _can_perform("jump", stamina_min_to_jump):
		velocity.y = jump_velocity
		_cooldowns["jump"] = jump_cooldownn

func _handle_kick_action_server() -> void:
	if _cooldowns["shoot"] != 0.0:
		return
	_handle_shoot_server()
	_handle_dribble_server()
	_handle_ball_stop_server()

func _handle_ball_stop_server() -> void:
	if _btn_down("stop_ball") and current_ball and is_instance_valid(current_ball) and _can_perform("stop", stamina_min_to_stop_ball):
		current_ball.linear_velocity = Vector3.ZERO
		current_ball.angular_velocity = Vector3.ZERO
		current_ball.sleeping = false
		_cooldowns["shoot"] = dribble_cooldown * 0.5

func _handle_dribble_server() -> void:
	if !_btn_down("dribble") or _cooldowns["shoot"] != 0.0:
		return
	#if not _can_perform("dribble", stamina_min_to_dribble): return
	var mvx := float(_net["mvx"])
	var mvz := float(_net["mvz"])
	if mvx + mvz == 0 or not _can_perform("dribble", stamina_min_to_dribble): return 
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
	print("about to apply impulse in dribble with values: ", J)
	current_ball.apply_impulse(J, local_contact)

func _handle_shoot_server() -> void:
	# Use edge up for the release shot
	if aim_active and current_ball != null and _btn_just_released("shoot"):
		#print("shoot all conditions have been met")
		_kick_at_contact_server()

func _kick_at_contact_server() -> void:
	if current_ball == null or !is_instance_valid(current_ball):
		return
	if aim_arrow == null or !is_instance_valid(aim_arrow):
		return
	if _charge <= 0.0:
		return

	# Ball center and radius
	var C: Vector3 = current_ball.global_transform.origin
	var R: float = _get_ball_radius(current_ball)

	# Ray from the aim arrow (forward is -Z after look_at)
	var axf: Transform3D = _net["aim_position"]
	var ro: Vector3 = axf.origin
	var rd: Vector3 = (-axf.basis.z).normalized()

	# ---- Ray → sphere (ball) ----
	var oc: Vector3 = ro - C
	var bq: float = 2.0 * rd.dot(oc)
	var cq: float = oc.dot(oc) - R * R
	var disc: float = bq * bq - 4.0 * cq

	var hit_point: Vector3 = Vector3.ZERO
	if disc >= 0.0:
		var sd: float = sqrt(disc)
		var t1: float = (-bq - sd) * 0.5
		var t2: float = (-bq + sd) * 0.5
		var t: float = -1.0
		if t1 > 0.0:
			t = t1
		elif t2 > 0.0:
			t = t2
		if t > 0.0:
			hit_point = ro + rd * t

	# Fallback: closest point along the arrow ray projected to the sphere surface
	if hit_point == Vector3.ZERO:
		var t_closest: float = maxf(-rd.dot(oc), 0.0)
		var closest: Vector3 = ro + rd * t_closest
		var dir_to: Vector3 = closest - C
		if dir_to == Vector3.ZERO:
			dir_to = ro - C
		hit_point = C + dir_to.normalized() * R

	# Impulse direction from contact → center (pure geometry)
	var dir: Vector3 = (C - hit_point).normalized()

	# Strength from charge (tweak exponent as you like)
	var q: float = clampf(_charge, 0.0, 1.0)
	var exponent: float = 2.0
	var strength: float = kick_force * pow(q, exponent)

	var J: Vector3 = dir * strength

	current_ball.sleeping = false
	#current_ball.apply_impulse(J,  hit_point - C)
	var ball := current_ball as Ball
	if not ball : print("ball bcame null when casted")
	ball.apply_hit(J,  hit_point - C, owner_peer_id)
	#_debug_red_dot(current_ball, hit_point, 500)
	# housekeeping
	_cooldowns["shoot"] = shoot_cooldown
	_charge = 0.0
	if is_instance_valid(_charge_bar):
		_charge_bar.value = 0.0

func get_aim_arrow_position() -> Transform3D:
	return aim_arrow.global_transform

func freeze(toggle : bool) -> void:
	_is_frozen = toggle


func _debug_red_dot(ball: Node3D,p: Vector3, seconds: float = 1.5, size: float = 0.06) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mi.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0)        # red
	mat.unshaded = true
	mat.disable_fog = true
	mi.material_override = mat

	mi.global_position = p

	# Put it under the current scene / world root
	#get_tree().current_scene.add_child(mi)
	current_ball.add_child(mi)
	# Place at the hit point relative to the ball
	mi.position = current_ball.to_local(p)
	# Auto-remove after a moment
	var t := get_tree().create_timer(seconds)
	t.timeout.connect(func(): if is_instance_valid(mi): mi.queue_free())

func _handle_tackle_input_server(delta: float) -> void:
	
	#if _net["tackle_pressed"] == 0: return
	#_net["tackle_pressed"] = _net["tackle_pressed"] - 1
	var can_perform : bool = _net["tackle_pressed"]
	#if _net["tackle_pressed"]>0:
		#print("the tackle pressed counter: ", _net["tackle_pressed"])
		#_net["tackle_pressed"] = _net["tackle_pressed"] - 1
		#can_perform = true  
	if tackle_active: 
		_update_tackle_server(delta)
		return
	#if !_btn_just_pressed("tackle"): return
	#if not Input.is_action_just_pressed("tackle"): return
	if tackle_require_floor and !is_on_floor(): return
	if can_perform : _start_tackle_server()
	#_net["tackle_pressed"] = false

func _start_tackle_server() -> void:

	var fwd := -global_transform.basis.z; fwd.y = 0.0
	if fwd.length() == 0.0: return
	fwd = fwd.normalized()

	var v0_xz := Vector3(_pre_move_vel.x, 0.0, _pre_move_vel.z)
	var speed0 := v0_xz.length()
	var s_norm := clampf(speed0 / maxf(0.001, sprint_speed), 0.0, 1.0)

	var w_dur := pow(s_norm, maxf(1.0, tackle_dur_curve))
	
	var slide_speed := clampf(speed0 * tackle_speed_mul, tackle_speed_min, tackle_speed_max)
	var w_spd := pow(s_norm, maxf(1.0, tackle_speed_curve))
	slide_speed = lerpf(slide_speed, tackle_speed_max, 0.25 * w_spd)
	tackle_velocity = fwd * slide_speed
	if not _can_perform("tackle", stamina_tackle_cost + tackle_cost_mul * slide_speed): return
	tackle_time_left = lerpf(tackle_dur_min, tackle_dur_max, w_dur)
	tackle_active = true

	#_latch_ball_server2(current_ball)

func _update_tackle_server(delta: float) -> void:
	# keep the ball glued while latched (server-side tick snap)
	
	_update_latched_ball_server(delta)
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

# Call when tackle begins and you decide to latch
func _latch_ball_server(ball: RigidBody3D) -> void:
	if ball == null:
		return

	_latched_ball = ball

	# Save collisions to restore later
	_saved_ball_layer = ball.collision_layer
	_saved_ball_mask  = ball.collision_mask

	# Compute offset: anchor^-1 * ball (so ball = anchor * offset each frame)
	_ball_offset = ball_latch_anchor.global_transform.affine_inverse() * ball.global_transform

	# Make physics tame while carried (no reparent)
	ball.freeze = true
	ball.linear_velocity  = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	# Optional: avoid blocking while carried (do replicate these to clients via tiny RPC if you need)
	ball.collision_layer = 0
	ball.collision_mask  = 0

	ball_latched = true

# Call when tackle ends
func _unlatch_ball_server() -> void:
	if _latched_ball == null:
		return

	var ball := _latched_ball
	_latched_ball = null
	#ball_latch_anchor = null
	ball_latched = false

	# Restore physics/collisions
	ball.freeze = false
	ball.collision_layer = _saved_ball_layer
	ball.collision_mask  = _saved_ball_mask

	# Optional: give it a finishing shove
	# ball.apply_impulse(impulse_vector, Vector3.ZERO)

func _update_latched_ball_server(delta: float) -> void:
	if ball_latched and _latched_ball != null and ball_latch_anchor != null:
		var target_xf: Transform3D = ball_latch_anchor.global_transform * _ball_offset
		_latched_ball.global_transform = target_xf
		# keep velocities calm while carried
		_latched_ball.linear_velocity  = Vector3.ZERO
		_latched_ball.angular_velocity = Vector3.ZERO

func _end_tackle_server() -> void:
	tackle_active = false
	if characters_layer_bit > 0:
		collision_mask = collision_mask # (restore if you modify it elsewhere)
	if ball_latched:
		_unlatch_ball_server()
	


# --- Misc / UI / aim ---

func _face_camera_yaw(delta: float) -> void:
	var target_yaw := float(_net.get("cam_yaw", rotation.y))
	var cur := rotation
	cur.y = lerp_angle(cur.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))
	rotation = cur

# Helper: face ball (body yaw + pivot pitch)
func _face_ball_server() -> void:
	_resolve_ball()
	if current_ball == null or !is_instance_valid(current_ball):
		return
	focus_at(current_ball)
	
func focus_at(current_ball : Node3D) -> void:
	var ball_pos: Vector3 = current_ball.global_transform.origin
	var body_pos: Vector3 = global_transform.origin
	var pivot_pos: Vector3 = (aim_pivot.global_transform.origin if is_instance_valid(aim_pivot) else body_pos)

	# --- Yaw on the upright body (ignore vertical) ---
	var v_h := ball_pos - body_pos
	v_h.y = 0.0
	if v_h.length_squared() > 1e-8:
		var r := rotation
		# Because -Z is forward, use (-x, -z) in atan2:
		r.y = atan2(-v_h.x, -v_h.z)
		# (equivalently: r.y = atan2(v_h.x, v_h.z) + PI)
		rotation = r

	# --- Pitch on the aim pivot (up/down toward ball) ---
	if is_instance_valid(aim_pivot):
		var v := ball_pos - pivot_pos
		var horiz := sqrt(v.x * v.x + v.z * v.z)
		var pitch := atan2(v.y, max(horiz, 1e-5))  # +up
		var pr := aim_pivot.rotation
		pr.x = clamp(pitch, min_pitch, max_pitch)
		aim_pivot.rotation = pr
func _update_player_facing_server(delta: float) -> void:
	if !multiplayer.is_server(): return

	var aiming := bool(_net.get("rmb", false))
	if aiming:
		print("[SERVER] APPLY face_ball (rmb=true) for peer=", owner_peer_id)
		_face_ball_server()
		return

	var f: Dictionary = _net.get("facing", {})
	var dy := float(f.get("yaw_delta", 0.0))
	var dp := float(f.get("pitch_delta", 0.0))

	# DEBUG: only print if anything would change
	if absf(dy) > 1e-6 or absf(dp) > 1e-6:
		print("[SERVER] APPLY facing dy=", dy, " dp=", dp, " for peer=", owner_peer_id)

	if absf(dy) > 1e-6:
		var r := rotation
		r.y = wrapf(r.y + clamp(dy, -0.35, 0.35), -PI, PI)
		rotation = r

	if is_instance_valid(aim_pivot) and absf(dp) > 1e-6:
		var pr := aim_pivot.rotation
		pr.x = clamp(pr.x + clamp(dp, -0.35, 0.35), min_pitch, max_pitch)
		aim_pivot.rotation = pr


func _ensure_aim_arrow() -> void:
	if !show_aim_arrow: return
	aim_arrow = Node3D.new()
	aim_arrow.name = "AimArrow"
	add_child(aim_arrow)

	arrow_shaft = MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.08, 0.08, 1.0)
	arrow_shaft.mesh = shaft_mesh
	arrow_shaft.position = Vector3(0, 0, -0.5)
	arrow_shaft.layers = WORLD_LAYER_MASK    # ensure visible to camera
	aim_arrow.add_child(arrow_shaft)

	arrow_head = MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.12
	head_mesh.height = 0.24
	arrow_head.mesh = head_mesh
	arrow_head.rotation_degrees.x = 90.0
	arrow_head.position = Vector3(0, 0, -1.0)
	arrow_head.layers = WORLD_LAYER_MASK     # ensure visible to camera
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

func _init_stamina_ui() -> void:
	_stam_layer = CanvasLayer.new()
	add_child(_stam_layer)

	_stam_root = Control.new()
	_stam_root.name = "StaminaUI"
	_stam_layer.add_child(_stam_root)

	# Anchor bottom-right like the charge bar
	_stam_root.anchor_left = 1.0
	_stam_root.anchor_top = 1.0
	_stam_root.anchor_right = 1.0
	_stam_root.anchor_bottom = 1.0

	# Place it just above the charge bar
	_stam_root.offset_right = -16
	_stam_root.offset_bottom = -44   # a bit higher than charge
	_stam_root.offset_left = _stam_root.offset_right - 200
	_stam_root.offset_top = _stam_root.offset_bottom - 20

	_stam_bar = ProgressBar.new()
	_stam_bar.min_value = 0.0
	_stam_bar.max_value = 100.0
	_stam_bar.step = 0.1
	_stam_bar.value = 100.0
	_stam_bar.rounded = true
	_stam_bar.show_percentage = false
	_stam_bar.anchor_left = 0.0
	_stam_bar.anchor_top = 0.0
	_stam_bar.anchor_right = 1.0
	_stam_bar.anchor_bottom = 1.0
	_stam_bar.offset_left = 0
	_stam_bar.offset_top = 0
	_stam_bar.offset_right = 0
	_stam_bar.offset_bottom = 0
	_stam_root.add_child(_stam_bar)

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

func _is_aiming() -> bool:
	return aim_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
# KickArea hooks
func _on_kick_area_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if body is RigidBody3D and body.is_in_group("ball"):
		var ball := body as RigidBody3D

		#var C: Vector3 = ball.global_transform.origin
		#var P: Vector3 = global_transform.origin
		#var dir: Vector3 = (C - P).normalized()

		current_ball_path = ball.get_path()
		aim_active = true
		#var R: float = _get_ball_radius(ball)
		#aim_contact = C - dir * R
		#aim_dir = (aim_contact - P).normalized()
func _on_kick_area_body_exited(body: Node) -> void:
	if not multiplayer.is_server(): return
	if body == current_ball:
		current_ball = null
		current_ball_path = NodePath("")
		aim_active = false
		_show_arrow(false)

func _on_tackle_field_body_entered(body: Node) -> void:
	if !multiplayer.is_server():
		return
	var rb := body as RigidBody3D
	if rb == null:
		return
	if !rb.is_in_group("ball"):
		return

	# start follow-with-offset latch (no reparent)
	if tackle_active:
		_latch_ball_server(rb)
