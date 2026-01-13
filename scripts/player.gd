extends CharacterBody3D
class_name Player
# --- Tunables (unchanged) ---
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.5
@export var jump_velocity: float = 6.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var air_control: float = 0.4

@export var tackle_cooldown_dur: float = 20.0  # 20 seconds cooldown
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
# --- Tackle phasing (pass through other players while tackling) ---
@export var tackle_phase_through_players: bool = true

var _saved_body_layer: int = 0
var _saved_body_mask: int = 0
var _tackle_phasing: bool = false
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
@export var latch_stamina_drain: float = 12.0   # per second while latched
@export var latch_min_to_start: float = 20.0    # need at least this to turn on
@export var latch_floor_speed_mul: float = 0.2  # 0.2 = 80% slower on ground

@export var mouse_sens: float = 0.008
@onready var aim_pivot: Node3D = $AimPivot
@export var min_pitch := deg_to_rad(-60)
@export var max_pitch := deg_to_rad( 60)
# --- Aiming/orbit state (client-local) ---
@export var aim_sens_x := 0.010   # radians per pixel (tune)
@export var aim_sens_y := 0.010
@export var aim_pitch_min := deg_to_rad(-80)
@export var aim_pitch_max := deg_to_rad( 80)
# --- Generic: keep air momentum (used by abilities like Grapple) ---
var _air_momentum_keep_left := 0.0

func start_air_momentum_keep(seconds: float) -> void:
	_air_momentum_keep_left = maxf(_air_momentum_keep_left, seconds)

# --- Generic: external pull (used by abilities) ---
var _external_pull_active := false
var _external_pull_to := Vector3.ZERO
var _external_pull_speed := 0.0
var _external_pull_stop_dist := 1.2

# --- Abilities ---
const ABILITY_REGISTRY := {
	"grapple": "res://scripts/Abilities/GrappleAbility.gd",
}
signal ability_ui_changed(labels: PackedStringArray, visible: bool, wants_crosshair: bool)

var ability_mode_active: bool = false
var _ability: AbilityBase = null
var _ability_id: StringName = &"grapple"
# replicated property (this is the one you added in MultiplayerSynchronizer)
@export var ability_id: StringName = &"grapple":
	set(v):
		if _ability_id == v:
			return
		_ability_id = v
		if is_inside_tree():
			# ✅ when replicated value arrives on client, auto-equip there
			set_ability_local(_ability_id)
	get:
		return _ability_id

var _aim_az := 0.0      # yaw around the ball (left/right)
var _aim_el := 0.0      # pitch around the ball (up/down)
var _captured := true
var _yaw_delta_accum: float = 0.0  # collected since last send
var _pitch_delta_accum := 0.0
var _yaw_abs: float = 0.0
var _pitch_abs: float = 0.0
var _is_frozen := true
const SELF_LAYER_UI := 19                     # the checkbox number in the inspector
const SELF_LAYER_MASK := 1 << (SELF_LAYER_UI - 1)  # convert 1..20 -> bit 0..19
const WORLD_LAYER_MASK := 1 << 0   # Layer 1 (default / visible to camera)
const EPS := 1e-6
# --- Stamina runtime (authoritative on server; replicated to owner) ---
var _stamina: float = 100.0
var _using_sprint: bool = false 

# UI nodes (client-local)
var _stam_layer: CanvasLayer
var _stam_root: Control
var _stam_bar: ProgressBar
var _can_stamina_regen : bool = true

# client-side prediction bookkeeping
var _next_input_seq: int = 0
var _pending_inputs: Array = []   # [{seq, yaw_delta, pitch_delta}, ...]

# server-side bookkeeping (used on server, and snapshot->client)
var last_server_seq: int = -1

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
# replicated to owner (UI only)
var tackle_cd_ui: float = 0.0

@export var tackle_steal_window: float = 0.20  # seconds (tune: 0.15–0.30)

var _tackle_steal_left: float = 0.0
var _tackle_has_stolen: bool = false


# Latch helpers (no reparenting in netcode—see notes below)
@export var latch_stuck_layer: int = 8
@export var latch_unstuck_player_move_dist: float = 0.15  # meters; tweak

var _latch_stuck: bool = false
var _latch_stuck_player_pos: Vector3 = Vector3.ZERO

func _layer_bit(layer_num: int) -> int:
	return 1 << (layer_num - 1)

var ball_latched: bool = false
var _latched_offset_local: Vector3 = Vector3.ZERO
var _saved_ball_layer: int = 0
var _saved_ball_mask: int = 0
var _latched_ball: RigidBody3D = null
var latch_mode_active: bool = false   # toggle state
# Layer numbers: 1 -> (1<<0), 3 -> (1<<2), 8 -> (1<<7)
@export var latch_block_mask: int = (1 << 0) | (1 << 2) | (1 << 7)
# set to walls + players layers (example below)
@export var latch_cast_margin: float = 0.02
const LATCH_EPS := 0.001
@export var latch_max_dist: float = 4.0  # meters (make smaller = harder to latch)

var _latch_shape := SphereShape3D.new()
var _latch_q := PhysicsShapeQueryParameters3D.new()

@export var assist_pass_cooldown_dur: float = 20.0
@export var assist_pass_max_dist: float = 100.0     # how far teammate can be
@export var assist_pass_force: float = 5.0        # base impulse strength
@export var assist_pass_lift: float = 0.6          # little arc
@export var assist_pass_cone_dot: float = -0.2     # -1..1 (higher = more forward-only)

const PASS_TRAP_META_KEY := "pass_trap_info"

var assist_pass_cd_ui: float = 0.0   # replicated to owner for UI


