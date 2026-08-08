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
const MAX_PLAYERS := 16
const CONNECTION_TIMEOUT_SECONDS := 8.0
const WORLD_SCENE := "res://scenes/worlds/ley_liw.tscn"

var _connection_timer: Timer = null


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
