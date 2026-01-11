extends Node3D
class_name GrappleShot

signal latched(point: Vector3)

@export var speed: float = 80.0
@export var rope_thickness: float = 0.03
@export var linger_time: float = 0.25
@export var stay_after_latch: bool = true

@onready var rope: MeshInstance3D = $Rope
@onready var hook: Node3D = $Hook

var _hit_once := false
var _latched := false

var _hook_mi: MeshInstance3D
var _rope_mesh: BoxMesh

var _start: Vector3                 # moving rope anchor (muzzle)
var _flight_from: Vector3           # fixed origin for the hook flight
var _end: Vector3

var _dir: Vector3 = Vector3.ZERO
var _target_len: float = 0.0
var _len: float = 0.0
var _linger_left: float = 0.0

func _ready() -> void:
	_hook_mi = hook.get_node_or_null("HookMesh") as MeshInstance3D
	if _hook_mi == null:
		_hook_mi = MeshInstance3D.new()
		_hook_mi.name = "HookMesh"
		hook.add_child(_hook_mi)

func is_latched() -> bool:
	return _latched

func get_latch_point() -> Vector3:
	return _end

# Rope start (muzzle) can move every frame
func set_start_world(from: Vector3) -> void:
	_start = from

func start(from: Vector3, to: Vector3) -> void:
	set_as_top_level(true)

	_start = from
	_flight_from = from
	_end = to

	_latched = false
	_hit_once = false

	var delta := _end - _flight_from
	_target_len = maxf(delta.length(), 0.001)
	_dir = delta / _target_len

	_len = 0.0
	_linger_left = linger_time

	_rope_mesh = BoxMesh.new()
	_rope_mesh.size = Vector3(rope_thickness, rope_thickness, 0.001)
	rope.mesh = _rope_mesh

	if _hook_mi.mesh == null:
		var s := SphereMesh.new()
		s.radius = 0.06
		s.height = 0.12
		_hook_mi.mesh = s

	_update_visuals()

	# Open while flying
	if hook.has_method("anim_open"):
		hook.call("anim_open")
	elif "open_amount" in hook:
		hook.set("open_amount", 1.0)

func _process(delta: float) -> void:
	# Flying
	if !_latched:
		_len = minf(_target_len, _len + speed * delta)

		# latch when we truly reach the end (based on flight origin)
		if (not _hit_once) and _len >= _target_len - 1e-6:
			_hit_once = true
			_latched = true

			# Close on hit
			if hook.has_method("anim_close"):
				hook.call("anim_close")
			elif "open_amount" in hook:
				hook.set("open_amount", 0.0)

			emit_signal("latched", _end)

			if not stay_after_latch:
				_linger_left = linger_time

	_update_visuals()

	# After hit: optional disappear
	if _latched and not stay_after_latch:
		_linger_left -= delta
		if _linger_left <= 0.0:
			queue_free()

func _update_visuals() -> void:
	# hook position:
	var hook_world: Vector3
	if _latched:
		hook_world = _end
	else:
		hook_world = _flight_from + _dir * _len

	# rope start is CURRENT muzzle
	var rope_start := _start
	var rope_vec := hook_world - rope_start
	var zlen := maxf(rope_vec.length(), 0.001)

	global_position = rope_start
	if zlen > 0.001:
		look_at(hook_world, Vector3.UP)

	_rope_mesh.size = Vector3(rope_thickness, rope_thickness, zlen)
	rope.position = Vector3(0, 0, -zlen * 0.5)
	hook.position = Vector3(0, 0, -zlen)
func set_end_world(to: Vector3) -> void:
	_end = to
	_update_visuals()
