# AI Agent Config

Portable configuration for AI coding agents, shared across **Claude Code**, **Codex CLI**, **OpenCode**, and **Gemini CLI**. One repo, one `setup.sh`, all four tools get the same skills, MCP servers, and plugin content.

## How it works

```
~/.agents/skills/          ← canonical skills (git-tracked, symlinked)
    ├── read natively by Codex, OpenCode, Gemini (agentskills.io convention)
    └── Claude Code reads via ~/.claude/skills symlink

.agents/mcp/servers.json   ← canonical MCP definitions (gitignored, holds API keys)
    └── generate.sh writes native configs for all 4 tools

.agents/plugins/flatten.sh ← SessionStart hook bridges plugin content cross-tool
    ├── skills: symlinked as-is (SKILL.md is a cross-vendor standard)
    └── agents: copied with per-tool frontmatter rewrite (sync-agents.sh)
```

## Quick start

```bash
git clone --recursive git@github.com:<you>/claude-config.git ~/sources/claude-config
cd ~/sources/claude-config
./setup.sh
```

`setup.sh` is idempotent — re-run after `git pull` to sync everything.

## What's shared

| Content | Shared? | Mechanism |
|---|---|---|
| **Skills** (39 SKILL.md) | ✅ all 4 tools | `~/.agents/skills/` — vendor-neutral discovery |
| **MCP servers** (5) | ✅ all 4 tools | `generate.sh` → JSON×3 + TOML |
| **Plugin skills** (96) | ✅ all 4 tools | `flatten.sh` symlinks `cc-*` dirs |
| **Plugin agents** (60) | ✅ Claude + OpenCode + Gemini | `sync-agents.sh` copies with per-tool format rewrite |
| **Plugins** (38) | ✅ Claude Code | `plugins.txt` manifest → `setup.sh` installs |
| **Marketplaces** (9) | ✅ Claude Code | `marketplaces.txt` manifest → `setup.sh` adds |
| **Commands** | ✅ all 4 tools | Collapsed into skills (SKILL.md subsumes commands) |

## Day-to-day

### Add a skill

```bash
npx skills add <repo>#<skill>
cd ~/sources/claude-config
git add .agents/skills/<name> .agents/.skill-lock.json
git commit -m "skills: add <name>" && git push
```

### Add an MCP server

```bash
$EDITOR .agents/mcp/servers.json     # add entry under .mcpServers
.agents/mcp/generate.sh              # propagate to all 4 tools
```

### Add a Claude Code plugin

```bash
claude plugin install <name>@<marketplace>
echo "<name>@<marketplace>" >> .agents/plugins.txt
git add .agents/plugins.txt && git commit -m "plugins: add <name>" && git push
# Next session: SessionStart hook auto-bridges skills + agents to other tools
```

### Sync another machine

```bash
cd ~/sources/claude-config && git pull && ./setup.sh
```

## Repo layout

```
.
├── .agents/
│   ├── skills/              ← git-tracked skills (+ cc-* symlinks, gitignored)
│   ├── mcp/
│   │   ├── generate.sh      ← MCP → 4 tool configs (JSON + TOML)
│   │   └── servers.json     ← gitignored (API keys)
│   ├── plugins/
│   │   ├── flatten.sh       ← SessionStart hook: skills bridge + calls sync-agents
│   │   └── sync-agents.sh   ← agent format rewriter (OpenCode + Gemini)
│   ├── plugins.txt          ← declarative plugin manifest
│   ├── marketplaces.txt     ← declarative marketplace manifest
│   └── .skill-lock.json     ← npx skills lock file
├── .claude/                 ← Claude Code config (symlinked to ~/.claude)
│   ├── settings.json        ← hooks, permissions, enabled plugins
│   ├── CLAUDE.md            ← global instructions
│   ├── hooks/               ← notification scripts
│   ├── plugins/             ← plugin cache (gitignored), manifests (tracked)
│   └── skills → ../.agents/skills
├── .backups/                ← pre-change snapshots (gitignored)
├── setup.sh                 ← idempotent bootstrap
├── rollback.sh              ← tiered undo (--mcp, --flattener, --skills, --all)
├── sync.sh                  ← git push/pull helper
├── docs/
│   ├── forward.md           ← setup walk-through, recipes, troubleshooting
│   └── rollback.md          ← undo modes, independence verification, FAQ
└── README.md
```

## MCP generator

`generate.sh` reads one canonical `servers.json` and writes each tool's native format:

| Tool | Target | Format |
|---|---|---|
| Claude Code | `~/.claude.json` | `.mcpServers` (JSON) |
| Gemini CLI | `~/.gemini/settings.json` | `.mcpServers` (JSON) |
| OpenCode | `~/.config/opencode/opencode.json` | `.mcp` (JSON, reshaped) |
| Codex CLI | `~/.codex/config.toml` | `[mcp_servers.*]` (TOML) |

Handles both stdio (`command` + `args`) and HTTP (`url`) transports. Atomic writes with round-trip validation. Non-MCP keys preserved in every target.

Seed from existing Claude config: `.agents/mcp/generate.sh seed`

## Plugin bridge

A Claude Code **SessionStart hook** runs `flatten.sh` on every session:

1. **Skills**: directory-level symlinks from `~/.agents/skills/cc-<plugin>-<skill>` (+ `~/.codex/skills/cc-*` fallback) into the plugin cache. All 4 tools see them via the `.agents/skills/` convention.

2. **Agents**: `sync-agents.sh` copies plugin agent files with per-tool frontmatter rewrite — OpenCode gets `tools: {read: true, …}` (record), Gemini gets `tools: [read_file, …]` (array). Uses `<plugin>--<agent>.md` naming.

Self-healing: plugin updates change cache paths (version dirs). The next session re-creates all symlinks/copies and sweeps stale entries.

## Rollback

```bash
./rollback.sh --flattener   # remove plugin bridge symlinks + agent copies
./rollback.sh --mcp         # restore tool configs from .backups/
./rollback.sh --skills      # un-flip skill symlinks to real dirs
./rollback.sh --all         # everything above in safe order
```

Each mode restores from timestamped snapshots in `.backups/`. See [docs/rollback.md](docs/rollback.md) for per-mode walk-through and independence verification.

## What's NOT tracked

| Item | Why | How to restore |
|---|---|---|
| `servers.json` | API keys | `generate.sh seed` from `~/.claude.json` |
| `.backups/` | Machine-specific snapshots | Recreated by `setup.sh` |
| `cc-*` skill symlinks | Machine-specific paths | Recreated by `flatten.sh` |
| `*--*.md` agent copies | Machine-specific | Recreated by `sync-agents.sh` |
| Plugin cache | Re-downloadable | `setup.sh` reinstalls from `plugins.txt` |
| Credentials | Per-machine auth | `claude auth`, tool-specific login |
| Sessions, history, telemetry | Ephemeral | N/A |

## Credits

- [agentskills.io](https://agentskills.io) — cross-vendor `.agents/skills/` convention
- [vercel-labs/skills](https://github.com/vercel-labs/skills) — `npx skills` CLI for skill management
