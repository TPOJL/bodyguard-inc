class_name AssassinNpc
extends Node3D
## High-Detail Rival Hitman ("The Shadow" / "Red Viper") with Scalable HP, Cryo-Freeze,
## Plasma Damage, WallColliderGrid Collision, and Bounty Rewards!

const CharacterRigBuilderLib := preload("res://src/world/character_rig_builder.gd")

const BASE_CHASE_SPEED: float = 3.35
const ATTACK_RANGE: float = 1.75
const ATTACK_DAMAGE: float = 38.0
const ATTACK_COOLDOWN_SEC: float = 1.85
const RESPAWN_TIME_SEC: float = 18.0
const ASSASSIN_RADIUS: float = 0.46

var assassin_name: String = "Rival Hitman"
var spawn_origin: Vector3 = Vector3(11.0, 0.0, -8.0)
var chase_speed: float = BASE_CHASE_SPEED
var max_hp: float = 140.0
var hp: float = 140.0
var active: bool = true
var frozen_timer: float = 0.0
var stunned_timer: float = 0.0
var ko_respawn_timer: float = 0.0
var wall_grid: RefCounted = null
var security_gate_locked: bool = false
var _attack_cooldown: float = 0.0

var _visual_root: Node3D = null
var _ice_shell: Node3D = null
var _label: Label3D = null
var _left_leg: Node3D = null
var _right_leg: Node3D = null
var _clock: float = 0.0


func configure_assassin(title: String, spawn_pos: Vector3, speed_mult: float = 1.0, level_max_hp: float = 140.0) -> void:
	assassin_name = title
	spawn_origin = spawn_pos
	position = spawn_pos
	chase_speed = BASE_CHASE_SPEED * clampf(speed_mult, 0.7, 1.9)
	max_hp = maxf(60.0, level_max_hp)
	hp = max_hp
	active = true
	frozen_timer = 0.0
	stunned_timer = 0.0
	ko_respawn_timer = 0.0
	_build_visuals()


func apply_weapon_hit(raw_damage: float, freeze_sec: float, shatter_crit_mult: float = 2.0) -> Dictionary:
	if not active or ko_respawn_timer > 0.0:
		return {"hit": false, "killed": false, "shatter_crit": false, "damage": 0.0}
	var was_frozen: bool = (frozen_timer > 0.0)
	var final_dmg: float = raw_damage
	var is_crit: bool = false
	if freeze_sec > 0.0:
		frozen_timer = maxf(frozen_timer, freeze_sec)
	elif was_frozen:
		final_dmg = raw_damage * shatter_crit_mult
		is_crit = true

	hp = maxf(0.0, hp - final_dmg)
	if hp <= 0.0:
		ko_respawn_timer = RESPAWN_TIME_SEC
		frozen_timer = 0.0
		stunned_timer = 0.0
		return {"hit": true, "killed": true, "shatter_crit": is_crit, "damage": final_dmg}
	return {"hit": true, "killed": false, "shatter_crit": is_crit, "damage": final_dmg}


func apply_knockout_or_stun(duration: float, is_full_ko: bool) -> bool:
	if not active or ko_respawn_timer > 0.0:
		return false
	if is_full_ko:
		hp = 0.0
		ko_respawn_timer = RESPAWN_TIME_SEC
		stunned_timer = 0.0
		frozen_timer = 0.0
		return true
	stunned_timer = maxf(stunned_timer, duration)
	return true


func step_assassin_physics(delta: float, vip_pos: Vector3, vip_is_alive: bool, aggro_range: float = 22.0) -> float:
	if not is_finite(delta) or delta <= 0.0 or not active:
		return 0.0

	if ko_respawn_timer > 0.0:
		ko_respawn_timer = maxf(0.0, ko_respawn_timer - delta)
		if ko_respawn_timer <= 0.0:
			position = spawn_origin
			hp = max_hp
		return 0.0

	if frozen_timer > 0.0:
		frozen_timer = maxf(0.0, frozen_timer - delta)
		return 0.0

	if stunned_timer > 0.0:
		stunned_timer = maxf(0.0, stunned_timer - delta)
		return 0.0

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	if not vip_is_alive:
		var back: Vector3 = spawn_origin - position
		back.y = 0.0
		if back.length() > 0.5:
			_move_resolved(back.normalized() * (chase_speed * 0.7) * delta)
		return 0.0

	var to_vip: Vector3 = vip_pos - position
	to_vip.y = 0.0
	var dist: float = to_vip.length()
	if dist > aggro_range:
		return 0.0

	if dist > ATTACK_RANGE * 0.85:
		var dir: Vector3 = to_vip.normalized()
		_move_resolved(dir * chase_speed * delta)
		if _visual_root != null:
			_visual_root.rotation.y = atan2(dir.x, dir.z)
		return 0.0

	if _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN_SEC
		return ATTACK_DAMAGE

	return 0.0


func _move_resolved(delta_vec: Vector3) -> void:
	var next_pos: Vector3 = position + delta_vec
	next_pos.y = 0.0
	if wall_grid != null:
		next_pos = wall_grid.call("resolve_position", next_pos, ASSASSIN_RADIUS, security_gate_locked)
	position = next_pos


func update_visuals() -> void:
	if _visual_root == null:
		return
	visible = (ko_respawn_timer <= 0.0)
	if not visible:
		return
	_clock += 0.016
	if _ice_shell != null:
		_ice_shell.visible = (frozen_timer > 0.0)
	_visual_root.rotation.x = deg_to_rad(52.0) if stunned_timer > 0.0 else 0.0

	if _left_leg != null and _right_leg != null:
		if frozen_timer <= 0.0 and stunned_timer <= 0.0:
			_left_leg.rotation.x = sin(_clock * 9.0) * 0.55
			_right_leg.rotation.x = -sin(_clock * 9.0) * 0.55
		else:
			_left_leg.rotation.x = 0.0
			_right_leg.rotation.x = 0.0

	if _label != null:
		var hp_str: String = "[%.0f/%.0f HP]" % [hp, max_hp]
		if frozen_timer > 0.0:
			_label.text = "❄️ %s FROZEN %.1fs %s (2x CRIT!)" % [assassin_name, frozen_timer, hp_str]
			_label.modulate = Color(0.40, 0.96, 1.0)
		elif stunned_timer > 0.0:
			_label.text = "⚡ %s [STUN %.1fs] %s" % [assassin_name, stunned_timer, hp_str]
			_label.modulate = Color(0.35, 0.90, 1.0)
		else:
			_label.text = "🗡️ %s %s — SHOOT [X] / CRYO [Z]" % [assassin_name, hp_str]
			_label.modulate = Color(1.0, 0.25, 0.30)


func _build_visuals() -> void:
	for child: Node in get_children():
		child.free()
	if DisplayServer.get_name() == "headless":
		return

	_visual_root = Node3D.new()
	_visual_root.name = "AssassinVisual"
	add_child(_visual_root)

	var rig: Dictionary = CharacterRigBuilderLib.build_sculpted_bodyguard(
		_visual_root,
		Color(0.11, 0.03, 0.07),
		Color(1.0, 0.14, 0.22),
		Color(0.06, 0.02, 0.04)
	)
	_left_leg = rig["left_leg"]
	_right_leg = rig["right_leg"]

	_ice_shell = CharacterRigBuilderLib.build_ice_crystal_shell(self)

	_label = Label3D.new()
	_label.position = Vector3(0.0, 2.45, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 22
	_label.outline_size = 8
	add_child(_label)
