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

Export `Linux Dedicated Server` from Godot. The preset strips visual resources
and automatically adds the `dedicated_server` feature, so the exported binary
starts headlessly and loads the world as a server.

Upload the contents of `build/server/` to the VPS, then run:

```bash
chmod +x LeyLiwServer.x86_64
./LeyLiwServer.x86_64 -- --port=7777
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
Players enter the VPS public IPv4 address in the Join field. Do not enter the
VPS private address.

## Alternative: host from home

The existing `Host Server` button can be internet-accessible when all of these
are true:

1. The internet connection has a real public IPv4 address.
2. The router forwards UDP `7777` to the host device's LAN address.
3. The host operating-system firewall allows UDP `7777`.
4. Players join using the router's public IPv4 address.

This generally does not work through mobile hotspots or many residential
connections using CGNAT. Port-forwarding TCP `7777` is unnecessary because
ENet uses UDP.

## Current security boundary

Internet transport is functional, but the prototype is not ready for an open
public launch. It currently has no accounts, server password, bans, encryption,
or persistent identity. Chat and voice are validated/rate-limited by the
server, but the ENet session itself should be treated as private-test traffic.

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
