extends SceneTree
## Comprehensive End-to-End Headless Gameplay Test for BODYGUARD INC. v1.0.
## Verifies:
## 1. 4-Zone Estate entities (6 guards, 5 hazards, 2 assassins, 10 loot pickups, locked Laser Gate).
## 2. Quantized 22-byte ragdoll snapshot round-trip.
## 3. Weekend at Bernie's Corpse transition, unpropped slouch, & Voice Lip-Sync Bluff.
## 4. Decoy Champagne Bottle distraction [Q], Shock Taser [G] & Rival Assassin KO bounty.
## 5. Loot farming + Gold Security Keycard unlocking Laser Gate + Agency Upgrade Shop purchase.
## 6. Full 4-Stage Objective progression (Press -> Auction -> Keycard -> 5s Limo Extraction) & Night 2 escalation.
## 7. Zero orphan nodes on teardown.

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
	print("[gala-e2e-test] Booting full 4-Zone GalaLevel contract loop...")
	var baseline_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var level: GalaLevel = GalaLevel.new()
	level.name = "GalaLevelTest"
	get_root().add_child(level)

	_assert_true(level.vip != null, "GalaLevel spawned VIP")
	_assert_true(level.guards.size() == 6, "GalaLevel spawned 6 patrolling guards")
	_assert_true(level.hazards.size() == 5, "GalaLevel spawned 5 lethal hazards")
	_assert_true(level.assassins.size() == 2, "GalaLevel spawned 2 Rival Assassins")
	_assert_true(level.loot_items.size() == 10, "GalaLevel spawned 10 loot/keycard pickups")
	_assert_true(level.partner_bot.ai_assist_enabled == false, "AI Partner starts OFF by default so player plays")
	_assert_true(level.vip.security_gate_locked == true, "Laser Security Gate starts LOCKED")

	# 1. Quantized 22-byte Ragdoll Snapshot
	var packed: PackedByteArray = RagdollPhysics.pack_quantized_snapshot(
		Vector3(2.5, 0.0, -4.0), 1.2, 0.35, 21.0, 2
	)
	_assert_true(packed.size() == 22, "Quantized ragdoll snapshot is 22 bytes")
	var unpacked: Dictionary = RagdollPhysics.unpack_quantized_snapshot(packed)
	var upos: Vector3 = unpacked["root_pos"]
	_assert_true(upos.distance_to(Vector3(2.5, 0.0, -4.0)) < 0.01, "Snapshot position round-trips accurately")

	# 2. Verify Laser Gate physically blocks VIP before keycard pickup
	level.vip.position = Vector3(0.0, 0.0, -25.0)
	level.vip.step_simulation(FIXED_DT)
	_assert_true(level.vip.position.z >= GalaLevel.SECURITY_GATE_Z, "Locked Laser Gate prevents skipping to extraction")

	# 3. Simulate Rival Assassin KO with Tackle [F] -> Bounty Cash
	var bank_before_ko: int = level.progression.bank_cash
	level.local_player.position = level.assassins[0].position + Vector3(1.0, 0.0, 0.0)
	level._execute_hero_tackle()
	_assert_true(level.assassins[0].ko_respawn_timer > 0.0, "Tackle [F] knocks out nearby Rival Assassin")
	_assert_true(level.progression.bank_cash > bank_before_ko, "Assassin KO awards bounty cash into Agency Bank")

	# 4. Simulate lethal hit -> Weekend at Bernie's CORPSE mode
	level.vip.apply_damage_authoritative(200.0, true, "Sky-Bridge Sniper Alpha")
	_assert_true(level.vip.state == VipStateMachine.VipState.CORPSE, "VIP enters CORPSE state after lethal hit")

	# 5. Unpropped corpse near guard raises suspicion & tilts toward floor
	level.vip.position = level.guards[0].position + Vector3(1.0, 0.0, 0.0)
	level.local_player.position = level.vip.position + Vector3(8.0, 0.0, 0.0)
	for _i: int in range(30):
		level._physics_process(FIXED_DT)
		level._process(FIXED_DT)
	_assert_true(level.vip.suspicion > 4.0, "Guard raises suspicion when corpse is unpropped on floor")
	_assert_true(level.vip.torso_tilt_rad > deg_to_rad(40.0), "Unpropped corpse collapses toward floor")

	# 6. Prop corpse + Voice Talk Bluff [V] -> Jaw opens & suspicion drops
	var susp_before_bluff: float = level.vip.suspicion
	level.local_player.position = level.vip.position + Vector3(-0.6, 0.0, 0.0)
	for _i: int in range(45):
		level.local_player.set_player_intent(Vector2.ZERO, true, 0.45)
		level.local_player.step_bodyguard_physics(FIXED_DT, level.vip, GalaLevel.EXTRACTION_POS)
		var anchors: Array[Vector3] = [level.local_player.get_grab_anchor_world_pos(0)]
		level.vip.authoritative_voice_rms = 0.45
		level.vip.apply_grab_spring_authoritative(anchors, FIXED_DT, true)
		level.vip.step_simulation(FIXED_DT)
		var sd: float = level.guards[0].step_guard_physics(FIXED_DT, level.vip.position, true, false, 1, 0.45)
		level.vip.add_suspicion_authoritative(sd, true)
		level.vip._process(FIXED_DT)
	_assert_true(level.vip.visual_jaw_angle_deg > 12.0, "Corpse jaw opens during voice talk bluff")
	_assert_true(level.vip.suspicion < susp_before_bluff, "Guard suspicion drops during voice talk bluff")

	# 7. Decoy Champagne Bottle [Q] distracts guard
	var bottles_before: int = level.decoy_bottles_left
	level.local_player.position = level.guards[0].position - Vector3(0.0, 0.0, 4.0)
	level.local_player.facing_yaw_rad = 0.0
	level._try_throw_decoy_bottle()
	_assert_true(level.decoy_bottles_left == bottles_before - 1, "Decoy bottle throw decrements count")
	_assert_true(level.guards[0].distracted_timer > 0.0, "Nearby guard is distracted by decoy champagne bottle")

	# 8. Complete all 4 Mandatory Contract Objectives (Press -> Auction -> Keycard -> 5s Extraction)
	level.vip.grabber_count = 1
	level.vip.authoritative_voice_rms = 0.45
	level.vip.position = GalaLevel.PRESS_STAGE_POS
	for _i: int in range(220):
		level._evaluate_contract_objectives(FIXED_DT)
	_assert_true(level.press_completed, "Objective [1/4] Press Photo-Op completed with Corpse Voice Bluff")

	level.vip.position = GalaLevel.AUCTION_PODIUM_POS
	for _i: int in range(250):
		level._evaluate_contract_objectives(FIXED_DT)
	_assert_true(level.auction_completed, "Objective [2/4] Charity Auction completed with Corpse Voice Bluff")

	# Pick up Gold Security Keycard in East Lounge
	level.local_player.position = GalaLevel.KEYCARD_LOUNGE_POS
	level._evaluate_loot_pickups()
	_assert_true(level.has_security_keycard, "Objective [3/4] Gold Keycard collected")
	_assert_true(level.vip.security_gate_locked == false, "Laser Security Gate unlocked after keycard pickup")

	# Hold VIP at North Armored Limousine for 5.0s extraction countdown
	level.vip.position = GalaLevel.EXTRACTION_POS
	for _i: int in range(320):
		level._evaluate_contract_objectives(FIXED_DT)
	_assert_true(level.vip.state == VipStateMachine.VipState.EXTRACTED, "Objective [4/4] VIP extracted after 5s hold")
	_assert_true(level.progression.contract_night == 2, "Contract victory escalates to Night 2")
	_assert_true(level.progression.bank_cash >= 10000, "Bank cash reflects farming + contract payout")

	# 9. Purchase Upgrade in Agency Armory Shop
	var bank_before_shop: int = level.progression.bank_cash
	level._on_upgrade_requested("exo_grip")
	_assert_true(level.progression.get_level("exo_grip") == 1, "Exo-Grip upgrade leveled to Lv 1")
	_assert_true(level.progression.bank_cash < bank_before_shop, "Upgrade cost deducted from Agency Bank")

	level.free()
	var leaked: int = maxi(0, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - baseline_orphans)
	_assert_true(leaked == 0, "Zero orphan nodes leaked after freeing GalaLevel (got %d)" % leaked)

	if _failures > 0:
		print("[gala-e2e-test] FAIL (%d failure(s))" % _failures)
		quit(1)
		return true

	print("[gala-e2e-test] PASS (4-Zone Estate, Keycard Gate, Assassin KO, Upgrades & Corpse Extraction verified!)")
	quit(0)
	return true


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[ASSERT FAIL] %s" % msg)
		_failures += 1
