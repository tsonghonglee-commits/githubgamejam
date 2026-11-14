class_name PrototypeAudio
extends Node

const SAMPLE_RATE := 44100
const VOICES := 24
const BOSS_ENTRY_EVENTS := ["entry_ink", "entry_cyber", "entry_sea", "entry_empire"]
const WEAPON_EVENTS := ["red_draw","red_dock","plasma_ignite","plasma_cross","heavy_charge","heavy_release","heavy_wave"]
const EVENT_NAMES := ["slash", "unsheathe", "blade_whoosh", "sheathe", "guard_raise", "guard_release", "hit", "kill", "parry", "perfect", "hurt", "gear", "start", "win", "lose", "windup", "enemy_swing", "ranged_charge", "ranged_fire", "boss_charge", "parry_clash", "explosion", "explosion_reflected", "flyby", "carrier_engine", "boss_release", "heavy_land", "boss_ink_break", "boss_cyber_arc", "boss_sea_rupture", "boss_ship_collapse"]

var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _voice_cursors: Dictionary = {}
var _variation := 0
var _random := RandomNumberGenerator.new()
var _last_event_msec: Dictionary = {}
var _contact_duck := 0.0
var _strong_contact_frame := -1
var _runner_wind_low: AudioStreamPlayer
var _runner_wind_high: AudioStreamPlayer
var _runner_step_players: Array[AudioStreamPlayer] = []
var _runner_step_sounds: Array[AudioStreamWAV] = []
var _runner_active := false
var _runner_effective_speed := 0.0
var _runner_stride_phase := 0.0
var _runner_distance := 0.0
var _runner_steps := 0
var _runner_low_gain := 0.0
var _runner_high_gain := 0.0
var _runner_low_target := 0.0
var _runner_high_target := 0.0
var _runner_cue_duck := 0.0


func _ready() -> void:
	for event_name in EVENT_NAMES+BOSS_ENTRY_EVENTS+WEAPON_EVENTS:
		_sounds[event_name] = _synthesize(event_name)
	for index in range(VOICES):
		var player := AudioStreamPlayer.new()
		player.volume_db = -15.0
		add_child(player)
		_players.append(player)
	_setup_runner_layers()


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.001)
	_contact_duck = maxf(0.0, _contact_duck - real_dt)
	_runner_cue_duck = maxf(0.0, _runner_cue_duck - real_dt)
	for player in _players:
		if player.playing and str(player.get_meta("event", "")) in ["slash", "blade_whoosh"]:
			player.volume_db = float(player.get_meta("base_gain_db", -18.0)) - 7.0 * clampf(_contact_duck / 0.09, 0.0, 1.0)
	_update_runner_layers(real_dt)


func _exit_tree() -> void:
	for layer in [_runner_wind_low, _runner_wind_high]:
		if is_instance_valid(layer):
			layer.stop()
			layer.stream = null
	for step_player in _runner_step_players:
		if is_instance_valid(step_player):
			step_player.stop()
			step_player.stream = null
	_runner_step_players.clear()
	_runner_step_sounds.clear()
	for player in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_players.clear()
	_sounds.clear()
	_last_event_msec.clear()
	_voice_cursors.clear()


