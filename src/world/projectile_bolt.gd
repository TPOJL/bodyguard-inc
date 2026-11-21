class_name ProjectileBolt
extends Node3D
## Authoritative 60 Hz Plasma & Cryo-Freeze Projectile fired by Bodyguards.
## Stops cleanly on solid walls (WallColliderGrid) and deals damage / freeze to Guards & Assassins.

enum BoltType {
	PLASMA_PISTOL,
	CRYO_FREEZE,
}

const PLASMA_SPEED: float = 28.0
const CRYO_SPEED: float = 22.0
const MAX_LIFETIME_SEC: float = 1.45
const HIT_RADIUS: float = 1.05

var bolt_type: BoltType = BoltType.PLASMA_PISTOL
var velocity: Vector3 = Vector3.ZERO
var damage: float = 40.0
var freeze_duration: float = 0.0
var shatter_crit_mult: float = 2.0
var age_sec: float = 0.0
var alive: bool = true


func configure_bolt(
	b_type: BoltType,
	start_pos: Vector3,
	direction: Vector3,
	dmg: float,
	freeze_sec: float,
	shatter_mult: float
) -> void:
	bolt_type = b_type
	position = start_pos
	var dir: Vector3 = direction.normalized() if (direction.is_finite() and direction.length_squared() > 0.001) else Vector3.FORWARD
	var spd: float = PLASMA_SPEED if b_type == BoltType.PLASMA_PISTOL else CRYO_SPEED
	velocity = Vector3(dir.x, 0.0, dir.z).normalized() * spd
	damage = maxf(1.0, dmg)
	freeze_duration = maxf(0.0, freeze_sec)
	shatter_crit_mult = maxf(1.0, shatter_mult)
	age_sec = 0.0
	alive = true
	_build_visual()


func step_bolt(delta: float, wall_grid: RefCounted, gate_locked: bool) -> bool:
	if not alive or not is_finite(delta) or delta <= 0.0:
		return false
	age_sec += delta
	if age_sec >= MAX_LIFETIME_SEC:
		alive = false
		return false

	position += velocity * delta
	if wall_grid != null and wall_grid.call("is_point_inside_solid", position, 0.15, gate_locked):
		alive = false
		return false
	return true


func _build_visual() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var col: Color = Color(1.0, 0.72, 0.20) if bolt_type == BoltType.PLASMA_PISTOL else Color(0.28, 0.94, 1.0)
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = 0.14 if bolt_type == BoltType.PLASMA_PISTOL else 0.22
	mesh_inst.mesh = sph
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)
