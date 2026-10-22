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
## Minimum interval between accepted spawn requests from one peer. A client
## legitimately requests once per session, so a tight limit still allows
## normal play while preventing a client from flooding the server with
## reliable spawn RPCs.
const SPAWN_REQUEST_COOLDOWN_MSEC := 1000
## Number of physics frames the server waits before it trusts a ground query.
## Static collision from the world scene only reaches the physics space after
## the scene tree has been flushed, so an early query would report "no ground"
## everywhere and the server would place players in the void.
const GROUND_PROBE_WARMUP_FRAMES := 4
## How far below a player the server looks for solid ground.
const GROUND_PROBE_LENGTH := 25.0
## How often the server checks whether a player is still over solid ground.
const GROUND_CHECK_INTERVAL_FRAMES := 6
## How far below the sampled position the ground probe looks.
const GROUND_PROBE_START_OFFSET := 2.0
## Number of rings the spawn search walks outwards when the spawn point has
## no ground under it.
const GROUND_SEARCH_RINGS := 8
## Distance between the rings of the spawn search.
const GROUND_SEARCH_STEP := 1.0
## Clearance the spawn search keeps from the edge of a hole. The ground is
## sampled in a small ring around the candidate, so a spawn point is only
## accepted when the whole ring is solid and the player cannot walk off it
## on the first step.
const GROUND_SEARCH_MARGIN := 1.5
## Largest drop from the sampled position that still counts as the court
## floor. A curb or bench top sits above the floor, so a sample that lands
## higher than the candidate is not the surface the player walks on.
const GROUND_MAX_DROP := 3.0
## Height below the court that counts as falling out of the world.
const OUT_OF_BOUNDS_Y := -10.0
## Shortest interval between two out-of-bounds recoveries for the same peer.
## Without it a world without any ground would respawn a player in a tight
## loop.
const RECOVERY_COOLDOWN_MSEC := 2000

@onready var _players: Node3D = $"../Players"
@onready var _spawn_point: Node3D = $"../SpawnPoint"
@onready var _spawner: MultiplayerSpawner = $"../MultiplayerSpawner"

var _last_spawn_request_at: Dictionary[int, int] = {}
## Number of physics frames the server has processed since the world loaded.
var _physics_frame_count := 0
## Ground-verified spawn positions, cached per peer.
var _safe_spawn_positions: Dictionary[int, Vector3] = {}
## Last out-of-bounds recovery per peer, used to rate limit recoveries.
var _last_recovery_at_msec: Dictionary[int, int] = {}


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


func _physics_process(delta: float) -> void:
	# The server owns every player's position validation. Clients replicate
	# their own position and rotation, so without this the server would trust
	# a client-supplied transform for melee range checks.
	if not multiplayer.is_server():
		return
	_physics_frame_count += 1
	for player in _players.get_children():
		if player.has_method("_server_validate_movement"):
			player.call("_server_validate_movement", delta)
	if _physics_frame_count < GROUND_PROBE_WARMUP_FRAMES:
		return
	if _physics_frame_count % GROUND_CHECK_INTERVAL_FRAMES != 0:
		return
	for player in _players.get_children():
		_check_player_is_on_ground(player)


## Returns a player to safety when it has fallen out of the world.
##
## The market court ground mesh has holes and an open edge, and the game has
## no kill plane, so a player that walks into one keeps falling forever. A
## player that drops below the court is placed back on a verified ground
## position.
func _check_player_is_on_ground(player: Node) -> void:
	if not player is Node3D:
		return
	var body := player as Node3D
	if body.global_position.y > OUT_OF_BOUNDS_Y:
		return
	# The player is below the court, so it fell through a hole or off the
	# open edge of the ground mesh.
	var peer_id := body.get_multiplayer_authority()
	var now := Time.get_ticks_msec()
	var last_recovery: int = _last_recovery_at_msec.get(
		peer_id,
		-RECOVERY_COOLDOWN_MSEC
	)
	if now - last_recovery < RECOVERY_COOLDOWN_MSEC:
		return
	_last_recovery_at_msec[peer_id] = now
	push_warning(
		"GameManager: player %s fell out of the world and was respawned"
			% peer_id
	)
	body.call("server_respawn", _get_spawn_position(peer_id))


## Returns the height of the first surface below [param position], or INF when
## nothing is hit within [constant GROUND_PROBE_LENGTH].
##
## Player bodies are always excluded. A player standing next to the sampled
## point would otherwise be hit by the ray and read as the floor.
func _find_surface_below(position: Vector3) -> float:
	var space_state := get_viewport().world_3d.direct_space_state
	if space_state == null:
		return INF
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3(0.0, GROUND_PROBE_START_OFFSET, 0.0),
		position + Vector3(0.0, -GROUND_PROBE_LENGTH, 0.0)
	)
	query.exclude = _player_rids()
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	var hit_position: Vector3 = hit["position"]
	return hit_position.y


