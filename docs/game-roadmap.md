# Game Roadmap

## Vision

Turn `Pew Pew Dead` from a small wave shooter prototype into a replayable co-op action roguelike:

- cute low-poly style
- short runs
- escalating waves
- build variety
- multiple enemy and weapon archetypes
- host / join multiplayer
- room for Steam-friendly online play later

The strongest current direction is:

`Cute low-poly co-op roguelike zombie survival shooter`

## Core Pillars

### Fast readable combat

- snappy movement
- easy-to-read enemies
- weapons that feel distinct
- high clarity even when runs get chaotic

### Roguelike replayability

- runs should branch through upgrades, items, and economy choices
- players should be able to create different builds every run
- failure should lead to "one more run" rather than frustration

### Co-op friendly systems

- mechanics should stay understandable in multiplayer
- builds should be fun alone and with friends
- support host / join sessions without requiring a dedicated server

### Stylized low-poly personality

- more characters
- better enemy silhouettes
- more props and breakables
- stronger environment identity as the game grows

## High-Priority Feature Buckets

### 1. Roguelike progression

- XP pickups
- level-up system
- choose 1 of 3 upgrades on level-up
- item rarity
- passive stacking
- synergy-based upgrades
- run-ending stats / summary

Example upgrade pool:

- move speed
- fire rate
- damage
- max HP
- reload speed if reloads are added
- crit chance
- crit damage
- splash shots
- chain shots
- lifesteal
- extra jump
- revive once per run

### 2. Enemy variety

The game needs more than one zombie type as soon as possible.

Good first set:

- basic walker
- fast runner
- tank brute

Good second set:

- ranged spitter
- exploder
- armored zombie
- support / healer enemy
- elite variants

Longer term:

- minibosses
- boss waves
- biome-specific enemies

### 3. Weapons

Weapons should change playstyle, not just stats.

Strong first batch:

- pistol
- shotgun
- SMG
- rifle

Good follow-ups:

- burst rifle
- revolver
- launcher
- energy gun
- melee backup weapon

Weapon systems worth adding later:

- reloads
- ammo economy
- alternate fire
- elemental or status effects
- weapon rarity / upgrades

### 4. Economy and shop loop

Between-wave decisions can turn the game into a full run-based loop.

Possible systems:

- coins from kills
- coins from breakables
- shop between waves
- heal station
- reroll shop
- temporary buffs
- permanent run upgrades

Shop examples:

- heal
- buy weapon
- buy passive item
- reroll choices
- increase max HP
- revive token

### 5. Breakables and pickups

Breakables make arenas more alive and reward movement.

Good additions:

- crates
- barrels
- lockers
- vending machines

Possible drops:

- XP
- coins
- healing
- ammo later
- temporary buffs

### 6. Character identities

Different playable characters can create instant replayability.

Good examples:

- Scout: fast movement, low HP
- Tank: high HP, slower movement
- Gunslinger: stronger crit / fire rate
- Medic: healing-oriented passive later
- Engineer: turret or gadget leaning later

Keep early versions simple:

- one starting passive
- one starting weapon bias
- one silhouette / color identity

## Movement Expansion

Movement can become a major fun pillar, not just a basic FPS controller.

### Good near-term upgrades

- sprinting
- sliding
- coyote time for jumps
- jump buffering
- stronger air control tuning
- better landing feel
- smoother acceleration / deceleration

### Good medium-term upgrades

- vaulting over low obstacles
- ledge grab
- mantling
- wall-jump or wall-run light variant
- dash
- double jump as upgrade

### Parkour direction

This should stay "light parkour," not a full movement shooter rewrite.

Best fit for this game:

- sprint into slide
- slide into jump for flow
- quick mantle over cover
- upgrade-driven extra mobility

That keeps combat readable while making movement more expressive.

## Risk of Rain Style Direction

If the project leans more into a Risk of Rain-like feel, the important ingredients are:

- stacking items
- wild synergies
- increasingly chaotic runs
- enemies scaling hard over time
- players becoming temporarily overpowered if the build comes together

Examples of fitting effects:

- chance to explode on kill
- chain lightning bullets
- orbiting drones
- healing on crit
- fire trail while sprinting
- extra projectile chance
- on-hit slow
- temporary shield on level-up

## Best Build Order

Recommended order for turning the prototype into a stronger game:

1. More enemy types
2. XP drops and level-up choices
3. More weapons
4. Coins and shop between waves
5. Breakables and pickup variety
6. Character selection and starting passives
7. Better movement: sprint, slide, light mantle
8. Meta progression and unlocks
9. Bosses, biomes, and bigger content expansions

## Next Milestone Recommendation

If only one milestone should happen next, this is the highest-value package:

- 3 enemy types total
- XP drops
- level-up choice screen
- 2 new weapons
- simple between-wave shop

That would change the game from "prototype shooter" into "early replayable roguelike shooter."

## Art and Blender Direction

Blender MCP is a strong fit for the next content pass.

Good art priorities:

- improved player model
- improved zombie base model
- distinct silhouettes for each enemy type
- weapon models
- breakable prop set
- environmental props for arena identity

Keep style goals:

- readable
- low-poly
- cute but dangerous
- bold silhouettes over detail noise

## Multiplayer Considerations

As systems grow, these should stay in mind:

- level-up choices need synchronized pause / UI flow in co-op
- shops need shared or per-player logic
- item drops need clear ownership / pickup rules
- movement abilities need to replicate cleanly
- new enemy behaviors should stay host-authoritative unless netcode is upgraded

## Later Systems

Strong later additions once the core loop is solid:

- meta progression
- unlockable characters
- achievements
- difficulty modifiers
- seeded runs
- map variants
- biome rotation
- events between waves
- challenge shrines
- boss encounters

## What Not To Do Too Early

Avoid spreading effort across too many shallow systems at once.

Lower priority until the core loop is stronger:

- huge narrative layer
- oversized map count
- too many weapons with tiny differences
- overly complicated inventory systems
- dedicated server infrastructure before the game loop proves itself

## Summary

The best identity for the project is not "random feature pile."

The best identity is:

- wave-based co-op zombie shooter
- roguelike build progression
- expressive but readable movement
- low-poly charm
- fast repeatable runs

That gives every future addition a clear filter: if it improves replayability, combat feel, co-op fun, or build variety, it probably belongs.
