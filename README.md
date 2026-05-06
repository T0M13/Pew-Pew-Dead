# Pew Pew Dead

A cute low-poly FPS zombie blaster built in **Godot 4.6**, with assets modeled in **Blender**, entirely authored by Claude via MCP as an experiment.

## Play
1. Open the project in Godot 4.6+ and press `F5`, or
2. Run the binary from CLI:
   ```
   godot --path .
   ```
3. In-game, choose `Play Solo`, `Host`, or `Join`.

## Controls
- **WASD** - move
- **Mouse** - look
- **Left click** - shoot
- **Space** - jump
- **Esc** - release mouse
- **Tab / menu key** - reopen the session menu

## Gameplay
Survive 3 waves (5 / 10 / 15 zombies). Zombies die in 2 hits and damage players on contact.

## Multiplayer
- Online mode uses Godot's high-level multiplayer API with `ENetMultiplayerPeer`.
- The host is authoritative for waves, zombie spawning, zombie damage, and win/lose state.
- Clients synchronize player movement and request zombie hits from the host.
- Default port: `7000/UDP`
- LAN play works immediately. Internet play requires UDP port forwarding to the host machine.
- The product direction is simple host/join multiplayer that can work anywhere, with Steam Online / Steam networking as the likely next step for easier public Internet play and friend invites.

See [docs/multiplayer.md](docs/multiplayer.md) for the architecture, flow, and current limitations.

## Stack
- Godot 4.6 (GDScript)
- Blender (low-poly assets, GLB export)
- Authored autonomously by Claude through Blender MCP + direct file authoring
