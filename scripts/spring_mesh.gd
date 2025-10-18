@tool
extends MeshInstance3D

# ---------- Editor controls (with rebuild-on-change) ----------
@export var coil_radius: float = 0.5 : set = _set_coil_radius
@export var wire_radius: float = 0.06 : set = _set_wire_radius
@export var turns: int = 6 : set = _set_turns
@export var height: float = 1.5 : set = _set_height
@export var segs_along: int = 180 : set = _set_segs_along
@export var segs_around: int = 12 : set = _set_segs_around
@export var smooth_shading: bool = true : set = _set_smooth

# Manual “button”: toggle true → rebuild → reset to false (works in Godot 4)
@export var rebuild_now: bool = false : set = _set_rebuild_now

# Optional material look
@export var metallic: float = 0.9 : set = _set_metallic
@export var roughness: float = 0.2 : set = _set_roughness
@export var albedo_color: Color = Color(0.85, 0.85, 0.9) : set = _set_color

# Auto rebuild master switch
@export var auto_rebuild: bool = true : set = _set_auto

func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild()

# ---------- Setters that trigger rebuild in the editor ----------
func _set_auto(v: bool) -> void:
	auto_rebuild = v
	if Engine.is_editor_hint() and auto_rebuild:
		_rebuild()

func _set_rebuild_now(v: bool) -> void:
	rebuild_now = false  # reset the toggle immediately
	if Engine.is_editor_hint():
		_rebuild()

func _set_coil_radius(v: float) -> void:
	coil_radius = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_wire_radius(v: float) -> void:
	wire_radius = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_turns(v: int) -> void:
	turns = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_height(v: float) -> void:
	height = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_segs_along(v: int) -> void:
	segs_along = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_segs_around(v: int) -> void:
	segs_around = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_smooth(v: bool) -> void:
	smooth_shading = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_metallic(v: float) -> void:
	metallic = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_roughness(v: float) -> void:
	roughness = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

func _set_color(v: Color) -> void:
	albedo_color = v
	if Engine.is_editor_hint() and auto_rebuild: _rebuild()

# ---------- Mesh building ----------
func _rebuild() -> void:
	var cr: float = max(0.001, coil_radius)
	var wr: float = clamp(wire_radius, 0.002, cr * 0.9)
	var tns: int = max(1, turns)
	var h: float = max(0.01, height)
	var sa: int = max(tns * 24, segs_along)
	var sr: int = max(3, segs_around)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.metallic = metallic
	mat.roughness = roughness
	mat.albedo_color = albedo_color
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	st.set_material(mat)

	var two_pi: float = TAU
	var n_rings: int = sa + 1

	var centers: Array = []; centers.resize(n_rings)
	var tangents: Array = []; tangents.resize(n_rings)

	var prev_tangent: Vector3 = Vector3.UP
	for i in range(n_rings):
		var t: float = float(i) / float(sa)
		var theta: float = two_pi * float(tns) * t
		var y: float = h * t
		var center: Vector3 = Vector3(cr * cos(theta), y, cr * sin(theta))
		centers[i] = center

		var t_next: float = clamp(t + (1.0 / float(sa)), 0.0, 1.0)
		var theta_n: float = two_pi * float(tns) * t_next
		var y_n: float = h * t_next
		var center_n: Vector3 = Vector3(cr * cos(theta_n), y_n, cr * sin(theta_n))

		var tangent: Vector3 = (center_n - center).normalized()
		if tangent.length() < 0.0001:
			tangent = prev_tangent
		tangents[i] = tangent
		prev_tangent = tangent

	var verts: Array = []; verts.resize(n_rings)
	var norms: Array = []; norms.resize(n_rings)

	for i in range(n_rings):
		var center_i: Vector3 = centers[i]
		var tangent_i: Vector3 = tangents[i]

		var up: Vector3 = Vector3.UP
		if abs(tangent_i.dot(up)) > 0.95:
			up = Vector3.RIGHT

		var binormal: Vector3 = tangent_i.cross(up).normalized()
		var normal_axis: Vector3 = binormal.cross(tangent_i).normalized()

		var ring_verts: PackedVector3Array = PackedVector3Array()
		ring_verts.resize(sr)
		var ring_norms: PackedVector3Array = PackedVector3Array()
		ring_norms.resize(sr)

		for j in range(sr):
			var phi: float = two_pi * float(j) / float(sr)
			var offset: Vector3 = normal_axis * cos(phi) * wr + binormal * sin(phi) * wr
			ring_verts[j] = center_i + offset
			ring_norms[j] = offset.normalized()

		verts[i] = ring_verts
		norms[i] = ring_norms

	for i in range(sa):
		var ring_a: PackedVector3Array = verts[i]
		var ring_b: PackedVector3Array = verts[i + 1]
		var norm_a: PackedVector3Array = norms[i]
		var norm_b: PackedVector3Array = norms[i + 1]

		for j in range(sr):
			var j_next: int = (j + 1) % sr

			var v0: Vector3 = ring_a[j]
			var v1: Vector3 = ring_b[j]
			var v2: Vector3 = ring_b[j_next]
			var v3: Vector3 = ring_a[j_next]

			var n0: Vector3 = norm_a[j]
			var n1: Vector3 = norm_b[j]
			var n2: Vector3 = norm_b[j_next]
			var n3: Vector3 = norm_a[j_next]

			if smooth_shading:
				st.set_normal(n0); st.add_vertex(v0)
				st.set_normal(n1); st.add_vertex(v1)
				st.set_normal(n2); st.add_vertex(v2)

				st.set_normal(n0); st.add_vertex(v0)
				st.set_normal(n2); st.add_vertex(v2)
				st.set_normal(n3); st.add_vertex(v3)
			else:
				var fn1: Vector3 = Plane(v0, v1, v2).normal
				var fn2: Vector3 = Plane(v0, v2, v3).normal
				st.set_normal(fn1); st.add_vertex(v0)
				st.set_normal(fn1); st.add_vertex(v1)
				st.set_normal(fn1); st.add_vertex(v2)
				st.set_normal(fn2); st.add_vertex(v0)
				st.set_normal(fn2); st.add_vertex(v2)
				st.set_normal(fn2); st.add_vertex(v3)

	mesh = st.commit()
