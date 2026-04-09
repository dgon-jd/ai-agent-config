# AI Tool Config

One canonical source of truth for skills and MCP servers, shared across **Claude Code**, **Codex CLI**, **OpenCode**, and **Gemini CLI**. Everything you add in one place shows up in all four tools.

## Mental model

```
~/.agents/skills/          ← canonical (symlink into this repo)
    │
    ├── read natively by Codex, OpenCode, Gemini
    │   (vendor-neutral .agents/skills/ convention, agentskills.io)
    │
    └── Claude Code reads it via ~/.claude/skills symlink

.agents/mcp/servers.json   ← canonical MCP definition
    │
    └── generate.sh writes native configs for all 4 tools
        (.claude.json / .gemini/settings.json / opencode.json / .codex/config.toml)
```

All four tools ship with their own agent/command/prompt directories. Only skills and MCP are shared here — everything else stays per-tool.

## New-machine setup

```bash
git clone --recursive git@github.com:<you>/claude-config.git ~/sources/claude-config
cd ~/sources/claude-config
./setup.sh
```

`setup.sh` is idempotent. Re-run it any time you `git pull` to refresh symlinks, regenerate MCP configs, and re-run the plugin bridge.

Then authenticate each tool you use (`claude`, `codex auth`, `opencode auth`, `gemini auth`).

## Day-to-day sync

```bash
./sync.sh pull     # pull latest
./sync.sh status   # what's changed locally
./sync.sh push     # push local changes
```

New skills installed via `npx skills add <repo>` land directly in `$REPO/.agents/skills/` (the symlink chain points there). Commit + push to sync across machines.

## What's shared vs per-tool

| Content | Shared across tools? | Where |
|---|---|---|
| **Skills** (SKILL.md) | ✅ all 4 tools | `.agents/skills/` — native cross-vendor discovery |
| **MCP servers** | ✅ all 4 tools | `.agents/mcp/servers.json` → generated per tool |
| **Plugin content** (Claude) | ✅ partial — see below | bridged via `.agents/plugins/flatten.sh` |
| Agents (roster) | ❌ per-tool | each tool's own `agents/` dir |
| Commands / prompts | ❌ per-tool | each tool's own dir (collapse into skills when possible) |

**Claude Code plugins** install into `~/.claude/plugins/cache/…`. A SessionStart hook runs `.agents/plugins/flatten.sh` to symlink plugin skills (and agents, for OpenCode + Gemini only) under `cc-<plugin>-<name>` so the other tools can see them too. Codex doesn't have an agent-roster concept, so it gets skills but not agents.

## Repo layout

```
.
├── .agents/
│   ├── skills/          ← canonical (git-tracked; cc-* symlinks gitignored)
│   ├── mcp/
│   │   ├── generate.sh  ← servers.json → 4 tool configs
│   │   └── servers.json ← gitignored (contains API keys)
│   ├── plugins/
│   │   └── flatten.sh   ← bridges plugin content cross-tool
│   └── .skill-lock.json ← vercel-labs/skills manifest
├── .claude/             ← Claude Code config (symlinked to ~/.claude)
│   ├── settings.json    ← SessionStart hook runs flatten.sh
│   ├── CLAUDE.md
│   ├── hooks/, plugins/, teams/, …
├── .backups/            ← pre-change snapshots from setup.sh (gitignored)
├── setup.sh             ← idempotent bootstrap
├── rollback.sh          ← tiered undo (--mcp, --flattener, --skills, --commands, --all)
├── sync.sh              ← git push/pull helper
├── docs/
│   ├── forward.md       ← how setup.sh works + day-to-day recipes
│   └── rollback.md      ← how to undo everything, mode by mode
└── README.md            ← this file
```

## Forward and backward operations

- **Forward operations** (setup, add a skill, add an MCP server, install a plugin and bridge it, sync across machines) → see [`docs/forward.md`](docs/forward.md)
- **Rollback** (undo the cross-tool changes, restore per-tool independence) → see [`docs/rollback.md`](docs/rollback.md)

Both documents describe the same system from opposite directions. Keep them in sync when you change `setup.sh` or `rollback.sh`.

## What's NOT tracked (machine-specific)

- `.agents/mcp/servers.json` — holds API keys, re-seed per machine from `~/.claude.json`
- `.agents/skills/cc-*/` — plugin-flattened symlinks, re-generated per machine
- `.backups/` — pre-change snapshots, machine-specific
- `.credentials.json`, session state, history, caches, telemetry, plugin binaries, project-specific state

## Acknowledgements

The `.agents/skills/` directory is a vendor-neutral convention championed by [agentskills.io](https://agentskills.io). Codex, OpenCode, and Gemini CLI all document explicit support for it. Claude Code reaches the same tree through a symlink.

Skills are managed with [vercel-labs/skills](https://github.com/vercel-labs/skills) (`npx skills add/update/remove`).
