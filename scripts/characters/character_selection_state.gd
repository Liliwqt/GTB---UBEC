extends Node
## Tracks which character profile is currently selected by the player.
##
## Autoloaded as [code]CharacterSelectionState[/code].  Set [member
## selected_profile] before switching to the gameplay scene so the player
## controller can pick it up.

## The profile the player chose (or [code]null[/code] to use the default).
var selected_profile: CharacterProfile
