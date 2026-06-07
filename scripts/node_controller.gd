class_name NodeController
extends Controller
var input_buffer : InputBuffer
var w_ball : Node
var mouse_sens: float = 0.008
var min_pitch: float = deg_to_rad(-70.0)
var max_pitch: float = deg_to_rad(75.0)

func get_snapshot() -> Dictionary:
	var player_data = player.get_snapshot()
	player_data["is_frozen"] = is_frozen
	player_data["yaw"] = look_yaw
	player_data["pitch"] = look_pitch
	return player_data


func process_input(delta):
	var input = input_buffer.get_input()
	_apply_inputs(input, delta)


func _init(p_player, pid, p_name, p_team, ball, i_buffer : InputBuffer):
	input_buffer = i_buffer
	w_ball = ball
	super._init(p_player, p_name, pid, p_team)

func physics_tick(delta: float) -> void:
	process_input(delta)


func _apply_inputs(input, delta) -> void:
	_generate_facing_direction_with_input(input)
	var p_input = _get_player_input(input)
	if not is_frozen:
		player.handle_movement(p_input, delta)
	player.set_look_rotation(look_yaw, look_pitch)

func _get_player_input(input) -> Dictionary:
	var mov_input = _get_player_movement(input)
	return mov_input


func _get_player_movement(input) -> Dictionary:

	if typeof(input) != TYPE_DICTIONARY or input == null:
		return {
			"mvx": 0.0,
			"mvz": 0.0,
			"sprint": false
		}

	var mvx: float = (
		float(input.get("move_right", 0.0)) -
		float(input.get("move_left", 0.0))
	)

	var mvz: float = (
		float(input.get("move_forward", 0.0)) -
		float(input.get("move_back", 0.0))
	)

	return {
		"mvx": mvx,
		"mvz": mvz,
		"sprint": bool(input.get("sprint", false))
	}

func _generate_facing_direction_with_input(input) -> void:
	look_yaw = input.get("yaw", 0)
	look_pitch = input.get("pitch", 0)
