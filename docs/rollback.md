# Rollback operations

How to undo the cross-tool config overhaul, in whole or in part, and restore per-tool independence. For the forward direction see [`forward.md`](forward.md).

## When you'd want to roll back

- **Experimenting with the setup** and want a pristine starting state.
- **A tool started misbehaving** after a `generate.sh` run and you want to isolate whether the shared config caused it.
- **Handing a machine off** without your personal config.
- **Bisecting** a problem — pull out the cross-tool layer to see if the issue is upstream.

## Safety net

Every `setup.sh` run begins with a pre-change snapshot into `$REPO/.backups/<ISO-timestamp>/` containing plain `cp` copies of every file it's about to mutate. The pointer at `$REPO/.backups/.latest` tracks the newest snapshot. `rollback.sh` reads from there by default and falls back to `jq`/`tomllib` rewrites when a backup isn't available.

```bash
# Peek at what's in the latest snapshot
ls "$(cat $REPO/.backups/.latest)"
# Usually: claude.json, codex-config.toml, gemini-settings.json,
#          opencode.json, claude-settings.json, agents-skill-lock.json
```

Snapshots accumulate across runs. Clean them up manually if the directory gets unwieldy:

```bash
# Keep only the five most recent
ls -1t $REPO/.backups/ | grep -E '^[0-9]{8}T' | tail -n +6 | while read d; do
  rm -rf "$REPO/.backups/$d"
done
```

## Modes

| Mode | Undoes | Safe to re-run? | Data-loss risk |
|---|---|---|---|
| `--flattener` | Plugin-bridge symlinks + SessionStart hook | Yes | None |
| `--mcp` | MCP writes to all 4 tool configs | Yes | None (restores from backup) |
| `--skills` | Skill/lock-file consolidation (symlink → real dir) | Yes | None (uses `.pre-migration` backups) |
| `--commands` | Command → skill migration (restores `.claude/commands/*.md` from git history) | ⚠ git-dependent | Low |
| `--all` | Everything above, in safe order | Yes | None if backups + git history intact |

## Per-mode walk-through

### `rollback.sh --flattener`

1. Removes all `cc-*` symlinks from:
   - `~/.agents/skills/`
   - `~/.config/opencode/agents/`
   - `~/.gemini/agents/`
2. Strips the `flatten.sh` entry from the SessionStart hook in `$REPO/.claude/settings.json` via `jq`.
3. Leaves `$REPO/.agents/plugins/flatten.sh` in place so you can re-enable by restoring the hook or running it manually.

**Verify:**
```bash
find -L ~/.agents/skills -maxdepth 1 -name 'cc-*' | wc -l   # → 0
ls ~/.config/opencode/agents/cc-*.md 2>/dev/null | wc -l    # → 0
ls ~/.gemini/agents/cc-*.md 2>/dev/null | wc -l             # → 0
jq '.hooks.SessionStart[0].hooks | length' $REPO/.claude/settings.json  # was 2, now 1
```

### `rollback.sh --mcp`

For each of the four tool configs:
1. If `$BACKUP_DIR/<tool>.json` (or `.toml`) exists → restore it via `cp`.
2. Otherwise → fall back to `jq 'del(.mcpServers)'` (or `.mcp` for OpenCode). For Codex, the fallback is more limited — manual removal of `[mcp_servers.*]` tables may be needed (the script warns).

Also deletes `$REPO/.agents/mcp/servers.json` (gitignored, will be re-seeded on the next `setup.sh` or `generate.sh seed`).

**Verify:**
```bash
jq '.mcpServers' ~/.claude.json                        # restored original 5 servers (from backup)
jq '.mcp        ' ~/.config/opencode/opencode.json     # null (no fallback for OpenCode — it never had MCP before)
jq '.mcpServers' ~/.gemini/settings.json               # null
grep '^\[mcp_servers\.' ~/.codex/config.toml           # no output
```

### `rollback.sh --skills`

1. `~/.agents/skills`: `rm` the symlink. If `~/.agents/skills.pre-migration/` exists → rename back. Otherwise → `cp -a` from `$REPO/.agents/skills/` (and strip any `cc-*` symlinks from the copy).
2. `~/.agents/.skill-lock.json`: `rm` the symlink. Restore from `$BACKUP_DIR/agents-skill-lock.json` if available, else `cp` from the repo.
3. `$REPO/.claude/skills`: repoint back through `~/.agents/skills` (undoing the direct-link optimization).

**Verify:**
```bash
file ~/.agents/skills ~/.agents/.skill-lock.json   # both should say "directory" / "JSON data", not "symbolic link"
readlink ~/.claude/skills                          # should be ~/.agents/skills (absolute) instead of ../.agents/skills
ls ~/.agents/skills | head                         # original content intact
```

