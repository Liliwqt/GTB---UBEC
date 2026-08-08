extends Control

@onready var singleplayer_button: Button = %SingleplayerButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var ip_line_edit: LineEdit = %IPLineEdit
@onready var character_option: OptionButton = %CharacterOption
@onready var status_label: Label = %StatusLabel
@onready var local_ip_label: Label = %LocalIPLabel

const WORLD_SCENE := "res://scenes/worlds/ley_liw.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_buttons_enabled(true)
	_populate_character_options()
	_update_local_ip_display()

	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
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


func _update_local_ip_display() -> void:
	var ips := IP.get_local_addresses()
	var valid_ips: Array[String] = []
	for ip in ips:
		if (
			not (":" in ip)
				and not ip.begins_with("127.")
				and not ip.begins_with("169.254.")
		):
			valid_ips.append(ip)

	if valid_ips.size() > 0:
		local_ip_label.text = "Host LAN IP(s): " + ", ".join(valid_ips)
	else:
		local_ip_label.text = "Your LAN IP: 127.0.0.1"


func _set_buttons_enabled(enabled: bool) -> void:
	singleplayer_button.disabled = not enabled
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	ip_line_edit.editable = enabled
	character_option.disabled = not enabled


func _on_singleplayer_pressed() -> void:
	status_label.text = "Starting Singleplayer..."
	_set_buttons_enabled(false)
	NetworkManager.start_offline()
	_change_to_world()


func _on_host_pressed() -> void:
	status_label.text = "Starting Host Server on port 7777..."
	_set_buttons_enabled(false)
	if NetworkManager.start_host(7777) == OK:
		_change_to_world()


func _on_join_pressed() -> void:
	var address := ip_line_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"

	status_label.text = "Connecting to %s:7777..." % address
	_set_buttons_enabled(false)
	if NetworkManager.start_client(address, 7777) == OK:
		# Load replicated scene paths while ENet is still connecting. This keeps
		# preplaced synchronizers from sending before the client owns the world.
		_change_to_world()


func _on_connection_failed() -> void:
	status_label.text = "Connection Failed! Check Host IP & Firewall (UDP 7777)."
	_set_buttons_enabled(true)


func _change_to_world() -> void:
	var error := get_tree().change_scene_to_file(WORLD_SCENE)
	if error == OK:
		return
	status_label.text = "Could not load the world (error %d)." % error
	_set_buttons_enabled(true)
