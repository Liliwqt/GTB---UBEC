extends Node
## Session text and push-to-talk voice communication.
##
## Clients submit data only to peer 1. The authoritative server validates and
## relays it to every peer, keeping client-to-client networking out of gameplay
## code. Voice uses 16-bit mono PCM at 16 kHz in 20 ms packets.

const MAX_CHAT_LENGTH := 240
const CHAT_COOLDOWN_MSEC := 350
const VOICE_SAMPLE_RATE := 16_000
const VOICE_PACKET_DURATION := 0.02
const VOICE_PACKET_FRAMES := 320
const VOICE_PACKET_BYTES := VOICE_PACKET_FRAMES * 2
const MAX_CAPTURE_PACKETS_PER_FRAME := 3
const MAX_VOICE_PACKETS_PER_SECOND := 60
## Maximum bytes of voice payload one peer may relay per second. The packet
## rate limit alone still lets a peer consume tens of KB/s of server uplink
## and re-broadcast bandwidth to every other player, so the byte rate is
## capped independently. 48 KB/s allows the intended 16 kHz mono stream
## (32 KB/s) with headroom for packet overhead.
const MAX_VOICE_BYTES_PER_SECOND := 48 * 1024
## A peer that exceeds the byte budget is disconnected rather than merely
## throttled, because a flooding peer can starve the server for everyone else.
const VOICE_FLOOD_GRACE_PERIODS := 3

@onready var overlay: Variant = $CommunicationOverlay

var _is_talking := false
var _input_frame_count := 0
var _last_chat_at: Dictionary[int, int] = {}
var _voice_players: Dictionary[int, AudioStreamPlayer] = {}
var _voice_playbacks: Dictionary[int, AudioStreamGeneratorPlayback] = {}
var _voice_window_started_at: Dictionary[int, int] = {}
var _voice_packets_in_window: Dictionary[int, int] = {}
var _voice_bytes_in_window: Dictionary[int, int] = {}
var _voice_over_budget_periods: Dictionary[int, int] = {}


func _ready() -> void:
	overlay.message_submitted.connect(send_chat_message)
	overlay.talking_changed.connect(set_talking)
	NetworkManager.peer_disconnected.connect(_remove_voice_peer)
	overlay.add_system_message(
		"Enter: text chat  •  Hold V or the mic button: push to talk"
	)
	if NetworkManager.is_dedicated_server():
		overlay.hide()
	_refresh_input_frame_count()


func _exit_tree() -> void:
	if _is_talking:
		AudioServer.set_input_device_active(false)


func _process(_delta: float) -> void:
	if not _is_talking or NetworkManager.mode == NetworkManager.Mode.OFFLINE:
		return

	var packets_sent := 0
	while (
		AudioServer.get_input_frames_available() >= _input_frame_count
			and packets_sent < MAX_CAPTURE_PACKETS_PER_FRAME
	):
		var input_frames := AudioServer.get_input_frames(_input_frame_count)
		if input_frames.is_empty():
			break
		_send_voice_packet(_encode_voice_packet(input_frames))
		packets_sent += 1


func send_chat_message(raw_message: String) -> void:
	var message := _sanitize_message(raw_message)
	if message.is_empty():
		return

	if NetworkManager.mode == NetworkManager.Mode.OFFLINE:
		_display_chat(multiplayer.get_unique_id(), message)
	elif multiplayer.is_server():
		_relay_chat.rpc(multiplayer.get_unique_id(), message)
	else:
		_submit_chat.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, message)


func set_talking(active: bool) -> void:
	if active == _is_talking:
		return
	if active:
		if OS.has_feature("android"):
			OS.request_permissions()
		var error := AudioServer.set_input_device_active(true)
		if error != OK:
			overlay.set_voice_status("Microphone unavailable (error %d)" % error)
			return
		_refresh_input_frame_count()
		_is_talking = true
		overlay.set_voice_status(
			"Talking (offline)" if NetworkManager.mode == NetworkManager.Mode.OFFLINE
			else "Talking",
			true
		)
	else:
		_is_talking = false
		AudioServer.set_input_device_active(false)
		overlay.set_voice_status("Voice ready — hold V")


