# Pew Pew Dead — agent handover notes

A cute low-poly Godot 4 FPS where you survive 3 waves of zombies. Built end-to-end by Claude as an experiment: AI authors the game, human only tests.

This file exists so the **next agent** (or human) walking in cold can be productive immediately. Read it before doing anything.

---

## 1. What's in the box

| Path | Purpose |
| --- | --- |
| `project.godot` | Godot 4.6 config: input map (WASD/mouse/shoot/jump/Esc), 4 collision layers (World/Player/Enemy/Hitbox), pastel clear color, MSAA 2x. |
| `scenes/main.tscn` + `scripts/main.gd` | Arena scene (root). Wires player ↔ HUD ↔ wave-manager signals. Reloads on win/lose. |
| `scenes/player.tscn` + `scripts/player.gd` | `CharacterBody3D` FPS controller. Mouse-look, raycast shoot, muzzle flash + recoil tween. Player on collision layer 2. |
| `scenes/zombie.tscn` + `scripts/zombie.gd` | `CharacterBody3D` enemy. Chases player via `look_at`, walk-bob, hit flinch, 2-hit death squash tween. Layer 3, mask `World+Player`. |
| `scripts/wave_manager.gd` | Spawns 5 / 10 / 15 zombies across 3 waves. 0.7 s spawn interval, 3 s wave break. |
| `scenes/hud.tscn` + `scripts/hud.gd` | `CanvasLayer` HUD: HP / Wave / Kills labels, crosshair, animated center messages, win/lose end states. |
| `assets/tree.glb` (+ `.import`) | Low-poly stacked-cone tree, modeled live in Blender via MCP. 6 instances scattered around the arena. |
| `assets/source/tree.blend` | Source `.blend` for re-export. Open in Blender, model, re-run the export call from the Blender MCP. |
| `validate.gd`, `smoke.gd` | Headless test scripts. Run via `godot --script <name>`. **Always run smoke.gd before pushing.** |

Pastel palette intentionally hardcoded in `main.tscn` sub-resources (mint floor, lavender walls, peach obstacles, sky gradient). No theme file yet — change the `Color(...)` literals if you want to adjust.

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

These run headlessly from PowerShell on Windows. The Godot binary lives in Steam:
```
C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
```

**Always quote the project path** when calling Godot from `Start-Process` — the path contains spaces and Start-Process splits on whitespace otherwise. Pattern:
```powershell
$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$projectPath = '"C:\Users\Tomi\Documents\Projects\Pew Pew Dead"'   # note the doubled quoting
Start-Process $godot -ArgumentList @("--headless","--path",$projectPath,"--script","smoke.gd") `
  -RedirectStandardOutput "$env:TEMP\out.txt" -RedirectStandardError "$env:TEMP\err.txt" -PassThru -Wait
```

Two test scripts:
- **`validate.gd`** — loads + instantiates every scene. Catches missing references and parse errors. Cheap.
- **`smoke.gd`** — instantiates `main.tscn` and runs 120 frames. Catches `_ready` crashes, signal-wiring bugs, anything that explodes during early simulation. Run this before opening a PR.

After modifying or adding a `.glb` / image / audio asset, also run:
```
godot --headless --path . --import
```
This pre-bakes `.godot/imported/<file>.scn` so headless tests and editor opens don't see "missing resource" errors.

The benign `WARNING: ObjectDB instances leaked at exit` in stderr is normal — happens because test scripts call `quit()` without freeing nodes. Ignore it.

---

## 4. Known gotchas (and how they bit us)

1. **GLB binary corruption on Windows clones.** Without `.gitattributes`, Git-for-Windows defaults (`core.autocrlf=true`) rewrite LF→CRLF inside binary GLBs on checkout, which silently breaks them. The project now ships a `.gitattributes` marking all binary asset extensions explicitly. *If a cloner's working tree was created before this file was added, they need `git rm --cached -r . && git reset --hard HEAD` to renormalize.*

2. **Stale editor state after asset reimport.** If the Godot editor was open before a new asset (e.g. `tree.glb`) finished importing, the editor caches the "missing resource" parse error and shows `vanished node` warnings on subsequent reloads. **Fix: Project → Reload Current Project**, or close + reopen the project window. The headless smoke test will say everything's fine while the editor still complains — trust the headless run.

3. **Zombie pathing is naive.** Straight `look_at` chase, no NavigationAgent3D. Zombies bunch up against obstacles. Acceptable for the prototype; if it becomes a problem, swap in a NavigationRegion3D + NavigationAgent3D.

4. **Bash vs PowerShell.** This is a Windows machine. The Bash tool runs POSIX bash (Git for Windows). PowerShell-only cmdlets (`Get-ChildItem`, etc.) require the PowerShell tool, not Bash. Pick the right one.

5. **Empty `-F` fields with `gh api`.** `gh api -F field=` sends an empty string, which the GitHub schema rejects with a 422 ("not a null"). When you need to send `null` (e.g. for `required_status_checks`), put the body in a JSON file and use `--input`.

6. **Branch protection on private repos costs money.** Classic protection requires GitHub Pro for private repos. We made the repo public; if a future change requires going private again, expect protection to disappear unless the account is upgraded.

---

## 5. MCP / external tooling

- **Blender MCP** (`mcp__blender__*`) — used to model `tree.glb` live in a running Blender instance. Pattern: clear scene → build with `bpy.ops.mesh.primitive_*` → assign materials → select hierarchy → `bpy.ops.export_scene.gltf(... export_yup=True ...)` to `assets/`. After exporting, run `godot --import` so Godot picks it up.
- **Godot MCP** is *not* installed. The project deliberately authors `.tscn` / `.gd` / `project.godot` as text via the regular Write/Edit tools — Godot scenes are plain text and round-trip cleanly. Validation goes through the Godot CLI, not an MCP server. Don't add Godot MCP unless there's a concrete reason; it adds setup friction without buying much.

---

## 6. If you only read one paragraph

Don't push to `main` — branch and PR. Run `smoke.gd` headlessly before opening the PR. After touching binary assets, run `--import` so the cache regenerates, and if the editor is open, **reload the project** to clear stale parse errors. GLBs are binary; `.gitattributes` already protects them, don't change that. The game logic is in five small `.gd` files and four `.tscn` files — read them top to bottom in 10 minutes and you'll know the whole codebase.
