# Forward operations

How to install, use, and extend the cross-tool config. For the reverse direction see [`rollback.md`](rollback.md).

## What `setup.sh` does, step by step

Every mutation is captured in `$REPO/.backups/<ISO-timestamp>/` before it happens. The pointer `$REPO/.backups/.latest` tracks the most recent snapshot. `rollback.sh` reads it to restore.

1. **Guard `~/.claude → $REPO/.claude` symlink.** No-op if already correct; error (with fix hint) if pointing elsewhere; create if missing.
2. **Initialize git submodules.** `_agents` and `PRPs-agentic-eng` are legacy — kept around but not shared cross-tool.
3. **Pre-change snapshot.** Copies every file the script might mutate (`~/.claude.json`, `~/.codex/config.toml`, `~/.config/opencode/opencode.json`, `~/.gemini/settings.json`, `$REPO/.claude/settings.json`, `~/.agents/.skill-lock.json`) into `$REPO/.backups/<ts>/`. Plain `cp` copies, no custom format.
4. **Skill consolidation** (`Step 3b`)
   - `~/.agents/skills`: real dir → rsync into `$REPO/.agents/skills/`, diff-verify, rename old to `.pre-migration`, create symlink.
   - `~/.agents/.skill-lock.json`: real file → drift-detect against repo, copy local in if different, rename + symlink.
   - `$REPO/.claude/skills`: repoint to `../.agents/skills` (relative, portable).
5. **Unmigrated command warning** (`Step 3c`). Checks for stale `.md` files in `$REPO/.claude/commands/`. If present, prints a hint to migrate them to skills. Plugin-managed subdirs like `gsd/` are left alone.
6. **MCP propagation** (`Step 3d`)
   - If `$REPO/.agents/mcp/servers.json` is missing and `~/.claude.json` has `mcpServers`, auto-run `generate.sh seed`.
   - Run `generate.sh` to write all four tool configs atomically.
7. **Gemini experimental flag** (`Step 3e`). Merge-set `experimental.enableAgents: true` in `~/.gemini/settings.json` without clobbering other experimental keys.
8. **Plugin bridge** (`Step 3f`). Run `.agents/plugins/flatten.sh` once. The SessionStart hook (added to `.claude/settings.json`) takes over for ongoing maintenance — it re-runs on every Claude Code session to handle plugin updates.
9. **Claude plugin marketplaces + user plugins** (guarded by `command -v claude`). Installs the pinned list; safe on machines without Claude Code.
10. **Runtime directories.** Creates `cache/`, `sessions/`, etc. so Claude Code doesn't complain on first launch.

## Day-to-day workflows

### Add a new skill (cross-tool)

```bash
npx skills add <github-owner>/<repo>#<skill-name>
# → lands in ~/.agents/skills/<skill-name>/ (= $REPO/.agents/skills/<skill-name>/)
# → ~/.agents/.skill-lock.json (= $REPO/.agents/.skill-lock.json) updated
cd $REPO && git add .agents/skills/<name> .agents/.skill-lock.json
git commit -m "skills: add <name>"
git push
# On another machine: git pull → skill immediately usable in all 4 tools
```

### Author a skill by hand

```bash
mkdir -p $REPO/.agents/skills/my-skill
cat > $REPO/.agents/skills/my-skill/SKILL.md <<'MD'
---
name: my-skill
description: One-sentence trigger description (what the user says or wants)
---

# Instructions

What the skill should do when invoked.
MD
cd $REPO && git add .agents/skills/my-skill && git commit -m "skills: add my-skill"
```

The `description` field is critical — it's what drives trigger matching in Claude Code and equivalent mechanisms in the other tools.

### Add an MCP server

```bash
$EDITOR $REPO/.agents/mcp/servers.json
# Add an entry under .mcpServers:
#   "my-server": {
#     "command": "npx", "args": ["-y", "my-mcp-server"], "env": {"KEY": "..."}
#   }
# Or for HTTP-type: { "url": "https://...", "headers": {...} }

$REPO/.agents/mcp/generate.sh
# → Writes to all 4 tool configs
```

`servers.json` is gitignored because entries often hold API keys. Re-seed per machine: `$REPO/.agents/mcp/generate.sh seed` extracts `.mcpServers` from the current `~/.claude.json`.

### Remove an MCP server

Delete the entry from `servers.json`, re-run `generate.sh`. The writer removes it from all four tool configs.

### Install a Claude Code plugin and use it cross-tool

```bash
claude plugin install <plugin>@<marketplace>
# The next Claude Code session triggers the SessionStart hook:
#   bash -c 'exec "$(dirname "$(readlink -f ~/.claude)")/.agents/plugins/flatten.sh"'
# → Creates ~/.agents/skills/cc-<plugin>-<skill>/ symlinks for every skill
# → Creates ~/.config/opencode/agents/cc-<plugin>-<name>.md symlinks
# → Creates ~/.gemini/agents/cc-<plugin>-<name>.md symlinks
# → Codex gets the skills (via ~/.agents/skills/) but not the agents
#   (no agent-roster concept)
```

To force an immediate refresh without starting a new Claude session:

```bash
$REPO/.agents/plugins/flatten.sh
```

### Sync across machines

```bash
cd $REPO && git pull
./setup.sh                        # idempotent; regenerates MCP, re-runs flattener
```

On a fresh machine you'll also need to re-seed `servers.json` (it's gitignored):

```bash
# First authenticate Claude Code to get your personal MCP config, then:
$REPO/.agents/mcp/generate.sh seed
$REPO/.agents/mcp/generate.sh
```

## Troubleshooting

**Codex doesn't see my skills**
`readlink -f ~/.agents/skills` should resolve inside `$REPO/.agents/skills/`. If it points elsewhere, re-run `setup.sh` — Step 3b will flip the symlink.

**MCP server missing in one tool**
Re-run `$REPO/.agents/mcp/generate.sh`. Sanity check:
```bash
jq -r '.mcpServers | keys[]' ~/.claude.json       | sort
jq -r '.mcpServers | keys[]' ~/.gemini/settings.json | sort
jq -r '.mcp        | keys[]' ~/.config/opencode/opencode.json | sort
grep -oP '^\[mcp_servers\.\K[^.\]]+' ~/.codex/config.toml | sort -u
```
All four lists must match.

**Plugin skill not visible in Codex after install**
The SessionStart hook hasn't fired yet. Either start a new Claude session, or run `.agents/plugins/flatten.sh` manually.

**Broken `cc-*` symlink after plugin update**
Expected between the plugin update and the next Claude session. The flattener self-heals: it removes the stale link and creates a fresh one pointing at the new version path. Run it manually if you can't wait.

**`git status` is noisy after `npx skills update`**
Expected — those are the skill content updates, now git-tracked. Review, commit, push.

**`~/.codex/config.toml` parse error after generating**
The Codex writer validates every output through `tomllib.loads()` before renaming. If it writes a broken file, it's a bug — the safety net failed. Restore from the latest snapshot:
```bash
cp "$(cat $REPO/.backups/.latest)/codex-config.toml" ~/.codex/config.toml
```
Then file an issue with the contents of `servers.json`.

## A note on npx skills and the `-a` flag

`npx skills add <repo>` writes skills to agent-specific paths if you pass `-a <agent>`. Don't — let it use the default, which lands under `~/.agents/skills/`. That way the install is shared across all four tools (via the vendor-neutral convention) AND tracked in git (via the symlink into `$REPO/.agents/skills/`). Using `-a codex` or `-a claude-code` defeats both.