@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_chat(raw_message: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var message := _sanitize_message(raw_message)
	if message.is_empty() or not _can_send_chat(sender_id):
		return
	_relay_chat.rpc(sender_id, message)


@rpc("authority", "call_local", "reliable", 0)
func _relay_chat(sender_id: int, message: String) -> void:
	_display_chat(sender_id, message)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_voice(packet: PackedByteArray) -> void:
	if not multiplayer.is_server() or packet.size() != VOICE_PACKET_BYTES:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _can_relay_voice(sender_id):
		return
	if not _is_within_voice_byte_budget(sender_id, packet.size()):
		_register_voice_budget_violation(sender_id)
		return
	_relay_voice.rpc(sender_id, packet)


@rpc("authority", "call_local", "unreliable_ordered", 1)
func _relay_voice(sender_id: int, packet: PackedByteArray) -> void:
	if sender_id == multiplayer.get_unique_id():
		return
	_push_voice_packet(sender_id, packet)


func _send_voice_packet(packet: PackedByteArray) -> void:
	if multiplayer.is_server():
		_relay_voice.rpc(multiplayer.get_unique_id(), packet)
	else:
		_submit_voice.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, packet)


func _encode_voice_packet(input_frames: PackedVector2Array) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(VOICE_PACKET_BYTES)
	for output_index in range(VOICE_PACKET_FRAMES):
		var source_index := mini(
			floori(
				float(output_index) * input_frames.size()
					/ VOICE_PACKET_FRAMES
			),
			input_frames.size() - 1
		)
		var stereo_frame := input_frames[source_index]
		var mono_sample := clampf(
			(stereo_frame.x + stereo_frame.y) * 0.5,
			-1.0,
			1.0
		)
		packet.encode_s16(output_index * 2, roundi(mono_sample * 32767.0))
	return packet


func _push_voice_packet(sender_id: int, packet: PackedByteArray) -> void:
	if packet.size() != VOICE_PACKET_BYTES:
		return
	var playback := _get_voice_playback(sender_id)
	if playback.get_frames_available() < VOICE_PACKET_FRAMES:
		return
	var frames := PackedVector2Array()
	frames.resize(VOICE_PACKET_FRAMES)
	for frame_index in range(VOICE_PACKET_FRAMES):
		var sample := packet.decode_s16(frame_index * 2) / 32768.0
		frames[frame_index] = Vector2(sample, sample)
	playback.push_buffer(frames)


func _get_voice_playback(sender_id: int) -> AudioStreamGeneratorPlayback:
	if _voice_playbacks.has(sender_id):
		return (
			_voice_playbacks[sender_id] as AudioStreamGeneratorPlayback
		)

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = VOICE_SAMPLE_RATE
	generator.buffer_length = 0.3
	var player := AudioStreamPlayer.new()
	player.name = "VoicePeer%d" % sender_id
	player.stream = generator
	add_child(player)
	player.play()
	var playback := (
		player.get_stream_playback() as AudioStreamGeneratorPlayback
	)
	_voice_players[sender_id] = player
	_voice_playbacks[sender_id] = playback
	return playback


func _remove_voice_peer(peer_id: int) -> void:
	_voice_playbacks.erase(peer_id)
	_voice_window_started_at.erase(peer_id)
	_voice_packets_in_window.erase(peer_id)
	_voice_bytes_in_window.erase(peer_id)
	_voice_over_budget_periods.erase(peer_id)
	# The chat cooldown map is keyed by peer id too. Leaving it behind would
	# grow it by one entry per disconnect for the whole lifetime of the
	# server.
	_last_chat_at.erase(peer_id)
	var player := _voice_players.get(peer_id) as AudioStreamPlayer
	_voice_players.erase(peer_id)
	if player != null:
		player.queue_free()


