extends Area3D

# --- visual animation wiring (set these in the Inspector) ---
@export var spring_mesh_path: NodePath       # MeshInstance3D (the coil)
@export var top_plate_root_path: NodePath    # Node3D parent of plate mesh + body

@export var compress_scale_y: float = 0.6
@export var plate_thickness: float = 0.08    # visual plate height (used to "touch" the spring)
@export var compress_time: float = 0.08
@export var release_time: float = 0.18
@export var overshoot_y: float = 1.08        # 1.0 = none

# === Tuning ===
@export var launch_speed: float = 16.0
@export var keep_horizontal: float = 1.0
@export var min_vertical_boost: float = 10.0
@export var cooldown: float = 0.2
@export var only_player: bool = true

var _cooling := false

# Cached at runtime
var _rest_mesh_scale: Vector3

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	# Cache rest scale so our tweens always compute from the same base
	var mesh := get_node_or_null(spring_mesh_path) as MeshInstance3D
	if mesh:
		_rest_mesh_scale = mesh.scale
		# One initial snap so the plate starts correctly placed
		_snap_plate_to_spring_top()

func _on_body_entered(body: Node) -> void:
	if _cooling:
		return
	if only_player and  not (body is CharacterBody3D):
		return

	var dir := _get_launch_dir()
	_launch_body(body, dir)
	_animate_bounce()
	_start_cooldown(cooldown)

func _get_launch_dir() -> Vector3:
	var marker := get_node_or_null("LaunchDir") as Node3D
	if marker:
		return marker.global_transform.basis.y.normalized()
	return global_transform.basis.y.normalized()

func _launch_body(body: Node, dir: Vector3) -> void:
	if body is CharacterBody3D:
		var cb := body as CharacterBody3D
		var v := cb.velocity
		var v_parallel := dir * v.dot(dir)
		var v_perp := v - v_parallel
		var curr_along := v.dot(dir)
		var new_parallel_speed: float = max(float(curr_along), float(min_vertical_boost)) + float(launch_speed)
		cb.velocity = v_perp * keep_horizontal + dir * new_parallel_speed
		return

	if body is RigidBody3D:
		var rb := body as RigidBody3D
		var mass : float = max(rb.mass, 0.001)
		rb.apply_impulse(dir * launch_speed * mass)
		return

	if body is Node3D:
		var n3 := body as Node3D
		var t := n3.global_transform
		t.origin += dir * 0.5
		n3.global_transform = t

func _start_cooldown(t: float) -> void:
	_cooling = true
	monitoring = false
	await get_tree().create_timer(t).timeout
	monitoring = true
	_cooling = false


# ---------------------------
# Plate placement helpers
# ---------------------------

func _spring_top_y_in_parent(spring: MeshInstance3D, parent: Node3D) -> float:
	# AABB is in the spring's LOCAL space; convert its top to parent space
	var aabb := spring.get_aabb()
	var top_local := Vector3(0.0, aabb.position.y + aabb.size.y, 0.0)
	var top_global := spring.to_global(top_local)
	var top_parent := parent.to_local(top_global)
	return top_parent.y

func _snap_plate_to_spring_top() -> void:
	var spring := get_node_or_null(spring_mesh_path) as MeshInstance3D
	var plate_root := get_node_or_null(top_plate_root_path) as Node3D
	if not spring or not plate_root:
		return
	var parent := plate_root.get_parent() as Node3D
	var top_y := _spring_top_y_in_parent(spring, parent)
	# Place the **bottom** of the plate touching the spring (minus half thickness)
	plate_root.position.y = top_y - 1.45#- (plate_thickness * 0.5)

# Scale helper that preserves "volume": y -> scale_y, x/z -> 1/sqrt(scale_y)
func _scale_vec_for_y(scale_y: float) -> Vector3:
	var y : float = max(scale_y, 0.0001)
	var inv := 1.0 / sqrt(y)
	return Vector3(inv, y, inv)

# Drive both the spring scale and the plate snap together (used by tween_method)
func _set_scale_and_snap(scale_y: float) -> void:
	var spring := get_node_or_null(spring_mesh_path) as MeshInstance3D
	if not spring:
		return
	var s := _scale_vec_for_y(scale_y)
	spring.scale = Vector3(
		_rest_mesh_scale.x * s.x,
		_rest_mesh_scale.y * s.y,
		_rest_mesh_scale.z * s.z
	)
	_snap_plate_to_spring_top()


# ---------------------------
# Animation (compress → overshoot → settle)
# ---------------------------

func _animate_bounce() -> void:
	var spring := get_node_or_null(spring_mesh_path) as MeshInstance3D
	var plate_root := get_node_or_null(top_plate_root_path) as Node3D
	if not spring or not plate_root:
		return

	var t := create_tween()

	# Compress
	t.tween_method(Callable(self, "_set_scale_and_snap"), 1.0, compress_scale_y, compress_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Release with overshoot
	t.tween_method(Callable(self, "_set_scale_and_snap"), compress_scale_y, overshoot_y, release_time * 0.6)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Settle back to rest (1.0)
	t.tween_method(Callable(self, "_set_scale_and_snap"), overshoot_y, 1.0, release_time * 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Final snap to be extra safe
	t.tween_callback(Callable(self, "_snap_plate_to_spring_top"))
