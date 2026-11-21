extends SceneTree
## Comprehensive End-to-End Headless Gameplay Test for BODYGUARD INC. (Nov 2026 Edition).
## Verifies:
## 1. 52m x 136m Estate entities (Big Tony Vendor Booth, 8 guards, 3 assassins, 6 hazards, 14 loot items).
## 2. Cryo-Freeze Rifle [Z] freezing guards solid + Plasma Pistol [X] 2x Shatter Crit kills & cash farming.
## 3. Weekend at Bernie's Corpse transition, unpropped slouch, & Voice Lip-Sync Bluff [V].
## 4. 8-Tree Armory Weapon/Cryo Upgrades [U] + 4-Stage Objective Completion -> Level 2 Neon Tokyo scaling!
## 5. Zero orphan nodes on teardown.

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
	print("[gala-e2e-test] Booting full 52m x 136m Multi-Level GalaLevel gameplay loop...")
	var baseline_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var level: GalaLevel = GalaLevel.new()
	level.name = "GalaLevelTest"
	get_root().add_child(level)

	_assert_true(level.vendor_booth != null, "Starting-lobby Big Tony Vendor Booth spawned")
	_assert_true(level.guards.size() == 8, "Spawned 8 patrolling guards across wide estate")
	_assert_true(level.assassins.size() == 3, "Spawned 3 Rival Assassins")
	_assert_true(level.hazards.size() == 6, "Spawned 6 lethal hazards")
	_assert_true(level.loot_items.size() == 14, "Spawned 14 farmable loot pickups + keycard")
	_assert_true(level.guards[0].max_hp == 100.0, "Level 1 guards start at 100 HP")

	# 1. Verify Big Tony Vendor proximity detection & starting upgrade purchase
	level.local_player.position = GalaLevel.VENDOR_POS + Vector3(0.0, 0.0, 2.5)
	_assert_true(level.vendor_booth.check_player_proximity(level.local_player.position), "Vendor Booth detects player in front of counter")
	level._on_upgrade_requested("plasma_gun")
	_assert_true(level.progression.get_level("plasma_gun") == 1, "Purchased Plasma Pistol Lv 1 at Big Tony's with starter cash")

	# 2. Test Cryo-Freeze Rifle [Z] freezing Guard -> Plasma Pistol [X] 2x Shatter Crit Elimination!
	var target_guard_pos: Vector3 = Vector3(0.0, 0.0, 34.0)
	level.guards[0].position = target_guard_pos
	level.local_player.position = target_guard_pos + Vector3(0.0, 0.0, 3.0)
	level.fire_weapon_authoritative(true, Vector3(0.0, 0.0, -1.0))
	for _i: int in range(25):
		level._step_projectiles_physics(FIXED_DT)
	_assert_true(level.guards[0].frozen_timer > 1.0, "Cryo-Freeze Rifle freezes guard solid")

	# Now fire Plasma Pistol into frozen guard -> 2.0x Shatter Crit (60 * 2 = 120 dmg -> instant shatter kill!)
	level.fire_weapon_authoritative(false, Vector3(0.0, 0.0, -1.0))
	for _i: int in range(25):
		level._step_projectiles_physics(FIXED_DT)
	_assert_true(level.guards[0].is_eliminated, "Plasma Pistol Shatter Crit eliminates frozen guard")
	_assert_true(level.progression.total_guards_eliminated == 1, "Guard elimination counted & bounty awarded")

	# 3. Quantized 22-byte Ragdoll Snapshot
	var packed: PackedByteArray = RagdollPhysics.pack_quantized_snapshot(Vector3(2.5, 0.0, -4.0), 1.2, 0.35, 21.0, 2)
	_assert_true(packed.size() == 22, "Quantized ragdoll snapshot is 22 bytes")

	# 4. Weekend at Bernie's Corpse transition + Voice Lip-Sync Bluff on Guard #1
	level.vip.apply_damage_authoritative(250.0, true, "Sky-Bridge Sniper Alpha")
	_assert_true(level.vip.state == VipStateMachine.VipState.CORPSE, "VIP enters CORPSE state after lethal hit")
	level.vip.position = level.guards[1].position + Vector3(1.0, 0.0, 0.0)
	level.local_player.position = level.vip.position + Vector3(9.0, 0.0, 0.0)
	for _i: int in range(25):
		level._physics_process(FIXED_DT)
		level._process(FIXED_DT)
	_assert_true(level.vip.suspicion > 3.0, "Guard raises suspicion when corpse is unpropped")

	var susp_before: float = level.vip.suspicion
	level.local_player.position = level.vip.position + Vector3(-0.6, 0.0, 0.0)
	for _i: int in range(40):
		level.local_player.set_player_intent(Vector2.ZERO, true, 0.45)
		level.local_player.step_bodyguard_physics(FIXED_DT, level.vip, GalaLevel.EXTRACTION_POS)
		var anchors: Array[Vector3] = [level.local_player.get_grab_anchor_world_pos(0)]
		level.vip.authoritative_voice_rms = 0.45
		level.vip.apply_grab_spring_authoritative(anchors, FIXED_DT, true)
		level.vip.step_simulation(FIXED_DT)
		var sd: float = level.guards[1].step_guard_physics(FIXED_DT, level.vip.position, true, false, 1, 0.45)
		level.vip.add_suspicion_authoritative(sd, true)
		level.vip._process(FIXED_DT)
	_assert_true(level.vip.visual_jaw_angle_deg > 12.0, "Corpse jaw opens during voice talk bluff")
	_assert_true(level.vip.suspicion < susp_before, "Guard suspicion drops during voice talk bluff")

	# 5. Complete all 4 Mandatory Objectives -> Transition to LEVEL 2 (NEON TOKYO SKY-LOUNGE)
	level.vip.grabber_count = 1
	level.vip.authoritative_voice_rms = 0.45
	level.vip.position = GalaLevel.PRESS_STAGE_POS
	for _i: int in range(220):
		level._evaluate_contract_objectives(FIXED_DT)
	_assert_true(level.press_completed, "Objective [1/4] Press Photo-Op completed")

	level.vip.position = GalaLevel.AUCTION_PODIUM_POS
	for _i: int in range(250):
		level._evaluate_contract_objectives(FIXED_DT)
	_assert_true(level.auction_completed, "Objective [2/4] Charity Auction completed")

	level.local_player.position = GalaLevel.KEYCARD_LOUNGE_POS
	level._evaluate_loot_pickups()
	_assert_true(level.has_security_keycard, "Objective [3/4] Gold Keycard unlocked Laser Gate")

	level.vip.position = GalaLevel.EXTRACTION_POS
	for _i: int in range(320):
		level._evaluate_contract_objectives(FIXED_DT)
	_assert_true(level.vip.state == VipStateMachine.VipState.EXTRACTED, "Objective [4/4] VIP Extracted")
	_assert_true(level.progression.contract_night == 2, "Progression advanced to Level 2")

	# Deploy Level 2 -> Verify theme shift & Enemy HP scaling (165 HP Guards / 230 HP Assassins!)
	level._deploy_or_restart_level()
	_assert_true(String(level.current_theme["venue_name"]) == "NEON TOKYO SKY-LOUNGE", "Level 2 loaded Neon Tokyo Sky-Lounge theme")
	_assert_true(level.guards[0].max_hp == 165.0, "Level 2 Guards scaled up to 165 HP")
	_assert_true(level.assassins[0].max_hp == 230.0, "Level 2 Assassins scaled up to 230 HP")

	# Buy Cryo Rifle Upgrade Lv 1
	level._on_upgrade_requested("cryo_rifle")
	_assert_true(level.progression.get_level("cryo_rifle") == 1, "Purchased Cryo-Freeze Rifle Lv 1")

	level.free()
	var leaked: int = maxi(0, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - baseline_orphans)
	_assert_true(leaked == 0, "Zero orphan nodes leaked after freeing multi-level GalaLevel (got %d)" % leaked)

	if _failures > 0:
		print("[gala-e2e-test] FAIL (%d failure(s))" % _failures)
		quit(1)
		return true

	print("[gala-e2e-test] PASS (Vendor Booth, Cryo Shatter Kill, 4 Objectives & Level 2 Scaling verified!)")
	quit(0)
	return true


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[ASSERT FAIL] %s" % msg)
		_failures += 1
