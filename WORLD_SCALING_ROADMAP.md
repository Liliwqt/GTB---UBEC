# LeyLiw world scaling roadmap

The current scene is a good prototype map. It should remain small while the
systems below are introduced, because adding more geometry and NPCs directly
to `ley_liw.tscn` will make loading, navigation, networking, and mobile
performance increasingly difficult to control.

## 1. Establish a persistent world shell

Keep one lightweight scene alive for the session with these responsibilities:

```text
WorldRoot
  WorldStreamer
  LoadedChunks
  DynamicEntities
    Players
    NPCs
  SessionManager
  WorldUI
```

Move environment geometry into independently loadable chunk scenes. Keep
players, NPCs, mission state, time, weather, and save data outside chunks so
unloading scenery never deletes persistent gameplay state.

## 2. Stream grid-based chunks

- Start with square chunks around 128–256 meters wide.
- Load the player's current chunk and its immediate neighbors.
- Use `ResourceLoader.load_threaded_request()` and finish attachment on the
  main thread to avoid visible stalls.
- Give every chunk a stable ID and explicit bounds; do not infer ownership
  from scene-tree names.
- Unload only after a distance/time hysteresis threshold so chunks do not
  repeatedly load at borders.

In multiplayer, the server owns the authoritative loaded simulation set.
Clients may load additional visual chunks but must not create authoritative
NPCs, pickups, or mission objects.

## 3. Replace temporary NPC wandering

Use a `NavigationRegion3D` per chunk with compatible edge connections. Run
high-level decisions at a low frequency and navigation/physics only near a
player. Far NPCs should use simplified simulation or be represented only by
saved state.

Suggested activity levels:

- Near: full CharacterBody3D, navigation, animation, and perception.
- Mid-distance: infrequent movement updates and reduced animation work.
- Far/unloaded: data-only schedule and position updates.

Pool frequently created NPCs and effects after behavior is stable; do not pool
everything preemptively.

## 4. Split the player controller by responsibility

`player_controller.gd` currently owns movement, camera, character swapping,
animation graph construction, combat, touch input hookup, and networking.
Before adding vehicles, weapons, or missions, extract these into focused child
components:

```text
Player
  PlayerMotor
  PlayerCameraRig
  CharacterPresenter
  PlayerAnimationController
  CombatController
  NetworkState
```

The root player should coordinate components and own authority. Components
should communicate through typed methods/signals, not hard-coded paths to
unrelated world systems.

## 5. Add entity definitions and persistence

- Give persistent entities stable IDs independent of runtime node names.
- Store definitions in custom Resources; store mutable save state separately.
- Version save data from the first release that writes a file.
- Save only authoritative gameplay state, not render nodes or entire scenes.
- Define spawn/despawn ownership in one server-side entity service.

## 6. Budget networking explicitly

- Replicate continuous transforms at a controlled tick rate with client-side
  interpolation.
- Replicate discrete state such as character selection and animation only when
  it changes.
- Use RPCs for events such as attacks; validate gameplay results on the server.
- Replace raw voice PCM with Opus and add a small adaptive jitter buffer before
  supporting larger sessions or internet play.
- Add interest management so clients receive only nearby entities and relevant
  global state.
- Test host and client as separate processes before increasing player count.

## 7. Build for mobile constraints from the start

- Generate mesh LODs and use visibility ranges/HLOD for buildings.
- Use simplified collision meshes instead of render geometry.
- Combine repeated static props with MultiMeshInstance3D.
- Reduce the current 4096 textures where visual testing permits it.
- Limit real-time shadow distance and the number of shadow-casting lights.
- Profile CPU frame time, GPU frame time, memory, and draw calls on a real
  low-end Android device; desktop GL Compatibility results are not enough.

## Recommended implementation order

1. Extract a persistent world shell and one test chunk.
2. Add threaded load/unload with a visible debug overlay.
3. Move navigation and NPC ownership into chunks/entity services.
4. Split the player controller without changing behavior.
5. Add transform interpolation and multiplayer interest management.
6. Add versioned persistence.
7. Expand the environment only after mobile and multiplayer budgets pass.