## Returns the collision object ids of every spawned player, so ground probes
## ignore player bodies.
func _player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if _players == null:
		return rids
	for player in _players.get_children():
		var body := player as CollisionObject3D
		if body != null:
			rids.append(body.get_rid())
	return rids


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
	if multiplayer.is_server() and player.has_method(
		"_server_reset_validated_position"
	):
		player.call("_server_reset_validated_position")


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
	# Reuse a position that was already verified to have ground under it.
	var cached: Variant = _safe_spawn_positions.get(peer_id)
	if cached != null:
		return _players.to_local(cached as Vector3)
	var rng := RandomNumberGenerator.new()
	rng.seed = peer_id
	var offset := Vector3(
		rng.randf_range(-1.5, 1.5),
		0.0,
		rng.randf_range(-1.5, 1.5)
	)
	var spawn_position := _spawn_point.global_position + offset
	# The market court ground has holes and a diagonal open edge, so the
	# jittered position may not have any ground under it. Walk outwards until
	# a spot with solid ground is found so a player never spawns in a hole and
	# falls out of the world.
	var safe_position := _find_safe_spawn_position(spawn_position)
	# Only a position the search actually verified may be cached. Caching an
	# unverified candidate would send a recovered player straight back into
	# the hole it just fell out of.
	if _physics_frame_count >= GROUND_PROBE_WARMUP_FRAMES:
		_safe_spawn_positions[peer_id] = safe_position
	return _players.to_local(safe_position)


## Returns a position near [param candidate] that has solid ground under it.
##
## The search starts at the candidate and walks outwards in rings, so the
## player keeps the intended spawn point whenever that point is solid. A
## candidate is only accepted when a ring of samples around it is solid, so
## the player does not spawn on the very edge of the court and fall off it
## on the first step.
func _find_safe_spawn_position(candidate: Vector3) -> Vector3:
	if _physics_frame_count < GROUND_PROBE_WARMUP_FRAMES:
		# The collision is not in the physics space yet, so no position can be
		# verified. Trust the candidate and let the out-of-bounds check recover
		# the player once the world is ready.
		return candidate
	# The court floor is the surface under the spawn point. Every candidate
	# is measured against that height, so a bench or a curb is never mistaken
	# for the floor and the player is always placed on the same level.
	var floor_height := _find_surface_below(candidate)
	if floor_height == INF:
		floor_height = _spawn_point.global_position.y
	if _has_solid_ground(candidate, floor_height):
		return candidate
	for ring in range(1, GROUND_SEARCH_RINGS + 1):
		var radius := float(ring) * GROUND_SEARCH_STEP
		for step in range(8):
			var angle := TAU * float(step) / 8.0
			var probe := candidate + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if _has_solid_ground(probe, floor_height):
				return probe
	return candidate


## Returns true when [param position] and a ring of samples around it all
## have ground underneath.
##
## A single ray is not enough: the market court is a flat plate with a
## diagonal edge, so a point can sit on solid ground while the ground one
## metre away is a hole. Sampling a ring rejects those edge positions.
##
## [param floor_height] is the height of the court floor. A sample that
## lands more than [constant GROUND_MAX_DROP] below it, or above it, is not
## the surface the player walks on and does not count as solid ground.
func _has_solid_ground(position: Vector3, floor_height: float) -> bool:
	if not _is_floor_at(position, floor_height):
		return false
	for step in range(8):
		var angle := TAU * float(step) / 8.0
		var sample := position + Vector3(cos(angle), 0.0, sin(angle)) * GROUND_SEARCH_MARGIN
		if not _is_floor_at(sample, floor_height):
			return false
	return true


## Returns true when the ground under [param position] is the court floor at
## [param floor_height].
func _is_floor_at(position: Vector3, floor_height: float) -> bool:
	var surface := _find_surface_below(position)
	if surface == INF:
		return false
	return absf(surface - floor_height) <= GROUND_MAX_DROP


## Removes the player node belonging to [param peer_id].
func _despawn_player(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func _request_player_spawn(requested_profile_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _can_request_spawn(sender_id):
		return
	_spawn_player(sender_id, requested_profile_index)


## Rate limits spawn requests per peer. Without this, any client can flood
## the server with reliable spawn RPCs. The duplicate-node guard in
## [method _spawn_player] already prevents unbounded growth, but it does not
## stop the traffic itself.
func _can_request_spawn(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var last_request: int = _last_spawn_request_at.get(
		peer_id,
		-SPAWN_REQUEST_COOLDOWN_MSEC
	)
	if now - last_request < SPAWN_REQUEST_COOLDOWN_MSEC:
		return false
	_last_spawn_request_at[peer_id] = now
	return true


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_despawn_player(peer_id)
		_last_spawn_request_at.erase(peer_id)


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