var cam: Camera3D = null  # local-only reference
var _ui_charge := 0.0  # client-only visual charge
@onready var name_tag: Label3D = $NameTag if has_node("NameTag") else null
@onready var ground_ray: RayCast3D = $GroundRay
@onready var kick_area: Area3D = $KickArea
@onready var tackle_field: Area3D = $TackleField
@onready var ball_latch_anchor: Node3D = Node3D.new()
@onready var is_mobile: bool = OS.has_feature("mobile")
@onready var joystick: Node = null
# Add "tackle": 0.0 to the dictionary
var _cooldowns := {"shoot": 0.0, "move": 0.0, "jump": 0.0, "tackle": 0.0, "assist_pass": 0.0}

# --- Net input state (fed by world.gd on the server) ---
var _net := {
	"mvx": 0.0,
	"mvz": 0.0,
	"sprint": false,
	"jump_pressed": false,
	"tackle_pressed": false,
	"dribble": false,
	"stop_ball": false,
	"shoot_down": false,
	"shoot_up": false,
	"rmb": false,
	"facing": {"yaw_delta" : _yaw_delta_accum, "pitch_delta" : _pitch_delta_accum},
	"aim_position": null,
	"latch_toggle": false,
	"assist_pass_pressed": false,
	"cam_yaw": 0.0,

	# ✅ ADD THESE:
	"ability_toggle": false,
	"ability_action1": false,
	"ability_action2": false,
	"ability_action3": false,
}


func apply_net_input(d: Dictionary) -> void:
	# SERVER ONLY: called by world.gd before simulate_server()
	if d.get("assist_pass_pressed", false):
		var who := "SERVER" if multiplayer.is_server() else "CLIENT"
		print("PLAYER GOT assist_pass_pressed! who=", who)

	for k in _net.keys():
		if d.has(k):
			_net[k] = d[k]
			#if k == "tackle_pressed":
				##print("net[k]: ", _net[k])
				##print("d[k]: ", d[k])
				#_net[k] = _net[k] + d[k]
			#else:
				#_net[k] = d[k]

func attach_camera(c: Camera3D, j: Node) -> void:
	joystick = j
	cam = c
	if cam and _is_local_owner():
		_mark_self_layer_recursive(self)  # ✅ move my visuals to SELF layer only
		cam.current = true
		cam.near = max(cam.near, 0.12)

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


func get_snapshot() -> Dictionary:
	var snapshot := {
			"pos" : global_position,
			"vel": velocity,
			"yaw": rotation.y,
			"pitch": (aim_pivot.rotation.x if is_instance_valid(aim_pivot) else 0.0),
			"is_frozen" : _is_frozen
		}
	return snapshot
func apply_snapshot(snap: Dictionary) -> void:
	var yaw := snap["yaw"] as float
	var pitch := snap["pitch"] as float
	_is_frozen = snap["is_frozen"]
	_apply_facing_absolute(yaw, pitch)
	global_position = snap["pos"]


#func get_input_data() -> Dictionary:
	#var mvx : float = 0.0
	#var mvz : float = 0.0
	#if is_mobile and is_instance_valid(joystick):
		#var v2: Vector2 = joystick.vector
		#if v2.length() > 0.01:
			#mvx = v2.x
			#mvz = v2.y	
	#else: 
		#mvx = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		#mvz = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	#
	#var input := {
			#"mvx": mvx,
			#"mvz": mvz,
			#"yaw_delta": _yaw_delta_accum,
			#"pitch_delta": _pitch_delta_accum,
			#"sprint" : Input.is_action_pressed("sprint")
		#}
	#return input

func get_input_data() -> Dictionary:
	var mvx : float = 0.0
	var mvz : float = 0.0
	if is_mobile and is_instance_valid(joystick):
		var v2: Vector2 = joystick.vector
		if v2.length() > 0.01:
			mvx = v2.x
			mvz = v2.y	
	else: 
		mvx = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		mvz = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	
	var input := {
			"mvx": mvx,
			"mvz": mvz,
			"yaw": _yaw_abs,
			"pitch": _pitch_abs,
			"sprint" : Input.is_action_pressed("sprint"),
		}
	return input

func update_player_states(input: Dictionary, delta) -> void:
	if _is_frozen:
		return
	
	_update_player_facing(input)
	_handle_movement(input, delta)
	#_yaw_delta_accum = 0.0
	#_pitch_delta_accum = 0.0



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

func _btn_down2(name: String, net : Dictionary) -> bool:
	match name:
		"sprint": return bool(net["sprint"])
		"dribble": return bool(net["dribble"])
		"stop_ball": return bool(net["stop_ball"])
		"shoot": return bool(net["shoot_down"])
		_: return false

func _btn_just_pressed(name: String) -> bool:
	match name:
		"jump": return bool(_net["jump_pressed"])
		"tackle": return bool(_net["tackle_pressed"])
		"assist_pass": return bool(_net["assist_pass_pressed"])
		"shoot": return false
		_: return false


func _btn_just_released(name: String) -> bool:
	match name:
		"shoot": return bool(_net["shoot_up"])
		_: return false

# --- Engine callbacks ---

func _ready() -> void:
	add_to_group("players")
		#add a script called ClientPlayer
	_yaw_abs = rotation.y
	_pitch_abs = 0.0  # or whatever you use
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
	set_ability_local(_ability_id)


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
		#_handle_player_facing(delta)
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
	# ✅ If latched, this is always the truth
	if ball_latched and _latched_ball != null and is_instance_valid(_latched_ball):
		current_ball = _latched_ball
		current_ball_path = _latched_ball.get_path()
		return current_ball

	if String(current_ball_path) == "":
		current_ball = null
		return null

	if current_ball != null and is_instance_valid(current_ball) and current_ball.get_path() == current_ball_path:
		return current_ball

	current_ball = get_node_or_null(current_ball_path) as RigidBody3D
	return current_ball

