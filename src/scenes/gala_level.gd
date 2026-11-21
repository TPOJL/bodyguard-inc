class_name GalaLevel
extends Node3D
## Full Playable 3D Co-op Game — BODYGUARD INC. ("The Penthouse Gala Estate").
## 4-Zone 104m multi-objective contract loop, loot farming, Rival Assassins,
## persistent Agency Bank & 6-tree Upgrade Shop [U], Shock Taser [G], Decoy Bottles [Q],
## tasteful Forward+ HDR glints ("Норм Блики") & sleek broadcast HUD.

const NetworkTransportLib := preload("res://src/core/network_transport.gd")
const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")
const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")
const AgencyProgressionLib := preload("res://src/core/agency_progression.gd")
const SynthSfxLib := preload("res://src/core/synth_sfx.gd")
const VipStateMachineLib := preload("res://src/vip/vip_state_machine.gd")
const BodyguardPlayerLib := preload("res://src/player/bodyguard_player.gd")
const GuardNpcLib := preload("res://src/world/guard_npc.gd")
const HazardZoneLib := preload("res://src/world/hazard_zone.gd")
const LootPickupLib := preload("res://src/world/loot_pickup.gd")
const AssassinNpcLib := preload("res://src/world/assassin_npc.gd")
const GalaVisualComposerLib := preload("res://src/world/gala_visual_composer.gd")
const GalaHudLib := preload("res://src/ui/gala_hud.gd")

const VIP_SPAWN_POS: Vector3 = Vector3(0.0, 0.0, 44.0)
const PLAYER1_SPAWN_POS: Vector3 = Vector3(-2.0, 0.0, 45.2)
const PARTNER_SPAWN_POS: Vector3 = Vector3(2.2, 0.0, 45.2)

const PRESS_STAGE_POS: Vector3 = Vector3(0.0, 0.0, 30.0)
const AUCTION_PODIUM_POS: Vector3 = Vector3(0.0, 0.0, 4.0)
const KEYCARD_LOUNGE_POS: Vector3 = Vector3(10.2, 0.0, -4.0)
const SECURITY_GATE_Z: float = -14.0
const EXTRACTION_POS: Vector3 = Vector3(0.0, 0.0, -46.0)
const EXTRACTION_RADIUS: float = 2.8

const PRESS_HOLD_SEC: float = 3.5
const AUCTION_HOLD_SEC: float = 4.0
const EXTRACTION_HOLD_SEC: float = 5.0
const TARGET_QUOTA_CASH: int = 10000

var transport: NetworkTransportLib = null
var audio_driver: AudioInputDriverLib = null
var progression: AgencyProgressionLib = null
var sfx: SynthSfxLib = null
var hud: GalaHudLib = null

var vip: VipStateMachineLib = null
var local_player: BodyguardPlayerLib = null
var partner_bot: BodyguardPlayerLib = null
var remote_players: Dictionary = {}
var guards: Array[GuardNpcLib] = []
var hazards: Array[HazardZoneLib] = []
var loot_items: Array[LootPickupLib] = []
var assassins: Array[AssassinNpcLib] = []
var laser_gate_node: Node3D = null

