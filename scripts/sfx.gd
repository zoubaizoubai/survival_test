extends Node

var streams := {}
var last_play := {}
var players: Array = []
var idx := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	streams["shoot"] = _tone(760.0, 420.0, 0.07, 0.22, "square")
	streams["kill"] = _tone(300.0, 90.0, 0.14, 0.32, "noise")
	streams["pickup"] = _tone(660.0, 990.0, 0.09, 0.28, "sine")
	streams["heal"] = _tone(440.0, 660.0, 0.16, 0.3, "sine")
	streams["hurt"] = _tone(180.0, 70.0, 0.18, 0.42, "saw")
	streams["thunder"] = _tone(900.0, 100.0, 0.2, 0.38, "noise")
	streams["levelup"] = _tone(520.0, 1040.0, 0.28, 0.38, "sine")
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)


func play(key: String) -> void:
	if not streams.has(key):
		return
	var now := Time.get_ticks_msec()
	if last_play.has(key) and now - int(last_play[key]) < 45:
		return
	last_play[key] = now
	var p: AudioStreamPlayer = players[idx]
	idx = (idx + 1) % players.size()
	p.stream = streams[key]
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


func _tone(f0: float, f1: float, dur: float, vol: float, shape: String) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var k := float(i) / float(n)
		var f := lerpf(f0, f1, k)
		phase += TAU * f / rate
		var s := 0.0
		match shape:
			"sine":
				s = sin(phase)
			"square":
				s = signf(sin(phase)) * 0.55
			"saw":
				s = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			"noise":
				s = rng.randf_range(-1.0, 1.0)
		var env := minf(k / 0.03, 1.0) * pow(1.0 - k, 1.4)
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
