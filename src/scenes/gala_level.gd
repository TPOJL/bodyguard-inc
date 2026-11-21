class_name GalaLevel
extends Node3D
## Main Playable 3D Co-op Level for BODYGUARD INC. ("The Penthouse Gala").
## Features Forward+ HDR Bloom/Glare ("БЛИКИ"), SSR Mirror Marble Floor, Volumetric Fog,
## Anamorphic Lens Flare Shader, Decoy Bottle Throws [Q], Hero Tackle Saves [F],
## Multi-Angle Camera [C], Synth Audio Feedback, and Styled Broadcast HUD.

const NetworkTransportLib := preload("res://src/core/network_transport.gd")
const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")
const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")
const SynthSfxLib := preload("res://src/core/synth_sfx.gd")
const VipStateMachineLib := preload("res://src/vip/vip_state_machine.gd")
const BodyguardPlayerLib := preload("res://src/player/bodyguard_player.gd")
const GuardNpcLib := preload("res://src/world/guard_npc.gd")
const HazardZoneLib := preload("res://src/world/hazard_zone.gd")
const GalaVisualComposerLib := preload("res://src/world/gala_visual_composer.gd")

const VIP_SPAWN_POS: Vector3 = Vector3(0.0, 0.0, 12.0)
const PLAYER1_SPAWN_POS: Vector3 = Vector3(-1.8, 0.0, 13.0)
const PARTNER_SPAWN_POS: Vector3 = Vector3(1.8, 0.0, 13.0)
const EXTRACTION_POS: Vector3 = Vector3(0.0, 0.0, -14.0)
const EXTRACTION_RADIUS: float = 2.6
const TARGET_QUOTA_CASH: int = 10000

var transport: NetworkTransportLib = null
var audio_driver: AudioInputDriverLib = null
var sfx: SynthSfxLib = null
var vip: VipStateMachineLib = null
var local_player: BodyguardPlayerLib = null
var partner_bot: BodyguardPlayerLib = null
var remote_players: Dictionary = {}
var guards: Array[GuardNpcLib] = []
var hazards: Array[HazardZoneLib] = []

# Authoritative mission state (Host)
var quota_cash: int = 0
var checkpoint_stage: int = 0
var decoy_bottles_left: int = 3
var camera_mode: int = 0
var network_status_label: String = "Solo + AI Co-op Partner ([H] Host / [J] Join P2P)"
var active_guard_bark: String = "Escort the VIP down the red carpet to the North Armored Limousine!"
var combo_popup_text: String = "MISSION START: PROTECT THE VIP (OR FAKE IT IF HE DIES!)"
var combo_popup_timer: float = 4.0

var _sim_clock: float = 0.0
var _snapshot_tick_counter: int = 0
var _bluff_score_cooldown: float = 0.0
var _camera_shake_trauma: float = 0.0
var _screen_flash_burst: float = 0.0
var _flare_shader_mat: ShaderMaterial = null
var _decoy_markers: Array[Node3D] = []

var _edge_key_k: bool = false
var _edge_key_r: bool = false
var _edge_key_tab: bool = false
var _edge_key_f: bool = false
var _edge_key_q: bool = false
var _edge_key_c: bool = false
var _edge_key_h: bool = false
var _edge_key_j: bool = false

# Visual camera & Styled HUD nodes (_process only)
var _camera: Camera3D = null
var _hud_status_label: Label = null
var _hud_combo_label: Label = null
var _hud_bars_label: Label = null
var _hud_voice_label: Label = null
var _hud_bark_label: Label = null
var _hud_controls_label: Label = null
var _health_bar: ProgressBar = null
var _suspicion_bar: ProgressBar = null
var _jaw_bar: ProgressBar = null


