class_name GalaLevel
extends Node3D
## Main Playable 3D Co-op Level for BODYGUARD INC. ("The Penthouse Gala").
## Strictly obeys AGENTS.md:
## - Fixed 60 Hz authoritative gameplay & physics in `_physics_process(delta)`.
## - Camera smoothing, jaw/limb visual updates, and HUD rendering in `_process(delta)`.

const NetworkTransportLib := preload("res://src/core/network_transport.gd")
const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")
const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")
const VipStateMachineLib := preload("res://src/vip/vip_state_machine.gd")
const BodyguardPlayerLib := preload("res://src/player/bodyguard_player.gd")
const GuardNpcLib := preload("res://src/world/guard_npc.gd")
const HazardZoneLib := preload("res://src/world/hazard_zone.gd")

const VIP_SPAWN_POS: Vector3 = Vector3(0.0, 0.0, 12.0)
const PLAYER1_SPAWN_POS: Vector3 = Vector3(-1.8, 0.0, 13.0)
const PARTNER_SPAWN_POS: Vector3 = Vector3(1.8, 0.0, 13.0)
const EXTRACTION_POS: Vector3 = Vector3(0.0, 0.0, -14.0)
const EXTRACTION_RADIUS: float = 2.6
const TARGET_QUOTA_CASH: int = 10000

var transport: NetworkTransportLib = null
var audio_driver: AudioInputDriverLib = null
var vip: VipStateMachineLib = null
var local_player: BodyguardPlayerLib = null
var partner_bot: BodyguardPlayerLib = null
var remote_players: Dictionary = {}
var guards: Array[GuardNpcLib] = []
var hazards: Array[HazardZoneLib] = []

# Authoritative mission state (Host)
var quota_cash: int = 0
var checkpoint_stage: int = 0
var network_status_label: String = "Solo + AI Co-op Partner (Press [H] Host / [J] Join P2P)"
var active_guard_bark: String = "Escort the VIP down the red carpet to the North Limousine!"
var _sim_clock: float = 0.0
var _snapshot_tick_counter: int = 0
var _edge_key_k: bool = false
var _edge_key_r: bool = false
var _edge_key_tab: bool = false
var _edge_key_f: bool = false
var _edge_key_h: bool = false
var _edge_key_j: bool = false

# Visual camera & HUD nodes (_process only)
var _camera: Camera3D = null
var _hud_status_label: Label = null
var _hud_bars_label: Label = null
var _hud_voice_label: Label = null
var _hud_bark_label: Label = null
var _hud_controls_label: Label = null


