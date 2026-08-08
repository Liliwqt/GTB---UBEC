# LeyLiw project memory

Last updated: 2026-08-01

## Project goal

LeyLiw is a Godot 4.7 third-person open-world prototype intended to grow into
a private and eventually multiplayer game that can be tested on desktop,
Android, and iOS.

## Collaboration preference

- Ask before importing, modifying, moving, converting, or replacing a newly
  introduced character model or its textures.
- Existing in-scope gameplay code and scenes may be changed when explicitly
  requested.
- Explain Godot workflows in beginner-friendly steps.

## Runtime architecture

```text
animations/humanoid/
  humanoid_animation_library.tres
  locomotion/
  combat/

animations/characters/carl_johnson/
  locomotion/
  combat/

assets/characters/liliw/model/
assets/characters/carl_johnson/model/
assets/environments/arawan_market_court/model/
characters/liliw/liliw.tscn
characters/liliw/liliw_model.tscn
characters/liliw/liliw_animation_library.tres
characters/liliw/liliw_profile.tres
characters/carl_johnson/carl_johnson.tscn
characters/carl_johnson/carl_johnson_model.tscn
characters/carl_johnson/carl_johnson_animation_library.tres
characters/carl_johnson/carl_johnson_profile.tres
scripts/characters/character_profile.gd
scripts/characters/character_registry.gd       (autoload: CharacterRegistry)
scripts/characters/character_selection_state.gd (autoload: CharacterSelectionState)
scripts/network/network_manager.gd             (autoload: NetworkManager)
scripts/network/game_manager.gd                 (node: GameManager in ley_liw.tscn)
scripts/network/communication_manager.gd

scenes/player/player.tscn
scripts/player/player_controller.gd

scenes/ui/mobile_controls.tscn
scenes/ui/main_menu.tscn
scripts/ui/mobile_controls.gd
scripts/ui/main_menu.gd
scripts/ui/menu_music.gd
scripts/ui/communication_overlay.gd
scenes/ui/communication_overlay.tscn

scenes/network/communication_manager.tscn

scenes/npcs/wandering_liliw_npc.tscn
scripts/npcs/wandering_npc.gd

scenes/worlds/ley_liw.tscn
```

- `player.tscn` is the shared gameplay/network base. Each playable character
  is an inherited full player scene with its own model transform, collision
  shape, camera overrides, `AnimationPlayer`, and animation library.
- The `_model.tscn` files are visual-only scenes reusable by NPCs.
- Each `CharacterProfile` selects its complete player scene; `GameManager`
  registers all profile scenes and spawns the requested variant directly.
- Carl and Liliw animation libraries and clip files are character-owned, so
  clips can be replaced manually without changing the other character.
- Carl Johnson is the active Player profile; Liliw remains selectable through
  `characters/liliw/liliw_profile.tres`.
- `scenes/player/player.tscn` owns shared player behavior and default nodes;
  inherited character scenes own their per-character overrides.
- `scripts/player/player_controller.gd` owns player movement and animation
  decisions.
- `scenes/ui/mobile_controls.tscn` provides the mobile HUD and
  `scripts/ui/mobile_controls.gd` translates multitouch input into the same
  actions used by desktop controls.
- The main-menu `BackgroundMusic` node plays a low-cost generated ambient
  fallback through the `Music` audio bus. Its current `custom_music` is
  `imports/NoPetsAllowed - Bundak sa Letra.mp3`; non-looping custom streams are
  replayed automatically, and clearing that property restores the fallback.
- `assets/branding/boot_logo.png` is the centered 512 px game artwork used by
  both boot splash layers on a black background; it is intentionally not
  stretched to fill the display.
- `animations/humanoid/humanoid_animation_library.tres` is the shared humanoid
  animation library.
- `scenes/worlds/ley_liw.tscn` is the current main world scene.
- `GameManager` in `ley_liw.tscn` spawns players via `MultiplayerSpawner` into `LeyLiw/Players`.
- Clients request their player spawn only after their world scene is ready,
  avoiding replication races during the menu-to-world transition.
- `NetworkManager` autoload handles networking states (offline singleplayer, host, client).
- `NetworkManager` also supports a headless dedicated-server mode through the
  `dedicated_server` feature or `--dedicated-server --port=<port>` arguments.
- Dedicated servers do not spawn a fake peer-1 player or display communication
  UI; clients request spawning after their world is ready.
- Offline singleplayer installs an `OfflineMultiplayerPeer`, which provides
  server/authority semantics with peer ID 1 without opening a network socket.