func _ready() -> void:
	audio_driver = AudioInputDriverLib.new()
	sfx = SynthSfxLib.new()
	sfx.name = "SynthSfx"
	add_child(sfx)

	_build_environment_and_arena()
	_spawn_entities()
	_build_hud()


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_sim_clock += delta
	if combo_popup_timer > 0.0:
		combo_popup_timer = maxf(0.0, combo_popup_timer - delta)
	if _bluff_score_cooldown > 0.0:
		_bluff_score_cooldown = maxf(0.0, _bluff_score_cooldown - delta)

	_poll_local_inputs_physics()

	var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if not is_host:
		return

	# 1. Step bodyguards (Local Player + AI Partner + Remote Clients)
	local_player.step_bodyguard_physics(delta, vip, EXTRACTION_POS)
	partner_bot.step_bodyguard_physics(delta, vip, EXTRACTION_POS)

	var grab_anchors: Array[Vector3] = []
	var max_voice_rms: float = local_player.current_voice_rms

	if local_player.is_grabbing_vip:
		grab_anchors.append(local_player.get_grab_anchor_world_pos(0))
	if partner_bot.is_grabbing_vip:
		grab_anchors.append(partner_bot.get_grab_anchor_world_pos(1))

	for peer_id_key: Variant in remote_players.keys():
		var rp: BodyguardPlayerLib = remote_players[peer_id_key]
		rp.step_bodyguard_physics(delta, vip, EXTRACTION_POS)
		if rp.is_grabbing_vip:
			grab_anchors.append(rp.get_grab_anchor_world_pos(grab_anchors.size()))
		max_voice_rms = maxf(max_voice_rms, rp.current_voice_rms)

	vip.authoritative_voice_rms = max_voice_rms
	if max_voice_rms >= 0.08 and sfx != null:
		sfx.play_voice_syllable(max_voice_rms)

	# 2. Update VIP suicidal target toward the nearest lethal hazard periodically
	if hazards.size() > 0:
		var target_idx: int = int(_sim_clock / 4.5) % hazards.size()
		vip.suicidal_target = hazards[target_idx].position
		vip.suicidal_whim_label = hazards[target_idx].hazard_title

	# 3. Apply critically-damped grab spring-damper forces to VIP & step VIP simulation
	vip.apply_grab_spring_authoritative(grab_anchors, delta, true)
	vip.step_simulation(delta)

	# 4. Evaluate lethal hazards (Sniper Laser, Poison Fountain, Balcony Ledge)
	var vip_alive: bool = (vip.state == VipStateMachineLib.VipState.ALIVE)
	for hazard: HazardZoneLib in hazards:
		var dmg: float = hazard.step_hazard_physics(delta, vip.position, vip_alive)
		if dmg > 0.0:
			vip.apply_damage_authoritative(dmg, true, hazard.hazard_title)
			_camera_shake_trauma = minf(1.0, _camera_shake_trauma + 0.55)
			_screen_flash_burst = 0.85
			if vip.state == VipStateMachineLib.VipState.CORPSE:
				_trigger_combo_banner("💀 VIP DIED (%s)! HOLD [E] TO PROP UP CORPSE & [V] TO TALK!" % hazard.hazard_title)
				if sfx != null:
					sfx.play_alert_chirp()

	# 5. Evaluate Security Guards & Paparazzi inspection + voice lip-sync bluff
	var vip_corpse: bool = (vip.state == VipStateMachineLib.VipState.CORPSE)
	var priority_bark: String = ""
	for guard: GuardNpcLib in guards:
		var susp_delta: float = guard.step_guard_physics(
			delta,
			vip.position,
			vip_corpse,
			vip_alive,
			vip.grabber_count,
			vip.authoritative_voice_rms
		)
		if susp_delta != 0.0:
			vip.add_suspicion_authoritative(susp_delta, true)
		if guard.paparazzi_flash_pulse > 0.85:
			_screen_flash_burst = maxf(_screen_flash_burst, 0.65)
		if guard.is_inspecting_vip:
			priority_bark = guard.last_inspection_bark
			if vip_corpse and vip.grabber_count > 0 and susp_delta < 0.0 and _bluff_score_cooldown <= 0.0:
				quota_cash += 250
				_bluff_score_cooldown = 1.6
				_trigger_combo_banner("🎙️ WEEKEND AT BERNIE'S JAW BLUFF! +$250 (-SUSPICION)")
				if sfx != null:
					sfx.play_cash_reward()

	if priority_bark != "":
		active_guard_bark = priority_bark
	elif vip_corpse and vip.grabber_count <= 0:
		active_guard_bark = "💀 VIP IS DEAD ON THE FLOOR! Hold [E] near the corpse to prop him up!"
	elif vip_corpse and vip.grabber_count > 0:
		active_guard_bark = "🕶️ Carrying VIP Corpse! Hold [V] to animate his jaw or press [Q] to throw a Decoy Bottle!"
	else:
		active_guard_bark = "🤵 VIP is obsessed with '%s'! Grab [E], Shove [F], or Sprint [Shift]!" % vip.suicidal_whim_label

	# 6. Evaluate Red Carpet checkpoints & Limousine Extraction Goal
	_evaluate_checkpoints_and_extraction()

	# 7. Broadcast <=20 Hz quantized ragdoll snapshot if multiplayer session is active
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
	# Strictly visual camera smoothing, glare shader parameters, character visuals & HUD rendering
	if not is_finite(delta) or delta <= 0.0:
		return

	_camera_shake_trauma = maxf(0.0, _camera_shake_trauma - delta * 2.2)
	_screen_flash_burst = maxf(0.0, _screen_flash_burst - delta * 2.8)

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

	# Update Anamorphic Lens Flare & Danger Glare Shader ("БЛИКИ")
	if _flare_shader_mat != null and vip != null:
		var max_sniper_pulse: float = 0.0
		for h: HazardZoneLib in hazards:
			if h.hazard_type == HazardZoneLib.HazardType.SNIPER_LASER:
				max_sniper_pulse = maxf(max_sniper_pulse, h.sniper_lock_timer / HazardZoneLib.SNIPER_LOCK_THRESHOLD_SEC)
		var danger: float = clampf(maxf(vip.suspicion / 100.0, max_sniper_pulse), 0.0, 1.0)
		_flare_shader_mat.set_shader_parameter("time_sec", _sim_clock)
		_flare_shader_mat.set_shader_parameter("danger_pulse", danger)
		_flare_shader_mat.set_shader_parameter("flash_burst", _screen_flash_burst)

	_update_camera_visuals(delta)
	_update_hud()


