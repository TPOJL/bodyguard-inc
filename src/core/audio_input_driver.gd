class_name AudioInputDriver
extends RefCounted
## Proximity voice abstraction with deterministic MockAudioInput for headless testing.

enum MockEnvelope {
	SILENCE,
	TALKING,
	SCREAMING,
}

const NOISE_GATE_RMS: float = 0.08
const TALKING_MAX_RMS: float = 0.70
const MAX_JAW_ANGLE_DEG: float = 42.0

var _mock_enabled: bool = false
var _mock_envelope: MockEnvelope = MockEnvelope.SILENCE
var _custom_rms: float = -1.0


func set_mock_mode(enabled: bool) -> void:
	_mock_enabled = enabled


func set_mock_envelope(envelope: MockEnvelope) -> void:
	_mock_envelope = envelope
	_custom_rms = -1.0


func set_custom_mock_rms(rms: float) -> void:
	_custom_rms = clampf(rms, 0.0, 1.0) if is_finite(rms) else 0.0


func sample_rms() -> float:
	if _mock_enabled:
		if _custom_rms >= 0.0:
			return _custom_rms
		match _mock_envelope:
			MockEnvelope.SILENCE:
				return 0.02
			MockEnvelope.TALKING:
				return 0.45
			MockEnvelope.SCREAMING:
				return 0.95
	# Hardware microphone capture is wired in Phase 1; safe zero fallback in headless mode.
	return 0.0


static func compute_jaw_angle_deg(rms: float) -> float:
	if not is_finite(rms):
		return 0.0
	var clamped: float = clampf(rms, 0.0, 1.0)
	if clamped < NOISE_GATE_RMS:
		return 0.0
	if clamped <= TALKING_MAX_RMS:
		var t: float = (clamped - NOISE_GATE_RMS) / (TALKING_MAX_RMS - NOISE_GATE_RMS)
		return lerpf(5.0, 28.0, t)
	var scream_t: float = (clamped - TALKING_MAX_RMS) / (1.0 - TALKING_MAX_RMS)
	return lerpf(28.0, MAX_JAW_ANGLE_DEG, scream_t)


static func evaluate_guard_suspicion_delta(rms: float, vip_is_corpse: bool) -> float:
	if not vip_is_corpse:
		return 0.0
	var safe_rms: float = clampf(rms, 0.0, 1.0) if is_finite(rms) else 0.0
	if safe_rms < NOISE_GATE_RMS:
		return 18.0
	if safe_rms <= 0.65:
		return -12.0
	if safe_rms > 0.80:
		return 10.0
	return 0.0
