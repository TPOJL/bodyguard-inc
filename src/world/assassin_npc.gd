class_name AssassinNpc
extends Node3D
## Rival Hitman ("The Shadow") who actively hunts the VIP across the Penthouse Gala.
## Bodyguards can intercept & KO him with Tackle [F] or Shock Taser [G] to farm $800 bounties!

const BASE_CHASE_SPEED: float = 3.25
const ATTACK_RANGE: float = 1.75
const ATTACK_DAMAGE: float = 38.0
const ATTACK_COOLDOWN_SEC: float = 1.85
const RESPAWN_TIME_SEC: float = 16.0

var assassin_name: String = "Rival Hitman"
var spawn_origin: Vector3 = Vector3(9.0, 0.0, -8.0)
var chase_speed: float = BASE_CHASE_SPEED
var active: bool = true
var stunned_timer: float = 0.0
var ko_respawn_timer: float = 0.0
var _attack_cooldown: float = 0.0

var _visual_root: Node3D = null
var _label: Label3D = null


func configure_assassin(title: String, spawn_pos: Vector3, speed_mult: float = 1.0) -> void:
	assassin_name = title
	spawn_origin = spawn_pos
	position = spawn_pos
	chase_speed = BASE_CHASE_SPEED * clampf(speed_mult, 0.7, 1.8)
	active = true
	stunned_timer = 0.0
	ko_respawn_timer = 0.0
	_build_visuals()


func apply_knockout_or_stun(duration: float, is_full_ko: bool) -> bool:
	if not active or ko_respawn_timer > 0.0:
		return false
	if is_full_ko:
		ko_respawn_timer = RESPAWN_TIME_SEC
		stunned_timer = 0.0
		return true
	stunned_timer = maxf(stunned_timer, duration)
	return true


func step_assassin_physics(delta: float, vip_pos: Vector3, vip_is_alive: bool, aggro_range: float = 18.0) -> float:
	## Runs at 60 Hz on Host. Returns authoritative damage dealt to VIP this tick.
	if not is_finite(delta) or delta <= 0.0 or not active:
		return 0.0

	if ko_respawn_timer > 0.0:
		ko_respawn_timer = maxf(0.0, ko_respawn_timer - delta)
		if ko_respawn_timer <= 0.0:
			position = spawn_origin
		return 0.0

	if stunned_timer > 0.0:
		stunned_timer = maxf(0.0, stunned_timer - delta)
		return 0.0

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	if not vip_is_alive:
		# Assassin only hunts living VIP; retreats when VIP is already dead
		var back: Vector3 = spawn_origin - position
		back.y = 0.0
		if back.length() > 0.5:
			position += back.normalized() * (chase_speed * 0.7) * delta
		return 0.0

	var to_vip: Vector3 = vip_pos - position
	to_vip.y = 0.0
	var dist: float = to_vip.length()
	if dist > aggro_range:
		return 0.0

	if dist > ATTACK_RANGE * 0.85:
		var dir: Vector3 = to_vip.normalized()
		position += dir * chase_speed * delta
		if _visual_root != null:
			_visual_root.rotation.y = atan2(dir.x, dir.z)
		return 0.0

	if _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN_SEC
		return ATTACK_DAMAGE

	return 0.0


func update_visuals() -> void:
	if _visual_root == null:
		return
	visible = (ko_respawn_timer <= 0.0)
	if not visible:
		return
	if stunned_timer > 0.0:
		_visual_root.rotation.x = deg_to_rad(55.0)
	else:
		_visual_root.rotation.x = 0.0

	if _label != null:
		if stunned_timer > 0.0:
			_label.text = "⚡ %s [TASERED %.1fs]" % [assassin_name, stunned_timer]
			_label.modulate = Color(0.35, 0.90, 1.0)
		else:
			_label.text = "🗡️ %s — TACKLE [F] / TASER [G] (+$800!)" % assassin_name
			_label.modulate = Color(1.0, 0.25, 0.30)


func _build_visuals() -> void:
	for child: Node in get_children():
		child.free()
	if DisplayServer.get_name() == "headless":
		return

	_visual_root = Node3D.new()
	_visual_root.name = "AssassinVisual"
	add_child(_visual_root)

	var cloak_mat: StandardMaterial3D = StandardMaterial3D.new()
	cloak_mat.albedo_color = Color(0.12, 0.03, 0.06)
	cloak_mat.metallic = 0.35
	cloak_mat.roughness = 0.28

	var visor_mat: StandardMaterial3D = StandardMaterial3D.new()
	visor_mat.albedo_color = Color(1.0, 0.14, 0.20)
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(1.0, 0.12, 0.18)
	visor_mat.emission_energy_multiplier = 2.0

	var body: MeshInstance3D = MeshInstance3D.new()
	var bbox: BoxMesh = BoxMesh.new()
	bbox.size = Vector3(0.58, 1.05, 0.36)
	body.mesh = bbox
	body.position = Vector3(0.0, 1.0, 0.0)
	body.material_override = cloak_mat
	_visual_root.add_child(body)

	var head: MeshInstance3D = MeshInstance3D.new()
	var hbox: BoxMesh = BoxMesh.new()
	hbox.size = Vector3(0.38, 0.40, 0.38)
	head.mesh = hbox
	head.position = Vector3(0.0, 1.74, 0.0)
	head.material_override = cloak_mat
	_visual_root.add_child(head)

	var red_visor: MeshInstance3D = MeshInstance3D.new()
	var vbox: BoxMesh = BoxMesh.new()
	vbox.size = Vector3(0.40, 0.09, 0.10)
	red_visor.mesh = vbox
	red_visor.position = Vector3(0.0, 1.76, 0.18)
	red_visor.material_override = visor_mat
	_visual_root.add_child(red_visor)

	_label = Label3D.new()
	_label.position = Vector3(0.0, 2.38, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 21
	_label.outline_size = 7
	add_child(_label)
