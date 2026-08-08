extends AudioStreamPlayer
## Plays a user-supplied lobby track, or a lightweight generated ambient loop
## until a final music asset is assigned in the MainMenu scene.

@export var custom_music: AudioStream
@export_range(50.0, 140.0, 1.0) var tempo_bpm := 76.0

const MIX_RATE := 22050.0
const CHORD_BEATS := 4.0
const CHORDS := [
	[48, 51, 55], # C minor
	[44, 48, 51], # A-flat major
	[39, 43, 46], # E-flat major
	[46, 50, 53], # B-flat major
]

func _ready() -> void:
	bus = &"Music"
	if custom_music != null:
		stream = custom_music
		finished.connect(_restart_custom_music)
		play()
		set_process(false)
		return

	stream = _create_generated_loop()
	play()
	set_process(false)


func _create_generated_loop() -> AudioStreamWAV:
	var progression_beats := CHORD_BEATS * CHORDS.size()
	var progression_seconds := progression_beats * 60.0 / tempo_bpm
	var frame_count := roundi(progression_seconds * MIX_RATE)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	for frame_index in frame_count:
		var sample := clampf(_generate_sample(frame_index), -1.0, 1.0)
		var encoded := roundi(sample * 32767.0)
		pcm[frame_index * 2] = encoded & 0xff
		pcm[frame_index * 2 + 1] = (encoded >> 8) & 0xff

	var generated_loop := AudioStreamWAV.new()
	generated_loop.format = AudioStreamWAV.FORMAT_16_BITS
	generated_loop.mix_rate = roundi(MIX_RATE)
	generated_loop.stereo = false
	generated_loop.data = pcm
	generated_loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	generated_loop.loop_begin = 0
	generated_loop.loop_end = frame_count
	return generated_loop


func _generate_sample(sample_index: int) -> float:
	var seconds := float(sample_index) / MIX_RATE
	var beat := seconds * tempo_bpm / 60.0
	var chord_position := beat / CHORD_BEATS
	var chord_index := floori(chord_position) % CHORDS.size()
	var chord_phase := fmod(chord_position, 1.0)
	# Fade the pad at chord boundaries so the frequency change never clicks.
	var pad_envelope := sqrt(maxf(sin(PI * chord_phase), 0.0))

	var chord: Array = CHORDS[chord_index]
	var pad := 0.0
	for midi_note_value in chord:
		var midi_note := int(midi_note_value)
		var frequency := _midi_to_frequency(midi_note)
		pad += sin(TAU * frequency * seconds)
		pad += 0.22 * sin(TAU * frequency * 2.0 * seconds)
	pad = pad / float(chord.size()) * pad_envelope

	# A soft half-beat arpeggio makes the generated fallback feel musical while
	# remaining inexpensive enough for mobile and web builds.
	var note_position := beat * 2.0
	var note_step := floori(note_position)
	var note_phase := fmod(note_position, 1.0)
	var note := int(chord[note_step % chord.size()]) + 12
	var note_frequency := _midi_to_frequency(note)
	var pluck_envelope := exp(-6.5 * note_phase)
	var note_seconds := note_phase * (30.0 / tempo_bpm)
	var pluck := sin(TAU * note_frequency * note_seconds) * pluck_envelope

	return (pad * 0.075) + (pluck * 0.035)


func _midi_to_frequency(midi_note: int) -> float:
	return 440.0 * pow(2.0, (float(midi_note) - 69.0) / 12.0)


func _restart_custom_music() -> void:
	if custom_music != null:
		play()


func _exit_tree() -> void:
	stop()
	stream = null