- `player_controller.gd` guards input, camera, and physics with `is_multiplayer_authority()`.
- Combat actions use `@rpc("authority", "call_local", "reliable")` so attack animations replicate across all peers.
- Sprint-dive-roll has exclusive full-body animation control: entering the
  dive aborts the upper-body punch layer, and attacks/damage are rejected until
  the roll finishes. The upper-body mask remains enabled for normal locomotion.
- `MultiplayerSynchronizer` nodes replicate position, rotation, and animation state for players and NPCs.

## Communication

- Enter focuses/submits the in-world text chat; messages are sanitized,
  length-limited, rate-limited, and reliably relayed by the server.
- Hold `V` on desktop or hold the on-screen microphone button for push-to-talk.
- Voice is captured as stereo input, converted to 16-bit mono PCM at 16 kHz,
  and sent in 20 ms packets over a separate unreliable-ordered RPC channel.
- The server validates packet size/rate and relays voice to per-peer
  `AudioStreamGenerator` playback nodes.

## Temporary combat

- Players have 100 server-authoritative health, synchronized separately from
  client-owned movement and character animation state.
- A valid punch deals 25 damage after the server checks cooldown, distance,
  vertical separation, and facing direction.
- At zero health the server restores full health, moves the player to their
  deterministic spawn-point offset, and grants one second of spawn protection.
- The owning client receives a reliable server respawn command and publishes
  the corrected transform through its movement synchronizer.
- `tools/smoke_test_combat.tscn` verifies damage and respawn across separate
  host/client processes; the local singleplayer regression covers the same
  combat path without a socket.
- Android microphone recording permission and Godot audio input are enabled.
- Current voice is global/non-spatial and uncompressed. Add Opus compression,
  jitter buffering, per-user mute/volume, and proximity filtering before
  scaling beyond small private sessions.
- Replication configurations live in the player and NPC scenes so they are
  ready before nodes enter the multiplayer replication system.
- Character profile and animation state use on-change replication instead of
  consuming bandwidth every network tick.
- All keyboard, mouse, and touch actions are declared centrally in
  `project.godot`; gameplay scripts no longer mutate the InputMap at runtime.
- The project display name is `LeyLiw`.
- The Cuenca environment assets were archived to `archive/environments/cuenca/`.
- Render screenshots were archived to `archive/renders/`.
- The former `IMport/` directory was archived to `archive/animations/` and deleted.
- `drunkin_fight.res` is archived but not used by any runtime code.
- The `Drunk` and `Style` animation libraries were removed from `player.tscn`;
  character-specific animations are delivered through `CharacterProfile` at runtime.

## Current animation names

```text
idle
start_walk
walk
run
stop_step
stop_walk
stop_run
jump_run
left_jab
right_punch
```

Stopping selection:

- Movement shorter than `stop_animation_trigger_time` (default `0.25s`) skips a
  stopping animation.
- Short established movement up to `stop_step_max_input_time` (default `0.8s`)
  uses `stop_step`.
- Established walking uses `stop_walk`.
- Established running uses `stop_run`.

The current `stop_walk` is approximately `0.733s`. The former `stop_walk`
animation was renamed to `stop_run`.

## Player movement

- Camera-relative movement with a freely rotating third-person camera.
- Character faces movement direction rather than being locked to the camera.
- Walk and run accelerate gradually.
- Sharp direction changes reduce speed temporarily.
- Animation playback speed follows physical locomotion speed within clamps.
- Start and stop clips are synchronized with controller movement.
- Transition-specific crossfades are exposed in the Player inspector.

Important tuning properties:

```text
speed
run_speed
walk_acceleration
run_acceleration
deceleration
start_to_walk_time
run_animation_entry_speed
stop_animation_trigger_time
stop_step_max_input_time
stop_animation_max_duration
idle_start_blend_time
gait_change_blend_time
stopping_blend_time
stop_idle_blend_time
```

## Combat animation

- Left mouse uses Carl's `combat/drunk_left_jab.res` as `left_jab`.
- Right mouse uses Carl's `combat/drunk_right_hook.res` as `right_punch`.
- `AnimationTree` is added to `player.tscn`.
- Its graph is constructed at runtime by `player_controller.gd`.
- Locomotion remains on the hips and legs while punch one-shots affect the
  spine, arms, hands, neck, and head.
- Punch fade-in and fade-out times are exposed under `Combat Animation`.
- Because the graph is runtime-built, it may look empty in the editor before
  the game runs.

