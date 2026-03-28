# Claude Code Config

Portable Claude Code configuration synced via git. Covers user-level settings, agents, skills, commands, hooks, and plugins.

## New Machine Setup

```bash
git clone --recursive git@github.com:<your-user>/claude-config.git ~/sources/claude-config
cd ~/sources/claude-config
./setup.sh
```

Then authenticate: `claude` (opens browser).

## Day-to-Day Sync

```bash
# Push local changes to remote
./sync.sh push

# Pull latest from remote
./sync.sh pull

# Check what's changed
./sync.sh status
```

## What's Tracked

| Component | Path | Description |
|-----------|------|-------------|
| Settings | `.claude/settings.json` | Preferences, hooks config, enabled plugins |
| Instructions | `.claude/CLAUDE.md` | Global workflow rules |
| Commands | `.claude/commands/` | Custom slash commands |
| Agents | `.claude/_agents/` (submodule) | Custom agent definitions |
| PRPs | `.claude/PRPs-agentic-eng/` (submodule) | Agent engineering resources |
| Hooks | `.claude/hooks/` | Hook scripts |
| Plugin manifests | `.claude/plugins/*.json` | Installed plugins & marketplace list |
| GSD framework | `.claude/get-shit-done/` | GSD workflows, templates, references |
| Skill lock | `.agents/.skill-lock.json` | Installed skills registry |

## What's NOT Tracked (Machine-Specific)

- Credentials (`.credentials.json`) - authenticate per machine
- MCP servers (`~/.claude.json`) - configure per machine
- Sessions, history, caches, telemetry
- Plugin binaries (re-downloaded by `setup.sh`)
- Project-specific state (keyed by absolute filesystem path)

## MCP Servers

MCP servers live in `~/.claude.json` which is machine-specific. Configure on each machine:

```bash
claude mcp add <name> -- <command> [args...]
```

For project-level MCP servers, use `.mcp.json` in the project repo (committed to git).
