# LeyLiw

A Godot 4.7 multiplayer open-world prototype. Players explore a market-court
arena, move with client-authoritative movement, and resolve melee combat
authoritatively on the server. Voice and chat are rate-limited by the server.

## Repository

- **GitHub:** `Liliwqt/GTB---UBEC` (private → public)
- **Engine:** Godot 4.7.1
- **Server:** dedicated Linux server over ENet/UDP (port 7777)

## Getting started

Open `project.godot` in Godot 4.7. Run the dedicated server:

```bash
./build/server/LeyLiwServer.x86_64 -- --port=7777
```

Or headless from source:

```bash
godot --headless --path . -- --dedicated-server --port=7777
```

## Security

This is a prototype. The server address is not hardcoded — see
`server_address.cfg.example` and `scripts/network/network_manager.gd` for the
layered resolution order (CLI > env > `user://server_address.cfg` >
`res://server_address.cfg`). No credentials, API keys, or private IPs are
committed to this repository.

See `INTERNET_HOSTING.md` for the current security boundary and production
recommendations.

## Third-party assets

See `THIRD_PARTY_NOTICES.md` for attribution and license terms of bundled
third-party content (including the Quaternius CC0 animation library).