func _ready() -> void:
	audio_driver = AudioInputDriverLib.new()
	_build_environment_and_arena()
	_spawn_entities()
	_build_hud()


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_sim_clock += delta
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

	# 2. Update VIP suicidal target toward the nearest lethal hazard periodically
	if hazards.size() > 0:
		var target_idx: int = int(_sim_clock / 4.5) % hazards.size()
		vip.suicidal_target = hazards[target_idx].position

	# 3. Apply critically-damped grab spring-damper forces to VIP & step VIP simulation
	vip.apply_grab_spring_authoritative(grab_anchors, delta, true)
	vip.step_simulation(delta)

	# 4. Evaluate lethal hazards (Sniper Laser, Poison Fountain, Balcony Ledge)
	var vip_alive: bool = (vip.state == VipStateMachineLib.VipState.ALIVE)
	for hazard: HazardZoneLib in hazards:
		var dmg: float = hazard.step_hazard_physics(delta, vip.position, vip_alive)
		if dmg > 0.0:
			vip.apply_damage_authoritative(dmg, true, hazard.hazard_title)

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
		if guard.is_inspecting_vip:
			priority_bark = guard.last_inspection_bark

	if priority_bark != "":
		active_guard_bark = priority_bark
	elif vip_corpse and vip.grabber_count <= 0:
		active_guard_bark = "VIP IS DEAD! Press & hold [E] near the corpse to prop him up 'Weekend at Bernie's' style!"
	elif vip_corpse and vip.grabber_count > 0:
		active_guard_bark = "Dragging VIP corpse! Hold [V] to animate his jaw whenever a guard inspects you!"
	else:
		active_guard_bark = "VIP is wandering toward hazards! Grab him with [E] or shove him with [F]!"

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
	# Strictly visual camera smoothing, character visuals & HUD rendering
	if not is_finite(delta) or delta <= 0.0:
		return

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

	if _camera != null and local_player != null and vip != null:
		var focus: Vector3 = (local_player.position * 0.55) + (vip.position * 0.45)
		var desired_cam_pos: Vector3 = focus + Vector3(0.0, 14.5, 11.5)
		_camera.position = _camera.position.lerp(desired_cam_pos, clampf(delta * 7.5, 0.0, 1.0))
		_camera.look_at(focus + Vector3(0.0, 0.8, 0.0), Vector3.UP)

	_update_hud()


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
	var talk_held: bool = Input.is_key_pressed(KEY_V)
	var scream_held: bool = Input.is_key_pressed(KEY_B)
	var rms: float = audio_driver.sample_interactive_rms(talk_held, scream_held, _sim_clock)

	local_player.set_player_intent(move, grab_held, rms)

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		transport.submit_player_intent.rpc_id(1, move, grab_held, rms)

	# Edge-triggered action keys
	var f_now: bool = Input.is_key_pressed(KEY_F)
	if f_now and not _edge_key_f:
		var imp: Vector3 = local_player.try_shove_vip(vip)
		if imp.length_squared() > 0.01:
			var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
			vip.apply_shove_impulse_authoritative(imp, is_host)
	_edge_key_f = f_now

	var k_now: bool = Input.is_key_pressed(KEY_K)
	if k_now and not _edge_key_k:
		var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
		if vip.state == VipStateMachineLib.VipState.ALIVE:
			vip.apply_damage_authoritative(100.0, is_host, "Debug Sudden Heart Attack ([K])")
	_edge_key_k = k_now

	var r_now: bool = Input.is_key_pressed(KEY_R)
	if r_now and not _edge_key_r:
		_restart_mission()
	_edge_key_r = r_now

	var tab_now: bool = Input.is_key_pressed(KEY_TAB)
	if tab_now and not _edge_key_tab:
		partner_bot.ai_assist_enabled = not partner_bot.ai_assist_enabled
	_edge_key_tab = tab_now

	var h_now: bool = Input.is_key_pressed(KEY_H)
	if h_now and not _edge_key_h:
		var err: Error = transport.host_session(17777, 3)
		network_status_label = "HOSTING P2P on 127.0.0.1:17777" if err == OK else "Host bind error (%d)" % err
	_edge_key_h = h_now

	var j_now: bool = Input.is_key_pressed(KEY_J)
	if j_now and not _edge_key_j:
		var err: Error = transport.join_session("127.0.0.1", 17777)
		network_status_label = "CLIENT connected to 127.0.0.1:17777" if err == OK else "Join error (%d)" % err
	_edge_key_j = j_now


func _evaluate_checkpoints_and_extraction() -> void:
	if vip.state == VipStateMachineLib.VipState.EXPOSED or vip.state == VipStateMachineLib.VipState.EXTRACTED:
		return

	if checkpoint_stage == 0 and vip.position.z <= 4.0:
		checkpoint_stage = 1
		quota_cash += 2500
	elif checkpoint_stage == 1 and vip.position.z <= -5.0:
		checkpoint_stage = 2
		quota_cash += 2500

	if vip.position.distance_to(EXTRACTION_POS) <= EXTRACTION_RADIUS:
		checkpoint_stage = 3
		quota_cash = TARGET_QUOTA_CASH
		vip.mark_extracted_authoritative(true)


func _restart_mission() -> void:
	var is_host: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if not is_host:
		return
	vip.reset_vip_authoritative(VIP_SPAWN_POS, true)
	local_player.position = PLAYER1_SPAWN_POS
	local_player.velocity = Vector3.ZERO
	partner_bot.position = PARTNER_SPAWN_POS
	partner_bot.velocity = Vector3.ZERO
	quota_cash = 0
	checkpoint_stage = 0