func _update_camera_visuals(delta: float) -> void:
	if _camera == null or local_player == null or vip == null:
		return

	var focus: Vector3 = (local_player.position * 0.55) + (vip.position * 0.45)
	var cam_offset: Vector3 = Vector3(0.0, 12.2, 10.2)
	var look_height: float = 0.95
	var target_fov: float = 56.0

	if camera_mode == 1:
		# Close Action Over-Shoulder Angle (shows SSR floor reflections, chandeliers & jaw close-up!)
		cam_offset = Vector3(0.0, 5.2, 6.4)
		look_height = 1.35
		target_fov = 64.0
	elif camera_mode == 2:
		# High Tactical Penthouse Overview
		cam_offset = Vector3(0.0, 19.5, 13.5)
		look_height = 0.5
		target_fov = 50.0

	if local_player.is_sprinting:
		target_fov += 4.5

	var shake_vec: Vector3 = Vector3.ZERO
	if _camera_shake_trauma > 0.01:
		var amt: float = _camera_shake_trauma * _camera_shake_trauma * 0.45
		shake_vec = Vector3(
			sin(_sim_clock * 47.0) * amt,
			cos(_sim_clock * 53.0) * amt,
			sin(_sim_clock * 39.0) * amt
		)

	var desired_cam_pos: Vector3 = focus + cam_offset + shake_vec
	_camera.position = _camera.position.lerp(desired_cam_pos, clampf(delta * 8.5, 0.0, 1.0))
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(delta * 6.0, 0.0, 1.0))
	_camera.look_at(focus + Vector3(0.0, look_height, 0.0), Vector3.UP)


