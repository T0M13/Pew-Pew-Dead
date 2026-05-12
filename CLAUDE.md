# Pew Pew Dead — agent handover notes

A cute low-poly Godot 4 FPS that grew into an endless wave roguelike. Built end-to-end by Claude as an experiment: AI authors the game, human tests.

This file exists so the **next agent** (or human) walking in cold can be productive immediately. Read it before doing anything.

---

## 1. What's in the box

| Path | Purpose |
| --- | --- |
| `project.godot` | Godot 4.6 config: input map (WASD/mouse/shoot/sprint/jump/slide/melee/console/Esc), 4 collision layers (World/Player/Enemy/Hitbox), pastel clear color, MSAA 2x. |
| `scenes/main.tscn` + `scripts/main.gd` | Arena scene (root). Wires player ↔ HUD ↔ wave-manager signals. Owns drop spawning, card-phase orchestration, MP RPCs. |
| `scenes/player.tscn` + `scripts/player.gd` | `CharacterBody3D` FPS controller. Mouse-look, slide, sprint, stamina-gated bhop with Quake-style air strafe, three weapons (pistol charge / rifle auto / shotgun spread), card-driven stat hooks. Player on collision layer 2. |
| `scenes/projectile.tscn` + `scripts/projectile.gd` | Charge-shot orb with pierce, bounce, ribbon trail, element rotation (solar/frost/venom/knockback). Used by all three weapons via `_spawn_projectile`. |
| `scenes/projectile_impact.tscn` + `scripts/projectile_impact.gd` | Hit burst + scorch effect spawned where a projectile resolves. |
| `scenes/zombie.tscn` + `scripts/zombie.gd` | Enemy actor. Variant-driven (`walker`/`runner`/`spitter`/`brute`/`exploder`/`boss`), per-zone hit boxes, attack windup state machine, gib system, status effects (slow/poison), spit attack for spitters, AoE death for exploders. Layer 3, mask `World+Player`. |
| `scenes/zombie_spit.tscn` + `scripts/zombie_spit.gd` | Spitter ranged projectile (Area3D, damages on player overlap). |
| `scenes/drop.tscn` + `scripts/drop.gd` | Bobbing pickup crystal. Types: `heal`, `max_health`, `speed`, `damage`. Server picks position; pickup goes through `player.apply_pickup`. |
| `scripts/wave_manager.gd` | Endless waves: `base_wave_size + wave_size_growth*(n-1)`. Picks variant per spawn with progressive odds. Bosses every 5th wave. Emits `card_phase_requested` between waves and awaits `card_phase_done`. |
| `scripts/card_library.gd` | Single source of truth for cards. CARDS array + match arms in `apply()`. Adding a card = one dict + one match arm, no other code changes. |
| `scripts/card_picker.gd` (in `hud.tscn`) | Full-screen overlay with 3 choice buttons (1/2/3 hotkeys). 0.4s input grace prevents accidental picks. |
| `scripts/blood_spray.gd` | Particle blood droplets spawned from `zombie.take_hit`. Imported from Mert's PR #10. |
| `scenes/muzzle_smoke.tscn` + `scripts/muzzle_smoke.gd` | Tween-driven puff + charge rings spawned by `_spawn_muzzle_smoke`. Imported from Mert's PR #10. |
| `scenes/hud.tscn` + `scripts/hud.gd` | `CanvasLayer` HUD: HP / Wave / Kills / STAM / WPN labels, crosshair, center messages, perf panel, debug console, menu, embedded `CardPicker`. |
| `assets/tree.glb` (+ `.import`) | Low-poly stacked-cone tree, modeled live in Blender via MCP. 6 instances scattered around the arena. |
| `assets/source/tree.blend` | Source `.blend` for re-export. Open in Blender, model, re-run the export call from the Blender MCP. |
| `validate.gd`, `smoke.gd` | Headless test scripts. Run via `godot --script <name>`. **Always run smoke.gd before pushing.** |

Pastel palette intentionally hardcoded in `main.tscn` sub-resources (mint floor, lavender walls, peach obstacles, sky gradient). No theme file yet — change the `Color(...)` literals if you want to adjust.

---

## 1a. Major systems at a glance

These are the load-bearing systems an agent will touch most often. Existing tuning values are intentional — see §4b before retuning.

