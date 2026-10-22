extends Node
## Manages the multiplayer peer connection for LeyLiw.
##
## Autoloaded as [code]NetworkManager[/code]. Call one of the three start
## methods before loading the world scene. The game defaults to offline
## singleplayer with no additional setup required.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connected_to_server
signal connection_failed

enum Mode { OFFLINE, HOST, CLIENT, DEDICATED_SERVER }

## Current network mode. Defaults to [enum Mode.OFFLINE].
var mode: Mode = Mode.OFFLINE

const DEFAULT_PORT := 7777
## Fallback address used when no other source is configured. Deliberately
## empty: a deployment endpoint must not be committed to a public repository,
## because that exposes the server's address to anyone who reads the source or
## the repository history.
##
## Resolution order, highest priority first:
##   1. `--server-address=<host>` command-line argument (development only).
##   2. `LEYLIW_SERVER_ADDRESS` environment variable (deployment).
##   3. `user://server_address.cfg` (per-user override on the local machine).
##   4. `res://server_address.cfg` (packaged into client exports; copy
##      `server_address.cfg.example` and keep the copy out of git).
##   5. This constant, which is empty by design.
const CONFIGURED_SERVER_ADDRESS := ""
const SERVER_ADDRESS_ENV_VAR := "LEYLIW_SERVER_ADDRESS"
const SERVER_PORT_ENV_VAR := "LEYLIW_SERVER_PORT"
const SERVER_ADDRESS_CONFIG_PATH := "res://server_address.cfg"
const SERVER_ADDRESS_USER_CONFIG_PATH := "user://server_address.cfg"
const PUBLIC_SERVER_PORT := DEFAULT_PORT
const MAX_PLAYERS := 16
const CONNECTION_TIMEOUT_SECONDS := 8.0
const WORLD_SCENE := "res://scenes/worlds/ley_liw.tscn"

var _connection_timer: Timer = null
var last_connection_error := ""


## Returns the production server address, or an empty string when no address
## has been configured. A command-line override is retained for
## editor/development testing without exposing an address field to players.
func get_public_server_address() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-address="):
			var address := argument.trim_prefix("--server-address=").strip_edges()
			if not address.is_empty():
				return address

	var environment_address := OS.get_environment(SERVER_ADDRESS_ENV_VAR).strip_edges()
	if not environment_address.is_empty():
		return environment_address

	var user_address := _read_address_from_config(SERVER_ADDRESS_USER_CONFIG_PATH)
	if not user_address.is_empty():
		return user_address

	var packaged_address := _read_address_from_config(SERVER_ADDRESS_CONFIG_PATH)
	if not packaged_address.is_empty():
		return packaged_address

	return CONFIGURED_SERVER_ADDRESS


## Returns [code]true[/code] when a server address has been configured through
## any supported source.
func has_public_server_address() -> bool:
	return not get_public_server_address().is_empty()


## Returns the production server UDP port, with optional development-only
## overrides matching the dedicated server's --port argument.
func get_public_server_port() -> int:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--server-port="):
			continue
		var requested_port := argument.trim_prefix("--server-port=").to_int()
		if requested_port >= 1 and requested_port <= 65535:
			return requested_port

	var environment_port := OS.get_environment(SERVER_PORT_ENV_VAR).strip_edges()
	if not environment_port.is_empty():
		var environment_value := environment_port.to_int()
		if environment_value >= 1 and environment_value <= 65535:
			return environment_value

	var user_port := _read_port_from_config(SERVER_ADDRESS_USER_CONFIG_PATH)
	if user_port > 0:
		return user_port

	var packaged_port := _read_port_from_config(SERVER_ADDRESS_CONFIG_PATH)
	if packaged_port > 0:
		return packaged_port

	return PUBLIC_SERVER_PORT