func _poll_local_inputs_physics() -> void:
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

	# [F] Hero Dive-Tackle / Shove VIP
	var f_now: bool = Input.is_key_pressed(KEY_F)
	if f_now and not _edge_key_f:
		var imp: Vector3 = local_player.try_shove_vip(vip)
		if imp.length_squared() > 0.01:
			var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
			vip.apply_shove_impulse_authoritative(imp, is_host)
			_camera_shake_trauma = 0.65
			_screen_flash_burst = 0.55
			if sfx != null:
				sfx.play_shove_whoosh()
			quota_cash += 500
			_trigger_combo_banner("💥 HERO TACKLE SAVE! +$500 (VIP KNOCKED CLEAR!)")
	_edge_key_f = f_now

	# [Q] Throw Decoy Champagne Bottle to distract Guards & Paparazzi
	var q_now: bool = Input.is_key_pressed(KEY_Q)
	if q_now and not _edge_key_q:
		_try_throw_decoy_bottle()
	_edge_key_q = q_now

	# [C] Cycle Camera Angle (Cinematic / Close Over-Shoulder / Tactical)
	var c_now: bool = Input.is_key_pressed(KEY_C)
	if c_now and not _edge_key_c:
		camera_mode = (camera_mode + 1) % 3
		var cam_names: Array[String] = ["CINEMATIC FOLLOW", "CLOSE ACTION CAM", "TACTICAL OVERVIEW"]
		_trigger_combo_banner("🎥 CAMERA: %s" % cam_names[camera_mode])
	_edge_key_c = c_now

	# [K] Instant Kill VIP (Test Weekend at Bernie's Corpse Mode)
	var k_now: bool = Input.is_key_pressed(KEY_K)
	if k_now and not _edge_key_k:
		var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
		if vip.state == VipStateMachineLib.VipState.ALIVE:
			vip.apply_damage_authoritative(100.0, is_host, "Poisoned Gala Martini ([K])")
			_camera_shake_trauma = 0.7
			_screen_flash_burst = 0.85
			_trigger_combo_banner("💀 WEEKEND AT BERNIE'S MODE ACTIVATED! HOLD [E] TO PROP CORPSE & [V] TO TALK!")
			if sfx != null:
				sfx.play_alert_chirp()
	_edge_key_k = k_now

	# [R] Restart Mission
	var r_now: bool = Input.is_key_pressed(KEY_R)
	if r_now and not _edge_key_r:
		_restart_mission()
	_edge_key_r = r_now

	# [Tab] Toggle AI Co-op Partner Bodyguard
	var tab_now: bool = Input.is_key_pressed(KEY_TAB)
	if tab_now and not _edge_key_tab:
		partner_bot.ai_assist_enabled = not partner_bot.ai_assist_enabled
		_trigger_combo_banner("🕶️ AI CO-OP PARTNER: %s" % ("ENABLED" if partner_bot.ai_assist_enabled else "PAUSED"))
	_edge_key_tab = tab_now

	# [H] / [J] Host or Join Localhost P2P Co-op
	var h_now: bool = Input.is_key_pressed(KEY_H)
	if h_now and not _edge_key_h:
		var err: Error = transport.host_session(17777, 3)
		network_status_label = "HOSTING P2P 127.0.0.1:17777" if err == OK else "Host bind error (%d)" % err
	_edge_key_h = h_now

	var j_now: bool = Input.is_key_pressed(KEY_J)
	if j_now and not _edge_key_j:
		var err: Error = transport.join_session("127.0.0.1", 17777)
		network_status_label = "CLIENT 127.0.0.1:17777" if err == OK else "Join error (%d)" % err
	_edge_key_j = j_now


func _try_throw_decoy_bottle() -> void:
	if decoy_bottles_left <= 0:
		_trigger_combo_banner("🍾 OUT OF DECOY BOTTLES! (Reach next checkpoint to restock)")
		return
	decoy_bottles_left -= 1
	var fwd: Vector3 = Vector3(sin(local_player.facing_yaw_rad), 0.0, cos(local_player.facing_yaw_rad))
	var landing_pos: Vector3 = local_player.position + fwd * 4.2
	landing_pos.x = clampf(landing_pos.x, -12.0, 12.0)
	landing_pos.z = clampf(landing_pos.z, -15.0, 15.0)
	landing_pos.y = 0.0

	var distracted_count: int = 0
	for guard: GuardNpcLib in guards:
		if guard.trigger_bottle_distraction(landing_pos, 8.0, 4.8):
			distracted_count += 1

	_screen_flash_burst = 0.5
	if sfx != null:
		sfx.play_bottle_throw()

	if DisplayServer.get_name() != "headless":
		var splash: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.45
		torus.outer_radius = 0.85
		splash.mesh = torus
		splash.position = landing_pos + Vector3(0.0, 0.06, 0.0)
		var smat: StandardMaterial3D = StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.albedo_color = Color(0.3, 0.95, 1.0)
		splash.material_override = smat
		add_child(splash)
		_decoy_markers.append(splash)

	if distracted_count > 0:
		quota_cash += 500 * distracted_count
		_trigger_combo_banner("🍾 CHAMPAGNE DECOY SHATTERED! DISTRACTED %d GUARD(S) (+$%d)!" % [distracted_count, 500 * distracted_count])
	else:
		_trigger_combo_banner("🍾 CHAMPAGNE BOTTLE THROWN (%d LEFT)" % decoy_bottles_left)


