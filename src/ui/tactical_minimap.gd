class_name TacticalMinimap
extends Control
## Live Top-Right 2026 Tactical Radar Minimap displaying walls, gates, shop, loot,
## guards, frozen enemies, assassins, VIP, active objective, and player in real time.

const MAP_MIN_X: float = -26.0
const MAP_MAX_X: float = 26.0
const MAP_MIN_Z: float = -72.0
const MAP_MAX_Z: float = 62.0

var snapshot: Dictionary = {}


func update_radar(data: Dictionary) -> void:
	snapshot = data
	queue_redraw()


func _world_to_map(wx: float, wz: float) -> Vector2:
	var nx: float = (wx - MAP_MIN_X) / (MAP_MAX_X - MAP_MIN_X)
	var nz: float = (wz - MAP_MIN_Z) / (MAP_MAX_Z - MAP_MIN_Z)
	return Vector2(clampf(nx, 0.02, 0.98) * size.x, clampf(nz, 0.02, 0.98) * size.y)


func _draw() -> void:
	# Sleek translucent radar backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.045, 0.08, 0.84), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.28, 0.78, 1.0, 0.55), false, 1.5)

	# Center carpet spine guide
	var c_top: Vector2 = _world_to_map(0.0, -64.0)
	var c_bot: Vector2 = _world_to_map(0.0, 56.0)
	draw_line(c_top, c_bot, Color(0.55, 0.12, 0.18, 0.45), 6.0)

	if snapshot.is_empty():
		return

	# Solid Walls & Locked Gate
	var gate_locked: bool = bool(snapshot.get("gate_locked", true))
	var wall_boxes: Array = snapshot.get("walls", [])
	for raw_b: Variant in wall_boxes:
		var b: Dictionary = raw_b
		var is_gate: bool = bool(b["is_gate"])
		if is_gate and not gate_locked:
			continue
		var p1: Vector2 = _world_to_map(float(b["min_x"]), float(b["min_z"]))
		var p2: Vector2 = _world_to_map(float(b["max_x"]), float(b["max_z"]))
		var wcol: Color = Color(1.0, 0.22, 0.24, 0.9) if is_gate else Color(0.45, 0.50, 0.62, 0.75)
		draw_rect(Rect2(p1, p2 - p1), wcol, true)

	# Vendor Booth (Gold Square)
	if snapshot.has("vendor_pos"):
		var vp: Vector3 = snapshot["vendor_pos"]
		var mp: Vector2 = _world_to_map(vp.x, vp.z)
		draw_rect(Rect2(mp - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color(1.0, 0.82, 0.24), true)

	# Active Objective Pulse Ring
	if snapshot.has("obj_pos"):
		var op: Vector3 = snapshot["obj_pos"]
		var mop: Vector2 = _world_to_map(op.x, op.z)
		draw_arc(mop, 6.5, 0.0, TAU, 16, Color(0.32, 1.0, 0.65), 1.8)

	# Farmable Loot Dots
	for raw_l: Variant in snapshot.get("loot", []):
		var lp: Vector3 = raw_l
		draw_circle(_world_to_map(lp.x, lp.z), 2.3, Color(0.30, 0.95, 0.48))

	# Patrolling Guards (Yellow = active, Ice Cyan = frozen)
	for raw_g: Variant in snapshot.get("guards", []):
		var gd: Dictionary = raw_g
		var gp: Vector3 = gd["pos"]
		var gcol: Color = Color(0.35, 0.95, 1.0) if bool(gd["frozen"]) else Color(1.0, 0.82, 0.24)
		draw_circle(_world_to_map(gp.x, gp.z), 3.2, gcol)

	# Rival Assassins (Crimson Triangles/Dots)
	for raw_a: Variant in snapshot.get("assassins", []):
		var ad: Dictionary = raw_a
		var ap: Vector3 = ad["pos"]
		var acol: Color = Color(0.35, 0.95, 1.0) if bool(ad["frozen"]) else Color(1.0, 0.16, 0.24)
		draw_circle(_world_to_map(ap.x, ap.z), 4.0, acol)

	# VIP (Bright Gold Dot)
	if snapshot.has("vip_pos"):
		var vip_p: Vector3 = snapshot["vip_pos"]
		draw_circle(_world_to_map(vip_p.x, vip_p.z), 4.4, Color(1.0, 0.86, 0.20))

	# Local Player Bodyguard (Bright Neon Cyan Dot)
	if snapshot.has("player_pos"):
		var pp: Vector3 = snapshot["player_pos"]
		draw_circle(_world_to_map(pp.x, pp.z), 4.2, Color(0.22, 0.92, 1.0))
