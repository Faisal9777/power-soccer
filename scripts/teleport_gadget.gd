extends RigidBody3D
class_name TeleportGadget

@export var lifetime: float = 10.0
@export var stick_on_first_contact := true
@export var stick_offset := 0.06

var stick_parent_path: NodePath = NodePath("")
var stick_local_xf: Transform3D = Transform3D.IDENTITY

# ---------------- VISUALS (match the screenshot) ----------------
@export var rebuild_blades := true

@export var blade_count := 3
@export var blade_len := 3.10
@export var blade_width := 0.65
@export var blade_thickness := 0.06
@export var blade_root_radius := 0.42          # starts outside the hub ring
@export var blade_len_segs := 28
@export var blade_width_segs := 12

@export var blade_cup := 0.28
@export var blade_sweep_deg := 34.0            # makes the blades “scythe” like the pic
@export var blade_twist_deg := 65.0            # twists along the blade
@export var blade_tip_scale := 0.35

@export var hub_ring_radius := 0.36            # dark ring around the center
@export var hub_ring_pipe := 0.07
@export var hub_disc_radius := 0.18
@export var hub_disc_height := 0.03

@export var hub_glow_radius := 0.10            # bright center circle
@export var hub_glow_height := 0.02
@export var hub_glow_energy := 7.0

@export var spoke_len := 0.26                  # 3 spokes from center to ring (like the pic)
@export var spoke_width := 0.055
@export var spoke_thickness := 0.02

@export var spin_speed_rad := 18.0 # radians/sec (increase for faster spin)

# ---------------------------------------------------------------

# Use Godot collision flags in Inspector easily
@export_flags_3d_physics var gadget_layer_mask := 1
@export_flags_3d_physics var collide_mask := ((1<<8)-1)

# Only allow swap target if collider is on layer 2 or 3
const SWAP_LAYERS_MASK := (1 << 1) | (1 << 2) # layer2 + layer3
var swap_target_path: NodePath = NodePath("")   # remembered target (server side)

var stuck_normal_world: Vector3 = Vector3.UP
var saved_linear_velocity: Vector3 = Vector3.ZERO
var _stuck := false

@onready var blades: MeshInstance3D = $MeshInstance3D
var _rotor: Node3D


func _process(delta: float) -> void:
	# spin the whole rotor (blades + ring + hub + spokes)
	if _rotor:
		_rotor.rotate_object_local(Vector3.UP, spin_speed_rad * delta)

	# follow the object we stuck to
	if _stuck and String(stick_parent_path) != "":
		var parent3d := get_tree().root.get_node_or_null(stick_parent_path) as Node3D
		if parent3d and is_instance_valid(parent3d):
			global_transform = parent3d.global_transform * stick_local_xf
		else:
			stick_parent_path = NodePath("")


func _ready() -> void:
		# Only the server simulates physics; clients just display it
	if !is_multiplayer_authority():
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_setup_rotor_root()
	_ensure_propeller_geometry()
	_apply_blade_material()
	_make_hub_parts()

	gravity_scale = 0.0
	can_sleep = false

	collision_layer = gadget_layer_mask
	collision_mask = collide_mask

	contact_monitor = true
	max_contacts_reported = 8

	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0

	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true

	continuous_cd = true


func _setup_rotor_root() -> void:
	_rotor = get_node_or_null("Rotor") as Node3D
	if _rotor == null:
		_rotor = Node3D.new()
		_rotor.name = "Rotor"
		add_child(_rotor)
		_rotor.transform = Transform3D.IDENTITY

	# move MeshInstance3D under Rotor so it spins with hub/ring/spokes
	if blades and blades.get_parent() != _rotor:
		var gxf := blades.global_transform
		var p := blades.get_parent()
		p.remove_child(blades)
		_rotor.add_child(blades)
		blades.global_transform = gxf


func _ensure_propeller_geometry() -> void:
	if blades == null:
		return
	if !rebuild_blades and blades.mesh != null:
		return

	var one_blade := _build_swept_blade_mesh(
		blade_root_radius,
		blade_len,
		blade_width,
		blade_thickness,
		blade_len_segs,
		blade_width_segs,
		blade_cup,
		blade_sweep_deg,
		blade_twist_deg,
		blade_tip_scale
	)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(blade_count):
		var ang := TAU * float(i) / float(blade_count)
		var xform := Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO)
		st.append_from(one_blade, 0, xform)

	st.generate_normals()
	blades.mesh = st.commit()