# --- Server gameplay loop (moved out of _physics_process for clarity) ---
func _is_local_owner() -> bool:
	return get_tree().get_multiplayer().get_unique_id() == owner_peer_id
func _local_process(delta: float) -> void:
	if _charge_bar:
		_update_charge_ui_from_replication()
	if _stam_bar:
		_update_stamina_ui_from_replication()
		# Always tick the ability for the LOCAL OWNER (so visuals can update reliably)
	if _is_local_owner() and _ability:
		_ability.client_tick(self, delta)



func _update_charge_ui_from_replication() -> void:
	# _charge here is replicated from the server via MultiplayerSynchronizer
	_charge_bar.value = _charge * 100.0
	_charge_bar.visible = _charge > 0.001 or _net["shoot_down"]

func simulate_server(delta: float) -> void:
	if _is_frozen:
		return
	_air_momentum_keep_left = maxf(0.0, _air_momentum_keep_left - delta)

	if current_ball_path:
		_resolve_ball()

	# ✅ latch toggle + stamina drain must still happen while reeling
	_handle_latch_mode_server(delta)
	#if is_instance_valid(current_ball) and current_ball.linear_velocity.length() > 0.1:
		#log_ball_velocity()
	if not _is_frozen:
		if current_ball_path:
			_resolve_ball() 
		_update_cooldowns(delta)
		_update_charge_server(delta)
		apply_gravity(delta)
		#_face_camera_yaw(delta)
		#_update_player_facing_server(delta)
		#_calculate_arrow_position(delta)
		var input_dir := _get_input_dir_server()
		_pre_move_vel = velocity
		_handle_tackle_input_server(delta)
		_handle_action_server(input_dir, delta)
		_update_stamina_server(delta)

	
	_handle_assist_pass_server()

	# ✅ if grapple reel already moved us this tick, don't do normal movement,
	# but DO keep stamina logic stable and keep ball glued.
	if _external_pull_active:
		var to := _external_pull_to - global_position
		var dist := to.length()
		if dist <= _external_pull_stop_dist:
			clear_external_pull()
		else:
			var dir = to / max(dist, 0.001)
			velocity.x = dir.x * _external_pull_speed
			velocity.z = dir.z * _external_pull_speed
			apply_gravity(delta)
			move_and_slide()
		return

	# normal sim continues here
	apply_gravity(delta)

	var input_dir := _get_input_dir_server()

	# sprint decision
	var mvx := float(_net.get("mvx", 0.0))
	var mvz := float(_net.get("mvz", 0.0))
	var mv_len := Vector2(mvx, mvz).length()
	var has_movement := mv_len > 0.01

	var want_sprint := _btn_down("sprint")
	_using_sprint = want_sprint and has_movement and _stamina > stamina_min_to_sprint

	_pre_move_vel = velocity
	_handle_tackle_input_server(delta)
	_handle_action_server(input_dir, delta)
	_update_stamina_server(delta)
	_update_latched_ball_server(delta)
	_handle_ability_mode_server()

	if ability_mode_active and _ability:
		_ability.server_tick(self, delta)

		# movement override (grapple reel)
		if _ability.server_movement_override(self, delta):
			_using_sprint = false
			_update_stamina_server(delta)
			_update_latched_ball_server(delta)
			return


func _can_perform(action: String, stamina_required: float, spend: bool = true) -> bool:
	# Special case: "stamina_regen" is just a condition check (no cost)
	if action == "stamina_regen":
		# Only regen when on floor and not sliding in tackle
		return not tackle_active and is_on_floor()

	if not _is_valid_action(action):
		return false

	# Not enough stamina for this action
	if _stamina < stamina_required:
		return false

	# Spend stamina once when requested
	if spend and stamina_required > 0.0:
		_stamina = maxf(0.0, _stamina - stamina_required)

	return true

func _is_valid_action(action: String) -> bool:
	return ["sprint", "tackle", "shoot", "dribble", "jump", "stop"].has(action)


#func _unhandled_input(event: InputEvent) -> void:
	#if !_is_local_owner():
		#return
	## Optional aim toggle you already had...
	#if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		#if event.pressed:
			#_captured = false
			#Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			## initialize arrow orbit from current facing: point to frontmost spot
			#if not current_ball:
				#_resolve_ball()
			#if current_ball and is_instance_valid(current_ball):
				#var C := current_ball.global_transform.origin
				#var pivot := get_node_or_null("AimPivot") as Node3D
				#var P := (pivot.global_transform.origin if is_instance_valid(pivot) else global_transform.origin)
				## front = from center toward player; start az=0, el=0 -> frontmost point
				#_aim_az = 0.0
				#_aim_el = 0.0
		#else:
			#_captured = true
			#Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
#
		#return