func _display_chat(sender_id: int, message: String) -> void:
	overlay.add_chat_message(_peer_display_name(sender_id), message)


func _peer_display_name(peer_id: int) -> String:
	var player := get_node_or_null("../Players/%d" % peer_id)
	if player != null:
		var profile = player.get("character_profile")
		if profile is CharacterProfile:
			return "%s [%d]" % [profile.display_name, peer_id]
	return "Player %d" % peer_id


func _sanitize_message(raw_message: String) -> String:
	var message := raw_message.replace("\n", " ").replace("\r", " ")
	message = message.strip_edges()
	return message.left(MAX_CHAT_LENGTH)


func _can_send_chat(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var last_sent: int = _last_chat_at.get(
		peer_id,
		-CHAT_COOLDOWN_MSEC
	)
	if now - last_sent < CHAT_COOLDOWN_MSEC:
		return false
	_last_chat_at[peer_id] = now
	return true


func _can_relay_voice(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var window_started: int = _voice_window_started_at.get(peer_id, now)
	var packet_count: int = _voice_packets_in_window.get(peer_id, 0)
	if now - window_started >= 1000:
		window_started = now
		packet_count = 0
		_voice_bytes_in_window[peer_id] = 0
	if packet_count >= MAX_VOICE_PACKETS_PER_SECOND:
		return false
	_voice_window_started_at[peer_id] = window_started
	_voice_packets_in_window[peer_id] = packet_count + 1
	return true


## Tracks how many voice bytes a peer relayed during the current one-second
## window and reports whether the peer stays inside the server's byte budget.
##
## The packet-rate limit alone does not bound bandwidth: a peer that keeps
## sending full-size packets stays under the packet cap while still pushing
## tens of KB/s through the server, and the server re-broadcasts every byte to
## every other player. This budget bounds that cost directly.
func _is_within_voice_byte_budget(peer_id: int, byte_count: int) -> bool:
	var now := Time.get_ticks_msec()
	var window_started: int = _voice_window_started_at.get(peer_id, now)
	var bytes_in_window: int = _voice_bytes_in_window.get(peer_id, 0)
	if now - window_started >= 1000:
		window_started = now
		bytes_in_window = 0
	_voice_window_started_at[peer_id] = window_started
	_voice_bytes_in_window[peer_id] = bytes_in_window + byte_count
	return bytes_in_window + byte_count <= MAX_VOICE_BYTES_PER_SECOND


## Records that a peer exceeded the voice byte budget. A peer that stays over
## budget for several consecutive windows is disconnected so it cannot starve
## the server and every other player.
func _register_voice_budget_violation(peer_id: int) -> void:
	var periods: int = _voice_over_budget_periods.get(peer_id, 0) + 1
	_voice_over_budget_periods[peer_id] = periods
	if periods < VOICE_FLOOD_GRACE_PERIODS:
		return
	_voice_over_budget_periods.erase(peer_id)
	push_warning(
		"CommunicationManager: disconnecting peer %d for flooding the voice relay"
			% peer_id
	)
	_disconnect_flooding_peer(peer_id)


## Removes a flooding peer from the session. The dedicated server closes the
## peer's transport; a hosted game asks ENet to drop the connection.
func _disconnect_flooding_peer(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return
	if peer is ENetMultiplayerPeer:
		(peer as ENetMultiplayerPeer).close()
		return
	# Fall back to Godot's generic disconnect path for other peer types.
	multiplayer.multiplayer_peer = null
	_remove_voice_peer(peer_id)


func _refresh_input_frame_count() -> void:
	_input_frame_count = maxi(
		roundi(AudioServer.get_input_mix_rate() * VOICE_PACKET_DURATION),
		1
	)