# Authoritative contract state (Host)
var quota_cash: int = 0
var contract_earned_cash: int = 0
var combo_mult: float = 1.0
var combo_decay_timer: float = 0.0
var decoy_bottles_left: int = 3
var taser_cooldown: float = 0.0

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
var network_status_label: String = "Solo ([H] Host / [J] Join)"
var active_guard_bark: String = "Escort VIP to Press Stage (North) -> Auction -> Keycard -> Limo!"
var combo_popup_text: String = "NIGHT 1: COMPLETE 4 OBJECTIVES & FARM LOOT FOR UPGRADES [U]!"
var combo_popup_timer: float = 4.5

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

	sfx = SynthSfxLib.new()
	sfx.name = "SynthSfx"
	add_child(sfx)

	_build_environment_and_arena()
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

	# 1. Step bodyguards (Local Player + AI Partner if toggled + Remote Clients)
	var active_goal: Vector3 = _get_current_objective_pos()
	local_player.step_bodyguard_physics(delta, vip, active_goal)
	partner_bot.step_bodyguard_physics(delta, vip, active_goal)

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

	# 2. Suicidal VIP always gravitates toward the nearest active lethal hazard!
	_assign_nearest_hazard_whim()

	# 3. Apply critically-damped grab spring-damper forces & step VIP physics
	vip.apply_grab_spring_authoritative(grab_anchors, delta, true)
	vip.step_simulation(delta)

	# 4. Evaluate Loot Pickups & Gold Security Keycard
	_evaluate_loot_pickups()

	# 5. Evaluate Lethal Hazards (Fountains, Sniper Lasers, Balcony)
	var vip_alive: bool = (vip.state == VipStateMachineLib.VipState.ALIVE)
	for hazard: HazardZoneLib in hazards:
		var dmg: float = hazard.step_hazard_physics(delta, vip.position, vip_alive)
		if dmg > 0.0:
			vip.apply_damage_authoritative(dmg, true, hazard.hazard_title)
			_camera_shake_trauma = minf(1.0, _camera_shake_trauma + 0.45)
			_screen_flash_burst = 0.55
			if vip.state == VipStateMachineLib.VipState.CORPSE:
				_trigger_combo_banner("💀 VIP KILLED BY %s! PROP CORPSE [E] & BLUFF GUARDS [V]!" % hazard.hazard_title)
				if sfx != null:
					sfx.play_alert_chirp()

	# 6. Evaluate Rival Assassins hunting the VIP
	for assassin: AssassinNpcLib in assassins:
		var admg: float = assassin.step_assassin_physics(delta, vip.position, vip_alive)
		if admg > 0.0:
			vip.apply_damage_authoritative(admg, true, assassin.assassin_name)
			_camera_shake_trauma = minf(1.0, _camera_shake_trauma + 0.55)
			_screen_flash_burst = 0.65
			_trigger_combo_banner("🗡️ %s STRUCK THE VIP! TACKLE [F] OR TASER [G] HIM!" % assassin.assassin_name)
			if sfx != null:
				sfx.play_alert_chirp()

	# 7. Evaluate Patrolling Security Guards & Paparazzi
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
			_screen_flash_burst = maxf(_screen_flash_burst, 0.35)
		if guard.is_inspecting_vip:
			priority_bark = guard.last_inspection_bark
			if vip_corpse and vip.grabber_count > 0 and tuned_delta < 0.0 and _bluff_score_cooldown <= 0.0:
				_award_farm_cash(350, "🎙️ WEEKEND AT BERNIE'S BLUFF!")
				_bluff_score_cooldown = 2.0

	if vip.state == VipStateMachineLib.VipState.EXPOSED and not contract_ended:
		contract_ended = true
		contract_victory = false
		_trigger_combo_banner("🚨 COVER BLOWN! PRESS [U] TO UPGRADE GEAR OR [R] TO RETRY!")
		if sfx != null:
			sfx.play_alert_chirp()
		if DisplayServer.get_name() != "headless":
			_set_shop_state(true)

	if priority_bark != "":
		active_guard_bark = priority_bark
	elif vip_corpse and vip.grabber_count <= 0:
		active_guard_bark = "💀 VIP CORPSE ON FLOOR! Hold [E] to prop him up before a guard spots him!"
	elif vip_corpse:
		active_guard_bark = "🕶️ Carrying Corpse! Hold [V] past guards or toss Decoy Bottle [Q]!"
	else:
		active_guard_bark = "🤵 VIP heading for %s — Grab [E] & steer toward active objective!" % vip.suicidal_whim_label

	# 8. Evaluate Mandatory 4-Stage Contract Objectives
	_evaluate_contract_objectives(delta)

	# 9. Broadcast <=20 Hz quantized ragdoll snapshot if multiplayer session is active
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
	# Strictly visual camera smoothing, subtle post-FX parameters, animations & HUD rendering
	if not is_finite(delta) or delta <= 0.0:
		return

	_camera_shake_trauma = maxf(0.0, _camera_shake_trauma - delta * 2.4)
	_screen_flash_burst = maxf(0.0, _screen_flash_burst - delta * 3.4)

	if local_player != null and vip != null:
		local_player.update_visuals(vip.position)
	if partner_bot != null and vip != null:
		partner_bot.update_visuals(vip.position)
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

	var focus: Vector3 = (local_player.position * 0.62) + (vip.position * 0.38)
	var cam_offset: Vector3 = Vector3(0.0, 11.8, 10.6)
	var look_height: float = 1.0
	var target_fov: float = 55.0

	if camera_mode == 1:
		cam_offset = Vector3(0.0, 5.0, 6.6)
		look_height = 1.35
		target_fov = 62.0
	elif camera_mode == 2:
		cam_offset = Vector3(0.0, 18.5, 13.5)
		look_height = 0.5
		target_fov = 50.0

	if local_player.is_sprinting:
		target_fov += 3.5

	var shake_vec: Vector3 = Vector3.ZERO
	if _camera_shake_trauma > 0.01:
		var amt: float = _camera_shake_trauma * _camera_shake_trauma * 0.38
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