#
	## Mouse move → just accumulate yaw delta; no local rotation
	#if event is InputEventMouseMotion:
		#var mm := event as InputEventMouseMotion
		#
		#if _is_aiming():
			## Arrow-only orbit control (do NOT rotate character)
			#_aim_az +=  mm.relative.x * aim_sens_x
			#_aim_el += mm.relative.y * aim_sens_y   # invert for typical feel
			## keep angles reasonable
			#_aim_az = wrapf(_aim_az, -PI, PI)
			#_aim_el = clamp(_aim_el, aim_pitch_min, aim_pitch_max)
		#else:
			## Normal mode: accumulate facing deltas (character will rotate on server)
			#_yaw_delta_accum   += -mm.relative.x * mouse_sens
			#_pitch_delta_accum += -mm.relative.y * mouse_sens
		## (If you track local camera pitch, you can still update that here; it’s local-only)

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
			_aim_az +=  mm.relative.x * aim_sens_x
			_aim_el +=  mm.relative.y * aim_sens_y
			_aim_az = wrapf(_aim_az, -PI, PI)
			_aim_el = clamp(_aim_el, aim_pitch_min, aim_pitch_max)
		else:
			# ✅ change: update absolute angles directly (still using relative mouse)
			_yaw_abs   = wrapf(_yaw_abs + (-mm.relative.x * mouse_sens), -PI, PI)
			_pitch_abs = clamp(_pitch_abs + (-mm.relative.y * mouse_sens), aim_pitch_min, aim_pitch_max)


func _update_stamina_ui_from_replication() -> void:
	# _stamina is replicated from server → owner via MultiplayerSynchronizer
	var pct := 100.0 * (_stamina / maxf(1e-6, stamina_max))
	_stam_bar.value = clampf(pct, 0.0, 100.0)
	# Optionally hide when full
	# _stam_bar.visible = pct < 99.9

func _update_stamina_server(delta: float) -> void:
	# Drain while actually sprinting
	if _using_sprint:
		_stamina = maxf(0.0, _stamina - stamina_sprint_drain * delta)
	else:
		# Regenerate when allowed
		if _can_perform("stamina_regen", 0.0, false):
			_stamina = minf(stamina_max, _stamina + stamina_regen_rate * delta)

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
	var prev_t = _cooldowns["tackle"]
	var prev_p = _cooldowns["assist_pass"]
	for k in _cooldowns.keys():
		_cooldowns[k] = max(_cooldowns[k] - delta, 0.0)

	if prev_p > 0.0 and _cooldowns["assist_pass"] == 0.0:
		assist_pass_cd_ui = 0.0
	# when tackle cooldown hits zero, notify UI once
	if prev_t > 0.0 and _cooldowns["tackle"] == 0.0:
		tackle_cd_ui = 0.0

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
	#if _cooldowns["move"] == 0.0:
		#_move_server(input_dir, delta)
	if _cooldowns["jump"] == 0.0:
		_handle_jump_server()
	_handle_kick_action_server()

func _handle_movement(inp, delta) -> void:
	if _cooldowns["move"] == 0.0:
		var yaw := rotation.y
		var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw); fwd.y = 0.0; fwd = fwd.normalized()
		var right := Vector3.RIGHT.rotated(Vector3.UP, yaw); right.y = 0.0; right = right.normalized()
		var mvx := float(inp["mvx"])
		var mvz := float(inp["mvz"])
		var input_dir := (right * mvx + fwd * mvz).normalized()
		var is_sprinting : bool = inp.get("sprint")
		_move_server(input_dir, delta, is_sprinting)

func _move_server(input_dir: Vector3, delta: float, is_sprinting : bool) -> void:
	var mag := 1.0
	if is_mobile and is_instance_valid(joystick):
		# 0..1 how hard the stick is pushed
		mag = clamp(joystick.mag, 0.0, 1.0)

	# Base speed is picked ONLY from sprint toggle.
	# Joystick magnitude just scales it down (analog walk).
	var base_speed := sprint_speed if _using_sprint else walk_speed
	var target_speed := base_speed * mag

# ✅ LATCH slow only on ground (NOT grapple)
	if ball_latched and is_on_floor():
		target_speed *= latch_floor_speed_mul


	var lateral := velocity
	lateral.y = 0.0

	var target_speed := sprint_speed if is_sprinting and _can_perform("sprint", stamina_sprint_drain * delta) else walk_speed
	var lateral := velocity; lateral.y = 0.0
	var target_vel := input_dir * target_speed
	var accel := 12.0 if is_on_floor() else 12.0 * air_control

	var no_input := input_dir.length_squared() < 0.0001

	# ✅ If we just released grapple and we're in the air with no input,
	var just_released := (_air_momentum_keep_left > 0.0)

	if !(just_released and no_input and !is_on_floor()):
		lateral = lateral.lerp(target_vel, clamp(accel * delta, 0.0, 1.0))
	# else: keep lateral as-is (momentum preserved)

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
	if to_ball_xz == Vector3.ZERO:
		return

	# 🔁 Use camera yaw, same as movement
	var yaw := float(_net.get("cam_yaw", rotation.y))
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	fwd.y = 0.0
	if fwd.length() == 0.0:
		return
	fwd = fwd.normalized()

	# ball must be roughly in front of the *camera*
	if fwd.dot(to_ball_xz.normalized()) < dribble_cone_dot:
		return

	var right_xz := fwd.cross(Vector3.UP).normalized()
	# remove forward drift
	var v := current_ball.linear_velocity
	current_ball.linear_velocity = v - fwd * v.dot(fwd)

	var J := right_xz * float(direction) * dribble_impulse + Vector3.UP * dribble_up
	var radius := _get_ball_radius(current_ball)
	var approx_contact := ball_pos - fwd * radius
	var local_contact := current_ball.to_local(approx_contact).lerp(Vector3.ZERO, 0.4)
	current_ball.sleeping = false
	current_ball.apply_impulse(J, local_contact)

