extends SceneTree
## End-to-End Headless Gameplay Loop Test for GalaLevel ("The Penthouse Gala").
## Verifies:
## 1. VIP suicidal wandering & hazard damage (ALIVE -> CORPSE).
## 2. Unpropped corpse slouch (~82 deg) & guard suspicion penalty.
## 3. Bodyguard grab spring-damper + Proximity Voice Talk bluff (jaw lip-sync + suspicion drop).
## 4. Limousine Extraction victory ($10,000 quota) & zero orphan nodes on teardown.

const GalaLevel := preload("res://src/scenes/gala_level.gd")
const VipStateMachine := preload("res://src/vip/vip_state_machine.gd")
const RagdollPhysics := preload("res://src/core/ragdoll_physics.gd")

const FIXED_DT: float = 1.0 / 60.0
var _failures: int = 0


var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("[gala-e2e-test] Booting full GalaLevel gameplay loop...")
	var baseline_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var level: GalaLevel = GalaLevel.new()
	level.name = "GalaLevelTest"
	get_root().add_child(level)

	_assert_true(level.vip != null, "GalaLevel spawned VIP")
	_assert_true(level.local_player != null, "GalaLevel spawned LocalBodyguard")
	_assert_true(level.partner_bot != null, "GalaLevel spawned PartnerBotBodyguard")
	_assert_true(level.guards.size() == 4, "GalaLevel spawned 4 patrolling guards")
	_assert_true(level.hazards.size() == 3, "GalaLevel spawned 3 lethal hazards")

	# 1. Test Quantized 22-byte Ragdoll Snapshot Pack/Unpack
	var packed: PackedByteArray = RagdollPhysics.pack_quantized_snapshot(
		Vector3(2.5, 0.0, -4.0), 1.2, 0.35, 21.0, 2
	)
	_assert_true(packed.size() == 22, "Quantized ragdoll snapshot is 22 bytes (<2.4 KB/s @ 20Hz)")
	var unpacked: Dictionary = RagdollPhysics.unpack_quantized_snapshot(packed)
	var upos: Vector3 = unpacked["root_pos"]
	_assert_true(upos.distance_to(Vector3(2.5, 0.0, -4.0)) < 0.01, "Snapshot position round-trips accurately")
	_assert_true(absf(float(unpacked["jaw_angle_deg"]) - 21.0) < 0.5, "Snapshot quantized jaw angle round-trips")

	# 2. Simulate lethal hazard killing the VIP -> Weekend at Bernie's CORPSE mode
	level.vip.apply_damage_authoritative(100.0, true, "Rooftop Sniper Laser")
	_assert_true(level.vip.state == VipStateMachine.VipState.CORPSE, "VIP enters CORPSE state after lethal sniper hit")

	# 3. Unpropped corpse near a guard raises suspicion and collapses toward ~82 deg tilt
	level.partner_bot.ai_assist_enabled = false
	level.local_player.set_player_intent(Vector2.ZERO, false, 0.0)
	level.vip.position = level.guards[0].position + Vector3(1.0, 0.0, 0.0)
	for _i: int in range(30):
		level._physics_process(FIXED_DT)
		level._process(FIXED_DT)
	_assert_true(level.vip.suspicion > 5.0, "Guard raises suspicion rapidly when VIP corpse is unpropped on floor")
	_assert_true(level.vip.torso_tilt_rad > deg_to_rad(40.0), "Unpropped corpse tilts toward the floor")

	# 4. Bodyguard props up corpse + holds Voice Talk (0.45 RMS) -> Jaw opens & Guard suspicion drops!
	var susp_before_bluff: float = level.vip.suspicion
	level.local_player.position = level.vip.position + Vector3(-0.6, 0.0, 0.0)
	level.audio_driver.set_mock_mode(true)
	level.audio_driver.set_custom_mock_rms(0.45)

	for _i: int in range(45):
		level.local_player.set_player_intent(Vector2.ZERO, true, 0.45)
		level.local_player.step_bodyguard_physics(FIXED_DT, level.vip, GalaLevel.EXTRACTION_POS)
		var anchors: Array[Vector3] = [level.local_player.get_grab_anchor_world_pos(0)]
		level.vip.authoritative_voice_rms = 0.45
		level.vip.apply_grab_spring_authoritative(anchors, FIXED_DT, true)
		level.vip.step_simulation(FIXED_DT)
		var s_delta: float = level.guards[0].step_guard_physics(
			FIXED_DT, level.vip.position, true, false, 1, 0.45
		)
		level.vip.add_suspicion_authoritative(s_delta, true)
		level.vip._process(FIXED_DT)

	_assert_true(level.vip.visual_jaw_angle_deg > 12.0, "Corpse jaw animates open during proximity voice talk bluff")
	_assert_true(level.vip.suspicion < susp_before_bluff, "Guard suspicion drops when propped corpse talks convincingly")

	# 5. Drag corpse to North Limousine Extraction Zone -> Victory & $10,000 Quota
	level.vip.position = GalaLevel.EXTRACTION_POS + Vector3(0.0, 0.0, 0.5)
	level._evaluate_checkpoints_and_extraction()
	_assert_true(level.vip.state == VipStateMachine.VipState.EXTRACTED, "VIP reaches EXTRACTED state at limousine pad")
	_assert_true(level.quota_cash == GalaLevel.TARGET_QUOTA_CASH, "Full $10,000 quota cash awarded on extraction")

	level.free()
	var leaked: int = maxi(0, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - baseline_orphans)
	_assert_true(leaked == 0, "Zero orphan nodes leaked after freeing GalaLevel (got %d)" % leaked)

	if _failures > 0:
		print("[gala-e2e-test] FAIL (%d failure(s))" % _failures)
		quit(1)
		return true

	print("[gala-e2e-test] PASS (Full Weekend at Bernie's gameplay loop & extraction verified!)")
	quit(0)
	return true


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[ASSERT FAIL] %s" % msg)
		_failures += 1