func _poll_local_inputs_physics() -> void:
	# Shop toggle [U] or Escape
	if _key_just_pressed(KEY_U) or (shop_open and _key_just_pressed(KEY_ESCAPE)):
		_set_shop_state(not shop_open)
		return

	# Hotkeys 1..6 purchase upgrades directly when shop is open
	if shop_open:
		var num_keys: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
		for i: int in range(num_keys.size()):
			if _key_just_pressed(num_keys[i]):
				var uid: String = String(AgencyProgressionLib.UPGRADE_CATALOG[i]["id"])
				_on_upgrade_requested(uid)
		if _key_just_pressed(KEY_R):
			_restart_mission()
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

	# [F] Hero Dive-Tackle (knocks VIP out of hazards OR knocks out nearby Rival Assassin!)
	if _key_just_pressed(KEY_F):
		_execute_hero_tackle()

	# [G] Shock Taser Baton (stuns nearby Assassins & Guards!)
	if _key_just_pressed(KEY_G):
		_execute_shock_taser()

	# [Q] Throw Decoy Champagne Bottle
	if _key_just_pressed(KEY_Q):
		_try_throw_decoy_bottle()

	# [C] Cycle Camera Angle
	if _key_just_pressed(KEY_C):
		camera_mode = (camera_mode + 1) % 3
		var cam_names: Array[String] = ["CINEMATIC FOLLOW", "CLOSE ACTION CAM", "TACTICAL OVERVIEW"]
		_trigger_combo_banner("🎥 CAMERA: %s" % cam_names[camera_mode])

	# [K] Instant Kill VIP (Test Weekend at Bernie's Corpse Mode)
	if _key_just_pressed(KEY_K):
		var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
		if vip.state == VipStateMachineLib.VipState.ALIVE:
			vip.apply_damage_authoritative(vip.max_health + 50.0, is_host, "Poisoned Martini ([K])")
			_camera_shake_trauma = 0.55
			_screen_flash_burst = 0.55
			_trigger_combo_banner("💀 WEEKEND AT BERNIE'S MODE! HOLD [E] TO PROP CORPSE & [V] TO BLUFF!")
			if sfx != null:
				sfx.play_alert_chirp()

	if _key_just_pressed(KEY_R):
		_restart_mission()

	if _key_just_pressed(KEY_TAB):
		partner_bot.ai_assist_enabled = not partner_bot.ai_assist_enabled
		_trigger_combo_banner("🕶️ AI CO-OP PARTNER: %s" % ("ENABLED" if partner_bot.ai_assist_enabled else "OFF"))

	if _key_just_pressed(KEY_H):
		var err: Error = transport.host_session(17777, 3)
		network_status_label = "HOSTING :17777" if err == OK else "Host err %d" % err

	if _key_just_pressed(KEY_J):
		var err: Error = transport.join_session("127.0.0.1", 17777)
		network_status_label = "CLIENT :17777" if err == OK else "Join err %d" % err