## Per-character animation sets

- Carl and Liliw each own a complete animation library and clip directory;
  NPC animation libraries remain unchanged.
- Carl's `locomotion/drunk_idle.res`, `drunk_walk.res`, and `drunk_run.res`
  provide his current idle, walk, and run styles.
- `jump_run` is the single canonical full-body jump slot for both characters.
  It currently points to each character's `locomotion/sprint_jump_roll.res`.
  A future jump style replaces the `jump_run` library entry instead of adding
  a separate `sprint_dive_roll` gameplay name.
- Full-body `jump_run` playback aborts the upper-body punch layer and prevents
  attack animation/damage until the jump style finishes.
- Punching while walking or running uses an `AnimationNodeOneShot` filtered to
  the skeleton hierarchy beginning at `mixamorig_Spine`. Hips and legs remain
  controlled by locomotion; the Inspector property `upper_body_root_bone`
  allows a manually configured rig to choose a different split bone.
- Non-authoritative remote player animation trees pause beyond 45 meters and
  recheck visibility four times per second. Both values are exported on the
  player for manual tuning; local gameplay and server hit validation continue.

## Multiplayer NPC population

- No NPCs are pre-placed under `LeyLiw/NPCs`.
- The server-only `NpcPopulationManager` creates a capped population of four
  NPCs at explicit `Marker3D` locations through a dedicated
  `MultiplayerSpawner`; joining clients receive the existing population.
- NPC AI, collision, gravity, and wandering run only on the server. Clients
  render replicas and derive idle/walk animation from synchronized velocity.
- Position, rotation, and velocity publish at 20 Hz to limit NPC bandwidth.
- Dedicated servers remove NPC meshes and animation players while retaining
  AI, collision, and synchronization.
- The NPC presentation rig is lowered independently of its physics body; live
  validation places animated foot/toe bones about `0.05–0.08 m` above a floor
  while the collision capsule remains exactly grounded.
- Proper world navigation will still require a `NavigationRegion3D`, a baked
  navigation mesh, and later distance/chunk-based activation.

## Character and texture workflow

- Imported FBX/GLB scenes are read-only source imports; editable organization
  belongs in inherited `.tscn` scenes and external animation resources.
- Download one Mixamo model **With Skin** to establish the rig.
- Download additional Mixamo animations **Without Skin**.
- Animation data and character materials are independent.
- A Tripo texture can be reapplied to a Mixamo-rigged version only when it is
  the exact same mesh and UV layout.
- Skin and cloth should normally use metallic `0.0` and moderate/high
  roughness.
- The archived old Tripo texture does not match the active Liliw model's UV
  layout.

## Mobile performance notes

- Touchscreen builds show a left movement joystick, right-side camera drag,
  and Run, Jump, Jab, and Hit buttons.
- The touch HUD hides automatically on devices without a touchscreen. Enable
  `show_on_desktop` on `MobileControls` to test its layout in the editor.
- `touch_look_sensitivity` is exposed on Player under Camera.

- The project uses the `GL Compatibility` renderer.
- Current animation blending and temporary NPC behavior are inexpensive.
- Several active textures are `4096x4096`; reduce important mobile character
  textures to `2048x2048` and ordinary NPC/environment textures to
  `1024x1024` where possible.
- A full open world will need LODs, visibility ranges, chunk/scene streaming,
  reduced mobile shadows, graphics presets, and profiling on real devices.
- Target a stable `30 FPS` on low-end mobile hardware.

## Validation

- Godot 4.7.1 is available at
  `/home/jhonryl-pamaybay/Godot_v4.7.1-stable_linux.x86_64`.
- Run the headless singleplayer regression check with:
  `/home/jhonryl-pamaybay/Godot_v4.7.1-stable_linux.x86_64 --headless --path . res://tools/smoke_test_singleplayer.tscn`
- The test verifies offline peer creation, local player spawning, multiplayer
  authority, input-map completeness, replication configuration, activation of
  the player's camera, actual movement, offline chat, and voice packet encoding.
- `tools/smoke_test_multiplayer_chat.tscn` runs as separate host/client
  processes to verify reliable text relay and voice-packet relay.
- `tools/smoke_test_dedicated_client.tscn` verifies that a full game client can
  connect to the exported Linux dedicated-server binary, receive its player
  spawn, replicate the Liliw character selection, and exchange a relayed chat
  message. The Godot 4.7.1 release export passed this end-to-end check. The
  dedicated server records replicated character profiles but never instantiates
  their stripped visual scenes.