func _handle_shoot_server() -> void:


	if aim_active and current_ball != null and _btn_just_released("shoot"):
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
	var can_perform : bool = _net["tackle_pressed"]
	
	if tackle_active: 
		_update_tackle_server(delta)
		return

	if tackle_require_floor and !is_on_floor(): 
		return

	# CHECK COOLDOWN HERE
	if can_perform and _cooldowns["tackle"] <= 0.0: 
		_start_tackle_server()
		
func _start_tackle_server() -> void:
	var fwd := Vector3.ZERO

	_resolve_ball()
	if aim_active and current_ball != null and is_instance_valid(current_ball):
		var to_ball := current_ball.global_transform.origin - global_transform.origin
		to_ball.y = 0.0
		if to_ball.length() > 0.001:
			fwd = to_ball.normalized()

	if fwd == Vector3.ZERO:
		fwd = -global_transform.basis.z
		fwd.y = 0.0

	if fwd.length() == 0.0:
		return
	fwd = fwd.normalized()

	var v0_xz := Vector3(_pre_move_vel.x, 0.0, _pre_move_vel.z)
	var speed0 := v0_xz.length()
	var s_norm := clampf(speed0 / maxf(0.001, sprint_speed), 0.0, 1.0)

	var w_dur := pow(s_norm, maxf(1.0, tackle_dur_curve))

	var slide_speed := clampf(speed0 * tackle_speed_mul, tackle_speed_min, tackle_speed_max)
	var w_spd := pow(s_norm, maxf(1.0, tackle_speed_curve))
	slide_speed = lerpf(slide_speed, tackle_speed_max, 0.25 * w_spd)

	tackle_velocity = fwd * slide_speed

	if not _can_perform("tackle", stamina_tackle_cost + tackle_cost_mul * slide_speed):
		return

	# ✅ APPLY COOLDOWN HERE
	#_cooldowns["tackle"] = tackle_cooldown_dur
	tackle_cd_ui = tackle_cooldown_dur
	tackle_time_left = lerpf(tackle_dur_min, tackle_dur_max, w_dur)
	tackle_active = true
	_enter_tackle_phasing()
	_tackle_steal_left = tackle_steal_window
	_tackle_has_stolen = false

func _update_tackle_server(delta: float) -> void:
	# keep the ball glued while latched (server-side tick snap)
	
	#_update_latched_ball_server(delta)
	# slide & gravity
	_tackle_steal_left = maxf(0.0, _tackle_steal_left - delta)
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
	current_ball = ball
	current_ball_path = ball.get_path()
	aim_active = true
	_latched_ball = ball
	_latch_stuck = false
	_latch_stuck_player_pos = global_position

	# Save collisions to restore later
	_saved_ball_layer = ball.collision_layer
	_saved_ball_mask  = ball.collision_mask

	_ball_offset = ball_latch_anchor.global_transform.affine_inverse() * ball.global_transform

	ball.freeze = true
	ball.linear_velocity  = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.collision_layer = 0
	ball.collision_mask  = 0

	_latch_shape.radius = _get_ball_radius_world(ball) + latch_cast_margin

	_latch_q.shape = _latch_shape
	_latch_q.margin = 0.0
	_latch_q.collision_mask = latch_block_mask
	_latch_q.exclude = [self.get_rid()]

	ball_latched = true

	# ✅ If the ball is ALREADY touching layer 8 when latch starts, stick immediately.
	if _is_latch_touching_layer(latch_stuck_layer, ball.global_position):
		_latch_stuck = true
		_latch_stuck_player_pos = global_position

func _ball_within_latch_range(ball: Node3D) -> bool:
	if ball == null or !is_instance_valid(ball):
		return false
	var p := global_transform.origin
	var b := ball.global_transform.origin
	return p.distance_to(b) <= latch_max_dist

# Call when tackle ends
func _unlatch_ball_server() -> void:
	if _latched_ball == null:
		return

	var ball := _latched_ball
	_latched_ball = null
	ball_latched = false

	# ✅ clear stuck state no matter what
	_latch_stuck = false

	# Restore physics/collisions
	ball.freeze = false
	ball.collision_layer = _saved_ball_layer
	ball.collision_mask  = _saved_ball_mask

func _handle_latch_mode_server(delta: float) -> void:
	# Edge-triggered latch toggle from network input
	var toggle := bool(_net.get("latch_toggle", false))
	if toggle:
		# consume the edge so it won't re-trigger
		_net["latch_toggle"] = false

		# If currently holding, toggle OFF
		if latch_mode_active:
			latch_mode_active = false
			if ball_latched:
				_unlatch_ball_server()
			return

		# Otherwise trying to toggle ON:
		# 1) Need stamina
		if _stamina < latch_min_to_start:
			return

		# 2) Need a ball AND it must be close enough RIGHT NOW
		var ball := _resolve_ball()
		if ball == null or !is_instance_valid(ball):
			return
		if !_ball_within_latch_range(ball):
			return

		# ✅ Only now do we enable latch mode and latch immediately
		latch_mode_active = true
		_latch_ball_server(ball)

	# Drain stamina ONLY while actually latched
	if latch_mode_active and ball_latched and is_instance_valid(_latched_ball):
		_stamina = maxf(0.0, _stamina - latch_stamina_drain * delta)

		# Auto-unlatch when empty
		if _stamina <= 0.0:
			latch_mode_active = false
			_unlatch_ball_server()

