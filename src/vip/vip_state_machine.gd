class_name VipStateMachine
extends Node3D
## Minimal dummy VIP state machine to prove autonomous testing & hooks end-to-end.
## Authoritative Owner: Host (peer_id == 1) exclusively.

enum VipState {
	ALIVE,
	CORPSE,
	EXPOSED,
}

signal state_changed(previous_state: VipState, next_state: VipState)

const MAX_HEALTH: float = 100.0
const MAX_SUSPICION: float = 100.0
const DEFAULT_MAX_IMPULSE: float = 150.0

var state: VipState = VipState.ALIVE
var health: float = MAX_HEALTH
var suspicion: float = 0.0
var simulation_ticks: int = 0


func _physics_process(delta: float) -> void:
	step_simulation(delta)


func step_simulation(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	simulation_ticks += 1
	if state == VipState.CORPSE and suspicion >= MAX_SUSPICION:
		_transition_to(VipState.EXPOSED)


func apply_damage_authoritative(amount: float, is_host: bool) -> void:
	if not is_host:
		return
	if not is_finite(amount) or amount <= 0.0:
		return
	if state != VipState.ALIVE:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_transition_to(VipState.CORPSE)


func add_suspicion_authoritative(delta_suspicion: float, is_host: bool) -> void:
	if not is_host:
		return
	if not is_finite(delta_suspicion):
		return
	suspicion = clampf(suspicion + delta_suspicion, 0.0, MAX_SUSPICION)
	if state == VipState.CORPSE and suspicion >= MAX_SUSPICION:
		_transition_to(VipState.EXPOSED)


func sanitize_impulse(raw_impulse: Vector3, max_magnitude: float = DEFAULT_MAX_IMPULSE) -> Vector3:
	if not raw_impulse.is_finite():
		return Vector3.ZERO
	if not is_finite(max_magnitude) or max_magnitude <= 0.0:
		return Vector3.ZERO
	return raw_impulse.limit_length(max_magnitude)


func _transition_to(next_state: VipState) -> void:
	if state == next_state:
		return
	var prev: VipState = state
	state = next_state
	state_changed.emit(prev, next_state)