func _execute_hero_tackle() -> void:
	# Priority 1: KO any Rival Assassin within 3.8m!
	for assassin: AssassinNpcLib in assassins:
		if assassin.ko_respawn_timer <= 0.0 and local_player.position.distance_to(assassin.position) <= 3.8:
			if assassin.apply_knockout_or_stun(0.0, true):
				progression.total_assassins_ko += 1
				_camera_shake_trauma = 0.65
				_screen_flash_burst = 0.45
				_award_farm_cash(800, "💥 ASSASSIN KNOCKED OUT!")
				if sfx != null:
					sfx.play_shove_whoosh()
				return

	# Priority 2: Shove VIP away from sniper laser / hazard
	var imp: Vector3 = local_player.try_shove_vip(vip)
	if imp.length_squared() > 0.01:
		var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
		vip.apply_shove_impulse_authoritative(imp, is_host)
		_camera_shake_trauma = 0.50
		_screen_flash_burst = 0.35
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
		if assassin.ko_respawn_timer <= 0.0 and local_player.position.distance_to(assassin.position) <= 5.2:
			if assassin.apply_knockout_or_stun(stun_sec, true):
				progression.total_assassins_ko += 1
				hits += 1
				_award_farm_cash(850, "⚡ TASER ASSASSIN KO!")

	for guard: GuardNpcLib in guards:
		if local_player.position.distance_to(guard.position) <= 4.8:
			guard.stun_with_taser(stun_sec)
			hits += 1

	_screen_flash_burst = 0.40
	if sfx != null:
		sfx.play_alert_chirp()
	if hits == 0:
		_trigger_combo_banner("⚡ SHOCK TASER FIRED (No hostile in 5m range)")
	else:
		_trigger_combo_banner("⚡ SHOCK TASER HIT %d TARGET(S) FOR %.1fs!" % [hits, stun_sec])


func _try_throw_decoy_bottle() -> void:
	if decoy_bottles_left <= 0:
		_trigger_combo_banner("🍾 OUT OF BOTTLES! Pick up blue Champagne Bottles or upgrade Utility Belt [U]!")
		return
	decoy_bottles_left -= 1
	var fwd: Vector3 = Vector3(sin(local_player.facing_yaw_rad), 0.0, cos(local_player.facing_yaw_rad))
	var landing_pos: Vector3 = local_player.position + fwd * 4.5
	landing_pos.x = clampf(landing_pos.x, -13.0, 13.0)
	landing_pos.z = clampf(landing_pos.z, -50.0, 46.0)
	landing_pos.y = 0.0

	var dur: float = progression.get_decoy_duration_sec()
	var distracted_count: int = 0
	for guard: GuardNpcLib in guards:
		if guard.trigger_bottle_distraction(landing_pos, 8.5, dur):
			distracted_count += 1

	_screen_flash_burst = 0.30
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
				vip.security_gate_locked = false
				local_player.security_gate_locked = false
				partner_bot.security_gate_locked = false
				_award_farm_cash(item.cash_value, "🗝️ GOLD KEYCARD ACQUIRED — SKY-BRIDGE LASER GATE UNLOCKED!")
			_:
				_award_farm_cash(item.cash_value, item.title + " COLLECTED!")


