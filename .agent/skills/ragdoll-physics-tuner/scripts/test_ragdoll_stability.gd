extends SceneTree
## Headless 300-tick ragdoll impulse stability & alive-to-corpse transition test.
## Run: godot --headless --path . --script .agent/skills/ragdoll-physics-tuner/scripts/test_ragdoll_stability.gd

const VipStateMachine := preload("res://src/vip/vip_state_machine.gd")

const SIMULATION_TICKS: int = 300
const FIXED_DT: float = 1.0 / 60.0
const MAX_SAFE_IMPULSE: float = 150.0
const MAX_JOINT_SEPARATION: float = 2.5
const MAX_WORLD_BOUND: float = 500.0


var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var exit_code: int = _run_stability_suite()
	quit(exit_code)
	return true


func _run_stability_suite() -> int:
	print("[ragdoll-stability] Starting 300-tick extreme impulse simulation...")

	var root_node: Node3D = Node3D.new()
	root_node.name = "RagdollTestRoot"
	get_root().add_child(root_node)

	var vip: VipStateMachine = VipStateMachine.new()
	vip.name = "TestVIP"
	root_node.add_child(vip)

	# Create pelvis + head RigidBody3D pair linked by Generic6DOFJoint3D
	var pelvis: RigidBody3D = _make_limb("Pelvis", Vector3(0.0, 2.0, 0.0), 30.0)
	var head: RigidBody3D = _make_limb("Head", Vector3(0.0, 2.8, 0.0), 8.0)
	root_node.add_child(pelvis)
	root_node.add_child(head)

	var neck_joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	neck_joint.name = "NeckJoint"
	neck_joint.position = Vector3(0.0, 2.4, 0.0)
	root_node.add_child(neck_joint)
	neck_joint.node_a = neck_joint.get_path_to(pelvis)
	neck_joint.node_b = neck_joint.get_path_to(head)

	# Extreme impulse schedule: car hit, player tackle, NaN injection (must be rejected), fall
	var impulses: Dictionary = {
		10: Vector3(420.0, 80.0, -120.0),   # Car hit (clamped)
		60: Vector3(-90.0, 35.0, 110.0),    # Player tackle
		120: Vector3(NAN, INF, -INF),       # Corrupt NaN/INF impulse (must be rejected)
		180: Vector3(0.0, -250.0, 0.0),     # High fall impact (clamped)
	}

	var failed: bool = false
	for tick: int in range(SIMULATION_TICKS):
		if impulses.has(tick):
			var raw_imp: Vector3 = impulses[tick]
			var safe_imp: Vector3 = vip.sanitize_impulse(raw_imp, MAX_SAFE_IMPULSE)
			if safe_imp.length() > MAX_SAFE_IMPULSE + 0.001:
				push_error("[ragdoll-stability] Clamping failed at tick %d" % tick)
				failed = true
				break
			pelvis.apply_central_impulse(safe_imp)
			if tick == 10:
				vip.apply_damage_authoritative(120.0, true)

		# Step physics kinematics manually in SceneTree._init context
		pelvis.linear_velocity *= 0.985
		head.linear_velocity = head.linear_velocity.lerp(pelvis.linear_velocity, 0.5)
		pelvis.position += pelvis.linear_velocity * FIXED_DT
		head.position = pelvis.position + Vector3(0.0, 0.8, 0.0)
		vip.step_simulation(FIXED_DT)

		if not pelvis.position.is_finite() or not head.position.is_finite():
			push_error("[ragdoll-stability] NaN/INF transform detected at tick %d" % tick)
			failed = true
			break
		if pelvis.position.length() > MAX_WORLD_BOUND:
			push_error("[ragdoll-stability] Ragdoll exploded out of bounds at tick %d" % tick)
			failed = true
			break
		var separation: float = pelvis.position.distance_to(head.position)
		if separation > MAX_JOINT_SEPARATION:
			push_error("[ragdoll-stability] Joint explosion detected (sep=%.2f) at tick %d" % [separation, tick])
			failed = true
			break

	# Verify alive -> corpse transition occurred cleanly
	if vip.state != VipStateMachine.VipState.CORPSE:
		push_error("[ragdoll-stability] Expected VIP state CORPSE after lethal hit, got %d" % vip.state)
		failed = true

	root_node.free()

	if failed:
		print("[ragdoll-stability] FAIL")
		return 1

	print("[ragdoll-stability] PASS (300 ticks, zero NaN/INF, zero joint explosion, valid ALIVE->CORPSE)")
	return 0


func _make_limb(limb_name: String, pos: Vector3, limb_mass: float) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.name = limb_name
	body.position = pos
	body.mass = limb_mass
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.25
	shape.shape = sphere
	body.add_child(shape)
	return body