func play_event(kind: String, intensity: float = 1.0) -> void:
	if not _sounds.has(kind) or _players.is_empty():
		return
	var now := Time.get_ticks_msec()
	var frame := Engine.get_process_frames()
	# A sever / real steel clash owns the contact transient in this frame.
	# Several targets may emit callbacks from one physical sword pass.
	if kind == "hit" and frame == _strong_contact_frame:
		return
	var minimum_gap := 0
	match kind:
		"slash": minimum_gap = 74 if intensity <= 0.55 else 35
		"blade_whoosh": minimum_gap = 82
		"unsheathe", "sheathe", "guard_raise", "guard_release": minimum_gap = 48
		"red_draw", "red_dock", "plasma_ignite", "plasma_cross", "heavy_charge", "heavy_release", "heavy_wave": minimum_gap = 65
		"hit": minimum_gap = 38
		"kill": minimum_gap = 24
		"gear": minimum_gap = 70
		"windup", "ranged_charge", "boss_charge": minimum_gap = 90
		"enemy_swing", "ranged_fire": minimum_gap = 35
		"parry_clash": minimum_gap = 35
		"explosion", "explosion_reflected": minimum_gap = 40
		"flyby": minimum_gap = 150
		"carrier_engine": minimum_gap = 1600
		"boss_release", "heavy_land": minimum_gap = 120
		"boss_ink_break", "boss_cyber_arc", "boss_sea_rupture", "boss_ship_collapse": minimum_gap = 250
		"entry_ink", "entry_cyber", "entry_sea", "entry_empire": minimum_gap = 150
	if now - int(_last_event_msec.get(kind, -100000)) < minimum_gap:
		return
	_last_event_msec[kind] = now
	# Crack, low-end core break and ringing parries each keep their own tails.
	# A dense stream of air cuts cannot steal the voice carrying a sever or clash.
	var pool := Vector2i(20, 2)
	match kind:
		"hit", "hurt": pool = Vector2i(0, 4)
		"kill", "explosion": pool = Vector2i(4, 3)
		# Real reflected impacts keep two finite voices, so simultaneous sever
		# callbacks cannot steal the low pressure / tearing-metal blast tail.
		"explosion_reflected": pool = Vector2i(22, 2)
		"parry", "perfect", "parry_clash": pool = Vector2i(7, 3)
		"windup", "enemy_swing", "ranged_charge", "ranged_fire", "boss_charge": pool = Vector2i(10, 2)
		"unsheathe", "sheathe", "guard_raise", "guard_release": pool = Vector2i(12, 3)
		"red_draw", "red_dock", "plasma_ignite", "plasma_cross", "heavy_charge", "heavy_release", "heavy_wave": pool = Vector2i(12, 3)
		"slash", "blade_whoosh": pool = Vector2i(15, 5)
		"flyby", "carrier_engine", "boss_release": pool = Vector2i(20, 2)
		"heavy_land": pool = Vector2i(4, 3)
		"boss_ink_break", "boss_cyber_arc", "boss_sea_rupture", "boss_ship_collapse": pool = Vector2i(20, 2)
	var cursor: int = int(_voice_cursors.get(pool.x, 0))
	var voice: int = pool.x + cursor % pool.y
	for offset in range(pool.y):
		var candidate: int = pool.x + (cursor + offset) % pool.y
		if not _players[candidate].playing:
			voice = candidate
			break
	_voice_cursors[pool.x] = (voice - pool.x + 1) % pool.y
	var player := _players[voice]
	player.stop()
	player.stream = _sounds[kind]
	_variation += 1
	var variation: float = [-0.025, 0.018, -0.008, 0.033][_variation % 4]
	player.pitch_scale = clampf(0.97 + intensity * 0.035 + variation, 0.85, 1.15)
	player.volume_db = -13.0 + clampf(intensity, 0.2, 2.0) * 1.7
	if kind == "kill":
		player.volume_db += 2.5
		player.pitch_scale = 0.94 + intensity * 0.025 + variation
	elif kind == "hit":
		player.volume_db += 0.5
	elif kind == "explosion_reflected":
		player.volume_db += 2.0
		player.pitch_scale = 0.92 + intensity * 0.025 + variation
	elif kind == "carrier_engine":
		player.volume_db -= 4.0
		player.pitch_scale = 0.90
	elif kind == "heavy_land":
		player.volume_db += 2.0
		_runner_cue_duck = 0.65
	elif kind in BOSS_ENTRY_EVENTS:
		player.volume_db += 3.0
		_runner_cue_duck = 0.85
	elif kind in ["slash", "blade_whoosh"]:
		player.volume_db -= 4.0 if intensity <= 0.55 else 2.0
	elif kind in ["unsheathe", "sheathe", "guard_raise", "guard_release"]:
		player.volume_db -= 4.0
	elif kind in ["perfect", "parry"]:
		# Recognition lives in the resonant tail; the real clash owns the attack.
		player.volume_db -= 3.0
	if kind in ["windup", "ranged_charge", "boss_charge"]:
		player.volume_db -= 4.0
		_runner_cue_duck = 0.26
	if kind in ["hit", "kill", "parry_clash", "explosion_reflected"]:
		_contact_duck = 0.14 if kind == "explosion_reflected" else 0.09
	if kind in ["kill", "parry_clash"]:
		_strong_contact_frame = frame
		for contact_voice in _players:
			if contact_voice.playing and str(contact_voice.get_meta("event", "")) == "hit" and int(contact_voice.get_meta("event_frame", -1)) == frame:
				contact_voice.volume_db = minf(contact_voice.volume_db, float(contact_voice.get_meta("base_gain_db", -12.0)) - 24.0)
	player.set_meta("event", kind)
	player.set_meta("event_frame", frame)
	player.set_meta("base_gain_db", player.volume_db)
	if kind in ["slash", "blade_whoosh"]:
		player.volume_db -= 7.0 * clampf(_contact_duck / 0.09, 0.0, 1.0)
	player.play()