func _update_latched_ball_server(delta: float) -> void:
	if !ball_latched or _latched_ball == null or ball_latch_anchor == null:
		return

	# ✅ If we are stuck, do not move ball at all until player moves enough.
	if _latch_stuck:
		_latched_ball.linear_velocity = Vector3.ZERO
		_latched_ball.angular_velocity = Vector3.ZERO

		if global_position.distance_to(_latch_stuck_player_pos) <= latch_unstuck_player_move_dist:
			return
		# Player moved (back/forward/sideways) → unstick
		_latch_stuck = false

	# ✅ If we are not stuck yet, but we are currently touching layer 8, stick now.
	if not _latch_stuck and _is_latch_touching_layer(latch_stuck_layer, _latched_ball.global_position):
		_latch_stuck = true
		_latch_stuck_player_pos = global_position
		return

	var target_xf: Transform3D = ball_latch_anchor.global_transform * _ball_offset

	var from_pos := _latched_ball.global_position
	var to_pos   := target_xf.origin
	var motion   := to_pos - from_pos

	if motion.length_squared() < 1e-10:
		_latched_ball.global_transform = target_xf
		_latched_ball.linear_velocity = Vector3.ZERO
		_latched_ball.angular_velocity = Vector3.ZERO
		return

	var space := get_world_3d().direct_space_state

	_latch_q.transform = Transform3D(Basis(), from_pos)
	_latch_q.motion = motion

	var fractions: PackedFloat32Array = space.cast_motion(_latch_q)
	var safe := 1.0
	if fractions.size() >= 1:
		safe = float(fractions[0])

	safe = clampf(safe - LATCH_EPS, 0.0, 1.0)
	var new_pos := from_pos + motion * safe

	# ✅ If blocked, check WHAT blocked us; if it's on layer 8 => hard-freeze latch movement
	if safe < 0.999:
		var rest := space.get_rest_info(_latch_q) # uses same motion sweep
		var col = rest.get("collider")
		if col is CollisionObject3D:
			var stuck_mask := _layer_bit(latch_stuck_layer)
			if (col.collision_layer & stuck_mask) != 0:
				# Place ball at safe position and freeze latch motion entirely
				var xf := target_xf
				xf.origin = new_pos
				_latched_ball.global_transform = xf
				_latched_ball.linear_velocity = Vector3.ZERO
				_latched_ball.angular_velocity = Vector3.ZERO

				_latch_stuck = true
				_latch_stuck_player_pos = global_position
				return

	# Normal latch movement (not stuck)
	var xf2 := target_xf
	xf2.origin = new_pos
	_latched_ball.global_transform = xf2
	_latched_ball.linear_velocity = Vector3.ZERO
	_latched_ball.angular_velocity = Vector3.ZERO

func _end_tackle_server() -> void:
	tackle_active = false
	_exit_tackle_phasing()
	_tackle_steal_left = 0.0
	_tackle_has_stolen = false

	_cooldowns["tackle"] = tackle_cooldown_dur  # ✅ cooldown starts after finishing
	tackle_cd_ui = tackle_cooldown_dur
	if ball_latched and !latch_mode_active:
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
		
		_face_ball_server()
		return

	var f: Dictionary = _net.get("facing", {})
	var dy := float(f.get("yaw_delta", 0.0))
	var dp := float(f.get("pitch_delta", 0.0))

	# DEBUG: only print if anything would change
	 
	if absf(dy) > 1e-6:
		var r := rotation
		r.y = wrapf(r.y + clamp(dy, -0.35, 0.35), -PI, PI)
		rotation = r

	if is_instance_valid(aim_pivot) and absf(dp) > 1e-6:
		var pr := aim_pivot.rotation
		pr.x = clamp(pr.x + clamp(dp, -0.35, 0.35), min_pitch, max_pitch)
		aim_pivot.rotation = pr

func _update_player_facing(cmd: Dictionary) -> void:
	var aiming := bool(_net.get("rmb", false))
	if aiming:
		_face_ball_server()
		return

	# ✅ Read absolute angles from the command (robust for unreliable + latest-wins)
	var yaw := float(cmd.get("yaw", rotation.y))
	var pitch_default := 0.0
	if is_instance_valid(aim_pivot):
		pitch_default = aim_pivot.rotation.x

	var pitch := float(cmd.get("pitch", pitch_default))

	# Keep them in safe ranges (server-side sanity)
	yaw = wrapf(yaw, -PI, PI)
	pitch = clamp(pitch, min_pitch, max_pitch)

	# Apply (no smoothing; this is authoritative input apply)
	_apply_facing_absolute(yaw, pitch, 1.0)

func _apply_facing_absolute(yaw: float, pitch: float, alpha: float = 1.0) -> void:
	# alpha=1.0 means snap, alpha<1 means smooth/lerp
	rotation.y = lerp_angle(rotation.y, yaw, alpha)

	if is_instance_valid(aim_pivot):
		aim_pivot.rotation.x = lerp(aim_pivot.rotation.x, pitch, alpha)

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

		current_ball_path = ball.get_path()
		aim_active = true

		# ⬇️ optional: if latch mode is already on, auto-latch immediately
		if latch_mode_active and _ball_within_latch_range(ball):
			_latch_ball_server(ball)

func _on_kick_area_body_exited(body: Node) -> void:
	if not multiplayer.is_server(): return

	# ✅ If it's our latched ball, keep refs
	if ball_latched and _latched_ball == body:
		return

	if body == current_ball:
		current_ball = null
		current_ball_path = NodePath("")
		aim_active = false
		_show_arrow(false)


