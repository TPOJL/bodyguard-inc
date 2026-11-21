class_name GalaLevel
extends Node3D
## Full Playable 3D Co-op Game — BODYGUARD INC. (November 2026 Edition).
## 52m x 136m Multi-Level Estate (5 escalating themes + endless Prestige),
## Starting-Lobby Vendor Booth ("Big Tony's Armory"), Plasma Pistol [LMB/X],
## Cryo-Freeze Rifle [RMB/Z] with 2x Shatter Crits, Solid Wall Collision Grid,
## 8-Tree Upgrade Armory [U], Live Tactical Radar Minimap, & Neo-Glass HUD.

const NetworkTransportLib := preload("res://src/core/network_transport.gd")
const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")
const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")
const AgencyProgressionLib := preload("res://src/core/agency_progression.gd")
const SynthSfxLib := preload("res://src/core/synth_sfx.gd")
const LevelThemesLib := preload("res://src/world/level_themes.gd")
const WallColliderGridLib := preload("res://src/world/wall_collider_grid.gd")
const ProjectileBoltLib := preload("res://src/world/projectile_bolt.gd")
const VendorBoothLib := preload("res://src/world/vendor_booth.gd")
const VipStateMachineLib := preload("res://src/vip/vip_state_machine.gd")
const BodyguardPlayerLib := preload("res://src/player/bodyguard_player.gd")
const GuardNpcLib := preload("res://src/world/guard_npc.gd")
const HazardZoneLib := preload("res://src/world/hazard_zone.gd")
const LootPickupLib := preload("res://src/world/loot_pickup.gd")
const AssassinNpcLib := preload("res://src/world/assassin_npc.gd")
const GalaVisualComposerLib := preload("res://src/world/gala_visual_composer.gd")
const GalaHudLib := preload("res://src/ui/gala_hud.gd")

const VIP_SPAWN_POS: Vector3 = Vector3(0.0, 0.0, 54.0)
const PLAYER1_SPAWN_POS: Vector3 = Vector3(-2.4, 0.0, 55.5)
const PARTNER_SPAWN_POS: Vector3 = Vector3(2.4, 0.0, 55.5)
const VENDOR_POS: Vector3 = Vector3(-9.5, 0.0, 52.5)

const PRESS_STAGE_POS: Vector3 = Vector3(0.0, 0.0, 28.0)
const AUCTION_PODIUM_POS: Vector3 = Vector3(0.0, 0.0, -2.0)
const KEYCARD_LOUNGE_POS: Vector3 = Vector3(16.5, 0.0, -6.0)
const SECURITY_GATE_Z: float = -22.0
const EXTRACTION_POS: Vector3 = Vector3(0.0, 0.0, -60.0)
const EXTRACTION_RADIUS: float = 3.0

const PRESS_HOLD_SEC: float = 3.5
const AUCTION_HOLD_SEC: float = 4.0
const EXTRACTION_HOLD_SEC: float = 5.0
const TARGET_QUOTA_CASH: int = 10000

var transport: NetworkTransportLib = null
var audio_driver: AudioInputDriverLib = null
var progression: AgencyProgressionLib = null
var wall_grid: WallColliderGridLib = null
var current_theme: Dictionary = {}
var sfx: SynthSfxLib = null
var hud: GalaHudLib = null

var vendor_booth: VendorBoothLib = null
var vip: VipStateMachineLib = null
var local_player: BodyguardPlayerLib = null
var partner_bot: BodyguardPlayerLib = null
var remote_players: Dictionary = {}
var guards: Array[GuardNpcLib] = []
var hazards: Array[HazardZoneLib] = []
var loot_items: Array[LootPickupLib] = []
var assassins: Array[AssassinNpcLib] = []
var projectiles: Array[ProjectileBoltLib] = []
var laser_gate_node: Node3D = null

# Dynamic theme root nodes (freed & rebuilt cleanly on level transition)
var _env_root: Node3D = null
var _arch_root: Node3D = null

# Authoritative contract state (Host)
var quota_cash: int = 0
var contract_earned_cash: int = 0
var combo_mult: float = 1.0
var combo_decay_timer: float = 0.0
var decoy_bottles_left: int = 3
var taser_cooldown: float = 0.0
var plasma_cooldown: float = 0.0
var cryo_cooldown: float = 0.0

# 4-Stage Mandatory Objective Progression
var press_progress_sec: float = 0.0
var press_completed: bool = false
var auction_progress_sec: float = 0.0
var auction_completed: bool = false
var has_security_keycard: bool = false
var extraction_progress_sec: float = 0.0

var shop_open: bool = false
var contract_ended: bool = false
var contract_victory: bool = false
var camera_mode: int = 0
var network_status_label: String = "Solo"
var active_guard_bark: String = "Visit Big Tony's Armory on your left [U] or escort VIP North!"
var combo_popup_text: String = "BUY WEAPONS & BUFFS AT BIG TONY'S BOOTH [U] — THEN ESCORT THE VIP!"
var combo_popup_timer: float = 5.0

var _sim_clock: float = 0.0
var _snapshot_tick_counter: int = 0
var _bluff_score_cooldown: float = 0.0
var _camera_shake_trauma: float = 0.0
var _screen_flash_burst: float = 0.0
var _flare_shader_mat: ShaderMaterial = null
var _decoy_markers: Array[Node3D] = []
var _camera: Camera3D = null
var _edge_keys: Dictionary = {}


