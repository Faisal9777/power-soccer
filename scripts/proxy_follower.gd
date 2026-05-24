extends Node3D

var _err: Vector3 = Vector3.ZERO
var _t_prev: Transform3D
var _t_curr: Transform3D
var _have := false
@export var catchup_speed := 18.0
@export var deadzone := 0.02
@export var snap_dist := 2.5

func init(anchor : Node, controller : PlayerController) -> void:
	_setup_anchor(anchor)
	controller.on_reconciled.connect(_calculate_error)
	controller.on_predicted.connect(_update_visual_position)

func snap_to(gb_transform : Transform3D) -> void:
	global_transform = gb_transform
	_err = Vector3.ZERO

func _process(delta: float) -> void:
	_smooth_local_view(delta)
	

func _smooth_local_view(delta: float) -> void:
	if not _have: return

	var frac := Engine.get_physics_interpolation_fraction()
	var base := _t_prev.interpolate_with(_t_curr, frac)

	var a := 1.0 - pow(0.001, delta * catchup_speed)
	_err = _err.lerp(Vector3.ZERO, a)

	base.origin += _err
	global_transform = base

func _calculate_error(new_pos : Transform3D) -> void:

	# Call ONCE per reconcile event, after apply snapshot + replay
	if not _have: return

	var base := new_pos
	var corr := global_position - base.origin
	var d := corr.length()

	if d < deadzone:
		return
	if d > snap_dist:
		_err = Vector3.ZERO
	else:
	
		_err += corr


func _setup_anchor(anchor : Node) -> void:
	_t_prev = anchor.global_transform
	_t_curr = anchor.global_transform
	_have = true

func _update_visual_position(new_pos :Transform3D) -> void:
	# Call from netcode _physics_process
	if not _have: return
	_t_prev = _t_curr
	_t_curr = new_pos