## Reads the `server/address` entry from a ConfigFile-formatted address file.
## Returns an empty string when the file is missing, unreadable, or does not
## contain a non-empty string address.
func _read_address_from_config(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return ""
	var value: Variant = config.get_value("server", "address", "")
	if typeof(value) != TYPE_STRING:
		return ""
	return str(value).strip_edges()


## Reads the `server/port` entry from a ConfigFile-formatted address file.
## Returns 0 when the file is missing, unreadable, or the port is out of range.
func _read_port_from_config(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return 0
	var value: Variant = config.get_value("server", "port", 0)
	if typeof(value) != TYPE_INT:
		return 0
	var port := int(value)
	if port < 1 or port > 65535:
		return 0
	return port


func _ready() -> void:
	_connection_timer = Timer.new()
	_connection_timer.one_shot = true
	_connection_timer.wait_time = CONNECTION_TIMEOUT_SECONDS
	_connection_timer.timeout.connect(_on_connection_timeout)
	add_child(_connection_timer)
	if _should_start_dedicated_server():
		var port := _get_dedicated_server_port()
		var error := start_dedicated_server(port)
		if error != OK:
			get_tree().quit(error)
			return
		print("LeyLiw dedicated server listening on UDP port %d" % port)
		_load_dedicated_world.call_deferred()
	else:
		# Also supports running a gameplay scene directly from the editor (F6).
		start_offline()


## Closes any active network session and restores offline singleplayer.
func start_offline() -> void:
	_connection_timer.stop()
	_disconnect_signals()
	# A null peer does not mean "offline server" in Godot 4.7. It leaves the
	# MultiplayerAPI unconfigured, so is_server(), get_unique_id(), authority
	# checks, MultiplayerSpawner, and MultiplayerSynchronizer all fail. The
	# dedicated offline peer keeps the normal peer ID 1/server semantics without
	# opening a socket, letting singleplayer use the same gameplay code path as
	# the host.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE


## Start as the authoritative server and listen on [param port]. Returns the
## ENet setup result so callers never enter the world after a failed bind.
func start_host(port: int = DEFAULT_PORT) -> Error:
	_connection_timer.stop()
	start_offline()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error(
			"NetworkManager: failed to create server on port %d (err %d)"
				% [port, err]
		)
		connection_failed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	_connect_signals()
	return OK


## Start a headless/public server without creating a local playable character.
func start_dedicated_server(port: int = DEFAULT_PORT) -> Error:
	var error := start_host(port)
	if error == OK:
		mode = Mode.DEDICATED_SERVER
	return error


## Begin connecting to a server at [param address]:[param port]. Returns only
## the immediate ENet setup result; final success remains signal-driven.
func start_client(address: String, port: int = DEFAULT_PORT) -> Error:
	last_connection_error = ""
	start_offline()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error(
			"NetworkManager: failed to connect to %s:%d (err %d)"
				% [address, port, err]
		)
		connection_failed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_connect_signals()
	_connection_timer.start()
	return OK


## Returns [code]true[/code] when this instance owns the world simulation
## (offline singleplayer or the host in multiplayer).
func is_server() -> bool:
	return (
		mode == Mode.OFFLINE
			or mode == Mode.HOST
			or mode == Mode.DEDICATED_SERVER
	)


func is_dedicated_server() -> bool:
	return mode == Mode.DEDICATED_SERVER


func _connect_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_connection_failed):
		multiplayer.server_disconnected.connect(_on_connection_failed)


func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_connection_failed):
		multiplayer.server_disconnected.disconnect(_on_connection_failed)


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	_connection_timer.stop()
	connected_to_server.emit()


func _on_connection_failed() -> void:
	_connection_timer.stop()
	last_connection_error = (
		"The open-world server is unavailable. Please try again."
	)
	start_offline()
	connection_failed.emit()


func _on_connection_timeout() -> void:
	if mode == Mode.CLIENT:
		push_error("NetworkManager: connection attempt timed out")
		_on_connection_failed()


func _should_start_dedicated_server() -> bool:
	return (
		OS.has_feature("dedicated_server")
			or "--dedicated-server" in OS.get_cmdline_user_args()
	)


func _get_dedicated_server_port() -> int:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--port="):
			continue
		var requested_port := argument.trim_prefix("--port=").to_int()
		if requested_port >= 1 and requested_port <= 65535:
			return requested_port
		push_warning(
			"NetworkManager: invalid server port '%s'; using %d"
				% [argument, DEFAULT_PORT]
		)
	return DEFAULT_PORT


func _load_dedicated_world() -> void:
	var error := get_tree().change_scene_to_file(WORLD_SCENE)
	if error != OK:
		push_error(
			"NetworkManager: dedicated server could not load world (err %d)"
				% error
		)
		get_tree().quit(error)