func _build_environment_and_arena() -> void:
	_camera = Camera3D.new()
	_camera.name = "FollowCamera"
	_camera.position = Vector3(0.0, 15.0, 24.0)
	_camera.current = true
	add_child(_camera)

	if DisplayServer.get_name() == "headless":
		return

	# Lighting & Sky Environment
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.40, 0.50)
	env.ambient_light_energy = 1.1
	env_node.environment = env
	add_child(env_node)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	# Ballroom Marble Floor
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(28.0, 0.4, 36.0)
	floor_mesh.mesh = fbox
	floor_mesh.position = Vector3(0.0, -0.2, 0.0)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.22)
	floor_mat.roughness = 0.35
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	# Gala Red Carpet Path (South Spawn -> North Limousine Extraction)
	var carpet: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(4.2, 0.04, 30.0)
	carpet.mesh = cbox
	carpet.position = Vector3(0.0, 0.02, -1.0)
	var carpet_mat: StandardMaterial3D = StandardMaterial3D.new()
	carpet_mat.albedo_color = Color(0.62, 0.09, 0.14)
	carpet.material_override = carpet_mat
	add_child(carpet)

	# Golden Limousine Extraction Pad (North End Goal)
	var pad: MeshInstance3D = MeshInstance3D.new()
	var pcyl: CylinderMesh = CylinderMesh.new()
	pcyl.top_radius = EXTRACTION_RADIUS
	pcyl.bottom_radius = EXTRACTION_RADIUS
	pcyl.height = 0.10
	pad.mesh = pcyl
	pad.position = EXTRACTION_POS + Vector3(0.0, 0.05, 0.0)
	var pad_mat: StandardMaterial3D = StandardMaterial3D.new()
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_mat.albedo_color = Color(0.20, 0.92, 0.55)
	pad.material_override = pad_mat
	add_child(pad)


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
	add_child(canvas)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(18.0, 14.0)
	panel.custom_minimum_size = Vector2(680.0, 210.0)
	canvas.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	panel.add_child(vbox)

	_hud_status_label = Label.new()
	_hud_status_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_hud_status_label)

	_hud_bars_label = Label.new()
	_hud_bars_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_hud_bars_label)

	_hud_voice_label = Label.new()
	_hud_voice_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_hud_voice_label)

	_hud_bark_label = Label.new()
	_hud_bark_label.add_theme_font_size_override("font_size", 15)
	_hud_bark_label.modulate = Color(1.0, 0.90, 0.35)
	vbox.add_child(_hud_bark_label)

	_hud_controls_label = Label.new()
	_hud_controls_label.add_theme_font_size_override("font_size", 13)
	_hud_controls_label.modulate = Color(0.75, 0.88, 1.0)
	vbox.add_child(_hud_controls_label)


func _update_hud() -> void:
	if _hud_status_label == null or vip == null:
		return

	var state_banner: String = ""
	match vip.state:
		VipStateMachineLib.VipState.ALIVE:
			state_banner = "VIP STATUS: ALIVE (Suicidal Low-IQ Mode — Escort to North Green Pad!)"
			_hud_status_label.modulate = Color(0.3, 1.0, 0.45)
		VipStateMachineLib.VipState.CORPSE:
			state_banner = "WEEKEND AT BERNIE'S MODE! VIP IS A CORPSE (%s) — DRAG & TALK [V]!" % vip.last_death_cause
			_hud_status_label.modulate = Color(1.0, 0.65, 0.15)
		VipStateMachineLib.VipState.EXPOSED:
			state_banner = "MISSION FAILED — GUARDS REALIZED THE VIP IS DEAD! (Press [R] to Restart)"
			_hud_status_label.modulate = Color(1.0, 0.25, 0.25)
		VipStateMachineLib.VipState.EXTRACTED:
			var bonus: String = "STEALTH CORPSE BLUFF BONUS!" if vip.health <= 0.0 else "FLAWLESS LIVE EXTRACTION!"
			state_banner = "VICTORY! VIP EXTRACTED TO LIMOUSINE — %s (Press [R] to Replay)" % bonus
			_hud_status_label.modulate = Color(0.25, 0.95, 1.0)

	_hud_status_label.text = "BODYGUARD INC. | " + state_banner

	var dist_goal: float = vip.position.distance_to(EXTRACTION_POS)
	_hud_bars_label.text = (
		"VIP Health: %3.0f%%  |  Guard Suspicion: %3.0f%% / 100%%  |  Bodyguards Grabbing: %d  |  Quota: $%d / $%d  |  Goal Dist: %.1fm"
		% [vip.health, vip.suspicion, vip.grabber_count, quota_cash, TARGET_QUOTA_CASH, dist_goal]
	)

	var voice_mode: String = "SILENT"
	if vip.authoritative_voice_rms > 0.70:
		voice_mode = "SCREAMING [B] (+Suspicion!)"
	elif vip.authoritative_voice_rms >= 0.08:
		voice_mode = "TALKING BLUFF [V] (-Suspicion!)"

	_hud_voice_label.text = (
		"Proximity Voice RMS: %.2f (%s)  |  Corpse Jaw Lip-Sync Angle: %4.1f deg  |  AI Partner [Tab]: %s"
		% [
			vip.authoritative_voice_rms,
			voice_mode,
			vip.visual_jaw_angle_deg,
			"ON" if partner_bot.ai_assist_enabled else "OFF",
		]
	)

	_hud_bark_label.text = "LIVE INTEL: " + active_guard_bark
	_hud_controls_label.text = (
		"CONTROLS: [WASD/Arrows] Move | [Hold E/Space] Grab/Prop VIP | [F] Shove VIP | [Hold V] Talk Bluff (Jaw Lip-Sync) | [Hold B] Scream | [K] Kill VIP (Test Corpse) | [R] Restart | "
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
