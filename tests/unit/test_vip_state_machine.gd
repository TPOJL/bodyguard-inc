extends SceneTree
## Headless unit test suite for VipStateMachine (strict static typing & NaN safety).
## Run: godot --headless --path . --script res://tests/unit/test_vip_state_machine.gd

const VipStateMachine := preload("res://src/vip/vip_state_machine.gd")

var _failures: int = 0


func _init() -> void:
	print("[unit-test] Running VipStateMachine tests...")
	_test_host_authoritative_death_transition()
	_test_client_cannot_mutate_vip_state()
	_test_nan_and_inf_impulse_guard()
	_test_corpse_to_exposed_on_full_suspicion()

	if _failures > 0:
		print("[unit-test] FAIL (%d failure(s))" % _failures)
		quit(1)
		return

	print("[unit-test] PASS (4/4 VipStateMachine unit tests passed)")
	quit(0)


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		push_error("[ASSERT FAIL] %s" % message)
		_failures += 1


func _test_host_authoritative_death_transition() -> void:
	var vip: VipStateMachine = VipStateMachine.new()
	_assert_true(vip.state == VipStateMachine.VipState.ALIVE, "VIP starts ALIVE")
	vip.apply_damage_authoritative(100.0, true)
	_assert_true(vip.state == VipStateMachine.VipState.CORPSE, "VIP transitions ALIVE -> CORPSE on lethal host damage")
	vip.free()


func _test_client_cannot_mutate_vip_state() -> void:
	var vip: VipStateMachine = VipStateMachine.new()
	vip.apply_damage_authoritative(100.0, false)
	_assert_true(vip.state == VipStateMachine.VipState.ALIVE, "Client must not mutate VIP alive/dead state")
	vip.add_suspicion_authoritative(100.0, false)
	_assert_true(vip.suspicion == 0.0, "Client must not mutate VIP suspicion")
	vip.free()


func _test_nan_and_inf_impulse_guard() -> void:
	var vip: VipStateMachine = VipStateMachine.new()
	var nan_res: Vector3 = vip.sanitize_impulse(Vector3(NAN, 10.0, 0.0))
	_assert_true(nan_res == Vector3.ZERO, "NaN impulse must be rejected as Vector3.ZERO")
	var inf_res: Vector3 = vip.sanitize_impulse(Vector3(INF, -INF, 0.0))
	_assert_true(inf_res == Vector3.ZERO, "INF impulse must be rejected as Vector3.ZERO")
	var huge_res: Vector3 = vip.sanitize_impulse(Vector3(9999.0, 0.0, 0.0), 150.0)
	_assert_true(is_equal_approx(huge_res.length(), 150.0), "Huge impulse must clamp to max_magnitude")
	vip.free()


func _test_corpse_to_exposed_on_full_suspicion() -> void:
	var vip: VipStateMachine = VipStateMachine.new()
	vip.apply_damage_authoritative(150.0, true)
	vip.add_suspicion_authoritative(100.0, true)
	_assert_true(vip.state == VipStateMachine.VipState.EXPOSED, "Corpse transitions to EXPOSED at 100 suspicion")
	vip.free()