func _evaluate_contract_objectives(delta: float) -> void:
	if contract_ended or vip.state == VipStateMachineLib.VipState.EXPOSED or vip.state == VipStateMachineLib.VipState.EXTRACTED:
		return

	var vip_corpse: bool = (vip.state == VipStateMachineLib.VipState.CORPSE)
	var corpse_bluff_valid: bool = (not vip_corpse) or (vip.grabber_count > 0 and vip.authoritative_voice_rms >= 0.08)

	# Objective 1: Press Photo-Op Stage (Zone 1)
	if not press_completed:
		if vip.position.distance_to(PRESS_STAGE_POS) <= 3.0:
			if corpse_bluff_valid:
				press_progress_sec += delta
				if press_progress_sec >= PRESS_HOLD_SEC:
					press_completed = true
					_award_farm_cash(1500, "📸 [1/4] PRESS PHOTO-OP COMPLETE!")
			else:
				active_guard_bark = "📸 Press Stage requires VIP propped [E] + talking [V] if he's dead!"
		return

	# Objective 2: Charity Auction Podium (Zone 2)
	if not auction_completed:
		if vip.position.distance_to(AUCTION_PODIUM_POS) <= 3.0:
			if corpse_bluff_valid:
				auction_progress_sec += delta
				if auction_progress_sec >= AUCTION_HOLD_SEC:
					auction_completed = true
					_award_farm_cash(1800, "🎤 [2/4] CHARITY AUCTION SPEECH COMPLETE! NOW GRAB EAST LOUNGE KEYCARD!")
			else:
				active_guard_bark = "🎤 Auction Crowd is staring! Prop VIP [E] & hold [V] to fake his speech!"
		return

	# Objective 3: Keycard unlock checked via loot pickup -> Gate at z = -14 unlocks!
	if not has_security_keycard:
		return

	# Objective 4: Armored Limousine Extraction Hold (5.0s countdown at Zone 4!)
	if vip.position.distance_to(EXTRACTION_POS) <= EXTRACTION_RADIUS:
		if (not vip_corpse) or vip.grabber_count > 0:
			extraction_progress_sec += delta
			if extraction_progress_sec >= EXTRACTION_HOLD_SEC:
				_complete_contract_victory()
		else:
			active_guard_bark = "🚘 Prop the VIP corpse [E] inside the green Limo ring to load him in!"
	else:
		extraction_progress_sec = maxf(0.0, extraction_progress_sec - delta * 0.5)


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
	_screen_flash_burst = 0.55
	var mode_txt: String = "WEEKEND AT BERNIE'S CORPSE BLUFF LEGEND!" if was_corpse else "FLAWLESS LIVE VIP EXTRACTION!"
	_trigger_combo_banner("🏆 %s (+$%d -> BANK: $%d)" % [mode_txt, award, progression.bank_cash])
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
	combo_decay_timer = 10.0
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
	combo_popup_timer = 3.8


func _set_shop_state(is_open: bool) -> void:
	shop_open = is_open
	if hud != null:
		hud.set_shop_visible(shop_open, progression, contract_ended, contract_victory)


func _on_upgrade_requested(upgrade_id: String) -> void:
	if progression.purchase_upgrade(upgrade_id):
		quota_cash = progression.bank_cash
		_apply_progression_stats()
		if sfx != null:
			sfx.play_cash_reward()
		_trigger_combo_banner("⬆️ UPGRADE INSTALLED: %s (Lv %d)" % [upgrade_id.to_upper(), progression.get_level(upgrade_id)])
	if hud != null:
		hud.refresh_shop(progression, contract_ended, contract_victory)


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