func _trigger_combo_banner(msg: String) -> void:
	combo_popup_text = msg
	combo_popup_timer = 3.5


func _evaluate_checkpoints_and_extraction() -> void:
	if vip.state == VipStateMachineLib.VipState.EXPOSED or vip.state == VipStateMachineLib.VipState.EXTRACTED:
		return

	if checkpoint_stage == 0 and vip.position.z <= 4.0:
		checkpoint_stage = 1
		quota_cash += 2500
		decoy_bottles_left = mini(3, decoy_bottles_left + 1)
		_screen_flash_burst = 0.55
		_trigger_combo_banner("✅ CHECKPOINT 1 CLEARED! +$2,500 & +1 DECOY BOTTLE!")
		if sfx != null:
			sfx.play_cash_reward()
	elif checkpoint_stage == 1 and vip.position.z <= -5.0:
		checkpoint_stage = 2
		quota_cash += 2500
		decoy_bottles_left = mini(3, decoy_bottles_left + 1)
		_screen_flash_burst = 0.55
		_trigger_combo_banner("✅ CHECKPOINT 2 CLEARED! +$2,500 — LIMOUSINE RIGHT AHEAD!")
		if sfx != null:
			sfx.play_cash_reward()

	if vip.position.distance_to(EXTRACTION_POS) <= EXTRACTION_RADIUS:
		checkpoint_stage = 3
		quota_cash = maxi(quota_cash + 5000, TARGET_QUOTA_CASH)
		vip.mark_extracted_authoritative(true)
		_screen_flash_burst = 1.0
		var mode_str: String = "WEEKEND AT BERNIE'S CORPSE BLUFF VICTORY!" if vip.health <= 0.0 else "FLAWLESS LIVE VIP EXTRACTION!"
		_trigger_combo_banner("🏆 %s ($%d EARNED!)" % [mode_str, quota_cash])
		if sfx != null:
			sfx.play_cash_reward()


func _restart_mission() -> void:
	var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if not is_host:
		return
	vip.reset_vip_authoritative(VIP_SPAWN_POS, true)
	local_player.position = PLAYER1_SPAWN_POS
	local_player.velocity = Vector3.ZERO
	local_player.stamina = 100.0
	partner_bot.position = PARTNER_SPAWN_POS
	partner_bot.velocity = Vector3.ZERO
	quota_cash = 0
	checkpoint_stage = 0
	decoy_bottles_left = 3
	for m: Node3D in _decoy_markers:
		if is_instance_valid(m):
			m.free()
	_decoy_markers.clear()
	_trigger_combo_banner("🔄 MISSION RESTARTED — ESCORT THE VIP TO THE NORTH LIMOUSINE!")