func set_runner_motion(speed: float, sim_dt: float, active: bool, world_scale: float = 1.0) -> void:
	# Environment time follows travel, while sword and impact voices stay in
	# real time. Explicit world_scale also handles a zero-time hit stop safely.
	_runner_active = active
	_runner_effective_speed = maxf(speed, 0.0) * maxf(world_scale, 0.0) if active else 0.0
	if not active or _runner_effective_speed < 0.01:
		_runner_low_target = 0.0
		_runner_high_target = 0.0
		return
	var pressure := clampf(_runner_effective_speed / 60.0, 0.0, 1.0)
	_runner_low_target = 0.020 + pow(pressure, 0.85) * 0.12
	_runner_high_target = 0.005 + pow(pressure, 1.65) * 0.105
	var distance := maxf(speed, 0.0) * maxf(sim_dt, 0.0)
	_runner_distance += distance
	var stride_length := lerpf(5.2, 10.5, clampf((speed - 18.0) / 42.0, 0.0, 1.0))
	var phase := _runner_stride_phase + distance / stride_length
	var steps := int(floor(phase))
	_runner_stride_phase = fposmod(phase, 1.0)
	for step_index in range(mini(steps, 2)):
		_play_runner_step(speed, _runner_steps + step_index)
	_runner_steps += steps


func get_runner_stride_phase() -> float:
	return _runner_stride_phase


func get_runner_gait_phase() -> float:
	return float(_runner_steps % 2) + _runner_stride_phase


func get_runner_audio_debug_state() -> Dictionary:
	return {"active": _runner_active, "effective_speed": _runner_effective_speed, "distance": _runner_distance, "stride_phase": _runner_stride_phase, "steps": _runner_steps, "wind_low_target": _runner_low_target, "wind_high_target": _runner_high_target, "wind_low_gain": _runner_low_gain, "wind_high_gain": _runner_high_gain, "contact_duck": _contact_duck, "cue_duck": _runner_cue_duck, "independent_step_voices": _runner_step_players.size()}


func _setup_runner_layers() -> void:
	_runner_wind_low = AudioStreamPlayer.new()
	_runner_wind_low.name = "RunnerPressureWind"
	_runner_wind_low.stream = _synthesize_runner_wind(false)
	_runner_wind_low.volume_db = -80.0
	add_child(_runner_wind_low)
	_runner_wind_high = AudioStreamPlayer.new()
	_runner_wind_high.name = "RunnerFastAir"
	_runner_wind_high.stream = _synthesize_runner_wind(true)
	_runner_wind_high.volume_db = -80.0
	add_child(_runner_wind_high)
	for index in range(2):
		_runner_step_sounds.append(_synthesize_runner_step(-1.0 if index == 0 else 1.0))
		var player := AudioStreamPlayer.new()
		player.name = "RunnerFootfall%d" % index
		add_child(player)
		_runner_step_players.append(player)


func _update_runner_layers(real_dt: float) -> void:
	var low_tau := 0.18 if _runner_low_target > _runner_low_gain else 0.075
	var high_tau := 0.13 if _runner_high_target > _runner_high_gain else 0.065
	_runner_low_gain = lerpf(_runner_low_gain, _runner_low_target, 1.0 - exp(-real_dt / low_tau))
	_runner_high_gain = lerpf(_runner_high_gain, _runner_high_target, 1.0 - exp(-real_dt / high_tau))
	var duck_db := maxf(8.0 * clampf(_contact_duck / 0.09, 0.0, 1.0), 5.0 * clampf(_runner_cue_duck / 0.26, 0.0, 1.0))
	var pressure := clampf(_runner_effective_speed / 60.0, 0.0, 1.0)
	if is_instance_valid(_runner_wind_low):
		_runner_wind_low.volume_db = linear_to_db(maxf(_runner_low_gain, 0.00001)) - duck_db
		_runner_wind_low.pitch_scale = lerpf(_runner_wind_low.pitch_scale, 0.78 + pressure * 0.38, 1.0 - exp(-real_dt * 8.0))
		if _runner_low_gain > 0.0002 and not _runner_wind_low.playing:
			_runner_wind_low.play()
		elif _runner_low_gain <= 0.0002 and _runner_wind_low.playing:
			_runner_wind_low.stop()
	if is_instance_valid(_runner_wind_high):
		_runner_wind_high.volume_db = linear_to_db(maxf(_runner_high_gain, 0.00001)) - duck_db
		_runner_wind_high.pitch_scale = lerpf(_runner_wind_high.pitch_scale, 0.82 + pressure * 0.54, 1.0 - exp(-real_dt * 8.0))
		if _runner_high_gain > 0.0002 and not _runner_wind_high.playing:
			_runner_wind_high.play()
		elif _runner_high_gain <= 0.0002 and _runner_wind_high.playing:
			_runner_wind_high.stop()


