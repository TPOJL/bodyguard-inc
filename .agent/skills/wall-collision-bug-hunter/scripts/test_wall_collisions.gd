extends SceneTree
## Automated Wall-Collision & Anti-Clipping Bug Hunter (`wall-collision-bug-hunter` skill).
## Systematically drives Player, VIP, Guards, Assassins, and Projectiles into every solid wall,
## archway wing, marble column, vendor booth, banquet table, perimeter rail, and locked laser gate.
## Fails immediately if ANY entity clips through a wall, escapes bounds, or shoots through a wall.

const GalaLevel := preload("res://src/scenes/gala_level.gd")
const ProjectileBolt := preload("res://src/world/projectile_bolt.gd")

const FIXED_DT: float = 1.0 / 60.0
var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("[wall-collision-bug-hunter] Running anti-clipping regression tests on 52m x 136m Estate...")
	var baseline_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var level: GalaLevel = GalaLevel.new()
	level.name = "WallCollisionAudit"
	get_root().add_child(level)

	# 1. Drive Local Player straight into Zone 1 West Archway Wall (x = -16, z = 42, size 18 x 1.1)
	level.local_player.position = Vector3(-14.0, 0.0, 44.5)
	for _i: int in range(90):
		level.local_player.set_player_intent(Vector2(0.0, -1.0), false, 0.0, true)
		level.local_player.step_bodyguard_physics(FIXED_DT, level.vip, GalaLevel.EXTRACTION_POS)
	_assert_true(
		level.local_player.position.z >= 42.55,
		"Player MUST NOT clip through Zone 1 West Archway Wall (got z=%.2f)" % level.local_player.position.z
	)

	# 2. Drive Player straight into Big Tony's Vendor Booth Counter (x = -9.5, z = 52.8)
	level.local_player.position = Vector3(-9.5, 0.0, 56.0)
	for _i: int in range(80):
		level.local_player.set_player_intent(Vector2(0.0, -1.0), false, 0.0, true)
		level.local_player.step_bodyguard_physics(FIXED_DT, level.vip, GalaLevel.EXTRACTION_POS)
	_assert_true(
		not level.wall_grid.is_point_inside_solid(level.local_player.position, 0.20, true),
		"Player MUST NOT clip inside Big Tony's Vendor Booth (pos=%s)" % str(level.local_player.position)
	)

	# 3. Drive Player diagonally into a Solid Marble Column (-19.5, 34.0, r=0.72)
	level.local_player.position = Vector3(-17.5, 0.0, 36.0)
	for _i: int in range(80):
		level.local_player.set_player_intent(Vector2(-1.0, -1.0), false, 0.0, true)
		level.local_player.step_bodyguard_physics(FIXED_DT, level.vip, GalaLevel.EXTRACTION_POS)
	var col_dist: float = Vector2(level.local_player.position.x - (-19.5), level.local_player.position.z - 34.0).length()
	_assert_true(
		col_dist >= 1.15,
		"Player MUST NOT clip into Marble Column (dist=%.2f, required>=1.15)" % col_dist
	)

	# 4. Drive VIP straight at Locked Security Laser Gate (z = -22.0) -> MUST be blocked
	level.vip.position = Vector3(0.0, 0.0, -19.5)
	level.vip.velocity = Vector3(0.0, 0.0, -10.0)
	for _i: int in range(60):
		level.vip.velocity = Vector3(0.0, 0.0, -10.0)
		level.vip.step_simulation(FIXED_DT)
	_assert_true(
		level.vip.position.z >= GalaLevel.SECURITY_GATE_Z + 0.55,
		"VIP MUST NOT pass Locked Laser Security Gate (got z=%.2f)" % level.vip.position.z
	)

	# 5. Drive Player into East Perimeter Balcony Railing (+24.8) -> MUST stay in bounds
	level.local_player.position = Vector3(22.0, 0.0, 30.0)
	for _i: int in range(80):
		level.local_player.set_player_intent(Vector2(1.0, 0.0), false, 0.0, true)
		level.local_player.step_bodyguard_physics(FIXED_DT, level.vip, GalaLevel.EXTRACTION_POS)
	_assert_true(
		level.local_player.position.x <= 24.4,
		"Player MUST NOT clip past East Perimeter Railing (got x=%.2f)" % level.local_player.position.x
	)

	# 6. Fire Plasma Bolt straight into Solid Dividing Wall -> MUST terminate at wall, NOT pass through!
	level.local_player.position = Vector3(-14.0, 0.0, 44.5)
	var bolt: ProjectileBolt = level.fire_weapon_authoritative(false, Vector3(0.0, 0.0, -1.0))
	var stopped_before_passing: bool = false
	for _i: int in range(40):
		if not bolt.step_bolt(FIXED_DT, level.wall_grid, true):
			stopped_before_passing = (bolt.position.z >= 41.2)
			break
	_assert_true(stopped_before_passing, "Plasma projectile MUST stop on solid dividing wall (z=%.2f)" % bolt.position.z)

	# 7. Verify Guards & Assassins resolve collisions against Banquet Table (-14.5, 32.0, r=1.45)
	level.assassins[0].position = Vector3(-14.5, 0.0, 35.0)
	level.vip.position = Vector3(-14.5, 0.0, 28.0)
	for _i: int in range(90):
		level.assassins[0].step_assassin_physics(FIXED_DT, level.vip.position, true, 30.0)
	var tbl_dist: float = Vector2(level.assassins[0].position.x - (-14.5), level.assassins[0].position.z - 32.0).length()
	_assert_true(tbl_dist >= 1.80, "Assassin MUST NOT walk through solid Banquet Table (dist=%.2f)" % tbl_dist)

	level.free()
	var leaked: int = maxi(0, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - baseline_orphans)
	_assert_true(leaked == 0, "Zero orphan nodes leaked after wall-collision audit (got %d)" % leaked)

	if _failures > 0:
		print("[wall-collision-bug-hunter] FAIL (%d wall-clipping violation(s))" % _failures)
		quit(1)
		return true

	print("[wall-collision-bug-hunter] PASS — Zero wall/pillar/table/gate/projectile clipping detected!")
	quit(0)
	return true


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("[WALL-BUG FAIL] %s" % msg)
		_failures += 1
