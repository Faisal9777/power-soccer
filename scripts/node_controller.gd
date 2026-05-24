class_name NodeController
extends Controller
var input_buffer : InputBuffer
var mouse_sens: float = 0.008
var min_pitch: float = deg_to_rad(-70.0)
var max_pitch: float = deg_to_rad(75.0)

func get_snapshot() -> Dictionary:
	return player.get_snapshot()


func process_input(delta):
	var input = input_buffer.get_input()
	_apply_inputs(input, delta)

func _init(p_player, pid, p_name, p_team, i_buffer : InputBuffer):
	input_buffer = i_buffer
	super._init(p_player, p_name, pid, p_team)

func physics_tick(delta: float) -> void:
	var inputs : Dictionary = input_buffer.get_input()
	_apply_inputs(inputs, delta)

func _apply_inputs(input, delta) -> void:
	var p_input = _get_player_input(input)
	var yaw = p_input["yaw"]
	var pitch = p_input["pitch"]
	player.handle_movement(p_input, delta)
	player.set_look_rotation(yaw, pitch)

func _get_player_input(input) -> Dictionary:
	var look_delta = input.get('mouse_delta', {"x":0, "y":0})
	look_yaw -= look_delta.x * mouse_sens
	look_pitch -= look_delta.y * mouse_sens

	look_pitch = clamp(look_pitch, min_pitch, max_pitch)

	var mov_input = _get_player_movement(input)
	mov_input["yaw"] = look_yaw
	mov_input["pitch"] = look_pitch
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
