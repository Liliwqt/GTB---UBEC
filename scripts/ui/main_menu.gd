extends Control

@onready var play_button: Button = %PlayButton
@onready var offline_button: Button = %OfflineButton
@onready var character_option: OptionButton = %CharacterOption
@onready var status_label: Label = %StatusLabel

const WORLD_SCENE := "res://scenes/worlds/ley_liw.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_buttons_enabled(true)
	_populate_character_options()
	if not NetworkManager.last_connection_error.is_empty():
		status_label.text = NetworkManager.last_connection_error
		NetworkManager.last_connection_error = ""

	play_button.pressed.connect(_on_play_pressed)
	offline_button.pressed.connect(_on_offline_pressed)
	character_option.item_selected.connect(_on_character_selected)

	NetworkManager.connection_failed.connect(_on_connection_failed)


func _populate_character_options() -> void:
	character_option.clear()
	for i in range(CharacterRegistry.profiles.size()):
		var profile := CharacterRegistry.profiles[i]
		character_option.add_item(profile.display_name, i)

	if CharacterRegistry.profiles.size() > 0:
		character_option.select(0)
		CharacterSelectionState.selected_profile = CharacterRegistry.profiles[0]
	else:
		status_label.text = "No playable character profiles were found."
		_set_buttons_enabled(false)


func _on_character_selected(index: int) -> void:
	if index >= 0 and index < CharacterRegistry.profiles.size():
		CharacterSelectionState.selected_profile = CharacterRegistry.profiles[index]


func _set_buttons_enabled(enabled: bool) -> void:
	play_button.disabled = not enabled
	offline_button.disabled = not enabled
	character_option.disabled = not enabled


func _on_play_pressed() -> void:
	var address := NetworkManager.get_public_server_address()
	if address.is_empty():
		status_label.text = (
			"No open-world server address is configured for this build."
		)
		_set_buttons_enabled(true)
		return
	var port := NetworkManager.get_public_server_port()
	status_label.text = "Connecting to the open world..."
	_set_buttons_enabled(false)
	if NetworkManager.start_client(address, port) == OK:
		# Load replicated scene paths while ENet is still connecting. This keeps
		# preplaced synchronizers from sending before the client owns the world.
		_change_to_world()


func _on_offline_pressed() -> void:
	status_label.text = "Starting offline open world..."
	_set_buttons_enabled(false)
	NetworkManager.start_offline()
	_change_to_world()


func _on_connection_failed() -> void:
	status_label.text = "The open-world server is unavailable. Please try again."
	_set_buttons_enabled(true)


func _change_to_world() -> void:
	var error := get_tree().change_scene_to_file(WORLD_SCENE)
	if error == OK:
		return
	status_label.text = "Could not load the world (error %d)." % error
	_set_buttons_enabled(true)
