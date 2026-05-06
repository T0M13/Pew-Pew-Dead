# Pew Pew Dead

A cute low-poly FPS zombie blaster built in **Godot 4.6**, with assets modeled in **Blender**, entirely authored by Claude via MCP as an experiment.

## Play
1. Open the project in Godot 4.6+ and press `F5`, or
2. Run the binary from CLI:
   ```
   godot --path .
   ```
3. In-game, choose `Play Solo`, `Host`, or `Join`.
4. Survive the zombie waves, use movement to stay mobile, and aim for headshots.

## How To Play
- `Play Solo` starts an instant local run.
- `Host` starts a listen server on `UDP 7000`.
- `Join` connects to a host by IP.
- `Esc` returns you to the main menu scene during a run.
- The current build has wave survival, multiplayer host/join, a debug console, sprinting, sliding, melee, headshots, and limb severing/crawl behavior on zombies.

## Controls
- **WASD** - move
- **Mouse** - look
- **Left click** - shoot
- **Shift** - sprint
- **Ctrl** or **C** - slide
- **F** - melee / shove
- **Space** - jump
- **Esc** - return to menu
- **`** or **F1** - toggle debug console

## Debug Console
- Shows `FPS` and `MS` in the HUD.
- Current commands:
  - `help`
  - `clear`
  - `restart`
  - `menu`
  - `killall`
  - `wave`

## Gameplay
Survive 3 waves (5 / 10 / 15 zombies). Zombies can lose limbs, crawl after leg loss, and are often one-shot with clean headshots.

## Multiplayer
- Online mode uses Godot's high-level multiplayer API with `ENetMultiplayerPeer`.
- The host is authoritative for waves, zombie spawning, zombie damage, and win/lose state.
- Clients synchronize player movement and request zombie hits from the host.
- Default port: `7000/UDP`
- LAN play works immediately. Internet play requires UDP port forwarding to the host machine.
- The product direction is simple host/join multiplayer that can work anywhere, with Steam Online / Steam networking as the likely next step for easier public Internet play and friend invites.

See [docs/multiplayer.md](docs/multiplayer.md) for the architecture, flow, and current limitations.

## Roadmap
- [docs/game-roadmap.md](docs/game-roadmap.md) tracks the current game direction: roguelike systems, enemy and weapon expansion, movement upgrades, economy, characters, and long-term progression ideas.

## Stack
- Godot 4.6 (GDScript)
- Blender (low-poly assets, GLB export)
- Authored autonomously by Claude through Blender MCP + direct file authoring
