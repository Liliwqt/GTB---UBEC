# LeyLiw project structure

The runtime project is split by responsibility so characters, animations, and
worlds can grow independently.

```text
animations/
  humanoid/                 Shared humanoid animation resources and libraries
  source/                   Source animation files ignored by Godot

assets/
  branding/                 Project icon and branding
  characters/<character>/   Imported models, textures, and DCC source files
  environments/<location>/  Imported world assets and DCC source files

characters/<character>/     Model-only character scenes
scenes/npcs/                 Reusable non-player character scenes
scenes/network/              Reusable session/network service scenes
scenes/player/               Reusable playable-character scene
scenes/worlds/               Maps and world scenes
scripts/npcs/                NPC behavior controllers
scripts/player/              Player controller code
third_party/                 Vendor packs ignored by Godot
archive/                     Unused legacy assets ignored by Godot
  characters/                  Archived character assets
  environments/                Archived environment assets (e.g. cuenca)
  renders/                     Historical render screenshots
tools/                       Offline Blender and validation utilities
  smoke_test_singleplayer.*  Headless singleplayer spawn/authority test
  smoke_test_dedicated_client.* Exported-server connection/chat test
  smoke_test_combat.*        Server-authoritative punch/respawn network test
WORLD_SCALING_ROADMAP.md     Recommended architecture for world growth
INTERNET_HOSTING.md          Dedicated-server and public deployment guide
```

## Runtime ownership

- `scenes/worlds/ley_liw.tscn` owns the map, spawn markers, and replicated
  player/NPC containers.
- `scenes/player/player.tscn` owns movement, collision, camera, and animation
  playback.
- `scripts/npcs/npc_population_manager.gd` is the server-only capped NPC
  spawner; `scenes/npcs/wandering_liliw_npc.tscn` is its replicated NPC scene.
- `characters/liliw/liliw.tscn` owns only Liliw's visual model and skeleton.
- `animations/humanoid/humanoid_animation_library.tres` owns the reusable
  animation list.
- `scripts/player/player_controller.gd` refers to animation names, not asset
  file paths.
- `tools/smoke_test_singleplayer.tscn` verifies that offline mode spawns an
  authoritative local player with working controls and an active camera.
- `scenes/network/communication_manager.tscn` owns text and push-to-talk voice
  communication for a loaded game session.

## Adding another humanoid character

1. Put the model and textures in `assets/characters/<name>/model/`.
2. Put Blender or other source files in `assets/characters/<name>/source/`
   with a `.gdignore`.
3. Create `characters/<name>/<name>.tscn` as a model-only scene.
4. Normalize or retarget its skeleton to the humanoid animation library.
5. Replace `ModelRoot/CharacterModel` in `scenes/player/player.tscn`.

Keep the instantiated node named `CharacterModel` and its skeleton named
`Skeleton3D` so the shared animation track paths continue to resolve.