func _grid_id(i: int, j: int, wsegs: int) -> int:
	return i * (wsegs + 1) + j


func _build_swept_blade_mesh(
		root_r: float,
		len: float,
		width: float,
		thick: float,
		len_segs: int,
		width_segs: int,
		cup: float,
		sweep_deg: float,
		twist_deg: float,
		tip_scale: float
	) -> ArrayMesh:

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var L = max(1, len_segs)
	var W = max(1, width_segs)

	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	top.resize((L + 1) * (W + 1))
	bot.resize((L + 1) * (W + 1))

	var sweep := deg_to_rad(sweep_deg)
	var twist := deg_to_rad(twist_deg)

	for i in range(L + 1):
		var u := float(i) / float(L)               # 0..1 along blade
		var theta := sweep * u                     # sweep in the disc plane
		var r := root_r + len * u

		var radial := Vector3(cos(theta), 0.0, sin(theta)).normalized()

		# twist the blade along its radial axis (gives the “propeller” feel)
		var up_dir := Vector3.UP
		if abs(twist_deg) > 0.001:
			up_dir = up_dir.rotated(radial, twist * u)

		# width direction (tangent) derived from the twisted frame
		var width_dir := up_dir.cross(radial).normalized()

		var center := radial * r

		var w = width * lerp(1.0, tip_scale, u)
		var cup_t = cup * lerp(0.6, 1.4, u)
		var cup_gain := pow(sin(u * PI), 1.2)

		for j in range(W + 1):
			var v := (float(j) / float(W)) * 2.0 - 1.0 # -1..1
			var p = center + width_dir * (v * w * 0.5)

			var w01 = abs(v)
			var cup_amt = cup_t * (1.0 - w01 * w01) * cup_gain
			p += up_dir * cup_amt

			top[_grid_id(i, j, W)] = p + up_dir * (thick * 0.5)
			bot[_grid_id(i, j, W)] = p - up_dir * (thick * 0.5)

	# top + bottom surfaces
	for i in range(L):
		for j in range(W):
			var a := top[_grid_id(i, j, W)]
			var b := top[_grid_id(i + 1, j, W)]
			var c := top[_grid_id(i + 1, j + 1, W)]
			var d := top[_grid_id(i, j + 1, W)]

			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

			var a2 := bot[_grid_id(i, j, W)]
			var b2 := bot[_grid_id(i + 1, j, W)]
			var c2 := bot[_grid_id(i + 1, j + 1, W)]
			var d2 := bot[_grid_id(i, j + 1, W)]

			# reversed winding for the bottom
			st.add_vertex(a2); st.add_vertex(c2); st.add_vertex(b2)
			st.add_vertex(a2); st.add_vertex(d2); st.add_vertex(c2)

	# side walls: left edge (j=0)
	for i in range(L):
		var t0 := top[_grid_id(i, 0, W)]
		var t1 := top[_grid_id(i + 1, 0, W)]
		var b0 := bot[_grid_id(i, 0, W)]
		var b1 := bot[_grid_id(i + 1, 0, W)]
		st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b1)
		st.add_vertex(t0); st.add_vertex(b1); st.add_vertex(b0)

	# side walls: right edge (j=W)
	for i in range(L):
		var t0 := top[_grid_id(i, W, W)]
		var t1 := top[_grid_id(i + 1, W, W)]
		var b0 := bot[_grid_id(i, W, W)]
		var b1 := bot[_grid_id(i + 1, W, W)]
		st.add_vertex(t0); st.add_vertex(b1); st.add_vertex(t1)
		st.add_vertex(t0); st.add_vertex(b0); st.add_vertex(b1)

	# cap tip (i=L)
	for j in range(W):
		var t0 := top[_grid_id(L, j, W)]
		var t1 := top[_grid_id(L, j + 1, W)]
		var b0 := bot[_grid_id(L, j, W)]
		var b1 := bot[_grid_id(L, j + 1, W)]
		st.add_vertex(t0); st.add_vertex(b1); st.add_vertex(t1)
		st.add_vertex(t0); st.add_vertex(b0); st.add_vertex(b1)

	# cap root (i=0) (usually hidden by ring, but prevents see-through)
	for j in range(W):
		var t0 := top[_grid_id(0, j, W)]
		var t1 := top[_grid_id(0, j + 1, W)]
		var b0 := bot[_grid_id(0, j, W)]
		var b1 := bot[_grid_id(0, j + 1, W)]
		st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b1)
		st.add_vertex(t0); st.add_vertex(b1); st.add_vertex(b0)

	st.generate_normals()
	return st.commit()


