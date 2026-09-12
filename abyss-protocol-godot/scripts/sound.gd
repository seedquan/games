extends Node
## Reuse a bounded voice pool; synthesize each distinct cue once.

const VOICES := 12
const CUES := {
	"gun": preload("res://assets/audio/gun.wav"),
	"heavy": preload("res://assets/audio/heavy.wav"),
	"blade": preload("res://assets/audio/blade.wav"),
	"bow": preload("res://assets/audio/bow.wav"),
	"arc": preload("res://assets/audio/arc.wav"),
	"impact": preload("res://assets/audio/impact.wav"),
	"dash": preload("res://assets/audio/dash.wav"),
	"ui": preload("res://assets/audio/ui.wav"),
	"clear": preload("res://assets/audio/clear.wav"),
}
var cache: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var gain := 0.64
var ambience: AudioStreamPlayer

func _ready() -> void:
	for i in range(VOICES):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	ambience = AudioStreamPlayer.new()
	var stream: AudioStreamWAV = preload("res://assets/audio/station_ambience.wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	ambience.stream = stream
	add_child(ambience)
	if DisplayServer.get_name() != "headless":
		ambience.play()
	for pair in [[180.0, 0.06], [480.0, 0.06], [260.0, 0.1], [650.0, 0.07], [1000.0, 0.25], [90.0, 0.14]]:
		cue(pair[0], pair[1])

func cue(frequency: float, duration: float) -> AudioStreamWAV:
	var id := Vector2(frequency, duration)
	if cache.has(id):
		return cache[id]
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var count := int(duration * 22050)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t := float(i) / 22050.0
		var envelope := minf(t / 0.004, 1.0) * pow(1.0 - float(i) / count, 2.0)
		var wave := sin(TAU * frequency * t) * 0.8 + sin(TAU * frequency * 2.01 * t) * 0.2
		bytes.encode_s16(i * 2, int(wave * envelope * 32767.0))
	wav.data = bytes
	# Only game-authored cue pairs call this; still cap residency defensively.
	if cache.size() >= 64:
		cache.erase(cache.keys()[0])
	cache[id] = wav
	return wav

func play_tone(frequency: float, duration: float, volume: float) -> void:
	if gain <= 0.0 or DisplayServer.get_name() == "headless":
		return
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % VOICES
	voice.stop()
	voice.stream = cue(frequency, duration)
	voice.volume_db = linear_to_db(maxf(0.0001, volume * gain))
	voice.play()

func update_gain(value: float, ambient_gain := 0.0) -> void:
	gain = value
	if is_instance_valid(ambience):
		ambience.volume_db = linear_to_db(maxf(0.0001, ambient_gain))
		ambience.stream_paused = ambient_gain <= 0.0
	if gain <= 0.0:
		for voice in voices:
			voice.stop()

func _exit_tree() -> void:
	for voice in voices:
		voice.stop()
		voice.stream = null
	if is_instance_valid(ambience):
		ambience.stop()
		ambience.stream = null
	cache.clear()

func play_cue(id: String, volume := 0.16) -> void:
	if gain <= 0.0 or DisplayServer.get_name() == "headless" or not CUES.has(id):
		return
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % VOICES
	voice.stop()
	voice.stream = CUES[id]
	voice.volume_db = linear_to_db(maxf(0.0001, volume * gain))
	voice.play()
