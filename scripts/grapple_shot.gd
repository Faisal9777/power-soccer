extends Node3D

@export var speed: float = 80.0          # how fast the rope extends (m/s)
@export var rope_thickness: float = 0.03 # visual thickness
@export var linger_time: float = 0.25    # keep it visible briefly when fully extended

@onready var rope: MeshInstance3D = $Rope
@onready var hook: Node3D = $Hook   # Hook is now a Node3D (root)


var _hit_once := false

var _hook_mi: MeshInstance3D         # the actual mesh holder under Hook

var _start: Vector3
var _end: Vector3
var _target_len: float = 0.0
var _len: float = 0.0
var _linger_left: float = 0.0
var _rope_mesh: BoxMesh

func _ready() -> void:
	# Find an existing MeshInstance3D under Hook, or create one
	_hook_mi = hook.get_node_or_null("HookMesh") as MeshInstance3D
	if _hook_mi == null:
		_hook_mi = MeshInstance3D.new()
		_hook_mi.name = "HookMesh"
		hook.add_child(_hook_mi)

func start(from: Vector3, to: Vector3) -> void:
	set_as_top_level(true) # treat positions as world-space
	_start = from
	_end = to

	global_position = _start
	look_at(_end, Vector3.UP)

	_target_len = maxf(_start.distance_to(_end), 0.001)
	_len = 0.0
	_linger_left = linger_time

	# Rope mesh (unique per instance)
	_rope_mesh = BoxMesh.new()
	_rope_mesh.size = Vector3(rope_thickness, rope_thickness, 0.001)
	rope.mesh = _rope_mesh

	# Simple hook mesh (optional; replace later)
	if _hook_mi.mesh == null:
		var s := SphereMesh.new()
		s.radius = 0.06
		s.height = 0.12
		_hook_mi.mesh = s

	_update_visuals()

	_hit_once = false

	# ✅ Open while flying
	if hook.has_method("anim_open"):
		hook.call("anim_open")
	elif "open_amount" in hook:
		hook.set("open_amount", 1.0)

func _process(delta: float) -> void:
	# Extend (flying)
	if _len < _target_len:
		_len = minf(_target_len, _len + speed * delta)
		_update_visuals()

		# ✅ Just reached the hit point this frame → CLOSE
		if (not _hit_once) and is_equal_approx(_len, _target_len):
			_hit_once = true
			if hook.has_method("anim_close"):
				hook.call("anim_close")
			elif "open_amount" in hook:
				hook.set("open_amount", 0.0)

		return

	# Linger then disappear
	_linger_left -= delta
	if _linger_left <= 0.0:
		queue_free()

func _update_visuals() -> void:
	var zlen := maxf(_len, 0.001)

	_rope_mesh.size = Vector3(rope_thickness, rope_thickness, zlen)
	# BoxMesh extends along +Z, but our forward is -Z (look_at points -Z).
	rope.position = Vector3(0, 0, -zlen * 0.5)

	# Hook root sits at the tip (the mesh is a child of this root)
	hook.position = Vector3(0, 0, -zlen)
func get_muzzle_from_camera(cam: Camera3D) -> Vector3:
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var forward := -cam.global_transform.basis.z  # camera forward is -Z

	return cam.global_position \
		+ right * 0.25 \
		+ up * -0.18 \
		+ forward * 0.60