func _restart_mission() -> void:
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
	decoy_bottles_left = progression.get_max_decoy_bottles()

	vip.reset_vip_authoritative(VIP_SPAWN_POS, true, progression.get_vip_max_hp())
	vip.security_gate_locked = true
	vip.security_gate_z = SECURITY_GATE_Z

	local_player.position = PLAYER1_SPAWN_POS
	local_player.velocity = Vector3.ZERO
	local_player.stamina = 100.0
	local_player.security_gate_locked = true
	local_player.security_gate_z = SECURITY_GATE_Z

	partner_bot.position = PARTNER_SPAWN_POS
	partner_bot.velocity = Vector3.ZERO
	partner_bot.security_gate_locked = true
	partner_bot.security_gate_z = SECURITY_GATE_Z

	for m: Node3D in _decoy_markers:
		if is_instance_valid(m):
			m.free()
	_decoy_markers.clear()

	# Respawn all loot pickups & escalate assassin speed with Night level
	var night_speed_mult: float = 1.0 + float(progression.contract_night - 1) * 0.14
	for item: LootPickupLib in loot_items:
		item.collected = false
		item.visible = true
	for assassin: AssassinNpcLib in assassins:
		assassin.configure_assassin(assassin.assassin_name, assassin.spawn_origin, night_speed_mult)

	_apply_progression_stats()
	_set_shop_state(false)
	_trigger_combo_banner("🌃 NIGHT %d DEPLOYED! COMPLETE ALL 4 OBJECTIVES TO EXTRACT!" % progression.contract_night)


func _build_environment_and_arena() -> void:
	_camera = Camera3D.new()
	_camera.name = "FollowCamera"
	_camera.position = Vector3(0.0, 12.0, 55.0)
	_camera.fov = 55.0
	_camera.current = true
	add_child(_camera)

	_flare_shader_mat = GalaVisualComposerLib.build_hdr_environment(self)
	laser_gate_node = GalaVisualComposerLib.build_estate_architecture(
		self,
		PRESS_STAGE_POS,
		AUCTION_PODIUM_POS,
		SECURITY_GATE_Z,
		EXTRACTION_POS,
		EXTRACTION_RADIUS
	)