func _play_runner_step(speed: float, ordinal: int) -> void:
	if _runner_step_players.is_empty():
		return
	var index := posmod(ordinal, 2)
	var player := _runner_step_players[index]
	player.stop()
	player.stream = _runner_step_sounds[index]
	var pressure := clampf((speed - 18.0) / 42.0, 0.0, 1.0)
	player.volume_db = lerpf(-17.5, -13.5, pressure)
	player.pitch_scale = 0.95 + pressure * 0.13 + (-0.025 if index == 0 else 0.025)
	player.play()


func _synthesize_runner_wind(high_band: bool) -> AudioStreamWAV:
	var count := SAMPLE_RATE * 2
	var overlap := 768
	var samples := PackedFloat32Array()
	samples.resize(count + overlap)
	var random := RandomNumberGenerator.new()
	random.seed = 76129 if high_band else 61837
	var low := 0.0
	var smooth := 0.0
	var rumble := 0.0
	for index in range(samples.size()):
		var noise := random.randf_range(-1.0, 1.0)
		var time := float(index) / SAMPLE_RATE
		low = lerpf(low, noise, 0.018)
		smooth = lerpf(smooth, noise, 0.25)
		rumble = lerpf(rumble, noise, 0.002)
		var turbulence := 0.83 + sin(TAU * 1.5 * time) * 0.10 + sin(TAU * 3.5 * time) * 0.07
		samples[index] = tanh(((smooth - low) * 1.1 if high_band else low * 4.0 + rumble * 4.6) * turbulence) * 0.72
	# Blend the continuation into the loop's opening. The final/first samples
	# follow the same filtered-noise sequence instead of making a seam click.
	for index in range(overlap):
		var weight := smoothstep(0.0, 1.0, float(index) / float(overlap - 1))
		samples[index] = lerpf(samples[count + index], samples[index], weight)
	var bytes := PackedByteArray()
	bytes.resize(count * 4)
	for index in range(count):
		var right_index := (index + 1783) % count
		bytes.encode_s16(index * 4, int(samples[index] * 30000.0))
		bytes.encode_s16(index * 4 + 2, int(samples[right_index] * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream


func _synthesize_runner_step(side: float) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.19)
	var bytes := PackedByteArray()
	bytes.resize(count * 4)
	var random := RandomNumberGenerator.new()
	random.seed = 3167 + int(side + 1.0)
	var smooth := 0.0
	for index in range(count):
		var time := float(index) / SAMPLE_RATE
		var noise := random.randf_range(-1.0, 1.0)
		smooth = lerpf(smooth, noise, 0.16)
		var heel := sin(TAU * (91.0 * time + 0.65 * (1.0 - exp(-time * 40.0)))) * exp(-time * 35.0)
		var plate := sin(TAU * 427.0 * time) * exp(-time * 42.0) * 0.12 + sin(TAU * 943.0 * time) * exp(-time * 56.0) * 0.075
		var grip := smooth * exp(-time * 43.0) * 0.75 + noise * exp(-time * 150.0) * 0.38
		var toe := exp(-pow((time - 0.030) / 0.008, 2.0)) * smooth * 0.65
		var sample := tanh((heel * 0.72 + plate + grip + toe) * minf(time / 0.0006, 1.0)) * 27000.0
		bytes.encode_s16(index * 4, int(sample * (0.84 - side * 0.14)))
		bytes.encode_s16(index * 4 + 2, int(sample * (0.84 + side * 0.14)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = bytes
	return stream


func _synthesize(kind: String) -> AudioStreamWAV:
	var duration := 0.16
	match kind:
		"red_draw", "red_dock": duration = 0.21
		"plasma_ignite", "plasma_cross": duration = 0.30
		"heavy_charge", "heavy_release", "heavy_wave": duration = 0.37
		"slash", "blade_whoosh": duration = 0.19
		"unsheathe": duration = 0.19
		"sheathe": duration = 0.17
		"guard_raise": duration = 0.14
		"guard_release": duration = 0.12
		"hit": duration = 0.17
		"kill": duration = 0.38
		"parry": duration = 0.26
		"perfect": duration = 0.36
		"hurt": duration = 0.25
		"gear": duration = 0.22
		"start": duration = 0.45
		"win": duration = 0.7
		"lose": duration = 0.55
		"windup": duration = 0.34
		"enemy_swing": duration = 0.20
		"ranged_charge": duration = 0.42
		"ranged_fire": duration = 0.12
		"boss_charge": duration = 0.65
		"parry_clash": duration = 0.32
		"explosion": duration = 0.55
		"explosion_reflected": duration = 0.72
		"flyby": duration = 1.15
		"carrier_engine": duration = 3.6
		"boss_release": duration = 0.85
		"heavy_land": duration = 1.10
		"boss_ink_break": duration = 1.30
		"boss_cyber_arc": duration = 1.20
		"boss_sea_rupture": duration = 1.45
		"boss_ship_collapse": duration = 1.70
		"entry_ink": duration = 1.22
		"entry_cyber": duration = 1.16
		"entry_sea": duration = 1.55
		"entry_empire": duration = 2.05
	_random.seed = int(kind.hash())
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var smooth_noise := 0.0
	var low_noise := 0.0
	var previous_noise := 0.0
	for index in range(count):
		var t := float(index) / SAMPLE_RATE
		var phase := t / duration
		var noise := _random.randf_range(-1.0, 1.0)
		smooth_noise = lerpf(smooth_noise, noise, 0.32)
		low_noise = lerpf(low_noise, noise, 0.045)
		var air_noise := smooth_noise - low_noise
		var grit := noise - previous_noise
		previous_noise = noise
		var envelope := sin(minf(phase * 28.0, PI * 0.5)) * pow(1.0 - phase, 2.1)
		if kind in ["slash", "blade_whoosh", "unsheathe", "sheathe", "guard_raise", "guard_release", "hit", "kill", "parry", "perfect", "parry_clash", "explosion", "explosion_reflected", "flyby", "carrier_engine", "boss_release", "heavy_land"]:
			# The transient and metallic/air tails already have independent envelopes.
			# Only soften the sample boundary, rather than burying the initial contact.
			envelope = minf(t / 0.0008, 1.0) * smoothstep(0.0, 0.026, duration - t)
		var sample := 0.0
		match kind:
			"red_draw", "red_dock":
				var latch_time := 0.006 if kind == "red_draw" else 0.045
				var latch := exp(-absf(t-latch_time)*150.0)
				var slide := exp(-pow((t-0.033)/0.028,2.0))
				var frequency := 390.0 if kind == "red_dock" else 565.0
				var ring := sin(TAU*frequency*t)*exp(-t*27.0)
				sample = grit*latch*0.9+air_noise*slide*0.95+ring*0.58
			"plasma_ignite", "plasma_cross":
				var pitch := 96.0 if kind == "plasma_ignite" else 138.0
				var ramp := 470.0
				var hum := sin(TAU*(pitch*t+ramp*t*t))
				var octave := sin(TAU*(pitch*2.0*t+ramp*1.7*t*t))
				var surge := smoothstep(0.0,0.038,t)*exp(-t*6.5)
				sample = (hum*0.65+octave*0.28+air_noise*0.78)*surge
			"heavy_charge", "heavy_release", "heavy_wave":
				var drive := sin(TAU*(46.0*t+140.0*t*t))*exp(-t*7.0)
				var clank := sin(TAU*241.0*t)*exp(-t*25.0)
				var attack := exp(-pow((t-0.033)/0.033,2.0))
				sample = drive*0.8+clank*0.3+low_noise*attack*1.2
				if kind == "heavy_release": sample += grit*attack*0.65
				if kind == "heavy_wave": sample = sample*0.45+air_noise*exp(-t*6.5)*1.5+sin(TAU*(630.0*t-455.0*t*t))*exp(-t*8.0)*0.48
			"entry_ink":
				var resonance := sin(TAU*(89.0*t+31.0*t*t))*0.64+sin(TAU*(178.0*t+62.0*t*t))*0.25
				var steel := sin(TAU*1643.0*t)*exp(-absf(t-0.42)*11.0)
				sample = resonance*(0.35+0.65*phase)+steel*0.30+air_noise*0.45
			"entry_cyber":
				var piston := exp(-pow((t-0.10)/0.035,2.0))+exp(-pow((t-0.30)/0.056,2.0))*0.86
				var motor := sin(TAU*(87.0*t+70.0*t*t))*0.54+sin(TAU*185.0*t)*0.22
				sample = motor*(0.32+0.68*piston)+grit*piston*0.45+low_noise*0.70
			"entry_sea":
				var swell := exp(-pow((t-0.53)/0.32,2.0))
				var pressure := sin(TAU*(42.0*t+19.0*t*t))*0.9+sin(TAU*69.0*t)*0.28
				sample = (pressure+air_noise*1.25+low_noise*2.2)*swell
			"entry_empire":
				var drive := sin(TAU*(32.0*t+13.0*t*t))*0.9+sin(TAU*(64.0*t+26.0*t*t))*0.40
				var brake := sin(TAU*(129.0*t+32.0*t*t))*exp(-pow((t-0.82)/0.31,2.0))*0.42
				sample = (drive+brake+low_noise*1.6+air_noise*0.55)*smoothstep(0.0,0.35,t)
			"boss_ink_break":
				var ring := sin(TAU*741.0*t)*exp(-t*4.6)+sin(TAU*1198.0*t)*exp(-t*6.1)*0.35
				var paper := air_noise*exp(-pow((t-0.24)/0.19,2.0))*0.75
				sample = ring*0.58+paper+grit*exp(-t*85.0)*0.9
			"boss_cyber_arc":
				var falling := sin(TAU*(270.0*t-92.0*t*t))*exp(-t*3.0)*0.45
				var arc := air_noise*pow(maxf(0.0,sin(TAU*23.0*t)),8.0)*exp(-t*3.5)
				sample = falling+arc*1.5+low_noise*exp(-t*5.0)*1.6
			"boss_sea_rupture":
				var pressure := sin(TAU*(43.0*t+0.5*(1.0-exp(-t*12.0))))*exp(-t*3.6)
				var spray := air_noise*exp(-pow((t-0.32)/0.26,2.0))*1.5
				sample = pressure*0.9+spray+low_noise*exp(-t*2.9)*1.7
			"boss_ship_collapse":
				var bass := sin(TAU*29.0*t)*exp(-t*2.0)+sin(TAU*47.0*t)*exp(-t*3.3)*0.45
				var cascade := grit*(exp(-pow((t-0.05)/0.03,2.0))+exp(-pow((t-0.25)/0.07,2.0))+exp(-pow((t-0.58)/0.12,2.0)))
				sample = bass*1.0+low_noise*exp(-t*1.8)*2.1+cascade*0.85
			"flyby":
				var pass_env: float = exp(-pow((phase-0.24)/0.19,2.0))
				var turbine: float = sin(TAU*(130.0*t+180.0*t*t-105.0*t*t*t))
				sample = (air_noise*1.8+turbine*0.45+low_noise*0.75)*pass_env
			"carrier_engine":
				var engine_env: float = smoothstep(0.0,0.6,t)*smoothstep(0.0,0.7,duration-t)
				var engine: float = sin(TAU*39.0*t)*0.40+sin(TAU*58.4*t)*0.24+sin(TAU*117.0*t)*0.10
				sample = (engine+low_noise*1.6+air_noise*0.22)*(0.86+0.14*sin(TAU*7.0*t))*engine_env
			"boss_release":
				var latch: float = sin(TAU*840.0*t)*exp(-t*11.0)+sin(TAU*1297.0*t)*exp(-t*17.0)*0.55
				sample = latch*0.52+grit*exp(-t*60.0)*0.8+low_noise*exp(-t*5.0)*0.7
			"heavy_land":
				var ground: float = sin(TAU*(34.0*t+1.1*(1.0-exp(-t*30.0))))*exp(-t*4.8)
				var steel: float = sin(TAU*173.0*t)*exp(-t*12.0)*0.30+sin(TAU*547.0*t)*exp(-t*20.0)*0.16
				sample = ground*1.5+steel+grit*exp(-t*120.0)*1.05+low_noise*exp(-t*3.8)*1.4
			"slash", "blade_whoosh":
				# Air belongs to blade velocity, not every input packet or impact.
				# No metallic click / pitched chirp is hidden inside the air layer.
				var air := exp(-pow((t - 0.040) / 0.032, 2.0))
				var trailing_air := exp(-pow((t - 0.088) / 0.041, 2.0))
				sample = (air_noise * 1.65 + low_noise * 0.72 + noise * 0.075) * air + air_noise * trailing_air * 0.20
			"unsheathe":
				var lip := exp(-t * 235.0)
				var slide := exp(-pow((t - 0.033) / 0.022, 2.0))
				var steel := sin(TAU * 2813.0 * t) * exp(-t * 42.0) + sin(TAU * 4259.0 * t) * exp(-t * 59.0) * 0.42
				sample = grit * lip * 0.48 + air_noise * slide * 1.25 + steel * 0.17 + sin(TAU * 435.0 * t) * lip * 0.14
			"sheathe":
				var lock := exp(-t * 172.0)
				var cavity := sin(TAU * 342.0 * t) * exp(-t * 48.0)
				sample = noise * lock * 0.46 + cavity * 0.30 + sin(TAU * 1731.0 * t) * exp(-t * 52.0) * 0.18 + air_noise * exp(-t * 38.0) * 0.18
			"guard_raise":
				var catch := exp(-t * 175.0)
				sample = grit * catch * 0.23 + sin(TAU * 2371.0 * t) * exp(-t * 47.0) * 0.16 + sin(TAU * 3617.0 * t) * exp(-t * 66.0) * 0.10 + air_noise * exp(-pow((t - 0.023) / 0.021, 2.0)) * 0.66
			"guard_release":
				sample = low_noise * exp(-t * 36.0) * 0.48 + air_noise * exp(-pow((t - 0.019) / 0.017, 2.0)) * 0.58 + sin(TAU * 691.0 * t) * exp(-t * 72.0) * 0.10
			"hit":
				var bite := exp(-t * 105.0)
				var scrape := exp(-t * 24.0) * (0.58 + sin(TAU * 91.0 * t) * 0.42)
				var thud := sin(TAU * (105.0 * t + 1.4 * (1.0 - exp(-t * 25.0)))) * exp(-t * 33.0)
				sample = thud * 0.43 + noise * bite * 0.70 + air_noise * scrape * 0.80 + sin(TAU * 2287.0 * t) * exp(-t * 44.0) * 0.12 + sin(TAU * 3457.0 * t) * exp(-t * 58.0) * 0.08
			"kill":
				var break_crackle := exp(-pow((t - 0.023) / 0.005, 2.0)) + exp(-pow((t - 0.048) / 0.008, 2.0)) * 0.70 + exp(-pow((t - 0.083) / 0.011, 2.0)) * 0.38
				var low_impact := sin(TAU * (61.0 * t + 1.8 * (1.0 - exp(-t * 34.0)))) * exp(-t * 15.0)
				var torn_metal := sin(TAU * (1180.0 * t - 720.0 * t * t)) * exp(-t * 25.0)
				sample = low_impact * 0.72 + noise * exp(-t * 150.0) * 0.75 + low_noise * exp(-t * 18.0) * 0.45 + air_noise * break_crackle * 1.0 + torn_metal * 0.17 + sin(TAU * 2671.0 * t) * exp(-t * 35.0) * 0.10
			"parry":
				var tail := smoothstep(0.0, 0.018, t)
				sample = (sin(TAU * 1280.0 * t) * exp(-t * 18.0) * 0.25 + sin(TAU * 1917.0 * t) * exp(-t * 22.0) * 0.17 + sin(TAU * 2770.0 * t) * exp(-t * 30.0) * 0.08) * tail
			"perfect":
				var bloom := smoothstep(0.0, 0.026, t)
				var shimmer := 0.91 + sin(TAU * 19.0 * t) * 0.09
				sample = (sin(TAU * 1568.0 * t) * 0.28 + sin(TAU * 2352.0 * t) * 0.16 + sin(TAU * 3136.0 * t) * 0.09) * exp(-t * 12.0) * shimmer * bloom
			"hurt":
				sample = sin(TAU * (105.0 * t - 95.0 * t * t)) * 0.65 + smooth_noise * 0.3
			"gear":
				sample = sin(TAU * (440.0 * t + 900.0 * t * t)) * 0.5 + sin(TAU * 880.0 * t) * 0.12
			"start", "win":
				var note := int(phase * 4.0)
				var frequency: float = [440.0, 554.37, 659.25, 880.0][mini(note, 3)]
				sample = sin(TAU * frequency * t) * 0.45 + sin(TAU * frequency * 2.0 * t) * 0.12
			"lose":
				sample = sin(TAU * (220.0 * t - 95.0 * t * t)) * 0.5 + smooth_noise * 0.14
			"windup":
				var tension := (0.25 + phase * 0.75) * (0.6 + sin(TAU * 18.0 * t) * 0.4)
				sample = (sin(TAU * (140.0 * t + 180.0 * t * t)) * 0.34 + smooth_noise * 0.31 + sin(TAU * 960.0 * t) * 0.07) * tension
			"enemy_swing":
				var sweep := sin(phase * PI)
				sample = smooth_noise * sweep * 0.65 + sin(TAU * (510.0 * t - 620.0 * t * t)) * 0.12 + noise * exp(-t * 90.0) * 0.22
			"ranged_charge":
				var charge := pow(phase, 0.65)
				sample = (sin(TAU * (330.0 * t + 1150.0 * t * t)) * 0.28 + sin(TAU * (660.0 * t + 2200.0 * t * t)) * 0.10 + smooth_noise * 0.12) * charge
			"ranged_fire":
				sample = noise * exp(-t * 60.0) * 0.5 + sin(TAU * (980.0 * t - 2200.0 * t * t)) * 0.28 + sin(TAU * 110.0 * t) * exp(-t * 26.0) * 0.22
			"boss_charge":
				var throb := 0.65 + sin(TAU * (7.0 * t + 4.0 * t * t)) * 0.35
				sample = (sin(TAU * (67.0 * t + 18.0 * t * t)) * 0.48 + smooth_noise * 0.22 + sin(TAU * (560.0 * t + 300.0 * t * t)) * 0.11) * throb * (0.35 + phase * 0.65)
			"parry_clash":
				sample = grit * exp(-t * 205.0) * 0.54 + sin(TAU * 1470.0 * t) * exp(-t * 17.0) * 0.32 + sin(TAU * 2311.0 * t) * exp(-t * 22.0) * 0.23 + sin(TAU * 3293.0 * t) * exp(-t * 29.0) * 0.15 + sin(TAU * 5123.0 * t) * exp(-t * 48.0) * 0.08 + sin(TAU * 154.0 * t) * exp(-t * 32.0) * 0.40
			"explosion":
				var pressure := sin(TAU*(48.0*t+1.3*(1.0-exp(-t*30.0))))*exp(-t*12.0)
				var crack := noise*exp(-t*105.0)+air_noise*exp(-t*17.0)*0.7
				var rubble := low_noise*exp(-t*7.0)*(0.65+0.35*sin(TAU*37.0*t))
				sample = pressure*0.95+crack*0.9+rubble*0.8
			"explosion_reflected":
				var pressure := sin(TAU*(43.0*t+2.5*(1.0-exp(-t*34.0))))*exp(-t*8.0)
				var crack := grit*exp(-t*155.0)*0.70+noise*exp(-t*74.0)*0.85
				var tear := sin(TAU*(1730.0*t-820.0*t*t))*exp(-t*19.0)*0.30+sin(TAU*2917.0*t)*exp(-t*27.0)*0.14
				var chips := exp(-pow((t-0.031)/0.007,2.0))+exp(-pow((t-0.067)/0.011,2.0))*0.76+exp(-pow((t-0.118)/0.015,2.0))*0.48
				var rubble := low_noise*exp(-t*5.5)*(0.64+sin(TAU*29.0*t)*0.36)
				sample = pressure*1.30+crack*1.20+tear+air_noise*(exp(-t*13.0)*0.55+chips*0.90)+rubble*1.05
		var value := int(tanh(sample * envelope * 1.18) * 29000.0)
		bytes.encode_s16(index * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