func _build_environment_and_arena() -> void:
	_camera = Camera3D.new()
	_camera.name = "FollowCamera"
	_camera.position = Vector3(0.0, 14.0, 22.0)
	_camera.fov = 56.0
	_camera.current = true
	add_child(_camera)

	_flare_shader_mat = GalaVisualComposerLib.build_hdr_environment(self)
	GalaVisualComposerLib.build_penthouse_architecture(self, EXTRACTION_POS, EXTRACTION_RADIUS)


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
	add_child(vip)

	local_player = BodyguardPlayerLib.new()
	local_player.name = "LocalBodyguard"
	local_player.peer_id = 1
	local_player.position = PLAYER1_SPAWN_POS
	add_child(local_player)

	partner_bot = BodyguardPlayerLib.new()
	partner_bot.name = "PartnerBotBodyguard"
	partner_bot.is_ai_partner = true
	partner_bot.ai_assist_enabled = true
	partner_bot.position = PARTNER_SPAWN_POS
	add_child(partner_bot)

	# 3 Lethal Hazards
	var fountain: HazardZoneLib = HazardZoneLib.new()
	fountain.configure_hazard(
		HazardZoneLib.HazardType.POISON_FOUNTAIN,
		"Poison Champagne Fountain",
		Vector3(5.2, 0.0, 4.5),
		2.3
	)
	add_child(fountain)
	hazards.append(fountain)

	var sniper: HazardZoneLib = HazardZoneLib.new()
	sniper.configure_hazard(
		HazardZoneLib.HazardType.SNIPER_LASER,
		"Rooftop Sniper Laser",
		Vector3(0.0, 0.0, -2.0),
		1.85
	)
	add_child(sniper)
	hazards.append(sniper)

	var balcony: HazardZoneLib = HazardZoneLib.new()
	balcony.configure_hazard(
		HazardZoneLib.HazardType.BALCONY_LEDGE,
		"High-Voltage Balcony Ledge",
		Vector3(-6.8, 0.0, -8.5),
		2.4
	)
	add_child(balcony)
	hazards.append(balcony)

	# 4 Patrolling Security Guards & Paparazzi
	var guard_specs: Array[Dictionary] = [
		{
			"title": "Inspector Vance",
			"pts": [Vector3(-4.5, 0.0, 6.0), Vector3(4.5, 0.0, 6.0)]
		},
		{
			"title": "Paparazzi Rex",
			"pts": [Vector3(5.0, 0.0, 0.0), Vector3(-5.0, 0.0, 0.0)]
		},
		{
			"title": "Officer Kowalski",
			"pts": [Vector3(-4.8, 0.0, -6.5), Vector3(4.8, 0.0, -6.5)]
		},
		{
			"title": "Limo Security Chief",
			"pts": [Vector3(-3.5, 0.0, -11.5), Vector3(3.5, 0.0, -11.5)]
		},
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


func _build_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "GameHUD"
	canvas.layer = 2
	add_child(canvas)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(18.0, 14.0)
	panel.custom_minimum_size = Vector2(820.0, 235.0)

	var card_style: StyleBoxFlat = StyleBoxFlat.new()
	card_style.bg_color = Color(0.04, 0.05, 0.09, 0.84)
	card_style.border_color = Color(0.95, 0.78, 0.25, 0.90)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(12)
	card_style.content_margin_left = 16.0
	card_style.content_margin_right = 16.0
	card_style.content_margin_top = 12.0
	card_style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", card_style)
	canvas.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_hud_status_label = Label.new()
	_hud_status_label.add_theme_font_size_override("font_size", 19)
	vbox.add_child(_hud_status_label)

	_hud_combo_label = Label.new()
	_hud_combo_label.add_theme_font_size_override("font_size", 16)
	_hud_combo_label.modulate = Color(0.35, 1.0, 0.75)
	vbox.add_child(_hud_combo_label)

	# Visual Progress Bars Row (VIP Health | Guard Suspicion | Corpse Jaw Angle)
	var bars_hbox: HBoxContainer = HBoxContainer.new()
	bars_hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(bars_hbox)

	_health_bar = _make_styled_bar(bars_hbox, "VIP HP", Color(0.18, 0.90, 0.42), 100.0)
	_suspicion_bar = _make_styled_bar(bars_hbox, "SUSPICION", Color(0.95, 0.22, 0.22), 100.0)
	_jaw_bar = _make_styled_bar(bars_hbox, "JAW LIP-SYNC", Color(0.25, 0.85, 1.0), 42.0)

	_hud_bars_label = Label.new()
	_hud_bars_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_hud_bars_label)

	_hud_voice_label = Label.new()
	_hud_voice_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_hud_voice_label)

	_hud_bark_label = Label.new()
	_hud_bark_label.add_theme_font_size_override("font_size", 15)
	_hud_bark_label.modulate = Color(1.0, 0.90, 0.35)
	vbox.add_child(_hud_bark_label)

	_hud_controls_label = Label.new()
	_hud_controls_label.add_theme_font_size_override("font_size", 12)
	_hud_controls_label.modulate = Color(0.75, 0.90, 1.0)
	vbox.add_child(_hud_controls_label)


func _make_styled_bar(parent: HBoxContainer, title: String, fill_col: Color, max_v: float) -> ProgressBar:
	var box: HBoxContainer = HBoxContainer.new()
	parent.add_child(box)
	var lbl: Label = Label.new()
	lbl.text = title + ":"
	lbl.add_theme_font_size_override("font_size", 13)
	box.add_child(lbl)

	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = max_v
	bar.custom_minimum_size = Vector2(140.0, 18.0)
	bar.show_percentage = false
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.12, 0.18)
	bg.set_corner_radius_all(5)
	var fg: StyleBoxFlat = StyleBoxFlat.new()
	fg.bg_color = fill_col
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	box.add_child(bar)
	return bar


