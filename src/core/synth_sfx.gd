class_name SynthSfx
extends Node
## Real-time procedural arcade sound & voice-chatter synthesizer using AudioStreamGenerator.
## Zero external audio files needed; auto-disables cleanly in `--headless` mode.

const SAMPLE_RATE: float = 22050.0

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _phase: float = 0.0
var _active_freq: float = 0.0
var _target_freq: float = 0.0
var _tone_timer: float = 0.0
var _tone_volume: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_player = AudioStreamPlayer.new()
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.08
	_player.stream = gen
	_player.volume_db = -11.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func play_shove_whoosh() -> void:
	_trigger_tone(180.0, 95.0, 0.14, 0.35)


func play_bottle_throw() -> void:
	_trigger_tone(520.0, 880.0, 0.16, 0.30)


func play_cash_reward() -> void:
	_trigger_tone(660.0, 1320.0, 0.24, 0.38)


func play_alert_chirp() -> void:
	_trigger_tone(840.0, 420.0, 0.12, 0.32)


func play_voice_syllable(rms: float) -> void:
	if _tone_timer > 0.03 or rms < 0.08:
		return
	var base_f: float = 165.0 + rms * 240.0
	_trigger_tone(base_f, base_f * 1.18, 0.055, minf(0.28, rms * 0.35))


func _trigger_tone(start_freq: float, end_freq: float, duration: float, vol: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_active_freq = start_freq
	_target_freq = end_freq
	_tone_timer = duration
	_tone_volume = vol


func _process(delta: float) -> void:
	if _playback == null or not is_finite(delta) or delta <= 0.0:
		return
	if _tone_timer > 0.0:
		_tone_timer = maxf(0.0, _tone_timer - delta)
		_active_freq = lerpf(_active_freq, _target_freq, clampf(delta * 18.0, 0.0, 1.0))
	else:
		_tone_volume = move_toward(_tone_volume, 0.0, delta * 4.0)

	var frames: int = _playback.get_frames_available()
	for _i: int in range(frames):
		if _tone_volume <= 0.001:
			_playback.push_frame(Vector2.ZERO)
		else:
			_phase = fmod(_phase + (_active_freq / SAMPLE_RATE), 1.0)
			var sample: float = (sin(_phase * TAU) * 0.7 + signf(sin(_phase * TAU)) * 0.3) * _tone_volume
			_playback.push_frame(Vector2(sample, sample))
