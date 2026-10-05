extends NodeController
class_name LocalController

var last_processed_seq  := -1
var can_simulate := false
var cam : Node
var joystick: Node
var is_mobile: bool = OS.has_feature("mobile")
var applied_cmd_id := -1
var _paused := false
var _next_input_seq : int = 0
var _pending_inputs: Array[Dictionary] = []
var can_process := false

func set_paused(state: bool) -> void:
	print("SET PAUSED CALLED: ", id, " -> ", state)

	_paused = state
	cam.freeze_rotation(state)

func process_input(delta):
	if GameState.is_paused:
		return

	var input = input_buffer.get_input()

	_apply_inputs(input, delta)


func set_position(gb_transform : Transform3D) -> void:
	super.set_position(gb_transform)
	cam.snap_to(gb_transform)

func freeze(toggle) -> void:
	#print("on: ", id)
	#print("freeze was called on with toggle: ", toggle)
	super.freeze(toggle)
	#cam.freeze_rotation(toggle)

func physics_tick(delta: float) -> void:
	player._local_physics_process(delta)
	super.physics_tick(delta)

func process_tick(delta: float) -> void:
	if can_process:
		player._local_process(delta)

func _init(p_player, pid, p_name, team, c_cam, ball, joystick, i_buffer : InputBuffer):
	cam = c_cam
	cam.set_rotation_source(self)
	p_player.enable_arrow(true)
	super._init(p_player, pid, p_name, team, ball, i_buffer)

func _get_player_movement(input) -> Dictionary:
	if _paused:
		return {"mvx": 0.0, "mvz": 0.0, "sprint": false}
	
	if typeof(input) == TYPE_DICTIONARY and input != null:
		if input.has("mvx") and input.has("mvz"):
			return {
				"mvx": float(input["mvx"]),
				"mvz": float(input["mvz"]),
				"sprint": bool(input.get("sprint", false)),
				"move_magnitude": clampf(float(input.get("move_magnitude", 1.0)), 0.0, 1.0)
			}

	if is_mobile and is_instance_valid(joystick):
		var mvx : float = 0.0
		var mvz : float = 0.0
		var v2: Vector2 = joystick.vector
		if v2.length() > 0.01:
			mvx = v2.x
			mvz = v2.y	
		return {
			"mvx" : mvx,
			"mvz": mvz,
			"sprint" : bool(input.get("sprint", false)) if typeof(input) == TYPE_DICTIONARY else false,
			"move_magnitude": clampf(joystick.mag, 0.0, 1.0)
		}

	return super._get_player_movement(input)

func _generate_facing_direction_with_input(input) -> void:
	if _paused:
		return
	if typeof(input) != TYPE_DICTIONARY or input == null:
		return

	if input.get('rmb'):
		# Direction FROM camera TO target
		var dir : Vector3 = (w_ball.global_position - player.global_position).normalized()
		look_yaw = atan2(-dir.x, -dir.z)
		look_pitch = clamp(
			asin(dir.y),
			min_pitch,
			max_pitch
		)
	else:
		var look_delta = input.get("mouse_delta")
		var facing = {"yaw" : look_yaw - look_delta.x * mouse_sens, 
		"pitch" : look_pitch - look_delta.y * mouse_sens}
		super._generate_facing_direction_with_input(facing)
		look_pitch = clamp(look_pitch, min_pitch, max_pitch)
	
	input["cam_yaw"] = look_yaw
	input["aim_position"] = player.get_aim_arrow_position() if player else null
	