### `rollback.sh --commands`

Restores the five migrated command files (`deploy-check.md`, `run-tests.md`, `lessons.md`, `finish-feature.md`, `start-feature.md`) from git history, and removes the corresponding skill dirs **only if** they were added in the migration commit (guards against deleting older same-named skills).

This is the most brittle mode — it depends on the `claude-config` git history being intact. If you've squashed commits or force-pushed over the migration commit, this mode can't help you. In that case, manually restore from the original command content in the `_agents` submodule or a separate backup.

**Verify:**
```bash
ls .claude/commands/*.md                 # restored files present
git log --diff-filter=A -- .claude/commands/deploy-check.md   # shows the original add commit
```

### `rollback.sh --all`

Runs the four modes in safe order: `--flattener` → `--mcp` → `--skills` → `--commands`. Order matters: flattener first (so stale `cc-*` symlinks don't confuse the skills rollback), then MCP (non-interacting), then skills (so the command rollback can find the right targets), then commands last.

## Independence verification

After `--all`, each tool should work in complete isolation. Run this block and expect every row to be green:

```bash
# 1. Claude Code — original symlinks + MCP config
readlink ~/.claude                                  # → /home/dgon/sources/claude-config/.claude
file ~/.claude/skills                               # symbolic link → ~/.agents/skills (absolute)
jq '.mcpServers | keys' ~/.claude.json              # original 5 servers

# 2. Codex CLI — no MCP, original sections intact
grep -E '^(model|\[projects|\[notice)' ~/.codex/config.toml  # present
grep '^\[mcp_servers\.' ~/.codex/config.toml                 # no output

# 3. OpenCode — permission block intact, no MCP
jq '.permission' ~/.config/opencode/opencode.json   # original entries
jq '.mcp'        ~/.config/opencode/opencode.json   # null

# 4. Gemini CLI — hooks + experimental intact, no MCP
jq '.hooks, .experimental' ~/.gemini/settings.json
jq '.mcpServers'           ~/.gemini/settings.json   # null

# 5. No stray flattened symlinks
find -L ~/.agents/skills ~/.config/opencode/agents ~/.gemini/agents -name 'cc-*' -print
# no output
```

Each tool should launch cleanly (`claude /help`, `codex --version`, `opencode --version`, `gemini --version`) with zero config-parse errors.

## Nuclear restore — when `rollback.sh` itself fails

Every snapshot is plain `cp` copies. No custom format. Manual restore:

```bash
BACKUP=$(cat $REPO/.backups/.latest)
cp "$BACKUP/claude.json"            ~/.claude.json
cp "$BACKUP/codex-config.toml"      ~/.codex/config.toml
cp "$BACKUP/opencode.json"          ~/.config/opencode/opencode.json
cp "$BACKUP/gemini-settings.json"   ~/.gemini/settings.json
cp "$BACKUP/claude-settings.json"   $REPO/.claude/settings.json
cp "$BACKUP/agents-skill-lock.json" ~/.agents/.skill-lock.json
```

For `~/.agents/skills/`, restore from `~/.agents/skills.pre-migration/` (renamed during Step 3b) if it still exists, or manually recreate by copying from `$REPO/.agents/skills/`.

## FAQ

**Will rollback affect my Claude Code plugins?**
No. Plugin cache (`~/.claude/plugins/cache/`) and `installed_plugins.json` are never touched by this plan. After rollback you still have every plugin installed.

**Will rollback affect my git history?**
No. `setup.sh`, `generate.sh`, `flatten.sh`, and `rollback.sh` never create or amend commits. You commit manually when you want changes to sync.

**Can I rollback `--all` and then `setup.sh` again to re-enable?**
Yes. The cycle is fully reversible. `setup.sh` is idempotent and will take a fresh snapshot into `.backups/` on the next run.

**What if I deleted `$REPO/.backups/` by accident?**
MCP rollback falls back to `jq del()` which drops the MCP section entirely. For Claude Code this loses your original `mcpServers` configuration; re-run `claude mcp add <name> -- <command>` for each server, or look for `~/.claude.json.backup` (Claude Code sometimes creates one automatically). For `~/.agents/skills/`, if the `.pre-migration` backup was also deleted, you still have the canonical copy in `$REPO/.agents/skills/` — `cp -a` it back.

**Does `rollback.sh` touch the `_agents` submodule?**
No. It's left exactly where it is, including the uninitialized state if you never ran `git submodule init`.

**Can I rollback a single MCP server but keep the rest?**
That's not a rollback mode — that's a `generate.sh` workflow. Edit `$REPO/.agents/mcp/servers.json` to remove the entry, re-run `generate.sh`, and the writer will drop it from all four tool configs.
