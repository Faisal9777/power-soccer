extends Node3D

@export var claw_count: int = 3

@export var hub_radius: float = 0.06
@export var hub_height: float = 0.10

@export var arm_len: float = 0.14
@export var arm_radius: float = 0.02

# Base "closed-ish" defaults (still used if you want)
@export var claw_curve_radius: float = 0.10
@export var claw_curve_angle_deg: float = 120.0
@export var claw_segments: int = 10
@export var claw_radius: float = 0.015
@export var claw_drop_y: float = 0.01
@export var tip_len: float = 0.045

# =========================
# ✅ OPEN / CLOSE CONTROLS
# =========================
@export_range(0.0, 1.0, 0.01) var open_amount: float:
	get: return _open_amount
	set(value):
		_open_amount = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_rebuild()

var _open_amount: float = 1.0

# Tune these until it matches your bat-claw picture
@export var curve_angle_closed_deg: float = 155.0   # more curl = more closed
@export var curve_angle_open_deg: float = 70.0      # less curl = more open

@export var open_time: float = 0.07
@export var close_time: float = 0.08

var _anim: Tween

@export var curve_radius_closed: float = 0.085      # tighter = more closed
@export var curve_radius_open: float = 0.135        # wider = more open

@export var tip_len_closed: float = 0.040
@export var tip_len_open: float = 0.060

@export var material_override: Material

func _ready() -> void:
	_ensure_steel_material()
	_rebuild()

func _ensure_steel_material() -> void:
	if material_override != null:
		return

	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.13, 1.0)  # dark steel
	m.metallic = 1.0
	m.roughness = 0.28
	m.specular = 0.8
	m.clearcoat = 0.15
	m.clearcoat_roughness = 0.12
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material_override = m

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.free()

	_add_hub()

	# ✅ Fixed 3-claw bat layout planes
	if claw_count == 3:
		var rolls_deg := [45.0, 135.0, 270.0] # top-right, top-left, bottom
		for d in rolls_deg:
			_add_claw(deg_to_rad(d))
	else:
		for i in range(claw_count):
			_add_claw(float(i) * TAU / float(claw_count))

func _apply_mat(mi: MeshInstance3D) -> void:
	if material_override:
		mi.material_override = material_override

func _add_mesh(mesh: Mesh, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	add_child(mi)
	_apply_mat(mi)
	return mi

func _add_hub() -> void:
	var hub := CylinderMesh.new()
	hub.top_radius = hub_radius
	hub.bottom_radius = hub_radius
	hub.height = hub_height
	hub.radial_segments = 24
	_add_mesh(hub, Transform3D(Basis.IDENTITY, Vector3.ZERO))

func _add_claw(roll: float) -> void:
	var root := Node3D.new()
	add_child(root)

	# 1) Point claw forward (arm +X -> world -Z)
	root.rotation.y = deg_to_rad(90.0)

	# 2) Put each claw into its own plane (your MS paint picture)
	# ✅ roll around local +X (forward axis)
	root.rotation.x = roll

	# ---- arm ----
	var arm := CylinderMesh.new()
	arm.top_radius = arm_radius
	arm.bottom_radius = arm_radius
	arm.height = arm_len
	arm.radial_segments = 18

	var arm_basis := Basis.IDENTITY.rotated(Vector3.FORWARD, deg_to_rad(-90.0))
	var arm_pos := Vector3(hub_radius + arm_len * 0.5, 0, 0)

	var arm_mi := MeshInstance3D.new()
	arm_mi.mesh = arm
	arm_mi.transform = Transform3D(arm_basis, arm_pos)
	root.add_child(arm_mi)
	_apply_mat(arm_mi)

	# ---- blade (open/close driven) ----
	var eff_angle_deg := lerpf(curve_angle_closed_deg, curve_angle_open_deg, _open_amount)
	var eff_radius := lerpf(curve_radius_closed, curve_radius_open, _open_amount)
	var eff_tip := lerpf(tip_len_closed, tip_len_open, _open_amount)

	var arc_center := Vector3(hub_radius + arm_len - eff_radius, 0, 0)
	var a0 := 0.0
	var a1 := -deg_to_rad(eff_angle_deg)

	var blade_mi := MeshInstance3D.new()
	blade_mi.mesh = _make_blade_claw_mesh(arc_center, eff_radius, a0, a1, eff_tip)
	root.add_child(blade_mi)
	_apply_mat(blade_mi)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func _make_blade_claw_mesh(
	arc_center: Vector3,
	curve_radius: float,
	a0: float,
	a1: float,
	tip_extra: float
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_thick = max(0.0015, claw_radius * 0.45)

	var half_w_outer_base = max(0.03, claw_radius * 7.5)
	var half_w_inner_base = half_w_outer_base * 0.45

	var n = max(3, claw_segments)

	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []

	for i in range(n + 1):
		var t := float(i) / float(n)
		var ang = lerp(a0, a1, t)

		# ✅ Arc in XZ plane (so each claw plane includes "forward")
		var p := arc_center + Vector3(
			cos(ang) * curve_radius,
			0.0,
			sin(ang) * curve_radius
		)

		# slight scoop
		p.y = -claw_drop_y * t

		var radial := Vector3(cos(ang), 0.0, sin(ang)).normalized()

		var taper_outer = lerp(1.0, 0.08, pow(t, 1.25))
		var taper_inner = lerp(1.0, 0.22, pow(t, 1.10))

		var half_w_outer = half_w_outer_base * taper_outer
		var half_w_inner = half_w_inner_base * taper_inner

		outer.append(p + radial * half_w_outer)
		inner.append(p - radial * half_w_inner)

	# tip
	var mid_last := (outer[n] + inner[n]) * 0.5
	var mid_prev := (outer[n - 1] + inner[n - 1]) * 0.5
	var fwd := (mid_last - mid_prev).normalized()
	var tip_p := mid_last + fwd * tip_extra
	outer.append(tip_p)
	inner.append(tip_p)

	# thickness along Y
	var up := Vector3(0, half_thick, 0)
	var dn := Vector3(0, -half_thick, 0)

	var count := outer.size()
	for i in range(count - 1):
		var o0 := outer[i]
		var i0 := inner[i]
		var o1 := outer[i + 1]
		var i1 := inner[i + 1]

		# TOP
		_tri(st, o0 + up, i0 + up, o1 + up)
		if i1 != o1:
			_tri(st, o1 + up, i0 + up, i1 + up)

		# BOTTOM (reverse winding)
		_tri(st, o0 + dn, o1 + dn, i0 + dn)
		if i1 != o1:
			_tri(st, o1 + dn, i1 + dn, i0 + dn)

		# OUTER side
		_tri(st, o0 + up, o1 + up, o1 + dn)
		_tri(st, o0 + up, o1 + dn, o0 + dn)

		# INNER side
		if i1 != o1:
			_tri(st, i0 + up, i0 + dn, i1 + dn)
			_tri(st, i0 + up, i1 + dn, i1 + up)

	# base cap
	_tri(st, outer[0] + up, outer[0] + dn, inner[0] + dn)
	_tri(st, outer[0] + up, inner[0] + dn, inner[0] + up)

	st.generate_normals()
	return st.commit()
func anim_open() -> void:
	if _anim and _anim.is_running():
		_anim.kill()
	open_amount = 0.0
	_anim = create_tween()
	_anim.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_anim.tween_property(self, "open_amount", 1.0, open_time)

func anim_close() -> void:
	if _anim and _anim.is_running():
		_anim.kill()
	_anim = create_tween()
	_anim.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_anim.tween_property(self, "open_amount", 0.0, close_time)