func _spawn_entities() -> void:
	transport = NetworkTransportLib.new()
	transport.name = "NetworkTransport"
	transport.peer_connected_safe.connect(_on_remote_peer_connected)
	transport.peer_disconnected_safe.connect(_on_remote_peer_disconnected)
	transport.validated_intent_received.connect(_on_remote_intent_received)
	transport.vip_snapshot_received.connect(_on_client_vip_snapshot)
	add_child(transport)

	vip = VipStateMachineLib.new()
	vip.name = "VIP"
	vip.managed_by_level = true
	vip.position = VIP_SPAWN_POS
	vip.security_gate_locked = true
	vip.security_gate_z = SECURITY_GATE_Z
	add_child(vip)

	local_player = BodyguardPlayerLib.new()
	local_player.name = "LocalBodyguard"
	local_player.peer_id = 1
	local_player.position = PLAYER1_SPAWN_POS
	local_player.security_gate_locked = true
	local_player.security_gate_z = SECURITY_GATE_Z
	add_child(local_player)

	partner_bot = BodyguardPlayerLib.new()
	partner_bot.name = "PartnerBotBodyguard"
	partner_bot.is_ai_partner = true
	partner_bot.ai_assist_enabled = false
	partner_bot.position = PARTNER_SPAWN_POS
	partner_bot.security_gate_locked = true
	partner_bot.security_gate_z = SECURITY_GATE_Z
	add_child(partner_bot)

	# 5 Lethal Hazards across the 4 Estate Zones
	var hazard_specs: Array[Dictionary] = [
		{"t": HazardZoneLib.HazardType.POISON_FOUNTAIN, "name": "Foyer Poison Fountain", "pos": Vector3(6.8, 0.0, 35.0), "r": 2.3},
		{"t": HazardZoneLib.HazardType.POISON_FOUNTAIN, "name": "Banquet Poison Fountain", "pos": Vector3(-6.8, 0.0, 10.0), "r": 2.3},
		{"t": HazardZoneLib.HazardType.SNIPER_LASER, "name": "Sky-Bridge Sniper Alpha", "pos": Vector3(0.0, 0.0, -21.0), "r": 1.9},
		{"t": HazardZoneLib.HazardType.SNIPER_LASER, "name": "Sky-Bridge Sniper Bravo", "pos": Vector3(2.5, 0.0, -31.0), "r": 1.9},
		{"t": HazardZoneLib.HazardType.BALCONY_LEDGE, "name": "High-Voltage Terrace Ledge", "pos": Vector3(-11.2, 0.0, -25.0), "r": 2.4},
	]
	for hs: Dictionary in hazard_specs:
		var hz: HazardZoneLib = HazardZoneLib.new()
		hz.configure_hazard(int(hs["t"]) as HazardZoneLib.HazardType, String(hs["name"]), hs["pos"], float(hs["r"]))
		add_child(hz)
		hazards.append(hz)

	# 6 Patrolling Security Guards & Paparazzi across the 4 Zones
	var guard_specs: Array[Dictionary] = [
		{"title": "Paparazzi Rex", "pts": [Vector3(-4.5, 0.0, 33.0), Vector3(4.5, 0.0, 33.0)]},
		{"title": "Inspector Vance", "pts": [Vector3(5.5, 0.0, 16.0), Vector3(-5.5, 0.0, 16.0)]},
		{"title": "Auction Chief", "pts": [Vector3(-5.0, 0.0, 2.0), Vector3(5.0, 0.0, 2.0)]},
		{"title": "Lounge Bouncer", "pts": [Vector3(8.5, 0.0, -1.5), Vector3(8.5, 0.0, -7.0)]},
		{"title": "Sky-Bridge Captain", "pts": [Vector3(-5.0, 0.0, -24.0), Vector3(5.0, 0.0, -24.0)]},
		{"title": "Limo Security Chief", "pts": [Vector3(-4.2, 0.0, -41.0), Vector3(4.2, 0.0, -41.0)]},
	]
	for spec: Dictionary in guard_specs:
		var g: GuardNpcLib = GuardNpcLib.new()
		var pts: Array[Vector3] = []
		for raw_pt: Variant in spec["pts"]:
			var v: Vector3 = raw_pt
			pts.append(v)
		g.configure_patrol(String(spec["title"]), pts)
		add_child(g)
		guards.append(g)

	# 2 Rival Assassins ("The Shadow" in Zone 2 & "Red Viper" in Zone 4)
	var night_speed_mult: float = 1.0 + float(progression.contract_night - 1) * 0.14
	var a1: AssassinNpcLib = AssassinNpcLib.new()
	a1.configure_assassin("The Shadow", Vector3(-11.0, 0.0, 6.0), night_speed_mult)
	add_child(a1)
	assassins.append(a1)

	var a2: AssassinNpcLib = AssassinNpcLib.new()
	a2.configure_assassin("Red Viper", Vector3(10.5, 0.0, -38.0), night_speed_mult * 1.08)
	add_child(a2)
	assassins.append(a2)

	# 10 Farmable Loot Pickups + Mandatory Gold Security Keycard
	var loot_specs: Array[Dictionary] = [
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(-7.8, 0.0, 39.0)},
		{"t": LootPickupLib.LootType.CHAMPAGNE_RESTOCK, "pos": Vector3(7.8, 0.0, 28.0)},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(-10.5, 0.0, 15.0)},
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(8.5, 0.0, 14.0)},
		{"t": LootPickupLib.LootType.SECURITY_KEYCARD, "pos": KEYCARD_LOUNGE_POS},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(-10.5, 0.0, -4.5)},
		{"t": LootPickupLib.LootType.CHAMPAGNE_RESTOCK, "pos": Vector3(5.5, 0.0, -17.5)},
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(-6.2, 0.0, -28.0)},
		{"t": LootPickupLib.LootType.BRIEFCASE, "pos": Vector3(9.5, 0.0, -36.0)},
		{"t": LootPickupLib.LootType.TIP_ENVELOPE, "pos": Vector3(-8.5, 0.0, -44.0)},
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
	hud.next_contract_requested.connect(_restart_mission)
	hud.restart_contract_requested.connect(_restart_mission)
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
		obj_text = "OBJECTIVE [3/4]: Grab GOLD KEYCARD in East VIP Lounge (%.1fm) to unlock Laser Gate!" % d3
	elif vip.state != VipStateMachineLib.VipState.EXTRACTED:
		var d4: float = vip.position.distance_to(EXTRACTION_POS)
		obj_text = "OBJECTIVE [4/4]: Hold VIP at North Armored Limousine (%.1f / %.1fs) — %.1fm ahead" % [extraction_progress_sec, EXTRACTION_HOLD_SEC, d4]
	else:
		obj_text = "🏆 CONTRACT COMPLETE! Press [U] to Upgrade Gear & Deploy Night %d!" % progression.contract_night

	var vip_pill: String = "🤵 VIP ALIVE (%.0f/%.0f HP)" % [vip.health, vip.max_health]
	var pill_col: Color = Color(0.32, 1.0, 0.52)
	if vip.state == VipStateMachineLib.VipState.CORPSE:
		vip_pill = "💀 CORPSE MODE — HOLD [E] PROP & [V] TALK! (Grabbers: %d)" % vip.grabber_count
		pill_col = Color(1.0, 0.68, 0.18)
	elif vip.state == VipStateMachineLib.VipState.EXPOSED:
		vip_pill = "🚨 BUSTED! PRESS [R] RETRY OR [U] ARMORY"
		pill_col = Color(1.0, 0.28, 0.28)
	elif vip.state == VipStateMachineLib.VipState.EXTRACTED:
		vip_pill = "🏆 EXTRACTED! PRESS [U] FOR NEXT NIGHT"
		pill_col = Color(0.32, 0.92, 1.0)

	var taser_txt: String = "READY" if taser_cooldown <= 0.05 else "%.1fs" % taser_cooldown
	var hotbar: String = (
		"[WASD] Move  |  [Shift] Sprint  |  [Hold E] Grab/Prop VIP  |  [F] Tackle  |  [G] Taser (%s)\n"
		+ "[Q] Decoy Bottle (%d)  |  [Hold V] Voice Jaw Bluff  |  [U] UPGRADE SHOP ($%d)  |  [C] Cam #%d  |  [K] Test Corpse  |  [Tab] Bot:%s  |  %s"
	) % [
		taser_txt,
		decoy_bottles_left,
		progression.bank_cash,
		camera_mode + 1,
		"ON" if partner_bot.ai_assist_enabled else "OFF",
		network_status_label,
	]

	hud.update_hud_state({
		"title": "BODYGUARD INC.  |  NIGHT %d (%s)  |  Combo x%.2f" % [progression.contract_night, progression.get_agency_rank(), combo_mult],
		"objective": obj_text,
		"cash_line": "BANK: $%d  (+ $%d Run)" % [progression.bank_cash, contract_earned_cash],
		"toast": ("⚡ " + combo_popup_text) if combo_popup_timer > 0.0 else "",
		"vip_pill": vip_pill,
		"vip_pill_color": pill_col,
		"vip_max_hp": vip.max_health,
		"vip_hp": vip.health,
		"suspicion": vip.suspicion,
		"stamina": local_player.stamina,
		"jaw_deg": vip.visual_jaw_angle_deg,
		"radio": "📻 " + active_guard_bark,
		"hotbar": hotbar,
	})


func _on_remote_peer_connected(peer_id: int) -> void:
	if peer_id == 1 or remote_players.has(peer_id):
		return
	var rp: BodyguardPlayerLib = BodyguardPlayerLib.new()
	rp.name = "RemoteBodyguard_%d" % peer_id
	rp.peer_id = peer_id
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
