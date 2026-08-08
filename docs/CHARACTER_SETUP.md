# Per-character player setup

Playable characters inherit the shared gameplay base at
`res://scenes/player/player.tscn`:

- `res://characters/carl_johnson/carl_johnson.tscn`
- `res://characters/liliw/liliw.tscn`

Open one of those character scenes—not `player.tscn`—when changing a specific
character. Changes made to the inherited base affect every character.

## Add or replace animations

1. Open the character `.tscn`.
2. Select its `AnimationPlayer`.
3. Open the Animation panel and choose **Animation > Manage Animations**.
4. Edit the character-owned library shown below, or drag an `Animation`
   resource into it:
   - Carl: `carl_johnson_animation_library.tres`
   - Liliw: `liliw_animation_library.tres`
5. Use the exact gameplay animation name from the table below.

| Required name | Purpose |
| --- | --- |
| `idle` | Default standing pose; required |
| `start_walk` | Walk start |
| `walk` | Walking loop |
| `run` | Running loop |
| `stop_step` | Stop after short movement |
| `stop_walk` | Walking stop |
| `stop_run` | Running stop |
| `jump_run` | Active full-body jump style |
| `left_jab` | Left attack |
| `right_punch` | Right attack |

Both libraries and all referenced clips are stored in that character's own
folder. Replacing Liliw's `walk`, for example, does not modify Carl's `walk`.

`jump_run` is the only gameplay jump slot. The current clip file is named
`sprint_jump_roll.res`, but it is registered in both libraries as `jump_run`.
To change jump style later, replace the library's `jump_run` entry; do not add
another gameplay name such as `sprint_dive_roll`.

The controller builds the `AnimationTree` graph at runtime from these names.
Do not rename `AnimationPlayer` or `AnimationTree`, and do not manually edit the
tree root expecting it to persist at runtime. Blend times, playback tuning, and
the upper-body root bone remain exported on the character scene's root Player.

## Change collision and camera

- Select `CollisionShape3D` to edit that character's unique capsule resource.
- Select the root `Player` and change `camera_height`; this is the camera pivot
  height used by the controller every frame.
- Select `Head/SpringArm3D` to change camera distance, margin, and collision
  behavior.
- Select `Head/SpringArm3D/Camera3D` for FOV, near plane, and camera settings.
- Select `ModelRoot/CharacterModel` to position, rotate, or scale the visual
  model independently of collision.

Keep the inherited node names intact because the shared controller addresses
them by name. The model-only scenes (`liliw_model.tscn` and
`carl_johnson_model.tscn`) are kept separate so NPCs can reuse visuals without
receiving player networking, UI, collision, or cameras.

## Add another playable character

1. Create a new inherited scene from `player.tscn`.
2. Add `ModelRoot/CharacterModel`, `AnimationPlayer`, and `AnimationTree` using
   the existing character scenes as templates.
3. Give it a unique collision shape and character animation library.
4. Create a `CharacterProfile` with its `player_scene` assigned.
5. Add the profile path to `CharacterRegistry.PROFILE_PATHS`.

`GameManager` automatically registers every profile's scene with
`MultiplayerSpawner`, validates the requested profile index, and spawns the
same character variant on all peers.