func _ready() -> void:
	audio_driver = AudioInputDriverLib.new()
	progression = AgencyProgressionLib.new()
	progression.load_from_disk()
	quota_cash = progression.bank_cash
	wall_grid = WallColliderGridLib.new()

	sfx = SynthSfxLib.new()
	sfx.name = "SynthSfx"
	add_child(sfx)

	_camera = Camera3D.new()
	_camera.name = "FollowCamera"
	_camera.position = Vector3(0.0, 14.0, 66.0)
	_camera.fov = 56.0
	_camera.current = true
	add_child(_camera)

	_rebuild_level_architecture()
	_spawn_entities()
	_build_hud()
	_apply_progression_stats()


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_sim_clock += delta
	if combo_popup_timer > 0.0:
		combo_popup_timer = maxf(0.0, combo_popup_timer - delta)
	if _bluff_score_cooldown > 0.0:
		_bluff_score_cooldown = maxf(0.0, _bluff_score_cooldown - delta)
	if taser_cooldown > 0.0:
		taser_cooldown = maxf(0.0, taser_cooldown - delta)
	if plasma_cooldown > 0.0:
		plasma_cooldown = maxf(0.0, plasma_cooldown - delta)
	if cryo_cooldown > 0.0:
		cryo_cooldown = maxf(0.0, cryo_cooldown - delta)
	if combo_decay_timer > 0.0:
		combo_decay_timer = maxf(0.0, combo_decay_timer - delta)
		if combo_decay_timer <= 0.0:
			combo_mult = 1.0

	_poll_local_inputs_physics()

	if shop_open:
		return

	var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if not is_host:
		return

	# 1. Step bodyguards & check starting-lobby Vendor Booth proximity
	var active_goal: Vector3 = _get_current_objective_pos()
	local_player.step_bodyguard_physics(delta, vip, active_goal)
	partner_bot.step_bodyguard_physics(delta, vip, active_goal)
	if vendor_booth != null:
		vendor_booth.check_player_proximity(local_player.position)

	var grab_anchors: Array[Vector3] = []
	var max_voice_rms: float = local_player.current_voice_rms

	if local_player.is_grabbing_vip:
		grab_anchors.append(local_player.get_grab_anchor_world_pos(0))
	if partner_bot.is_grabbing_vip:
		grab_anchors.append(partner_bot.get_grab_anchor_world_pos(1))

	for peer_id_key: Variant in remote_players.keys():
		var rp: BodyguardPlayerLib = remote_players[peer_id_key]
		rp.step_bodyguard_physics(delta, vip, active_goal)
		if rp.is_grabbing_vip:
			grab_anchors.append(rp.get_grab_anchor_world_pos(grab_anchors.size()))
		max_voice_rms = maxf(max_voice_rms, rp.current_voice_rms)

	vip.authoritative_voice_rms = max_voice_rms
	if max_voice_rms >= 0.08 and sfx != null:
		sfx.play_voice_syllable(max_voice_rms)

	# 2. Suicidal VIP gravitates toward nearest active lethal hazard
	_assign_nearest_hazard_whim()

	# 3. Apply critically-damped grab spring-damper forces & step VIP
	vip.apply_grab_spring_authoritative(grab_anchors, delta, true)
	vip.step_simulation(delta)

	# 4. Step Plasma & Cryo Projectiles against Solid Walls, Guards, and Assassins
	_step_projectiles_physics(delta)

	# 5. Evaluate Loot Pickups & Gold Security Keycard
	_evaluate_loot_pickups()

	# 6. Evaluate Lethal Hazards
	var vip_alive: bool = (vip.state == VipStateMachineLib.VipState.ALIVE)
	for hazard: HazardZoneLib in hazards:
		var dmg: float = hazard.step_hazard_physics(delta, vip.position, vip_alive)
		if dmg > 0.0:
			vip.apply_damage_authoritative(dmg, true, hazard.hazard_title)
			_camera_shake_trauma = minf(1.0, _camera_shake_trauma + 0.45)
			_screen_flash_burst = 0.50
			if vip.state == VipStateMachineLib.VipState.CORPSE:
				_trigger_combo_banner("💀 VIP KILLED BY %s! PROP CORPSE [E] & BLUFF [V]!" % hazard.hazard_title)
				if sfx != null:
					sfx.play_alert_chirp()

	# 7. Evaluate Rival Assassins hunting the VIP
	for assassin: AssassinNpcLib in assassins:
		var admg: float = assassin.step_assassin_physics(delta, vip.position, vip_alive)
		if admg > 0.0:
			vip.apply_damage_authoritative(admg, true, assassin.assassin_name)
			_camera_shake_trauma = minf(1.0, _camera_shake_trauma + 0.50)
			_screen_flash_burst = 0.55
			_trigger_combo_banner("🗡️ %s STRUCK VIP! FREEZE [Z/RMB] OR SHOOT [X/LMB]!" % assassin.assassin_name)
			if sfx != null:
				sfx.play_alert_chirp()

	# 8. Evaluate Patrolling Security Guards & Paparazzi
	var vip_corpse: bool = (vip.state == VipStateMachineLib.VipState.CORPSE)
	var priority_bark: String = ""
	var bluff_mult: float = progression.get_voice_bluff_multiplier()
	var susp_gain_mult: float = progression.get_suspicion_gain_multiplier()

	for guard: GuardNpcLib in guards:
		var raw_delta: float = guard.step_guard_physics(
			delta,
			vip.position,
			vip_corpse,
			vip_alive,
			vip.grabber_count,
			vip.authoritative_voice_rms
		)
		var tuned_delta: float = (raw_delta * bluff_mult) if raw_delta < 0.0 else (raw_delta * susp_gain_mult)
		if tuned_delta != 0.0:
			vip.add_suspicion_authoritative(tuned_delta, true)
		if guard.paparazzi_flash_pulse > 0.85:
			_screen_flash_burst = maxf(_screen_flash_burst, 0.30)
		if guard.is_inspecting_vip:
			priority_bark = guard.last_inspection_bark
			if vip_corpse and vip.grabber_count > 0 and tuned_delta < 0.0 and _bluff_score_cooldown <= 0.0:
				_award_farm_cash(350, "🎙️ WEEKEND AT BERNIE'S BLUFF!")
				_bluff_score_cooldown = 2.0

	if vip.state == VipStateMachineLib.VipState.EXPOSED and not contract_ended:
		contract_ended = true
		contract_victory = false
		_trigger_combo_banner("🚨 COVER BLOWN! VISIT BIG TONY'S ARMORY [U] OR RETRY [R]!")
		if sfx != null:
			sfx.play_alert_chirp()
		if DisplayServer.get_name() != "headless":
			_set_shop_state(true)

	if priority_bark != "":
		active_guard_bark = priority_bark
	elif vendor_booth != null and vendor_booth.is_player_in_range:
		active_guard_bark = "🛒 Big Tony: 'Press [U] to buy Plasma/Cryo Weapons & Buffs before heading North!'"
	elif vip_corpse and vip.grabber_count <= 0:
		active_guard_bark = "💀 VIP CORPSE ON FLOOR! Hold [E] to prop him up!"
	elif vip_corpse:
		active_guard_bark = "🕶️ Carrying Corpse! Hold [V] to bluff guards, Freeze [Z/RMB], or Shoot [X/LMB]!"
	else:
		active_guard_bark = "🤵 VIP heading for %s — Grab [E] or clear guards with Cryo [Z] + Plasma [X]!" % vip.suicidal_whim_label

	# 9. Evaluate Mandatory 4-Stage Objectives
	_evaluate_contract_objectives(delta)

	# 10. Broadcast <=20 Hz quantized ragdoll snapshot
	_snapshot_tick_counter += 1
	if multiplayer.has_multiplayer_peer() and (_snapshot_tick_counter % 3 == 0):
		var snap: PackedByteArray = RagdollPhysicsLib.pack_quantized_snapshot(
			vip.position,
			vip.facing_yaw_rad,
			vip.torso_tilt_rad,
			vip.visual_jaw_angle_deg,
			vip.grabber_count
		)
		transport.broadcast_vip_snapshot.rpc(snap)


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return

	_camera_shake_trauma = maxf(0.0, _camera_shake_trauma - delta * 2.4)
	_screen_flash_burst = maxf(0.0, _screen_flash_burst - delta * 3.4)

	if local_player != null and vip != null:
		local_player.update_visuals(vip.position)
	if partner_bot != null and vip != null:
		partner_bot.update_visuals(vip.position)
	if vendor_booth != null:
		vendor_booth.update_visuals(delta)
	for peer_id_key: Variant in remote_players.keys():
		var rp: BodyguardPlayerLib = remote_players[peer_id_key]
		rp.update_visuals(vip.position)

	for guard: GuardNpcLib in guards:
		guard.update_guard_visuals()
	for hazard: HazardZoneLib in hazards:
		hazard.update_hazard_visuals()
	for item: LootPickupLib in loot_items:
		item.update_visuals(delta)
	for assassin: AssassinNpcLib in assassins:
		assassin.update_visuals()

	if laser_gate_node != null:
		laser_gate_node.visible = not has_security_keycard

	if _flare_shader_mat != null and vip != null:
		var max_sniper_pulse: float = 0.0
		for h: HazardZoneLib in hazards:
			if h.hazard_type == HazardZoneLib.HazardType.SNIPER_LASER:
				max_sniper_pulse = maxf(max_sniper_pulse, h.sniper_lock_timer / HazardZoneLib.SNIPER_LOCK_THRESHOLD_SEC)
		var danger: float = clampf(maxf(maxf(0.0, (vip.suspicion - 35.0) / 65.0), max_sniper_pulse), 0.0, 1.0)
		_flare_shader_mat.set_shader_parameter("danger_pulse", danger)
		_flare_shader_mat.set_shader_parameter("flash_burst", _screen_flash_burst)

	_update_camera_visuals(delta)
	_update_hud_display()


