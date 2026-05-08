## Code quality

- **Leave it better than you found it.** If you touch a file, fix obvious mess in the same area: dead code, unused vars, duplicated logic, inconsistent style. You're authorised to delete clearly unused code, exports, and stale references when you encounter them, as long as it won't break anything.
- **No over-abstraction.** Three similar lines is fine. Don't extract a helper for hypothetical future reuse. Build for what's actually needed now. Don't add interfaces, base classes, or config layers that the current code doesn't justify.
- **No duplication.** If you're about to copy-paste a block, factor it instead.
- **Keep diff noise low and scoped.** Don't reformat unrelated code. Don't rename things outside the task. Don't bundle a refactor with a feature.
- **Code is self-documenting.** Use clear identifier names. Don't write comments that just describe *what* the code does.
- **Comments only when the *why* is non-obvious** — a hidden constraint, a Godot quirk, a workaround for a specific bug, a subtle invariant. If removing the comment wouldn't confuse a future reader, don't write it.
- **No backwards-compat shims** for removed code (no `# removed`, no renamed `_var`s, no re-exports). Just delete.

## Debug logs

- `debug/engine_logs/<timestamp>.log` — Godot stdout + stderr (parser errors, push_warning, push_error, all `print()`s)
- `debug/game_logs/<timestamp>.log` — written by the `GameLog` autoload (`Levels/game_log.gd`)

Both folders share the same timestamp per run

**When the user reports a bug:** read the most recent files in both folders before guessing. The `ls -t debug/engine_logs/ | head -1` will give you the freshest.
**When fixing a bug:** add `GameLog.info/warn/error` calls around the area so the next occurrence is diagnosable. The log system was added after most of the game existed — coverage is sparse. Expand it as you go.

**Log levels:**
- `GameLog.info(msg)` — state transitions (run start, wave, level-up, death, ability unlock, upgrade picked)
- `GameLog.warn(msg)` — unexpected-but-recoverable (also calls `push_warning`)
- `GameLog.error(msg)` — things that should never happen (also calls `push_error`)

Logs include timestamp + level automatically — just pass the message.

## run.sh

- Defaults to **debug mode**: captures engine + game logs, rotates folders.
- Pass `--no-debug` (anywhere in args) to skip log capture and run Godot directly.
- All other args pass through to Godot.
- After making a code or scene change for the user, start the game with `./run.sh` so the user can immediately try it.

```bash
./run.sh                                    # default — debug logs on
./run.sh --headless --quit-after 600       # smoke test with logs
./run.sh --no-debug                         # no logs, just runs
./run.sh --no-debug --headless --quit-after 60
```
## Maintaining this file

If you notice the user repeatedly asks for the same thing, corrects the same mistake, or applies the same preference across sessions, add it to this file. AGENTS.md exists so the user doesn't have to repeat themselves to the next agent.
Conversely, prune entries that have become wrong or no longer matter. Don't write content that will rot in a month — file paths, specific signals, current architecture snapshots. Those belong in the code, not here. Keep this file about durable principles, workflow, and Godot/tooling gotchas.

## Testing

- There is a headless smoke run: `./run.sh --headless --quit-after 600 res://Levels/game_level.tscn`.
- This catches scene-load errors, parser errors, missing UIDs, null refs in `_ready` / first second of `_process`. It does **not** catch behaviour bugs at wave 5.
- After Godot adds new `class_name` types, run `godot --headless --import` once to refresh `.godot/` script class registry; otherwise other scripts that reference the new type fail to parse on first load.