func _on_tackle_field_body_entered(body: Node) -> void:
	if !multiplayer.is_server():
		return

	# ✅ STEAL ONLY INSIDE THE HIT WINDOW
	if tackle_active and _tackle_steal_left > 0.0 and !_tackle_has_stolen:
		var victim := body as Player
		if victim == null or victim == self:
			return

		# Victim must be holding a latched ball
		if victim.ball_latched and victim._latched_ball != null and is_instance_valid(victim._latched_ball):
			var ball := victim._latched_ball

			# Victim drops it
			victim.latch_mode_active = false
			victim._unlatch_ball_server()
			victim.current_ball = null
			victim.current_ball_path = NodePath("")
			victim.aim_active = false

			# If we were holding, drop first
			if ball_latched:
				_unlatch_ball_server()

			# Take it
			current_ball_path = ball.get_path()
			current_ball = ball
			aim_active = true
			_latch_ball_server(ball)

			_tackle_has_stolen = true
			_tackle_steal_left = 0.0
			return

	# Existing: latch a BALL if it enters tackle field
	var rb := body as RigidBody3D
	if rb == null or !rb.is_in_group("ball"):
		return

	if (tackle_active or latch_mode_active) and _ball_within_latch_range(rb):
		_latch_ball_server(rb)

func _player_layer_mask() -> int:
	# characters_layer_bit is a layer number (1..32). You said player layer is 2.
	return 1 << (characters_layer_bit - 1)

func _enter_tackle_phasing() -> void:
	if !tackle_phase_through_players or _tackle_phasing:
		return
	_tackle_phasing = true
	_saved_body_layer = collision_layer
	_saved_body_mask  = collision_mask

	var p_mask := _player_layer_mask()
	# Remove player layer from BOTH so neither side collides with the other
	collision_layer = collision_layer & ~p_mask
	collision_mask  = collision_mask  & ~p_mask

func _exit_tackle_phasing() -> void:
	if !_tackle_phasing:
		return
	_tackle_phasing = false
	collision_layer = _saved_body_layer
	collision_mask  = _saved_body_mask
func _get_ball_radius_world(ball: RigidBody3D) -> float:
	var r := _get_ball_radius(ball)
	var s := ball.global_transform.basis.get_scale()
	return r * maxf(s.x, maxf(s.y, s.z))
