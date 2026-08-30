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

func set_paused(state: bool) -> void:
	print("SET PAUSED CALLED: ", id, " -> ", state)

	_paused = state
	cam.freeze_rotation(state)

func process_input(delta):
	if GameState.is_paused:
		return

	var input = input_buffer.get_input()

	if is_mobile and is_instance_valid(joystick):
		input["mvx"] = joystick.vector.x
		input["mvz"] = joystick.vector.y
		input["move_magnitude"] = joystick.mag

		# IMPORTANT: get camera yaw BEFORE movement is calculated
		if is_instance_valid(cam) and cam.has_method("get_cam_yaw"):
			look_yaw = cam.get_cam_yaw()
			look_pitch = cam.get_cam_pitch()

		input["yaw"] = look_yaw
		input["pitch"] = look_pitch
	else:
		input["move_magnitude"] = 1.0

	_apply_inputs(input, delta)

	if not input.has("yaw"):
		input["yaw"] = look_yaw
		input["pitch"] = look_pitch

	_next_input_seq = int(input["seq"]) + 1
	var stored := input.duplicate(true)
	_pending_inputs.append(stored)

	if _pending_inputs.size() > 100:
		_pending_inputs = _pending_inputs.slice(
			_pending_inputs.size() - 100,
			_pending_inputs.size()
		)

func set_position(gb_transform : Transform3D) -> void:
	super.set_position(gb_transform)
	cam.snap_to(gb_transform)

func freeze(toggle) -> void:
	#print("on: ", id)
	#print("freeze was called on with toggle: ", toggle)
	super.freeze(toggle)
	#cam.freeze_rotation(toggle)

func _init(p_player, pid, p_name, team, c_cam, ball, joystick, i_buffer : InputBuffer):
	cam = c_cam
	cam.set_rotation_source(self)
	self.joystick = joystick

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

	if input.has("yaw") and input.has("pitch"):
		look_yaw = float(input["yaw"])
		look_pitch = clamp(float(input["pitch"]), min_pitch, max_pitch)
		return

	if is_mobile:
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
		var look_delta = input.get("mouse_delta", Vector2.ZERO)
		if look_delta is Vector2:
			look_yaw = look_yaw - look_delta.x * mouse_sens
			look_pitch = clamp(look_pitch - look_delta.y * mouse_sens, min_pitch, max_pitch)
	
