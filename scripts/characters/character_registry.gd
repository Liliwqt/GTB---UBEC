extends Node
## Holds references to all available [CharacterProfile] resources.
##
## Autoloaded as [code]CharacterRegistry[/code]. Other systems (lobby UI,
## character-selection state, etc.) query [member profiles] to enumerate the
## characters the player may choose from.

## Ordered list of every selectable character profile.
## Populated in [method _ready]; safe to read from any autoload or scene.
var profiles: Array[CharacterProfile] = []

const PROFILE_PATHS: PackedStringArray = [
	"res://characters/carl_johnson/carl_johnson_profile.tres",
	"res://characters/liliw/liliw_profile.tres",
]


func _ready() -> void:
	profiles.clear()
	for profile_path in PROFILE_PATHS:
		var profile := load(profile_path) as CharacterProfile
		if profile == null:
			push_error("CharacterRegistry: invalid profile at %s" % profile_path)
			continue
		profiles.append(profile)
