extends Node
## Spawns and despawns players in the LeyLiw world.
##
## Attach this script to the [code]GameManager[/code] node inside
## [code]ley_liw.tscn[/code]. Works identically in offline singleplayer and
## networked multiplayer — no extra configuration required for singleplayer.
##
## Spawn flow:
## [codeblock]
## _ready()
##   → if server (or offline): _spawn_player(my_peer_id)
##   → clients request their spawn only after their world is ready
##   → MultiplayerSpawner replicates spawn to connected clients
##   → each spawned player node's is_multiplayer_authority() returns true
##     only for the owning peer
## [/codeblock]

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var _players: Node3D = $"../Players"
@onready var _spawn_point: Node3D = $"../SpawnPoint"
@onready var _spawner: MultiplayerSpawner = $"../MultiplayerSpawner"


func _ready() -> void:
	# Every profile owns a complete inherited player scene. Register all of them
	# before spawning so MultiplayerSpawner can reproduce the selected variant.
	for profile in CharacterRegistry.profiles:
		if profile.player_scene != null:
			_spawner.add_spawnable_scene(profile.player_scene.resource_path)

	# The server (or the singleplayer host) spawns its own player immediately.
	if multiplayer.is_server() and not NetworkManager.is_dedicated_server():
		_spawn_player(multiplayer.get_unique_id(), _selected_profile_index())
	elif not multiplayer.is_server():
		_prepare_client_spawn_request()

	# A connected client may not have loaded this scene yet. Spawning from the
	# peer_connected signal races MultiplayerSpawner against the client's scene
	# transition, so clients explicitly request a spawn from _ready() instead.
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_lost)


## Instantiates a player scene for [param peer_id] and adds it to the
## [code]Players[/code] container. Safe to call multiple times for the same
## peer (duplicate calls are silently ignored).
func _spawn_player(peer_id: int, requested_profile_index := 0) -> void:
	if _players.has_node(str(peer_id)):
		return
	if CharacterRegistry.profiles.is_empty():
		push_error("GameManager: no player profiles are registered")
		return
	var selected_index := clampi(
		requested_profile_index,
		0,
		CharacterRegistry.profiles.size() - 1
	)
	var profile := CharacterRegistry.profiles[selected_index]
	var player := profile.instantiate_player()
	if player == null:
		push_error("GameManager: could not instantiate %s" % profile.display_name)
		return
	player.name = str(peer_id)
	player.set("profile_index", selected_index)
	# Assign authority so only the owning peer processes input and physics.
	player.set_multiplayer_authority(peer_id)
	# Set the initial transform before add_child(). MultiplayerSpawner captures
	# spawn properties as the node enters the tree, so assigning it afterward
	# can briefly create remote players at the scene origin.
	player.position = _get_spawn_position(peer_id)
	# Adding with force_readable_name=true lets MultiplayerSpawner replicate
	# this child to all connected peers.
	_players.add_child(player, true)


func respawn_player(player: Node3D) -> void:
	if not multiplayer.is_server() or player == null:
		return
	player.call(
		"server_respawn",
		_get_spawn_position(player.get_multiplayer_authority())
	)


func _get_spawn_position(peer_id: int) -> Vector3:
	if _spawn_point == null:
		return Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = peer_id
	var offset := Vector3(
		rng.randf_range(-1.5, 1.5),
		0.0,
		rng.randf_range(-1.5, 1.5)
	)
	return _players.to_local(_spawn_point.global_position + offset)


## Removes the player node belonging to [param peer_id].
func _despawn_player(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func _request_player_spawn(requested_profile_index: int) -> void:
	if multiplayer.is_server():
		_spawn_player(
			multiplayer.get_remote_sender_id(),
			requested_profile_index
		)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_despawn_player(peer_id)


func _prepare_client_spawn_request() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_local_player_spawn()
		return
	NetworkManager.connected_to_server.connect(
		_request_local_player_spawn,
		CONNECT_ONE_SHOT
	)


func _request_local_player_spawn() -> void:
	_request_player_spawn.rpc_id(
		MultiplayerPeer.TARGET_PEER_SERVER,
		_selected_profile_index()
	)


func _selected_profile_index() -> int:
	var selected_profile := CharacterSelectionState.selected_profile
	var selected_index := CharacterRegistry.profiles.find(selected_profile)
	return selected_index if selected_index >= 0 else 0


func _on_connection_lost() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if error != OK:
		push_error("GameManager: could not return to the main menu (err %d)" % error)
