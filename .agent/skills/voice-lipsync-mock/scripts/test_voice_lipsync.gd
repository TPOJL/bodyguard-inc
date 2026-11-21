extends SceneTree
## Headless automated test for MockAudioInput -> Corpse Jaw Angle & Guard Reaction.
## Run: godot --headless --path . --script .agent/skills/voice-lipsync-mock/scripts/test_voice_lipsync.gd

const AudioInputDriver := preload("res://src/core/audio_input_driver.gd")


func _init() -> void:
	var exit_code: int = _run_tests()
	quit(exit_code)


func _run_tests() -> int:
	print("[voice-lipsync-mock] Testing synthetic voice envelopes (SILENCE, TALKING, SCREAMING)...")
	var driver: AudioInputDriver = AudioInputDriver.new()
	driver.set_mock_mode(true)

	# 1. Silence envelope -> jaw closed, guard suspicion rises
	driver.set_mock_envelope(AudioInputDriver.MockEnvelope.SILENCE)
	var rms_silence: float = driver.sample_rms()
	var jaw_silence: float = AudioInputDriver.compute_jaw_angle_deg(rms_silence)
	var susp_delta_silence: float = AudioInputDriver.evaluate_guard_suspicion_delta(rms_silence, true)
	if jaw_silence != 0.0 or susp_delta_silence <= 0.0:
		push_error("[voice-lipsync-mock] SILENCE failed: jaw=%.2f delta=%.2f" % [jaw_silence, susp_delta_silence])
		return 1

	# 2. Talking envelope -> jaw opens moderately, guard suspicion decreases
	driver.set_mock_envelope(AudioInputDriver.MockEnvelope.TALKING)
	var rms_talk: float = driver.sample_rms()
	var jaw_talk: float = AudioInputDriver.compute_jaw_angle_deg(rms_talk)
	var susp_delta_talk: float = AudioInputDriver.evaluate_guard_suspicion_delta(rms_talk, true)
	if jaw_talk < 5.0 or jaw_talk > 30.0 or susp_delta_talk >= 0.0:
		push_error("[voice-lipsync-mock] TALKING failed: jaw=%.2f delta=%.2f" % [jaw_talk, susp_delta_talk])
		return 1

	# 3. Screaming envelope -> jaw wide open (clamped <= 42 deg), guard suspicion rises
	driver.set_mock_envelope(AudioInputDriver.MockEnvelope.SCREAMING)
	var rms_scream: float = driver.sample_rms()
	var jaw_scream: float = AudioInputDriver.compute_jaw_angle_deg(rms_scream)
	var susp_delta_scream: float = AudioInputDriver.evaluate_guard_suspicion_delta(rms_scream, true)
	if jaw_scream < 28.0 or jaw_scream > 42.0 or susp_delta_scream <= 0.0:
		push_error("[voice-lipsync-mock] SCREAMING failed: jaw=%.2f delta=%.2f" % [jaw_scream, susp_delta_scream])
		return 1

	# 4. NaN / out-of-range guard
	var jaw_nan: float = AudioInputDriver.compute_jaw_angle_deg(NAN)
	if jaw_nan != 0.0:
		push_error("[voice-lipsync-mock] NaN RMS guard failed: jaw=%.2f" % jaw_nan)
		return 1

	print("[voice-lipsync-mock] PASS (jaw: silence=%.1f°, talk=%.1f°, scream=%.1f°)" % [jaw_silence, jaw_talk, jaw_scream])
	return 0