func _update_camera_visuals(delta: float) -> void:
	if _camera == null or local_player == null or vip == null:
		return
	var focus: Vector3 = (local_player.position * 0.72) + (vip.position * 0.28)
	var cam_offset: Vector3 = Vector3(0.0, 12.8, 11.4)
	var look_height: float = 1.0
	var target_fov: float = 56.0

	if camera_mode == 1:
		cam_offset = Vector3(0.0, 5.2, 6.8)
		look_height = 1.35
		target_fov = 62.0
	elif camera_mode == 2:
		cam_offset = Vector3(0.0, 21.5, 15.0)
		look_height = 0.4
		target_fov = 52.0

	if local_player.is_sprinting:
		target_fov += 3.5

	var shake_vec: Vector3 = Vector3.ZERO
	if _camera_shake_trauma > 0.01:
		var amt: float = _camera_shake_trauma * _camera_shake_trauma * 0.36
		shake_vec = Vector3(
			sin(_sim_clock * 47.0) * amt,
			cos(_sim_clock * 53.0) * amt,
			sin(_sim_clock * 39.0) * amt
		)

	var desired_cam_pos: Vector3 = focus + cam_offset + shake_vec
	_camera.position = _camera.position.lerp(desired_cam_pos, clampf(delta * 8.5, 0.0, 1.0))
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(delta * 6.0, 0.0, 1.0))
	_camera.look_at(focus + Vector3(0.0, look_height, 0.0), Vector3.UP)


func _key_just_pressed(keycode: Key) -> bool:
	var now: bool = Input.is_key_pressed(keycode)
	var prev: bool = bool(_edge_keys.get(keycode, false))
	_edge_keys[keycode] = now
	return now and not prev


func _get_aim_direction_for_fire() -> Vector3:
	# If playing windowed with mouse cursor over viewport, aim precisely at cursor world position!
	if DisplayServer.get_name() != "headless" and _camera != null and get_viewport() != null:
		var mpos: Vector2 = get_viewport().get_mouse_position()
		var ray_orig: Vector3 = _camera.project_ray_origin(mpos)
		var ray_dir: Vector3 = _camera.project_ray_normal(mpos)
		if absf(ray_dir.y) > 0.001:
			var t: float = (1.0 - ray_orig.y) / ray_dir.y
			if t > 0.0:
				var hit_pt: Vector3 = ray_orig + ray_dir * t
				var diff: Vector3 = hit_pt - local_player.position
				diff.y = 0.0
				if diff.length_squared() > 0.25:
					var aim: Vector3 = diff.normalized()
					local_player.facing_yaw_rad = atan2(aim.x, aim.z)
					return aim
	return local_player.get_aim_direction()


func _poll_local_inputs_physics() -> void:
	if _key_just_pressed(KEY_U) or (shop_open and _key_just_pressed(KEY_ESCAPE)):
		_set_shop_state(not shop_open)
		return

	if shop_open:
		var num_keys: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
		for i: int in range(num_keys.size()):
			if _key_just_pressed(num_keys[i]):
				var uid: String = String(AgencyProgressionLib.UPGRADE_CATALOG[i]["id"])
				_on_upgrade_requested(uid)
		if _key_just_pressed(KEY_R):
			_deploy_or_restart_level()
		return

	var move: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0

	var grab_held: bool = Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE)
	var sprint_held: bool = Input.is_key_pressed(KEY_SHIFT)
	var talk_held: bool = Input.is_key_pressed(KEY_V)
	var scream_held: bool = Input.is_key_pressed(KEY_B)
	var rms: float = audio_driver.sample_interactive_rms(talk_held, scream_held, _sim_clock)

	local_player.set_player_intent(move, grab_held, rms, sprint_held)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		transport.submit_player_intent.rpc_id(1, move, grab_held, rms)

	# [Left Click / X] Fire Plasma Pistol (kills high-HP Guards & Assassins; 2x+ Shatter Crit on frozen!)
	if (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_X)) and plasma_cooldown <= 0.0:
		fire_weapon_authoritative(false, _get_aim_direction_for_fire())

	# [Right Click / Z] Fire Cryo-Freeze Rifle (freezes Guards & Assassins solid in 3D ice blocks!)
	if (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_Z)) and cryo_cooldown <= 0.0:
		fire_weapon_authoritative(true, _get_aim_direction_for_fire())

	if _key_just_pressed(KEY_F):
		_execute_hero_tackle()
	if _key_just_pressed(KEY_G):
		_execute_shock_taser()
	if _key_just_pressed(KEY_Q):
		_try_throw_decoy_bottle()
	if _key_just_pressed(KEY_C):
		camera_mode = (camera_mode + 1) % 3
		var cam_names: Array[String] = ["CINEMATIC FOLLOW", "CLOSE ACTION CAM", "TACTICAL OVERVIEW"]
		_trigger_combo_banner("🎥 CAMERA: %s" % cam_names[camera_mode])
	if _key_just_pressed(KEY_K):
		var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
		if vip.state == VipStateMachineLib.VipState.ALIVE:
			vip.apply_damage_authoritative(vip.max_health + 50.0, is_host, "Poisoned Martini ([K])")
			_camera_shake_trauma = 0.55
			_screen_flash_burst = 0.45
			_trigger_combo_banner("💀 WEEKEND AT BERNIE'S MODE! HOLD [E] TO PROP CORPSE & [V] TO TALK!")
			if sfx != null:
				sfx.play_alert_chirp()
	if _key_just_pressed(KEY_R):
		_deploy_or_restart_level()
	if _key_just_pressed(KEY_TAB):
		partner_bot.ai_assist_enabled = not partner_bot.ai_assist_enabled
		_trigger_combo_banner("🕶️ AI CO-OP PARTNER: %s" % ("ENABLED" if partner_bot.ai_assist_enabled else "OFF"))
	if _key_just_pressed(KEY_H):
		var err: Error = transport.host_session(17777, 3)
		network_status_label = "HOST :17777" if err == OK else "Host err %d" % err
	if _key_just_pressed(KEY_J):
		var err: Error = transport.join_session("127.0.0.1", 17777)
		network_status_label = "CLIENT :17777" if err == OK else "Join err %d" % err