### Weapons (player.gd)
Three slots, hotkeys `1`/`2`/`3`:
- **Pistol** — hold to charge, release to fire. Charge ramps damage, pierce, bounce, projectile size.
- **Rifle** — hold to full-auto. `weapon_rifle_rpm`, low per-shot damage, light spread.
- **Shotgun** — click for 5-pellet spread, per-shot cooldown.
All three route through `_spawn_projectile(direction, charge, damage_mult)` so card stat bonuses (`damage_bonus`, `projectile_speed_bonus`, `projectile_pierce_bonus`, `projectile_bounce_bonus`) apply to every weapon automatically.

### Cards (card_library.gd + card_picker.gd)
Server picks 3 random cards per player at end of every wave, presents via `present_cards` RPC, collects via `submit_card_pick`, applies via `apply_card_remote`. Wave manager halts on `card_phase_requested` / `await card_phase_done`. To add a card: append to `CARDS` and add a match arm in `apply()`. Don't add new player fields without updating the apply-time mutations.

### Enemy variants (zombie.gd)
`@export var variant: StringName` switches stats and tint at `_ready` via `_apply_variant_config`. Wave manager's `_pick_variant` chooses which to spawn. Variants:
- `walker` — default chaser
- `runner` — small, fast, fragile
- `spitter` — purple, holds range, fires `zombie_spit`
- `brute` — large, slow, tanky, big punch
- `exploder` — yellow, fast, low HP, AoE on death (`_trigger_exploder_blast`)
- `boss` — red, scales 2.2x, spawned alongside regular pack on every 5th wave via `_spawn_boss`

### Drops (drop.gd, server-authoritative)
End of each wave, server rolls `drop_chance_per_wave + growth` and spawns a drop via `spawn_drop` RPC at a clear-of-obstacles position. Pickup runs `player.apply_pickup` locally on the player who touches it; server broadcasts despawn.

### Stamina-gated bhop (player.gd)
`stamina_max`/`stamina_per_jump`/`stamina_regen`/`stamina_min_to_jump` gate jumping. `air_speed_cap` is the bhop ceiling, tuned to ~sprint speed by default; the `speed` drop and several cards raise it (so chained bhops only go fast after build investment). Auto-jump on hold (`Input.is_action_pressed("jump")` re-arms the buffer).

### Lifesteal (player.gd + main.gd)
`lifesteal_per_kill` set by the Vampire card. `main._on_zombie_died_for_lifesteal` heals nearby (≤ 12 m) lifesteal-carrying players when a zombie dies; routed via `grant_lifesteal` RPC for non-host peers.

### Effects (muzzle_smoke.gd / blood_spray.gd)
`player._spawn_muzzle_smoke` fires after every projectile spawn. `zombie._spawn_blood_spray` fires inside `take_hit`, anchored at the hit zone's hitbox center.

---

## 2. Workflow rules — read this before committing

**`main` is protected.** Direct push fails for everyone, including the repo owner (`enforce_admins: true`). The flow is always:

```
git checkout -b <prefix>/<short-description>
# ... edits ...
git commit -m "..."
git push -u origin <branch>
gh pr create --title "..." --body "..."
gh pr merge <num> --squash --delete-branch
```

Important repo habit:
- After pushing any working branch, **always create the PR immediately** unless the user explicitly says not to.

Repo settings already enforce:
- PR required (0 reviews needed — solo project; bump to 1 once a real collaborator exists)
- No force pushes, no deletions, linear history, conversation resolution required
- Auto-delete merged branches on the remote (`delete_branch_on_merge: true`)
- Local stale refs: `git fetch --prune` after a PR merges

Branch prefixes used so far: `fix/...` for bug fixes. Add `feat/...`, `chore/...`, `docs/...` as needed.

---

## 3. Validating changes (the rituals)

**One-time setup per machine** — create a gitignored `.godot-path` file in the project root containing just the path to your Godot binary (no quotes, no trailing newline):
```
echo 'C:\path\to\your\Godot.exe' > .godot-path
```
All scripts (`run.sh`, `scripts/post-merge.hook`) read this file automatically. No paths are hardcoded anywhere in the repo.

Also install the git hooks once:
```bash
bash scripts/install-hooks.sh
```

**To launch the game with logging** (output → `debug/engine_logs/`), run from Git Bash:
```bash
bash run.sh
```
`run.sh` resolves Godot from: `.godot-path` file → `GODOT` env var → `godot` on `$PATH`.

**Headless tests** — run from PowerShell:
```powershell
$godot = Get-Content .godot-path
$proj   = $PSScriptRoot   # or the project root path
Start-Process $godot -ArgumentList @("--headless","--path",$proj,"--script","smoke.gd") `
  -RedirectStandardOutput "$env:TEMP\out.txt" -RedirectStandardError "$env:TEMP\err.txt" -PassThru -Wait
