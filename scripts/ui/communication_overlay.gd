class_name CommunicationOverlay
extends CanvasLayer

signal message_submitted(message: String)
signal talking_changed(active: bool)

@onready var history: RichTextLabel = %History
@onready var message_input: LineEdit = %MessageInput
@onready var send_button: Button = %SendButton
@onready var microphone_button: Button = %MicrophoneButton
@onready var voice_status: Label = %VoiceStatus

var message_count := 0
var _keyboard_talking := false
var _button_talking := false

@onready var chat_margin: MarginContainer = $ChatMargin


func _ready() -> void:
	send_button.pressed.connect(_submit_current_message)
	microphone_button.button_down.connect(_on_microphone_button_down)
	microphone_button.button_up.connect(_on_microphone_button_up)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"push_to_talk") and not event.is_echo():
		if not message_input.has_focus() and not _keyboard_talking:
			_keyboard_talking = true
			_emit_talking_state()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released(&"push_to_talk") and _keyboard_talking:
		_keyboard_talking = false
		_emit_talking_state()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"ui_cancel") and message_input.has_focus():
		_close_chat_input()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if (
		key_event.keycode != KEY_ENTER
			and key_event.keycode != KEY_KP_ENTER
			and key_event.physical_keycode != KEY_ENTER
			and key_event.physical_keycode != KEY_KP_ENTER
	):
		return

	if message_input.has_focus():
		_submit_current_message()
	else:
		message_input.grab_focus()
	get_viewport().set_input_as_handled()


func add_chat_message(sender_name: String, message: String) -> void:
	message_count += 1
	history.push_bold()
	history.add_text(sender_name)
	history.pop()
	history.add_text(": %s\n" % message)


func add_system_message(message: String) -> void:
	history.push_color(Color("8fb8de"))
	history.add_text(message + "\n")
	history.pop()


func set_voice_status(message: String, is_talking: bool = false) -> void:
	voice_status.text = message
	microphone_button.text = "Talking..." if is_talking else "Hold to Talk"
	microphone_button.modulate = (
		Color(1.0, 0.55, 0.55) if is_talking else Color.WHITE
	)


func _submit_current_message() -> void:
	var message := message_input.text.strip_edges()
	message_input.clear()
	_close_chat_input()
	if not message.is_empty():
		message_submitted.emit(message)


func _close_chat_input() -> void:
	message_input.release_focus()


func _on_microphone_button_down() -> void:
	_button_talking = true
	_emit_talking_state()


func _on_microphone_button_up() -> void:
	_button_talking = false
	_emit_talking_state()


func _emit_talking_state() -> void:
	talking_changed.emit(_keyboard_talking or _button_talking)


func _update_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	chat_margin.offset_right = minf(476.0, viewport_size.x - 16.0)
	chat_margin.offset_bottom = minf(270.0, viewport_size.y - 16.0)