func fire_weapon_authoritative(is_cryo: bool, aim_dir: Vector3) -> ProjectileBoltLib:
	var dir: Vector3 = aim_dir.normalized() if (aim_dir.is_finite() and aim_dir.length_squared() > 0.001) else local_player.get_aim_direction()
	var spawn_pt: Vector3 = local_player.position + Vector3(dir.x, 0.0, dir.z) * 0.75 + Vector3(0.0, 1.15, 0.0)
	var bolt: ProjectileBoltLib = ProjectileBoltLib.new()

	if is_cryo:
		cryo_cooldown = progression.get_cryo_cooldown()
		bolt.configure_bolt(
			ProjectileBoltLib.BoltType.CRYO_FREEZE,
			spawn_pt,
			dir,
			14.0,
			progression.get_cryo_freeze_duration(),
			progression.get_cryo_shatter_crit_mult()
		)
	else:
		plasma_cooldown = progression.get_plasma_cooldown()
		bolt.configure_bolt(
			ProjectileBoltLib.BoltType.PLASMA_PISTOL,
			spawn_pt,
			dir,
			progression.get_plasma_damage(),
			0.0,
			progression.get_cryo_shatter_crit_mult()
		)

	add_child(bolt)
	projectiles.append(bolt)
	local_player.notify_weapon_fired(is_cryo)
	if sfx != null:
		if is_cryo:
			sfx.play_bottle_throw()
		else:
			sfx.play_shove_whoosh()
	return bolt


func _step_projectiles_physics(delta: float) -> void:
	var gate_locked: bool = not has_security_keycard
	var idx: int = projectiles.size() - 1
	while idx >= 0:
		var bolt: ProjectileBoltLib = projectiles[idx]
		var still_flying: bool = bolt.step_bolt(delta, wall_grid, gate_locked)
		var hit_enemy: bool = false

		if still_flying:
			# Check Guard hits
			for guard: GuardNpcLib in guards:
				if guard.is_eliminated:
					continue
				var flat_b: Vector3 = Vector3(bolt.position.x, 0.0, bolt.position.z)
				if flat_b.distance_to(guard.position) <= ProjectileBoltLib.HIT_RADIUS:
					var res: Dictionary = guard.apply_weapon_hit(bolt.damage, bolt.freeze_duration, bolt.shatter_crit_mult)
					hit_enemy = true
					bolt.alive = false
					if bool(res["killed"]):
						progression.total_guards_eliminated += 1
						var tag: String = "❄️💥 CRYO SHATTER KILL!" if bool(res["shatter_crit"]) else "🔫 GUARD ELIMINATED!"
						_award_farm_cash(450, tag)
						_camera_shake_trauma = minf(1.0, _camera_shake_trauma + 0.30)
					elif bolt.freeze_duration > 0.0:
						_trigger_combo_banner("❄️ %s FROZEN FOR %.1fs! SHOOT [LMB/X] FOR %.1fx CRIT!" % [guard.guard_title, bolt.freeze_duration, bolt.shatter_crit_mult])
					break

			# Check Rival Assassin hits
			if not hit_enemy:
				for assassin: AssassinNpcLib in assassins:
					if assassin.ko_respawn_timer > 0.0:
						continue
					var flat_b2: Vector3 = Vector3(bolt.position.x, 0.0, bolt.position.z)
					if flat_b2.distance_to(assassin.position) <= ProjectileBoltLib.HIT_RADIUS:
						var ares: Dictionary = assassin.apply_weapon_hit(bolt.damage, bolt.freeze_duration, bolt.shatter_crit_mult)
						hit_enemy = true
						bolt.alive = false
						if bool(ares["killed"]):
							progression.total_assassins_ko += 1
							var atag: String = "❄️💥 CRYO SHATTER ASSASSIN!" if bool(ares["shatter_crit"]) else "🔫 ASSASSIN ELIMINATED!"
							_award_farm_cash(950, atag)
							_camera_shake_trauma = minf(1.0, _camera_shake_trauma + 0.45)
						elif bolt.freeze_duration > 0.0:
							_trigger_combo_banner("❄️ %s FROZEN! SHATTER WITH PLASMA [LMB/X]!" % assassin.assassin_name)
						break

		if not still_flying or not bolt.alive:
			projectiles.remove_at(idx)
			bolt.free()
		idx -= 1


func _execute_hero_tackle() -> void:
	for assassin: AssassinNpcLib in assassins:
		if assassin.ko_respawn_timer <= 0.0 and local_player.position.distance_to(assassin.position) <= 3.8:
			if assassin.apply_knockout_or_stun(0.0, true):
				progression.total_assassins_ko += 1
				_camera_shake_trauma = 0.60
				_screen_flash_burst = 0.40
				_award_farm_cash(850, "💥 ASSASSIN TACKLE KO!")
				if sfx != null:
					sfx.play_shove_whoosh()
				return

	var imp: Vector3 = local_player.try_shove_vip(vip)
	if imp.length_squared() > 0.01:
		var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
		vip.apply_shove_impulse_authoritative(imp, is_host)
		_camera_shake_trauma = 0.45
		_screen_flash_burst = 0.30
		if sfx != null:
			sfx.play_shove_whoosh()
		_award_farm_cash(450, "💥 HERO VIP SHOVE SAVE!")


func _execute_shock_taser() -> void:
	if taser_cooldown > 0.0:
		_trigger_combo_banner("⚡ TASER RECHARGING (%.1fs)" % taser_cooldown)
		return
	taser_cooldown = progression.get_taser_cooldown()
	var stun_sec: float = progression.get_taser_stun_duration()
	var hits: int = 0

	for assassin: AssassinNpcLib in assassins:
		if assassin.ko_respawn_timer <= 0.0 and local_player.position.distance_to(assassin.position) <= 5.5:
			if assassin.apply_knockout_or_stun(stun_sec, true):
				progression.total_assassins_ko += 1
				hits += 1
				_award_farm_cash(900, "⚡ TASER ASSASSIN KO!")

	for guard: GuardNpcLib in guards:
		if not guard.is_eliminated and local_player.position.distance_to(guard.position) <= 5.2:
			guard.stun_with_taser(stun_sec)
			hits += 1

	_screen_flash_burst = 0.35
	if sfx != null:
		sfx.play_alert_chirp()
	if hits == 0:
		_trigger_combo_banner("⚡ SHOCK TASER FIRED (No hostile within 5.5m)")
	else:
		_trigger_combo_banner("⚡ SHOCK TASER HIT %d TARGET(S) FOR %.1fs!" % [hits, stun_sec])