Get-Content "$env:TEMP\out.txt"; Get-Content "$env:TEMP\err.txt"
```

Two test scripts:
- **`validate.gd`** — loads + instantiates every scene. Catches missing references and parse errors. Cheap.
- **`smoke.gd`** — instantiates `main.tscn` and runs 120 frames. Catches `_ready` crashes, signal-wiring bugs, anything that explodes during early simulation. Run this before opening a PR.

After modifying or adding a `.glb` / image / audio asset, also run:
```bash
bash run.sh --no-debug --quit   # or just open the editor which auto-imports
```
This pre-bakes `.godot/imported/<file>.scn` so headless tests and editor opens don't see "missing resource" errors.

**Known headless quirk**: `CardLibrary` (`class_name` script) shows parse errors in stderr under `--script`/`--headless` because class registrations aren't populated before the test script runs. Game uses cached bytecode and runs fine — ignore those errors. The `ObjectDB instances leaked at exit` warning is also benign.

**After pulling changes**: the `post-merge` hook auto-runs `godot --import`. If the editor is open, also do **Project → Reload Current Project** to clear stale cached state.

---

## 4. Known gotchas (and how they bit us)

1. **GLB binary corruption on Windows clones.** Without `.gitattributes`, Git-for-Windows defaults (`core.autocrlf=true`) rewrite LF→CRLF inside binary GLBs on checkout, which silently breaks them. The project now ships a `.gitattributes` marking all binary asset extensions explicitly. *If a cloner's working tree was created before this file was added, they need `git rm --cached -r . && git reset --hard HEAD` to renormalize.*

2. **Stale editor state after asset reimport.** If the Godot editor was open before a new asset (e.g. `tree.glb`) finished importing, the editor caches the "missing resource" parse error and shows `vanished node` warnings on subsequent reloads. **Fix: Project → Reload Current Project**, or close + reopen the project window. The headless smoke test will say everything's fine while the editor still complains — trust the headless run.

3. **Zombie pathing is naive.** Straight `look_at` chase, no NavigationAgent3D. Zombies bunch up against obstacles. Acceptable for the prototype; if it becomes a problem, swap in a NavigationRegion3D + NavigationAgent3D.

4. **Bash vs PowerShell.** This is a Windows machine. The Bash tool runs POSIX bash (Git for Windows). PowerShell-only cmdlets (`Get-ChildItem`, etc.) require the PowerShell tool, not Bash. Pick the right one.

5. **Empty `-F` fields with `gh api`.** `gh api -F field=` sends an empty string, which the GitHub schema rejects with a 422 ("not a null"). When you need to send `null` (e.g. for `required_status_checks`), put the body in a JSON file and use `--input`.

6. **Branch protection on private repos costs money.** Classic protection requires GitHub Pro for private repos. We made the repo public; if a future change requires going private again, expect protection to disappear unless the account is upgraded.

---

## 4b. Don't change what already works

Existing systems are **locked** unless the user explicitly asks for that change. Do not retune existing exported values, restructure existing scenes, rename existing signals or methods, or rewrite existing RPC signatures. If a feature is already in the game and the user did not flag it, leave it alone — add new content beside it instead.

Exceptions:
- Bugs the user reported.
- Refactors the user explicitly requested.

Even in those cases, change the smallest area that fixes the report. When in doubt, ask before editing existing code; adding a new file is always safer than rewriting an existing one.

---

## 5. MCP / external tooling

- **Blender MCP** (`mcp__blender__*`) — used to model `tree.glb` live in a running Blender instance. Pattern: clear scene → build with `bpy.ops.mesh.primitive_*` → assign materials → select hierarchy → `bpy.ops.export_scene.gltf(... export_yup=True ...)` to `assets/`. After exporting, run `godot --import` so Godot picks it up.
- **Godot MCP** is *not* installed. The project deliberately authors `.tscn` / `.gd` / `project.godot` as text via the regular Write/Edit tools — Godot scenes are plain text and round-trip cleanly. Validation goes through the Godot CLI, not an MCP server. Don't add Godot MCP unless there's a concrete reason; it adds setup friction without buying much.

---

## 6. If you only read one paragraph

Don't push to `main` — branch and PR. Run `smoke.gd` headlessly before opening the PR. After touching binary assets, run `--import` so the cache regenerates, and if the editor is open, **reload the project** to clear stale parse errors. GLBs are binary; `.gitattributes` already protects them, don't change that. The game logic is in five small `.gd` files and four `.tscn` files — read them top to bottom in 10 minutes and you'll know the whole codebase.
