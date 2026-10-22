# Internet hosting

LeyLiw uses Godot ENet over UDP. For reliable internet access, run the game as
a dedicated server on a Linux VPS with a public IPv4 address. This avoids home
router configuration and mobile-carrier CGNAT.

## Recommended: public VPS

Minimum prototype server:

- 1–2 shared CPU cores
- 1–2 GB RAM
- Ubuntu or another current 64-bit Linux distribution
- A public IPv4 address
- Inbound UDP port `7777` allowed by both the VPS provider firewall and Linux

Export `Linux Dedicated Server` for an x86-64 VPS, or `Linux Dedicated Server
(ARM64)` for an Oracle Ampere A1 VM. Both presets add the `dedicated_server`
feature, so the exported binary starts headlessly and loads the world as a
server.

Upload the contents of `build/server/` to the VPS, then run:

```bash
chmod +x LeyLiwServer.x86_64
./LeyLiwServer.x86_64 -- --port=7777
```

For an Oracle ARM64 VM, upload `build/server-arm64/` and run:

```bash
chmod +x LeyLiwServer.arm64
./LeyLiwServer.arm64 -- --port=7777
```

For development without exporting:

```bash
/path/to/godot --headless --path /path/to/uc-random-game \
  -- --dedicated-server --port=7777
```

Open the firewall on Ubuntu when UFW is enabled:

```bash
sudo ufw allow 7777/udp
```

Also add an inbound UDP `7777` rule in the VPS provider's network firewall.

## Server address configuration

The server address is **not hardcoded** in source. `NetworkManager` resolves
it in this order:

1. `--server-address=` / `--port=` command-line arguments
2. `LEYLIW_SERVER_ADDRESS` / `LEYLIW_SERVER_PORT` environment variables
3. `user://server_address.cfg` (per-user, ignored by git)
4. `res://server_address.cfg` (bundled, ignored by git)
5. Empty fallback (localhost / no public address)

See `server_address.cfg.example` for the config file format. Client builds
connect from the `Play Open World` button with no login or address entry.
Before exporting a public client, configure `server_address.cfg` with the VPS
public IPv4 address or DNS name. Do not use the VPS private address.

## Alternative: host from home

Hosting from home can be internet-accessible when all of these are true:

1. The internet connection has a real public IPv4 address.
2. The router forwards UDP `7777` to the host device's LAN address.
3. The host operating-system firewall allows UDP `7777`.
4. `server_address.cfg` (or `LEYLIW_SERVER_ADDRESS`) contains the router's
   public IPv4 address.

This generally does not work through mobile hotspots or many residential
connections using CGNAT. Port-forwarding TCP `7777` is unnecessary because
ENet uses UDP.

## Current security boundary

Internet transport is functional, but the prototype is not ready for an open
public launch. It currently has no accounts, server password, bans, encryption,
or persistent identity. Chat and voice are validated/rate-limited by the
server, but the ENet session itself should be treated as private-test traffic.

Known gaps (documented for transparency):

- Voice bandwidth cap (48 KB/s) exists, but there is no per-peer packet-rate
  limit.
- Spawn RPC is unthrottled on the server side (a 1000 ms client cooldown
  exists, but no server-side rate limit).
- `_last_chat_at` is cleaned up on voice-peer removal but not on chat-peer
  removal — a long-lived chat peer can leave a stale entry.
- Melee is client-controlled: the client sends the attack RPC and the server
  validates range/facing from its own validated-position copy, but the
  validated position can lag behind replicated movement.
- Movement is client-authoritative (`position`/`rotation` replicate with mode
  1 / Always). The server validates reachability but does not re-simulate
  physics.
- Out-of-bounds recovery: players who fall below `y = -10` are respawned at a
  ground-verified position. The market-court ground has a diagonal open edge
  near the spawn point; the recovery uses an 8-sample ring probe to avoid
  respawning into the same hole.

Before publishing the server address broadly, add:

- server authentication or invite tokens;
- protocol/version checks during connection;
- moderation, mute, kick, and ban controls;
- encrypted application payloads or a secure session layer;
- Opus voice compression and per-user bandwidth limits;
- monitoring, backups, automatic restart, and log rotation;
- authoritative validation for movement and combat.

## Production process

Run the exported server under `systemd` or a container so it restarts after a
crash or VPS reboot. Keep UDP `7777` as the only public game port unless future
services explicitly require more.
