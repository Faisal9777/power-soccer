extends RigidBody3D
#
#func _ready() -> void:
	#contact_monitor = true
	#max_contacts_reported = 16
	#print("[Ball] ready; contact monitor on.")
#
#func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	#if linear_velocity.x != 0:
		#print("[Ball] _integrate_forces tick")  # prove this runs
		#var n: int = state.get_contact_count()
		#for i in range(n):
			#var other_rid: RID = state.get_contact_collider(i)
			#if not other_rid.is_valid():
				#continue
			#var inst_id: int = PhysicsServer3D.body_get_object_instance_id(other_rid)
			#if inst_id == 0:
				#continue
			#var obj: Object = instance_from_id(inst_id)
			#if obj is CollisionObject3D:
				#var co := obj as CollisionObject3D
				#var pos: Vector3 = state.get_contact_collider_position(i)
				#var nrm: Vector3 = state.get_contact_local_normal(i)
				#var v_at: Vector3 = state.get_contact_collider_velocity_at_position(i)
				#print("Contact with:", co.name, " class=", co.get_class(),
					  #" at:", pos, " normal:", nrm, " collider_v_at_pos:", v_at)