func _try_throw_decoy_bottle() -> void:
	if decoy_bottles_left <= 0:
		_trigger_combo_banner("🍾 OUT OF BOTTLES! Pick up blue Champagne Bottles or upgrade at Tony's [U]!")
		return
	decoy_bottles_left -= 1
	var fwd: Vector3 = local_player.get_aim_direction()
	var landing_pos: Vector3 = wall_grid.resolve_position(
		local_player.position + fwd * 4.8, 0.35, not has_security_keycard
	)
	landing_pos.y = 0.0

	var dur: float = progression.get_decoy_duration_sec()
	var distracted_count: int = 0
	for guard: GuardNpcLib in guards:
		if guard.trigger_bottle_distraction(landing_pos, 9.0, dur):
			distracted_count += 1

	_screen_flash_burst = 0.28
	if sfx != null:
		sfx.play_bottle_throw()

	if DisplayServer.get_name() != "headless":
		var splash: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.72
		splash.mesh = torus
		splash.position = landing_pos + Vector3(0.0, 0.05, 0.0)
		var smat: StandardMaterial3D = StandardMaterial3D.new()
		smat.albedo_color = Color(0.28, 0.88, 1.0)
		smat.roughness = 0.25
		splash.material_override = smat
		add_child(splash)
		_decoy_markers.append(splash)

	if distracted_count > 0:
		_award_farm_cash(400 * distracted_count, "🍾 DECOY DISTRACTED %d GUARD(S)!" % distracted_count)
	else:
		_trigger_combo_banner("🍾 CHAMPAGNE DECOY THROWN (%d LEFT)" % decoy_bottles_left)


func _evaluate_loot_pickups() -> void:
	for item: LootPickupLib in loot_items:
		if item.collected:
			continue
		var picked: bool = item.check_pickup(local_player.position) or item.check_pickup(vip.position)
		if not picked:
			continue
		match item.loot_type:
			LootPickupLib.LootType.CHAMPAGNE_RESTOCK:
				decoy_bottles_left = mini(progression.get_max_decoy_bottles(), decoy_bottles_left + 1)
				_award_farm_cash(item.cash_value, "🍾 +1 DECOY BOTTLE FOUND!")
			LootPickupLib.LootType.SECURITY_KEYCARD:
				has_security_keycard = true
				_set_gate_locked_for_all(false)
				_award_farm_cash(item.cash_value, "🗝️ GOLD KEYCARD ACQUIRED — SOLID LASER GATE UNLOCKED!")
			_:
				_award_farm_cash(item.cash_value, item.title + " COLLECTED!")


func _set_gate_locked_for_all(locked: bool) -> void:
	vip.security_gate_locked = locked
	local_player.security_gate_locked = locked
	partner_bot.security_gate_locked = locked
	for g: GuardNpcLib in guards:
		g.security_gate_locked = locked
	for a: AssassinNpcLib in assassins:
		a.security_gate_locked = locked
	for pk: Variant in remote_players.keys():
		var rp: BodyguardPlayerLib = remote_players[pk]
		rp.security_gate_locked = locked


func _evaluate_contract_objectives(delta: float) -> void:
	if contract_ended or vip.state == VipStateMachineLib.VipState.EXPOSED or vip.state == VipStateMachineLib.VipState.EXTRACTED:
		return

	var vip_corpse: bool = (vip.state == VipStateMachineLib.VipState.CORPSE)
	var corpse_bluff_valid: bool = (not vip_corpse) or (vip.grabber_count > 0 and vip.authoritative_voice_rms >= 0.08)

	if not press_completed:
		if vip.position.distance_to(PRESS_STAGE_POS) <= 3.2:
			if corpse_bluff_valid:
				press_progress_sec += delta
				if press_progress_sec >= PRESS_HOLD_SEC:
					press_completed = true
					_award_farm_cash(1600, "📸 [1/4] PRESS PHOTO-OP COMPLETE!")
			else:
				active_guard_bark = "📸 Press Stage requires VIP propped [E] + talking [V] if dead!"
		return

	if not auction_completed:
		if vip.position.distance_to(AUCTION_PODIUM_POS) <= 3.2:
			if corpse_bluff_valid:
				auction_progress_sec += delta
				if auction_progress_sec >= AUCTION_HOLD_SEC:
					auction_completed = true
					_award_farm_cash(2000, "🎤 [2/4] CHARITY AUCTION COMPLETE! GRAB EAST VAULT KEYCARD!")
			else:
				active_guard_bark = "🎤 Crowd is watching! Prop VIP [E] & hold [V] to bluff speech!"
		return

	if not has_security_keycard:
		return

	if vip.position.distance_to(EXTRACTION_POS) <= EXTRACTION_RADIUS:
		if (not vip_corpse) or vip.grabber_count > 0:
			extraction_progress_sec += delta
			if extraction_progress_sec >= EXTRACTION_HOLD_SEC:
				_complete_contract_victory()
		else:
			active_guard_bark = "🚘 Prop VIP corpse [E] inside the green Limo ring!"
	else:
		extraction_progress_sec = maxf(0.0, extraction_progress_sec - delta * 0.45)


func _complete_contract_victory() -> void:
	if contract_ended:
		return
	contract_ended = true
	contract_victory = true
	var was_corpse: bool = (vip.state == VipStateMachineLib.VipState.CORPSE)
	vip.mark_extracted_authoritative(true)
	var award: int = progression.record_contract_victory(was_corpse)
	quota_cash = progression.bank_cash
	contract_earned_cash += award
	_screen_flash_burst = 0.50
	var next_cfg: Dictionary = LevelThemesLib.get_level_config(progression.contract_night)
	var mode_txt: String = "CORPSE BLUFF LEGEND!" if was_corpse else "FLAWLESS EXTRACTION!"
	_trigger_combo_banner("🏆 %s (+$%d) -> READY FOR %s!" % [mode_txt, award, String(next_cfg["display_name"])])
	if sfx != null:
		sfx.play_cash_reward()
	if DisplayServer.get_name() != "headless":
		_set_shop_state(true)


func _award_farm_cash(base_amount: int, banner_msg: String) -> void:
	var gained: int = int(round(float(base_amount) * combo_mult))
	progression.add_cash(gained)
	quota_cash = progression.bank_cash
	contract_earned_cash += gained
	combo_mult = minf(4.0, combo_mult + 0.25)
	combo_decay_timer = 11.0
	_trigger_combo_banner("%s  +$%d (Combo x%.2f)" % [banner_msg, gained, combo_mult])
	if sfx != null:
		sfx.play_cash_reward()


func _assign_nearest_hazard_whim() -> void:
	if hazards.is_empty():
		return
	var best_h: HazardZoneLib = hazards[0]
	var best_dist: float = 99999.0
	for h: HazardZoneLib in hazards:
		var d: float = vip.position.distance_to(h.position)
		if d < best_dist:
			best_dist = d
			best_h = h
	vip.suicidal_target = best_h.position
	vip.suicidal_whim_label = best_h.hazard_title


