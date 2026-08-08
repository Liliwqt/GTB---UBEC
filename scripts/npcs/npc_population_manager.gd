extends Node
## Server-owned population controller for dynamically replicated NPCs.

const NPC_SCENE_PATH := "res://scenes/npcs/wandering_liliw_npc.tscn"
const NPC_SCENE := preload(NPC_SCENE_PATH)

@export_range(0, 32, 1) var initial_population := 4

@onready var _npcs: Node3D = $"../NPCs"
@onready var _spawn_points: Node3D = $"../NPCSpawnPoints"
@onready var _spawner: MultiplayerSpawner = $"../NPCSpawner"


func _ready() -> void:
	_spawner.add_spawnable_scene(NPC_SCENE_PATH)
	if multiplayer.is_server():
		_spawn_initial_population.call_deferred()


func _spawn_initial_population() -> void:
	if not multiplayer.is_server():
		return
	var available_points := _spawn_points.get_children()
	var spawn_count := mini(initial_population, available_points.size())
	for index in range(spawn_count):
		_spawn_npc(index, available_points[index] as Node3D)


func _spawn_npc(index: int, spawn_point: Node3D) -> void:
	if spawn_point == null:
		return
	var npc := NPC_SCENE.instantiate() as CharacterBody3D
	if npc == null:
		push_error("NpcPopulationManager: NPC scene has an invalid root")
		return
	npc.name = "NPC_%03d" % (index + 1)
	npc.position = _npcs.to_local(spawn_point.global_position)
	npc.rotation.y = spawn_point.global_rotation.y
	# MultiplayerSpawner observes this server-side add and creates the same
	# named NPC under NPCs on every client, including clients joining later.
	_npcs.add_child(npc, true)
