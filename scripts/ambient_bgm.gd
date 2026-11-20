class_name AmbientBgm
extends Node
## Procedural cozy-cute-dark ambient Background Music (BGM) player.
## Synthesizes two seamless looping WAV layers (Cozy Meadow/Village chimes +
## Dark Cavern/Webwood resonance) and crossfades them with environment & night state.

const SAMPLE_RATE := 22050
const LOOP_SECS := 12.0

var _cozy_player: AudioStreamPlayer
var _dark_player: AudioStreamPlayer
var _dark_mix: float = 0.12
var _settings: Node = null
var _cave_atm: Node = null
var _time_weather: Node = null
var _accum_t: float = 0.0
var _synth_task_id: int = -1
var _synth_ready: bool = false
var _synth_fade_in: float = 0.0


func _ready() -> void:
	add_to_group("ambient_bgm")
	if DisplayServer.get_name() == "headless":
		return
	_settings = SlimeSettings.get_or_create()

	_cozy_player = AudioStreamPlayer.new()
	_cozy_player.name = "CozyBgmPlayer"
	_cozy_player.volume_db = -80.0
	add_child(_cozy_player)

	_dark_player = AudioStreamPlayer.new()
	_dark_player.name = "DarkBgmPlayer"
	_dark_player.volume_db = -80.0
	add_child(_dark_player)

	# Synthesize both looping PCM WAV streams on a background worker thread so
	# startup never stalls the main thread (~860ms saved during debug boot).
	_synth_task_id = WorkerThreadPool.add_task(_synth_worker_task)


func _synth_worker_task() -> void:
	var cozy_wav := _synth_cozy_loop()
	var dark_wav := _synth_dark_loop()
	call_deferred("_on_bgm_synthesized", cozy_wav, dark_wav)


func _on_bgm_synthesized(cozy_wav: AudioStreamWAV, dark_wav: AudioStreamWAV) -> void:
	if _synth_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_synth_task_id)
		_synth_task_id = -1
	if not is_inside_tree() or _cozy_player == null or _dark_player == null:
		return
	_cozy_player.stream = cozy_wav
	_dark_player.stream = dark_wav
	_cozy_player.play()
	_dark_player.play()
	_synth_ready = true
	_synth_fade_in = 0.0
	_update_volumes(0.05)


func _exit_tree() -> void:
	if _synth_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_synth_task_id)
		_synth_task_id = -1


func _process(delta: float) -> void:
	if _cozy_player == null or _dark_player == null or not _synth_ready:
		return
	if _synth_fade_in < 1.0:
		_synth_fade_in = minf(1.0, _synth_fade_in + delta * 1.8)
	_accum_t += delta
	if _accum_t < 0.15:
		return
	var step := _accum_t
	_accum_t = 0.0
	_update_volumes(step)


func _update_volumes(step: float) -> void:
	if _settings == null or not is_instance_valid(_settings):
		_settings = SlimeSettings.get_or_create()
	var muted := false
	var master_v := 0.8
	var music_v := 0.7
	if _settings != null:
		var mv = _settings.get_value("audio", "mute_all")
		muted = mv is bool and mv
		var mst = _settings.get_value("audio", "master_volume")
		if mst != null:
			master_v = clampf(float(mst) / 100.0, 0.0, 1.0)
		var mus = _settings.get_value("audio", "music_volume")
		if mus != null:
			music_v = clampf(float(mus) / 100.0, 0.0, 1.0)

	if _cave_atm == null or not is_instance_valid(_cave_atm):
		_cave_atm = get_tree().get_first_node_in_group("cave_atmosphere")
	if _time_weather == null or not is_instance_valid(_time_weather):
		_time_weather = get_tree().get_first_node_in_group("world_time_weather")

	var target_dark := 0.10
	if _cave_atm != null:
		var cf := float(_cave_atm.get("_cave_factor")) if "_cave_factor" in _cave_atm else 0.0
		var wf := float(_cave_atm.get("_webwood_factor")) if "_webwood_factor" in _cave_atm else 0.0
		var rf := float(_cave_atm.get("_ruins_factor")) if "_ruins_factor" in _cave_atm else 0.0
		target_dark = clampf(maxf(cf, maxf(wf * 0.82, rf * 0.65)), 0.10, 1.0)
	if _time_weather != null and "night_light_strength" in _time_weather:
		target_dark = clampf(maxf(target_dark, float(_time_weather.get("night_light_strength")) * 0.55), 0.10, 1.0)

	_dark_mix = lerpf(_dark_mix, target_dark, clampf(step * 1.4, 0.0, 1.0))

	var base_gain := 0.0 if muted else (master_v * music_v * 0.24 * _synth_fade_in)
	var cozy_gain := base_gain * (1.0 - _dark_mix * 0.72)
	var dark_gain := base_gain * (0.18 + _dark_mix * 0.82)
	_cozy_player.volume_db = linear_to_db(maxf(cozy_gain, 0.0001))
	_dark_player.volume_db = linear_to_db(maxf(dark_gain, 0.0001))


func _make_loop_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var v := clampi(int(roundf(clampf(samples[i], -0.95, 0.95) * 32767.0)), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _synth_cozy_loop() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * LOOP_SECS)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# Warm Fmaj7 -> Dm7 -> Bbmaj7 -> C6 cozy pad + gentle music-box pentatonic plucks
	var chords := [
		[174.61, 220.00, 261.63, 329.63],
		[146.83, 220.00, 261.63, 349.23],
		[116.54, 174.61, 220.00, 293.66],
		[130.81, 196.00, 220.00, 261.63],
	]
	var bell_notes := [523.25, 659.25, 587.33, 440.0, 523.25, 698.46, 659.25, 523.25]
	var chord_len := LOOP_SECS / float(chords.size())
	var bell_step := LOOP_SECS / float(bell_notes.size())
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var ci := int(t / chord_len) % chords.size()
		var ct := fmod(t, chord_len) / chord_len
		var env_c := sin(ct * PI)
		var pad := 0.0
		for f: float in chords[ci]:
			pad += sin(TAU * f * t) * 0.11
		pad *= (0.35 + 0.65 * env_c)
		var bi := int(t / bell_step) % bell_notes.size()
		var bt := fmod(t, bell_step)
		var bf: float = bell_notes[bi]
		var bell := (sin(TAU * bf * t) + 0.30 * sin(TAU * bf * 2.0 * t)) * exp(-bt * 3.8) * 0.14
		buf[i] = (pad + bell) * 0.72
	return _make_loop_wav(buf)


func _synth_dark_loop() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * LOOP_SECS)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# Hollow D-minor cavern drone + soft glassy crystal chimes
	var chimes := [587.33, 698.46, 523.25, 440.0, 659.25, 440.0]
	var chime_step := LOOP_SECS / float(chimes.size())
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var swell := 0.55 + 0.45 * sin(TAU * t / LOOP_SECS)
		var drone := (sin(TAU * 73.42 * t) * 0.24 + sin(TAU * 110.0 * t) * 0.14 + sin(TAU * 146.83 * t) * 0.10) * swell
		var ci := int(t / chime_step) % chimes.size()
		var ct := fmod(t, chime_step)
		var cf: float = chimes[ci]
		var chime := sin(TAU * cf * t) * exp(-ct * 2.4) * 0.11
		buf[i] = (drone + chime) * 0.72
	return _make_loop_wav(buf)