func _get_current_objective_pos() -> Vector3:
	if not press_completed:
		return PRESS_STAGE_POS
	if not auction_completed:
		return AUCTION_PODIUM_POS
	if not has_security_keycard:
		return KEYCARD_LOUNGE_POS
	return EXTRACTION_POS


func _trigger_combo_banner(msg: String) -> void:
	combo_popup_text = msg
	combo_popup_timer = 4.0


func _set_shop_state(is_open: bool) -> void:
	shop_open = is_open
	if hud != null:
		var next_cfg: Dictionary = LevelThemesLib.get_level_config(progression.contract_night)
		hud.set_shop_visible(shop_open, progression, contract_ended, contract_victory, String(next_cfg["display_name"]))


func _on_upgrade_requested(upgrade_id: String) -> void:
	if progression.purchase_upgrade(upgrade_id):
		quota_cash = progression.bank_cash
		_apply_progression_stats()
		if sfx != null:
			sfx.play_cash_reward()
		_trigger_combo_banner("⬆️ BIG TONY INSTALLED: %s (Lv %d)" % [upgrade_id.to_upper(), progression.get_level(upgrade_id)])
	if hud != null:
		var next_cfg: Dictionary = LevelThemesLib.get_level_config(progression.contract_night)
		hud.refresh_shop(progression, contract_ended, contract_victory, String(next_cfg["display_name"]))


func _apply_progression_stats() -> void:
	if local_player != null:
		local_player.carry_speed_mult = progression.get_carry_speed_multiplier()
		local_player.grab_range_bonus = progression.get_grab_range_bonus()
		local_player.sprint_speed_mult = progression.get_sprint_speed_multiplier()
		local_player.stamina_regen_mult = progression.get_stamina_regen_multiplier()
	if partner_bot != null:
		partner_bot.carry_speed_mult = progression.get_carry_speed_multiplier()
		partner_bot.grab_range_bonus = progression.get_grab_range_bonus()
	if vip != null:
		vip.wander_speed_multiplier = progression.get_vip_wander_multiplier()
		var target_max: float = progression.get_vip_max_hp()
		if target_max > vip.max_health:
			var diff: float = target_max - vip.max_health
			vip.max_health = target_max
			if vip.state == VipStateMachineLib.VipState.ALIVE:
				vip.health += diff
	decoy_bottles_left = maxi(decoy_bottles_left, progression.get_max_decoy_bottles())


func _deploy_or_restart_level() -> void:
	var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if not is_host:
		return
	shop_open = false
	contract_ended = false
	contract_victory = false
	press_progress_sec = 0.0
	press_completed = false
	auction_progress_sec = 0.0
	auction_completed = false
	has_security_keycard = false
	extraction_progress_sec = 0.0
	contract_earned_cash = 0
	combo_mult = 1.0
	combo_decay_timer = 0.0
	taser_cooldown = 0.0
	plasma_cooldown = 0.0
	cryo_cooldown = 0.0
	decoy_bottles_left = progression.get_max_decoy_bottles()

	# Clear active projectiles & decoy splashes cleanly (0 orphan nodes!)
	for b: ProjectileBoltLib in projectiles:
		if is_instance_valid(b):
			b.free()
	projectiles.clear()
	for m: Node3D in _decoy_markers:
		if is_instance_valid(m):
			m.free()
	_decoy_markers.clear()

	# Rebuild level theme visuals & wall grid for the new Venue Level!
	_rebuild_level_architecture()
	if vendor_booth != null:
		vendor_booth.configure_booth(VENDOR_POS, current_theme["accent_color"])

	vip.reset_vip_authoritative(VIP_SPAWN_POS, true, progression.get_vip_max_hp())
	local_player.position = PLAYER1_SPAWN_POS
	local_player.velocity = Vector3.ZERO
	local_player.stamina = 100.0
	partner_bot.position = PARTNER_SPAWN_POS
	partner_bot.velocity = Vector3.ZERO
	_set_gate_locked_for_all(true)

	# Respawn all 14 loot pickups & scale all Guards and Assassins to new Level HP & Speed!
	var g_hp: float = float(current_theme["guard_max_hp"])
	var a_hp: float = float(current_theme["assassin_max_hp"])
	var spd_m: float = float(current_theme["enemy_speed_mult"])

	for item: LootPickupLib in loot_items:
		item.collected = false
		item.visible = true
	for guard: GuardNpcLib in guards:
		guard.configure_patrol(guard.guard_title, guard.waypoints, g_hp, spd_m)
	for assassin: AssassinNpcLib in assassins:
		assassin.configure_assassin(assassin.assassin_name, assassin.spawn_origin, spd_m, a_hp)

	_apply_progression_stats()
	_set_shop_state(false)
	_trigger_combo_banner("🌃 DEPLOYED %s — GUARDS: %.0f HP | ASSASSINS: %.0f HP!" % [String(current_theme["display_name"]), g_hp, a_hp])


func _rebuild_level_architecture() -> void:
	current_theme = LevelThemesLib.get_level_config(progression.contract_night)
	if _env_root != null and is_instance_valid(_env_root):
		_env_root.free()
		_env_root = null
	if _arch_root != null and is_instance_valid(_arch_root):
		_arch_root.free()
		_arch_root = null

	var env_res: Dictionary = GalaVisualComposerLib.build_hdr_environment(self, current_theme)
	_env_root = env_res["env_root"]
	_flare_shader_mat = env_res["flare_mat"]

	var arch_res: Dictionary = GalaVisualComposerLib.build_estate_architecture(
		self,
		wall_grid,
		current_theme,
		VENDOR_POS,
		PRESS_STAGE_POS,
		AUCTION_PODIUM_POS,
		SECURITY_GATE_Z,
		EXTRACTION_POS,
		EXTRACTION_RADIUS
	)
	_arch_root = arch_res["arch_root"]
	laser_gate_node = arch_res["gate_root"]


