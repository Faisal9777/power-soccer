extends NodeController
class_name LocalController

var last_processed_seq  := -1
var can_simulate := false
var cam : Node
var joystick: Node
var is_mobile: bool = OS.has_feature("mobile")
var applied_cmd_id := -1

func set_position(gb_transform : Transform3D) -> void:
	super.set_position(gb_transform)
	cam.snap_to(gb_transform)

func get_snapshot() -> Dictionary:
	var snap = player.get_snapshot()
	return snap

func freeze(toggle) -> void:
	super.freeze(toggle)
	cam.freeze_rotation(toggle)

func process_input(delta):
	if is_frozen:
		return
	var input = input_buffer.get_input()
	applied_cmd_id += 1
	_apply_inputs(input, delta)

func _init(p_player, pid, p_name, team, c_cam, ball, joystick, i_buffer : InputBuffer):
	cam = c_cam
	cam.set_rotation_source(self)
	super._init(p_player, pid, p_name, team, ball, i_buffer)

func _get_player_movement(input) -> Dictionary:
	var mvx : float = 0.0
	var mvz : float = 0.0
	var mov_input = {}
	if is_mobile and is_instance_valid(joystick):
		var v2: Vector2 = joystick.vector
		if v2.length() > 0.01:
			mvx = v2.x
			mvz = v2.y	
		mov_input = {"mvx" : mvx, "mvz":mvz, "sprint" : input.get("sprint") }

	else:
		mov_input = super._get_player_movement(input)
	return mov_input