func _is_latch_touching_layer(layer_num: int, at_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state

	# Save and temporarily narrow the query to ONLY the stuck layer.
	var old_mask := _latch_q.collision_mask
	_latch_q.collision_mask = _layer_bit(layer_num)

	_latch_q.transform = Transform3D(Basis(), at_pos)
	_latch_q.motion = Vector3.ZERO
	_latch_q.collide_with_bodies = true
	_latch_q.collide_with_areas = true  # important if your layer8 thing is Area3D

	var hits := space.intersect_shape(_latch_q, 8)

	_latch_q.collision_mask = old_mask
	return hits.size() > 0
func _handle_assist_pass_server() -> void:
	if !multiplayer.is_server():
		return

	var pressed := bool(_net.get("assist_pass_pressed", false))
	if !pressed:
		return

	# ✅ consume the edge
	_net["assist_pass_pressed"] = false

	print("ASSIST: pressed on server")

	if _cooldowns["assist_pass"] > 0.0:
		print("ASSIST: blocked by cooldown ", _cooldowns["assist_pass"])
		return

	_resolve_ball()

	# Optional: if latched, use the latched ball as the source of truth
	if (current_ball == null or !is_instance_valid(current_ball)) and ball_latched and is_instance_valid(_latched_ball):
		current_ball = _latched_ball
		current_ball_path = current_ball.get_path()

	if current_ball == null or !is_instance_valid(current_ball):
		print("ASSIST: no current_ball (path=", current_ball_path, " latched=", ball_latched, ")")
		return

	var target := _pick_best_teammate_for_pass()
	if target == null:
		print("ASSIST: no teammate found")
		return

	print("ASSIST: passing to ", target.owner_peer_id, " ", target.name)

	if ball_latched:
		latch_mode_active = false
		_unlatch_ball_server()
	# before applying impulse / apply_hit
	_mark_pass_trap_for_receiver(current_ball, target)

	_do_pass_to(target)

	_cooldowns["assist_pass"] = assist_pass_cooldown_dur
	assist_pass_cd_ui = assist_pass_cooldown_dur
	print("ASSIST: done. cooldown=", _cooldowns["assist_pass"])


func _pick_best_teammate_for_pass() -> Player:
	var my_team := GameState.get_team(owner_peer_id)
	if my_team == GameState.TEAM_NONE:
		return null

	# forward direction based on cam yaw (same as your movement)
	var yaw := float(_net.get("cam_yaw", rotation.y))
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	fwd.y = 0.0
	fwd = fwd.normalized()

	var best: Player = null
	var best_score := INF

	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p == self:
			continue
		if GameState.get_team(p.owner_peer_id) != my_team:
			continue

		var to_p := p.global_position - global_position
		to_p.y = 0.0
		var d := to_p.length()
		if d <= 0.01 or d > assist_pass_max_dist:
			continue

		# Prefer teammates generally in front (cone). If you want “any direction”, remove this.
		var dir := to_p / d
		if fwd.dot(dir) < assist_pass_cone_dot:
			continue

		# score: nearest wins (you can add extra weighting later)
		if d < best_score:
			best_score = d
			best = p

	# Fallback: if none in cone, allow nearest teammate in any direction
	if best == null:
		for n in get_tree().get_nodes_in_group("players"):
			var p := n as Player
			if p == null or p == self:
				continue
			if GameState.get_team(p.owner_peer_id) != my_team:
				continue
			var d2 := global_position.distance_to(p.global_position)
			if d2 < best_score and d2 <= assist_pass_max_dist:
				best_score = d2
				best = p

	return best


func _do_pass_to(target: Player) -> void:
	if current_ball == null or !is_instance_valid(current_ball):
		return

	# aim a bit above ground (feels nicer)
	var aim_pos := target.global_position + Vector3.UP * 0.6

	var from := current_ball.global_position
	var dir := (aim_pos - from)
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()

	# clear old movement
	current_ball.freeze = false
	current_ball.linear_velocity = Vector3.ZERO
	current_ball.angular_velocity = Vector3.ZERO
	current_ball.sleeping = false

	var J := dir * assist_pass_force + Vector3.UP * assist_pass_lift

	# If your ball is class_name Ball and you want tracking, use apply_hit:
	var b := current_ball as Ball
	if b != null:
		b.apply_hit(J, Vector3.ZERO, owner_peer_id)
	else:
		current_ball.apply_impulse(J, Vector3.ZERO)
func _mark_pass_trap_for_receiver(ball: RigidBody3D, receiver: Node) -> void:
	if ball == null or !is_instance_valid(ball) or receiver == null:
		return

	var info := {
		"team": GameState.get_team(owner_peer_id),
		"from_role": GameState.get_role(owner_peer_id), # must exist in GameState
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"used": false,
		"receiver_path": receiver.get_path(),
		"from_path": get_path(),  # so bots can exclude passer if needed
	}
	ball.set_meta(PASS_TRAP_META_KEY, info)


func get_muzzle_from_camera(cam: Camera3D) -> Vector3:
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var forward := -cam.global_transform.basis.z  # camera forward is -Z

	return cam.global_position \
		+ right * 0.25 \
		+ up * -0.18 \
		+ forward * 0.60

func _make_ability(id: StringName) -> AbilityBase:
	var key := String(id)
	var path: String = ABILITY_REGISTRY.get(key, "")
	if path == "":
		return null

	var script := load(path) as Script
	if script == null:
		push_error("Ability script not found: %s" % path)
		return null

	var inst = script.new()
	if inst is AbilityBase:
		return inst as AbilityBase

	push_error("Ability '%s' (%s) does NOT extend AbilityBase" % [key, path])
	return null

func set_ability_local(id: StringName) -> void:
	if _ability:
		_ability.on_unequipped(self)

	# ✅ set backing field directly
	_ability_id = id

	_ability = _make_ability(id)
	if _ability:
		_ability.on_equipped(self)

	_emit_ability_ui()

func _emit_ability_ui() -> void:
	var visible := ability_mode_active and _ability != null
	var labels := PackedStringArray(["Action1","Action2","Action3"])
	var cross := false
	if _ability:
		labels = _ability.labels()
		cross = _ability.wants_crosshair()
	ability_ui_changed.emit(labels, visible, cross)
func _handle_ability_mode_server() -> void:
	if !multiplayer.is_server():
		return

	if bool(_net.get("ability_toggle", false)):
		_net["ability_toggle"] = false
		ability_mode_active = !ability_mode_active

		rpc_id(owner_peer_id, "_rpc_set_ability_mode", ability_mode_active)
		if _ability:
			_ability.on_mode_changed(self, ability_mode_active)

@rpc("authority","reliable","call_local")
func _rpc_set_ability_mode(v: bool) -> void:
	ability_mode_active = v
	_emit_ability_ui()
	if _ability:
		_ability.on_mode_changed(self, ability_mode_active)
func _request_ability_latched(point: Vector3, target_path: NodePath) -> void:
	rpc_id(1, "_rpc_ability_latched", point, target_path)

func _request_ability_reel(on: bool) -> void:
	rpc_id(1, "_rpc_ability_reel", on)

func _request_ability_pull(on: bool) -> void:
	rpc_id(1, "_rpc_ability_pull", on)

func _request_ability_release() -> void:
	rpc_id(1, "_rpc_ability_release")
@rpc("any_peer","reliable","call_local")
func _rpc_ability_latched(point: Vector3, target_path: NodePath) -> void:
	if !multiplayer.is_server(): return
	if multiplayer.get_remote_sender_id() != owner_peer_id: return
	if _ability:
		_ability.sv_on_latched(self, point, target_path)

@rpc("any_peer","reliable", "call_local")
func _rpc_ability_reel(on: bool) -> void:
	if !multiplayer.is_server(): return
	if multiplayer.get_remote_sender_id() != owner_peer_id: return
	if _ability:
		_ability.sv_on_reel(self, on)

@rpc("any_peer","reliable", "call_local")
func _rpc_ability_pull(on: bool) -> void:
	if !multiplayer.is_server(): return
	if multiplayer.get_remote_sender_id() != owner_peer_id: return
	if _ability:
		_ability.sv_on_pull(self, on)

@rpc("any_peer","reliable", "call_local")
func _rpc_ability_release() -> void:
	if !multiplayer.is_server(): return
	if multiplayer.get_remote_sender_id() != owner_peer_id: return
	if _ability:
		_ability.sv_on_release(self)
func apply_external_pull(to_pos: Vector3, speed: float, stop_dist: float = 1.2) -> void:
	_external_pull_active = true
	_external_pull_to = to_pos
	_external_pull_speed = speed
	_external_pull_stop_dist = stop_dist

func clear_external_pull() -> void:
	_external_pull_active = false
	_external_pull_to = Vector3.ZERO
	_external_pull_speed = 0.0
	_external_pull_stop_dist = 1.2
func get_ability_icons() -> Dictionary:
	if _ability == null:
		return {}
	return {
		"ability": _ability.ability_icon,
		"a1": _ability.action1_icon,
		"a2": _ability.action2_icon,
		"a3": _ability.action3_icon,
	}
func refresh_ability_ui() -> void:
	_emit_ability_ui()