func _spawn_entities() -> void:
	transport = NetworkTransportLib.new()
	transport.name = "NetworkTransport"
	transport.peer_connected_safe.connect(_on_remote_peer_connected)
	transport.peer_disconnected_safe.connect(_on_remote_peer_disconnected)
	transport.validated_intent_received.connect(_on_remote_intent_received)
	transport.vip_snapshot_received.connect(_on_client_vip_snapshot)
	add_child(transport)

	# Starting-Lobby Arms Dealer Booth ("Big Tony's Black-Market Armory")
	vendor_booth = VendorBoothLib.new()
	vendor_booth.name = "BigTonysArmory"
	vendor_booth.configure_booth(VENDOR_POS, current_theme["accent_color"])
	add_child(vendor_booth)

	vip = VipStateMachineLib.new()
	vip.name = "VIP"
	vip.managed_by_level = true
	vip.wall_grid = wall_grid
	vip.position = VIP_SPAWN_POS
	vip.security_gate_locked = true
	vip.security_gate_z = SECURITY_GATE_Z
	add_child(vip)

	local_player = BodyguardPlayerLib.new()
	local_player.name = "LocalBodyguard"
	local_player.peer_id = 1
	local_player.wall_grid = wall_grid
	local_player.position = PLAYER1_SPAWN_POS
	local_player.security_gate_locked = true
	local_player.security_gate_z = SECURITY_GATE_Z
	add_child(local_player)

	partner_bot = BodyguardPlayerLib.new()
	partner_bot.name = "PartnerBotBodyguard"
	partner_bot.is_ai_partner = true
	partner_bot.ai_assist_enabled = false
	partner_bot.wall_grid = wall_grid
	partner_bot.position = PARTNER_SPAWN_POS
	partner_bot.security_gate_locked = true
	partner_bot.security_gate_z = SECURITY_GATE_Z
	add_child(partner_bot)

	# 6 Lethal Hazards across the 52m x 136m Estate
	var hazard_specs: Array[Dictionary] = [
		{"t": HazardZoneLib.HazardType.POISON_FOUNTAIN, "name": "Exhibition Poison Fountain", "pos": Vector3(8.5, 0.0, 32.0), "r": 2.3},
		{"t": HazardZoneLib.HazardType.POISON_FOUNTAIN, "name": "Banquet Poison Fountain", "pos": Vector3(-8.5, 0.0, 4.0), "r": 2.3},
		{"t": HazardZoneLib.HazardType.SNIPER_LASER, "name": "Sky-Bridge Sniper Alpha", "pos": Vector3(0.0, 0.0, -29.0), "r": 1.9},
		{"t": HazardZoneLib.HazardType.SNIPER_LASER, "name": "Sky-Bridge Sniper Bravo", "pos": Vector3(3.5, 0.0, -39.0), "r": 1.9},
		{"t": HazardZoneLib.HazardType.SNIPER_LASER, "name": "Helipad Sniper Charlie", "pos": Vector3(-3.0, 0.0, -52.0), "r": 1.9},
		{"t": HazardZoneLib.HazardType.BALCONY_LEDGE, "name": "High-Voltage Terrace", "pos": Vector3(-16.5, 0.0, -34.0), "r": 2.4},
	]
	for hs: Dictionary in hazard_specs:
		var hz: HazardZoneLib = HazardZoneLib.new()
		hz.configure_hazard(int(hs["t"]) as HazardZoneLib.HazardType, String(hs["name"]), hs["pos"], float(hs["r"]))
		add_child(hz)
		hazards.append(hz)

	# 8 Patrolling Guards & Paparazzi with Escalating Level HP
	var g_hp: float = float(current_theme["guard_max_hp"])
	var spd_m: float = float(current_theme["enemy_speed_mult"])
	var guard_specs: Array[Dictionary] = [
		{"title": "Paparazzi Rex", "pts": [Vector3(-5.5, 0.0, 34.0), Vector3(5.5, 0.0, 34.0)]},
		{"title": "Gallery Guard", "pts": [Vector3(-12.0, 0.0, 26.0), Vector3(-5.0, 0.0, 20.0)]},
		{"title": "Inspector Vance", "pts": [Vector3(6.5, 0.0, 10.0), Vector3(-6.5, 0.0, 10.0)]},
		{"title": "Auction Chief", "pts": [Vector3(-6.0, 0.0, -4.0), Vector3(6.0, 0.0, -4.0)]},
		{"title": "East Vault Guard", "pts": [Vector3(14.5, 0.0, -2.0), Vector3(14.5, 0.0, -10.0)]},
		{"title": "Sky-Bridge Captain", "pts": [Vector3(-6.5, 0.0, -30.0), Vector3(6.5, 0.0, -30.0)]},
		{"title": "Terrace Patrol", "pts": [Vector3(9.5, 0.0, -42.0), Vector3(-9.5, 0.0, -42.0)]},
		{"title": "Limo Security Chief", "pts": [Vector3(-5.0, 0.0, -55.0), Vector3(5.0, 0.0, -55.0)]},
	]
	for spec: Dictionary in guard_specs:
		var g: GuardNpcLib = GuardNpcLib.new()
		var pts: Array[Vector3] = []
		for raw_pt: Variant in spec["pts"]:
			var v: Vector3 = raw_pt
			pts.append(v)
		g.wall_grid = wall_grid
		g.security_gate_locked = true
		g.configure_patrol(String(spec["title"]), pts, g_hp, spd_m)
		add_child(g)
		guards.append(g)

	# 3 Rival Assassins across the Estate
	var a_hp: float = float(current_theme["assassin_max_hp"])
	var assassin_specs: Array[Dictionary] = [
		{"name": "The Shadow", "pos": Vector3(-16.5, 0.0, 26.0)},
		{"name": "Crimson Blade", "pos": Vector3(-16.5, 0.0, -2.0)},
		{"name": "Red Viper", "pos": Vector3(15.0, 0.0, -52.0)},
	]
	for aspec: Dictionary in assassin_specs:
		var a: AssassinNpcLib = AssassinNpcLib.new()
		a.wall_grid = wall_grid
		a.security_gate_locked = true
		a.configure_assassin(String(aspec["name"]), aspec["pos"], spd_m, a_hp)
		add_child(a)
		assassins.append(a)

	# 14 Farmable Loot Pickups + Mandatory Gold Keycard in East Vault
	var loot_specs: Array[Dictionary] = [
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(9.0, 0.0, 52.0)},
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(-10.5, 0.0, 36.0)},
		{"t": LootPickupLib.LootType.CHAMPAGNE_RESTOCK, "pos": Vector3(11.0, 0.0, 26.0)},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(-18.0, 0.0, 28.0)},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(18.0, 0.0, 24.0)},
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(-11.0, 0.0, 9.0)},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(17.5, 0.0, 8.0)},
		{"t": LootPickupLib.LootType.SECURITY_KEYCARD, "pos": KEYCARD_LOUNGE_POS},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(-17.5, 0.0, -6.0)},
		{"t": LootPickupLib.LootType.CHAMPAGNE_RESTOCK, "pos": Vector3(9.0, 0.0, -26.0)},
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(-9.5, 0.0, -34.0)},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(16.5, 0.0, -38.0)},
		{"t": LootPickupLib.LootType.CHAMPAGNE_RESTOCK, "pos": Vector3(-12.5, 0.0, -52.0)},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(14.5, 0.0, -56.0)},
	]
	for ls: Dictionary in loot_specs:
		var item: LootPickupLib = LootPickupLib.new()
		item.configure_loot(int(ls["t"]) as LootPickupLib.LootType, ls["pos"])
		add_child(item)
		loot_items.append(item)


func _build_hud() -> void:
	hud = GalaHudLib.new()
	hud.name = "GalaHud"
	hud.upgrade_requested.connect(_on_upgrade_requested)
	hud.shop_close_requested.connect(func() -> void: _set_shop_state(false))
	hud.next_contract_requested.connect(_deploy_or_restart_level)
	hud.restart_contract_requested.connect(_deploy_or_restart_level)
	add_child(hud)


