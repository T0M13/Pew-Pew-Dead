# Multiplayer Notes

## Goal

Keep the existing prototype intact and add the easiest playable online mode:

- same arena
- same zombie waves
- host/client instead of dedicated server
- minimal new UI
- minimal scene churn

Longer-term product direction:

- simple host / join flow
- multiplayer usable outside LAN
- Steam-friendly online play so friends can connect more easily
- room to evolve toward server-like session behavior without rebuilding the whole game

## Current Architecture

- Transport: Godot high-level multiplayer over `ENetMultiplayerPeer`
- Topology: listen server
- Default port: `7000/UDP`
- Authority model:
  - host owns wave progression
  - host spawns zombies
  - host applies zombie damage
  - host resolves zombie hit requests from clients
  - each player owns and broadcasts their own transform state

What works today:

- solo play
- LAN host / join
- Internet host / join if the host forwards `UDP 7000`

What the intended end-state is:

- host / join multiplayer that feels like lightweight servers
- sessions that work anywhere, not only on local network
- likely Steam Online / Steam networking integration for discovery, invites, and easier NAT traversal

## Scene Flow

The game still boots into `scenes/main.tscn`, but it no longer starts combat immediately.

`HUD` now exposes:

- `Play Solo`
- `Host`
- `Join`

`Main` waits for one of those actions, then starts the session.

## Node Responsibilities

### `scripts/main.gd`

- starts solo / host / join flows
- manages peer connect/disconnect signals
- spawns player instances dynamically
- keeps host and clients in sync for:
  - player roster
  - current wave
  - total kills
  - existing zombies for late joiners
  - win / lose state

### `scripts/player.gd`

- local player handles input, movement, jump, shooting
- remote players interpolate received transform state
- in multiplayer, direct zombie damage only happens on the host
- clients send zombie hit requests to peer `1`

### `scripts/zombie.gd`

- host runs AI, targeting, attacks, and death
- clients only interpolate zombie state from the host
- zombies target the nearest alive player instead of the first player node

### `scripts/wave_manager.gd`

- no longer auto-starts in `_ready()`
- starts only when the host or solo game begins
- emits `zombie_spawned` so `Main` can assign network IDs and replicate spawns

## Late Join Behavior

When a new client connects mid-session, the host sends:

- existing players
- the joining player
- all currently alive zombies
- current wave label state
- current kill count

This keeps new clients visually and logically close to the host state without adding a full lobby system yet.

## Tradeoffs

This is intentionally the easiest viable pass, not a production-grade netcode stack.

- No prediction or rollback
- No lag compensation
- No dedicated lobby scene
- No NAT punch-through
- No replication framework nodes yet (`MultiplayerSynchronizer`, `MultiplayerSpawner`)
- No Steam networking yet

That tradeoff is deliberate: the current game is tiny, so manual RPC sync is easier to reason about and change quickly.

## Testing

Headless checks that should stay in the loop:

- `validate.gd`
- `smoke.gd`

Validated in this pass:

- scenes load and instantiate
- main scene survives 120 headless frames after starting solo mode

Still needed manually in Godot:

- host + join from two real game instances
- verify remote player interpolation feels acceptable
- verify zombie hit registration from a remote client
- verify host disconnect / client disconnect behavior
- verify Internet play with UDP forwarding if you want non-LAN sessions
- later: verify Steam-based connection flow once that layer exists

## Why ENet

This project uses the simplest official path for a real-time action prototype:

- Godot's high-level multiplayer API provides RPCs on scene nodes
- `ENetMultiplayerPeer` is the straightforward host/client transport for action gameplay
- Internet hosting needs UDP port forwarding on the chosen port

Relevant official docs used for this design:

- https://docs.godotengine.org/en/latest/tutorials/networking/high_level_multiplayer.html
- https://docs.godotengine.org/en/4.6/classes/class_multiplayerapi.html
- https://docs.godotengine.org/en/4.3/classes/class_enetmultiplayerpeer.html

## Future Upgrades

Good next steps, in order:

1. Add a small lobby scene with player names and ready state
2. Move player and zombie replication to `MultiplayerSynchronizer` / `MultiplayerSpawner`
3. Add shot VFX replication for remote players
4. Add better player / enemy art using Blender MCP
5. Add Steam Online / Steam networking support so host / join works more like public online sessions
6. Add host migration or a dedicated server path if the project grows