func _update_hud() -> void:
	if _hud_status_label == null or vip == null:
		return

	var state_banner: String = ""
	match vip.state:
		VipStateMachineLib.VipState.ALIVE:
			state_banner = "VIP ALIVE (Suicidal Mode -> Escort to North Armored Limo!)"
			_hud_status_label.modulate = Color(0.3, 1.0, 0.45)
		VipStateMachineLib.VipState.CORPSE:
			state_banner = "🕶️ WEEKEND AT BERNIE'S MODE! VIP CORPSE (%s) — PROP [E] & TALK [V]!" % vip.last_death_cause
			_hud_status_label.modulate = Color(1.0, 0.68, 0.15)
		VipStateMachineLib.VipState.EXPOSED:
			state_banner = "🚨 MISSION FAILED — GUARDS EXPOSED THE CORPSE! (Press [R] to Restart)"
			_hud_status_label.modulate = Color(1.0, 0.25, 0.25)
		VipStateMachineLib.VipState.EXTRACTED:
			var bonus: String = "WEEKEND AT BERNIE'S STEALTH BLUFF!" if vip.health <= 0.0 else "FLAWLESS LIVE EXTRACTION!"
			state_banner = "🏆 VICTORY! LIMOUSINE EXTRACTION — %s (Press [R] to Replay)" % bonus
			_hud_status_label.modulate = Color(0.25, 0.95, 1.0)

	_hud_status_label.text = "BODYGUARD INC.  |  " + state_banner
	_hud_combo_label.text = "⚡ " + (combo_popup_text if combo_popup_timer > 0.0 else "Tip: Throw Decoy Bottles [Q] to distract guards or hold [V] to animate the corpse's jaw!")

	if _health_bar != null:
		_health_bar.value = vip.health
	if _suspicion_bar != null:
		_suspicion_bar.value = vip.suspicion
	if _jaw_bar != null:
		_jaw_bar.value = vip.visual_jaw_angle_deg

	var dist_goal: float = vip.position.distance_to(EXTRACTION_POS)
	_hud_bars_label.text = (
		"Quota Cash: $%d / $%d  |  Decoy Bottles [Q]: %d  |  Sprint Stamina [Shift]: %3.0f%%  |  Grabbers: %d  |  Limo Dist: %.1fm"
		% [quota_cash, TARGET_QUOTA_CASH, decoy_bottles_left, local_player.stamina, vip.grabber_count, dist_goal]
	)

	var voice_mode: String = "SILENT"
	if vip.authoritative_voice_rms > 0.70:
		voice_mode = "SCREAMING [B] (+Suspicion!)"
	elif vip.authoritative_voice_rms >= 0.08:
		voice_mode = "TALKING BLUFF [V] (-Suspicion & +$$$!)"

	_hud_voice_label.text = (
		"Proximity Voice RMS: %.2f (%s)  |  3D Jaw Lip-Sync: %4.1f°  |  AI Partner [Tab]: %s  |  Cam [C]: #%d"
		% [
			vip.authoritative_voice_rms,
			voice_mode,
			vip.visual_jaw_angle_deg,
			"ON" if partner_bot.ai_assist_enabled else "OFF",
			camera_mode + 1,
		]
	)

	_hud_bark_label.text = "GUARD RADIO: " + active_guard_bark
	_hud_controls_label.text = (
		"[WASD] Move | [Shift] Sprint | [Hold E/Space] Grab/Prop Corpse | [F] Hero Tackle | [Q] Throw Decoy Bottle | [Hold V] Voice Talk Bluff | [Hold B] Scream | [C] Camera | [K] Kill VIP | [R] Restart | "
		+ network_status_label
	)


func _on_remote_peer_connected(peer_id: int) -> void:
	if peer_id == 1 or remote_players.has(peer_id):
		return
	var rp: BodyguardPlayerLib = BodyguardPlayerLib.new()
	rp.name = "RemoteBodyguard_%d" % peer_id
	rp.peer_id = peer_id
	rp.position = PLAYER1_SPAWN_POS + Vector3(float(remote_players.size() + 1) * 1.5, 0.0, 0.0)
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