func _apply_blade_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06, 1.0)
	mat.metallic = 1.0
	mat.roughness = 0.18
	mat.specular = 0.9
	mat.clearcoat = 0.8
	mat.clearcoat_roughness = 0.05
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	blades.material_override = mat


func _make_hub_parts() -> void:
	if _rotor == null:
		return

	# dark hub disc
	if _rotor.get_node_or_null("HubDisc") == null:
		var disc := MeshInstance3D.new()
		disc.name = "HubDisc"
		var cyl := CylinderMesh.new()
		cyl.top_radius = hub_disc_radius
		cyl.bottom_radius = hub_disc_radius
		cyl.height = hub_disc_height
		cyl.radial_segments = 36
		disc.mesh = cyl

		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.03, 1.03, 1.0, 1.0)
		m.metallic = 1.0
		m.roughness = 0.22
		m.specular = 0.9
		disc.material_override = m
		_rotor.add_child(disc)


	# 3 spokes (little arms) like in the screenshot
	for i in range(blade_count):
		var n := "Spoke_%d" % i
		if _rotor.get_node_or_null(n) != null:
			continue

		var spoke := MeshInstance3D.new()
		spoke.name = n
		var bm := BoxMesh.new()
		bm.size = Vector3(spoke_len, spoke_thickness, spoke_width)
		spoke.mesh = bm

		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.04, 0.04, 0.045, 1.0)
		sm.metallic = 1.0
		sm.roughness = 0.22
		sm.specular = 0.9
		spoke.material_override = sm

		var ang := TAU * float(i) / float(blade_count)
		spoke.rotation.y = ang
		spoke.position = Basis(Vector3.UP, ang) * Vector3(spoke_len * 0.5, 0.0, 0.0)

		_rotor.add_child(spoke)

	# center glow (bright white circle)
	if _rotor.get_node_or_null("HubGlow") == null:
		var hub := MeshInstance3D.new()
		hub.name = "HubGlow"

		var gcyl := CylinderMesh.new()
		gcyl.top_radius = hub_glow_radius
		gcyl.bottom_radius = hub_glow_radius
		gcyl.height = hub_glow_height
		gcyl.radial_segments = 36
		hub.mesh = gcyl

		var gmat := StandardMaterial3D.new()
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gmat.emission_enabled = true
		gmat.emission = Color(1, 1, 1)
		gmat.emission_energy_multiplier = hub_glow_energy
		hub.material_override = gmat

		_rotor.add_child(hub)
		hub.position = Vector3(0, 0.002, 0)

		var light := OmniLight3D.new()
		light.light_color = Color(1, 1, 1)
		light.light_energy = 1.8
		light.omni_range = 1.5
		hub.add_child(light)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _stuck or !stick_on_first_contact:
		return

	var cc := state.get_contact_count()
	if cc <= 0:
		return

	saved_linear_velocity = state.linear_velocity

	var local_n := state.get_contact_local_normal(0)
	var n := (state.transform.basis * local_n).normalized()

	if saved_linear_velocity.dot(n) > 0.0:
		n = -n

	stuck_normal_world = n

	swap_target_path = NodePath("")
	stick_parent_path = NodePath("")
	stick_local_xf = Transform3D.IDENTITY

	var col_obj: Object = state.get_contact_collider_object(0)
	if col_obj is CollisionObject3D:
		var co := col_obj as CollisionObject3D
		if (co.collision_layer & SWAP_LAYERS_MASK) != 0 and col_obj is Node:
			swap_target_path = (col_obj as Node).get_path()

	if col_obj is Node3D:
		var parent3d := col_obj as Node3D
		stick_parent_path = parent3d.get_path()
		stick_local_xf = parent3d.global_transform.affine_inverse() * state.transform

	var xf := state.transform
	xf.origin = xf.origin + n * stick_offset
	state.transform = xf

	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO

	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	can_sleep = true
	_stuck = true
