class_name CharacterProfile
extends Resource

@export var display_name := "Character"
@export var player_scene: PackedScene


func instantiate_player() -> Node3D:
	if player_scene == null:
		return null
	return player_scene.instantiate() as Node3D