func _update_hud_display() -> void:
	if hud == null or vip == null:
		return

	var obj_text: String = ""
	if not press_completed:
		var d1: float = vip.position.distance_to(PRESS_STAGE_POS)
		obj_text = "OBJECTIVE [1/4]: Hold VIP at Press Photo-Op Stage (%.1f / %.1fs) — %.1fm ahead" % [press_progress_sec, PRESS_HOLD_SEC, d1]
	elif not auction_completed:
		var d2: float = vip.position.distance_to(AUCTION_PODIUM_POS)
		obj_text = "OBJECTIVE [2/4]: Hold VIP at Charity Auction Podium (%.1f / %.1fs) — %.1fm ahead" % [auction_progress_sec, AUCTION_HOLD_SEC, d2]
	elif not has_security_keycard:
		var d3: float = local_player.position.distance_to(KEYCARD_LOUNGE_POS)
		obj_text = "OBJECTIVE [3/4]: Grab GOLD KEYCARD in East Vault (%.1fm) to unlock Laser Gate!" % d3
	elif vip.state != VipStateMachineLib.VipState.EXTRACTED:
		var d4: float = vip.position.distance_to(EXTRACTION_POS)
		obj_text = "OBJECTIVE [4/4]: Hold VIP at Armored Limousine (%.1f / %.1fs) — %.1fm ahead" % [extraction_progress_sec, EXTRACTION_HOLD_SEC, d4]
	else:
		obj_text = "🏆 LEVEL CLEARED! Press [U] to Upgrade Weapons & Deploy Level %d!" % progression.contract_night

	var vip_pill: String = "🤵 VIP ALIVE (%.0f/%.0f HP)" % [vip.health, vip.max_health]
	var pill_col: Color = Color(0.32, 1.0, 0.52)
	if vip.state == VipStateMachineLib.VipState.CORPSE:
		vip_pill = "💀 CORPSE MODE — PROP [E] & BLUFF [V]! (Grabbers: %d)" % vip.grabber_count
		pill_col = Color(1.0, 0.68, 0.18)
	elif vip.state == VipStateMachineLib.VipState.EXPOSED:
		vip_pill = "🚨 BUSTED! PRESS [R] RETRY OR [U] SHOP"
		pill_col = Color(1.0, 0.28, 0.28)
	elif vip.state == VipStateMachineLib.VipState.EXTRACTED:
		vip_pill = "🏆 EXTRACTED! PRESS [U] FOR NEXT LEVEL"
		pill_col = Color(0.32, 0.92, 1.0)

	# Build compact live Radar Minimap data
	var radar_loot: Array[Vector3] = []
	for item: LootPickupLib in loot_items:
		if not item.collected:
			radar_loot.append(item.position)
	var radar_guards: Array[Dictionary] = []
	for g: GuardNpcLib in guards:
		if not g.is_eliminated:
			radar_guards.append({"pos": g.position, "frozen": g.frozen_timer > 0.0})
	var radar_assassins: Array[Dictionary] = []
	for a: AssassinNpcLib in assassins:
		if a.ko_respawn_timer <= 0.0:
			radar_assassins.append({"pos": a.position, "frozen": a.frozen_timer > 0.0})

	var dock: Dictionary = {
		"plasma": "🔫 [LMB/X]\nPLASMA %.0f" % progression.get_plasma_damage(),
		"cryo": "❄️ [RMB/Z]\n%s" % ("CRYO %.1fs" % progression.get_cryo_freeze_duration() if cryo_cooldown <= 0.05 else "%.1fs" % cryo_cooldown),
		"grab": "🤝 [E]\n%s" % ("HOLDING" if local_player.is_grabbing_vip else "GRAB VIP"),
		"tackle": "💥 [F]\nTACKLE",
		"bottle": "🍾 [Q]\nDECOY (%d)" % decoy_bottles_left,
		"taser": "⚡ [G]\n%s" % ("TASER" if taser_cooldown <= 0.05 else "%.1fs" % taser_cooldown),
		"voice": "🎙️ [V]\nBLUFF %.0f°" % vip.visual_jaw_angle_deg,
		"shop": "🛒 [U]\nSHOP ($%d)" % progression.bank_cash,
	}

	hud.update_hud_state({
		"title": "%s  |  %s  |  Combo x%.2f  |  [Tab] Bot:%s" % [
			String(current_theme["display_name"]),
			progression.get_agency_rank(),
			combo_mult,
			"ON" if partner_bot.ai_assist_enabled else "OFF",
		],
		"objective": obj_text,
		"cash_line": "BANK: $%d  (+$%d)" % [progression.bank_cash, contract_earned_cash],
		"toast": ("⚡ " + combo_popup_text) if combo_popup_timer > 0.0 else "",
		"vip_pill": vip_pill,
		"vip_pill_color": pill_col,
		"vip_max_hp": vip.max_health,
		"vip_hp": vip.health,
		"suspicion": vip.suspicion,
		"stamina": local_player.stamina,
		"jaw_deg": vip.visual_jaw_angle_deg,
		"radio": "📻 " + active_guard_bark,
		"dock": dock,
		"radar": {
			"gate_locked": not has_security_keycard,
			"walls": wall_grid.solid_boxes,
			"vendor_pos": VENDOR_POS,
			"obj_pos": _get_current_objective_pos(),
			"loot": radar_loot,
			"guards": radar_guards,
			"assassins": radar_assassins,
			"vip_pos": vip.position,
			"player_pos": local_player.position,
		},
	})


func _on_remote_peer_connected(peer_id: int) -> void:
	if peer_id == 1 or remote_players.has(peer_id):
		return
	var rp: BodyguardPlayerLib = BodyguardPlayerLib.new()
	rp.name = "RemoteBodyguard_%d" % peer_id
	rp.peer_id = peer_id
	rp.wall_grid = wall_grid
	rp.position = PLAYER1_SPAWN_POS + Vector3(float(remote_players.size() + 1) * 1.5, 0.0, 0.0)
	rp.security_gate_locked = not has_security_keycard
	rp.security_gate_z = SECURITY_GATE_Z
	add_child(rp)
	remote_players[peer_id] = rp


func _on_remote_peer_disconnected(peer_id: int) -> void:
	if remote_players.has(peer_id):
		var rp: BodyguardPlayerLib = remote_players[peer_id]
		remote_players.erase(peer_id)
		rp.queue_free()


func _on_remote_intent_received(sender_id: int, move_dir: Vector2, grab: bool, voice_rms: float) -> void:
	if not remote_players.has(sender_id):
		_on_remote_peer_connected(sender_id)
	var rp: BodyguardPlayerLib = remote_players[sender_id]
	rp.set_player_intent(move_dir, grab, voice_rms)


func _on_client_vip_snapshot(snapshot: PackedByteArray) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var data: Dictionary = RagdollPhysicsLib.unpack_quantized_snapshot(snapshot)
		vip.position = data["root_pos"]
		vip.facing_yaw_rad = float(data["yaw_rad"])
		vip.torso_tilt_rad = float(data["tilt_rad"])
		vip.visual_jaw_angle_deg = float(data["jaw_angle_deg"])
		vip.grabber_count = int(data["grabber_count"])
