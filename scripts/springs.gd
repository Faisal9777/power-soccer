extends Node3D

@export var use_triplanar := true

func _ready() -> void:
	_apply_to_all_springpads()

func _apply_to_all_springpads() -> void:
	for c in get_children():
		if c is Node3D and String(c.name).begins_with("SpringPad"):
			_apply_to_one_pad(c)

func _apply_to_one_pad(pad: Node3D) -> void:
	var spring_mesh := pad.get_node_or_null("SpringMesh") as MeshInstance3D
	var top_plate := pad.get_node_or_null("TopPlateRoot/TopPlate") as MeshInstance3D

	if spring_mesh:
		spring_mesh.material_override = _make_spring_metal()

	if top_plate:
		top_plate.material_override = _make_top_plate_red()

func _make_spring_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()

	# ✅ Chrome / polished steel look
	m.albedo_color = Color.html("#C0C0C0")
	m.metallic = 1.0
	m.roughness = 0.06                             # lower = shinier
	m.specular = 1.0
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.03

	# If your mesh has bad/no UVs
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(3.0, 3.0, 3.0)

	return m

func _make_top_plate_red() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.80, 0.08, 0.08, 1.0)
	m.metallic = 0.25
	m.roughness = 0.28
	m.specular = 1.0
	m.clearcoat = 0.9
	m.clearcoat_roughness = 0.05

	if use_triplanar:
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(1.5, 1.5, 1.5)

	return m
