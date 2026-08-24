# proxy_follower.gd — full file
extends Node3D

var _err: Vector3 = Vector3.ZERO
var _t_prev: Transform3D
var _t_curr: Transform3D
var _have := false
@export var catchup_speed := 18.0        # decay rate for small corrections
@export var deadzone := 0.02
@export var max_correction_speed := 10.0 # m/s cap so big corrections glide, not teleport
@export var snap_dist := 6.0             # true teleports only (respawn / goal reset)

func init(anchor : Node, controller : PlayerController) -> void:
	_setup_anchor(anchor)
	controller.on_reconciled.connect(_calculate_error)
	controller.on_predicted.connect(_update_visual_position)

func snap_to(gb_transform : Transform3D) -> void:
	global_transform = gb_transform
	_t_prev = gb_transform
	_t_curr = gb_transform
	_err = Vector3.ZERO

func _process(delta: float) -> void:
	_smooth_local_view(delta)

func _smooth_local_view(delta: float) -> void:
	if not _have: return

	var frac := Engine.get_physics_interpolation_fraction()
	var base := _t_prev.interpolate_with(_t_curr, frac)

	var a := 1.0 - pow(0.001, delta * catchup_speed)
	var target := _err.lerp(Vector3.ZERO, a)
	var shrink := _err - target
	var max_shrink := max_correction_speed * delta
	if shrink.length() > max_shrink:
		shrink = shrink.normalized() * max_shrink
	_err -= shrink

	base.origin += _err
	global_transform = base

func _calculate_error(error_delta : Vector3, new_transform : Transform3D) -> void:
	if not _have: return

	_t_prev = _t_curr
	_t_curr = new_transform

	var d := error_delta.length()
	if d < deadzone:
		return
	if d > snap_dist:
		_err = Vector3.ZERO
	else:
		_err += error_delta

func _setup_anchor(anchor : Node) -> void:
	_t_prev = anchor.global_transform
	_t_curr = anchor.global_transform
	_have = true

func _update_visual_position(new_pos : Transform3D) -> void:
	if not _have: return
	_t_prev = _t_curr
	_t_curr = new_pos
