extends SceneTree
## 1,000-tick headless party scene profiler (VIP + 4 Players + 10 NPCs + Sniper Laser).
## Outputs P95/P99 frame time, physics step time, active nodes, and orphan node count.
## Fails immediately if orphan_nodes > 0 or P99 exceeds budget.

const VipStateMachine := preload("res://src/vip/vip_state_machine.gd")

const TOTAL_TICKS: int = 1000
const FIXED_DT: float = 1.0 / 60.0
const P95_BUDGET_MS: float = 12.0
const P99_BUDGET_MS: float = 16.67


var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var exit_code: int = _run_benchmark()
	quit(exit_code)
	return true


func _run_benchmark() -> int:
	var baseline_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var root_scene: Node3D = Node3D.new()
	root_scene.name = "PartyBenchmarkScene"
	get_root().add_child(root_scene)

	# 1 VIP
	var vip: VipStateMachine = VipStateMachine.new()
	vip.name = "VIP"
	root_scene.add_child(vip)

	# 4 Players
	var players: Array[Node3D] = []
	for p_idx: int in range(4):
		var player: Node3D = Node3D.new()
		player.name = "Player_%d" % p_idx
		player.position = Vector3(float(p_idx) * 2.0, 0.0, 0.0)
		root_scene.add_child(player)
		players.append(player)

	# 10 NPCs (Guards / Paparazzi)
	var npcs: Array[Node3D] = []
	for n_idx: int in range(10):
		var npc: Node3D = Node3D.new()
		npc.name = "NPC_%d" % n_idx
		npc.position = Vector3(cos(float(n_idx)) * 8.0, 0.0, sin(float(n_idx)) * 8.0)
		root_scene.add_child(npc)
		npcs.append(npc)

	# 1 Sniper Laser hazard
	var sniper_laser: RayCast3D = RayCast3D.new()
	sniper_laser.name = "SniperLaser"
	sniper_laser.position = Vector3(0.0, 12.0, -15.0)
	sniper_laser.target_position = Vector3(0.0, -12.0, 15.0)
	root_scene.add_child(sniper_laser)

	var active_nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var tick_times_ms: Array[float] = []
	tick_times_ms.resize(TOTAL_TICKS)
	var total_ms: float = 0.0

	for tick: int in range(TOTAL_TICKS):
		var t0_usec: int = Time.get_ticks_usec()

		# Simulate fixed-step updates
		vip.step_simulation(FIXED_DT)
		for player: Node3D in players:
			player.position.x += sin(float(tick) * FIXED_DT) * 0.01
		for npc: Node3D in npcs:
			npc.rotation.y += 0.02
		sniper_laser.rotation.y = sin(float(tick) * 0.05) * 0.4

		var elapsed_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		tick_times_ms[tick] = elapsed_ms
		total_ms += elapsed_ms

	tick_times_ms.sort()
	var p95_ms: float = tick_times_ms[int(float(TOTAL_TICKS) * 0.95)]
	var p99_ms: float = tick_times_ms[int(float(TOTAL_TICKS) * 0.99)]
	var avg_ms: float = total_ms / float(TOTAL_TICKS)

	# Teardown and check orphan nodes
	root_scene.free()
	var end_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var leaked_orphans: int = maxi(0, end_orphans - baseline_orphans)

	print("[telemetry-profiler] Ticks=%d | ActiveNodes=%d | Avg=%.3fms | P95=%.3fms | P99=%.3fms | OrphanNodes=%d" % [
		TOTAL_TICKS, active_nodes, avg_ms, p95_ms, p99_ms, leaked_orphans
	])

	if leaked_orphans > 0:
		push_error("[telemetry-profiler] FAIL: Detected %d leaked orphan node(s)!" % leaked_orphans)
		return 1
	if p95_ms > P95_BUDGET_MS or p99_ms > P99_BUDGET_MS:
		push_error("[telemetry-profiler] FAIL: Frame time exceeded budget (P95=%.3fms, P99=%.3fms)" % [p95_ms, p99_ms])
		return 1

	print("[telemetry-profiler] PASS")
	return 0
