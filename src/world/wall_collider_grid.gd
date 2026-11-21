class_name WallColliderGrid
extends RefCounted
## Authoritative 60 Hz 2D XZ Solid Wall, Pillar, Furniture & Gate Collision Resolver.
## Guarantees zero clipping through architectural walls, columns, vendor kiosk, or locked laser gate.

const ARENA_MIN_X: float = -24.8
const ARENA_MAX_X: float = 24.8
const ARENA_MIN_Z: float = -70.5
const ARENA_MAX_Z: float = 60.5

# Each box: { "min_x": float, "max_x": float, "min_z": float, "max_z": float, "tag": String, "is_gate": bool }
var solid_boxes: Array[Dictionary] = []
# Each circle: { "x": float, "z": float, "r": float, "tag": String }
var solid_circles: Array[Dictionary] = []


func clear() -> void:
	solid_boxes.clear()
	solid_circles.clear()


func add_box(center_x: float, center_z: float, size_x: float, size_z: float, tag: String = "wall", is_gate: bool = false) -> void:
	solid_boxes.append({
		"min_x": center_x - size_x * 0.5,
		"max_x": center_x + size_x * 0.5,
		"min_z": center_z - size_z * 0.5,
		"max_z": center_z + size_z * 0.5,
		"tag": tag,
		"is_gate": is_gate,
	})


func add_circle(center_x: float, center_z: float, radius: float, tag: String = "pillar") -> void:
	solid_circles.append({
		"x": center_x,
		"z": center_z,
		"r": maxf(0.1, radius),
		"tag": tag,
	})


func resolve_position(pos: Vector3, entity_radius: float, gate_locked: bool) -> Vector3:
	if not pos.is_finite():
		return Vector3.ZERO
	var r: float = maxf(0.15, entity_radius)
	var x: float = clampf(pos.x, ARENA_MIN_X + r, ARENA_MAX_X - r)
	var z: float = clampf(pos.z, ARENA_MIN_Z + r, ARENA_MAX_Z - r)

	# Run 2 relaxation iterations to prevent corner tunneling between adjacent walls/pillars
	for _iter: int in range(2):
		for b: Dictionary in solid_boxes:
			if bool(b["is_gate"]) and not gate_locked:
				continue
			var min_x: float = float(b["min_x"])
			var max_x: float = float(b["max_x"])
			var min_z: float = float(b["min_z"])
			var max_z: float = float(b["max_z"])

			var closest_x: float = clampf(x, min_x, max_x)
			var closest_z: float = clampf(z, min_z, max_z)
			var dx: float = x - closest_x
			var dz: float = z - closest_z
			var dist_sq: float = dx * dx + dz * dz

			if dist_sq < r * r:
				if dist_sq > 0.00001:
					var dist: float = sqrt(dist_sq)
					var push: float = r - dist
					x += (dx / dist) * push
					z += (dz / dist) * push
				else:
					# Center ended up strictly inside AABB -> push out along shortest axis
					var pen_left: float = absf(x - min_x)
					var pen_right: float = absf(max_x - x)
					var pen_top: float = absf(z - min_z)
					var pen_bot: float = absf(max_z - z)
					var min_pen: float = minf(minf(pen_left, pen_right), minf(pen_top, pen_bot))
					if min_pen == pen_left:
						x = min_x - r
					elif min_pen == pen_right:
						x = max_x + r
					elif min_pen == pen_top:
						z = min_z - r
					else:
						z = max_z + r

		for c: Dictionary in solid_circles:
			var cx: float = float(c["x"])
			var cz: float = float(c["z"])
			var min_dist: float = float(c["r"]) + r
			var dx_c: float = x - cx
			var dz_c: float = z - cz
			var d_sq: float = dx_c * dx_c + dz_c * dz_c
			if d_sq < min_dist * min_dist:
				if d_sq > 0.00001:
					var d: float = sqrt(d_sq)
					var push_c: float = min_dist - d
					x += (dx_c / d) * push_c
					z += (dz_c / d) * push_c
				else:
					x = cx + min_dist

		x = clampf(x, ARENA_MIN_X + r, ARENA_MAX_X - r)
		z = clampf(z, ARENA_MIN_Z + r, ARENA_MAX_Z - r)

	return Vector3(x, pos.y, z)


func is_point_inside_solid(pos: Vector3, margin: float, gate_locked: bool) -> bool:
	if not pos.is_finite():
		return true
	if pos.x < ARENA_MIN_X + margin or pos.x > ARENA_MAX_X - margin:
		return true
	if pos.z < ARENA_MIN_Z + margin or pos.z > ARENA_MAX_Z - margin:
		return true
	for b: Dictionary in solid_boxes:
		if bool(b["is_gate"]) and not gate_locked:
			continue
		if (
			pos.x > float(b["min_x"]) - margin
			and pos.x < float(b["max_x"]) + margin
			and pos.z > float(b["min_z"]) - margin
			and pos.z < float(b["max_z"]) + margin
		):
			return true
	for c: Dictionary in solid_circles:
		var dx: float = pos.x - float(c["x"])
		var dz: float = pos.z - float(c["z"])
		var lim: float = float(c["r"]) + margin
		if (dx * dx + dz * dz) < (lim * lim):
			return true
	return false
