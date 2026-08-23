extends Node

# 程序化背景音乐 - 轻量循环，无资源依赖
var player: AudioStreamPlayer
var base_vol: float = 0.22

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.autoplay = false
	add_child(player)
	# 无头测试没有音频输出；创建 WAV 仍会注册 playback/stream，导致进程
	# 退出时留下 ObjectDB 实例，因此在 headless 下完全跳过音源构造。
	if DisplayServer.get_name() == "headless" or OS.has_feature("headless"):
		return
	player.stream = _make_music()
	player.volume_db = linear_to_db(base_vol)
	player.finished.connect(_on_finished)
	player.play()

func _on_finished() -> void:
	if player and not OS.has_feature("headless"):
		player.play()

func _make_music() -> AudioStreamWAV:
	var rate := 22050
	var dur := 8.0
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var chords: Array = [
		[261.6, 329.6, 392.0],
		[220.0, 261.6, 329.6],
		[174.6, 220.0, 261.6],
		[196.0, 246.9, 293.7],
	]
	for i in n:
		var t: float = float(i) / float(rate)
		var chord_idx: int = int(t / 2.0) % chords.size()
		var chord: Array = chords[chord_idx]
		var s := 0.0
		for f in chord:
			var vib: float = 1.0 + 0.02 * sin(TAU * 5.0 * t)
			s += sin(TAU * f * vib * t) * 0.22
			s += sin(TAU * f * 2.0 * t) * 0.08
		var env: float = 1.0
		if t < 0.05:
			env = t / 0.05
		elif t > dur - 0.05:
			env = (dur - t) / 0.05
		env *= 0.85 + 0.15 * sin(TAU * 0.5 * t)
		var v := int(clampf(s * env, -1.0, 1.0) * 14000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	wav.data = data
	return wav

func set_enabled(v: bool) -> void:
	if player:
		player.stream_paused = not v

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and player:
		player.stop()
		# AudioStreamPlaybackWAV keeps a reference to the generated stream after
		# stop(). Release it explicitly so scene changes and headless shutdown do
		# not leave the playback/stream pair alive.
		player.stream = null
