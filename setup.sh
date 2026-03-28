#!/usr/bin/env bash
set -euo pipefail

# Claude Code Config - Bootstrap Script
# Run this on a new machine after cloning the repo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR/.claude"

echo "=== Claude Code Config Setup ==="
echo "Repo: $SCRIPT_DIR"
echo ""

# --- Step 1: Create ~/.claude symlink ---
if [ -L "$HOME/.claude" ]; then
    CURRENT_TARGET="$(readlink "$HOME/.claude")"
    if [ "$CURRENT_TARGET" = "$CLAUDE_DIR" ]; then
        echo "[ok] ~/.claude already points to $CLAUDE_DIR"
    else
        echo "[!!] ~/.claude points to $CURRENT_TARGET (expected $CLAUDE_DIR)"
        echo "     Remove it manually and re-run: rm ~/.claude"
        exit 1
    fi
elif [ -d "$HOME/.claude" ]; then
    echo "[!!] ~/.claude is a real directory (not a symlink)."
    echo "     Back it up and remove it, then re-run:"
    echo "       mv ~/.claude ~/.claude.backup"
    echo "       $0"
    exit 1
else
    ln -s "$CLAUDE_DIR" "$HOME/.claude"
    echo "[ok] Created symlink: ~/.claude -> $CLAUDE_DIR"
fi

# --- Step 2: Initialize git submodules ---
echo ""
echo "--- Initializing submodules (_agents, PRPs) ---"
cd "$SCRIPT_DIR"
git submodule update --init --recursive
echo "[ok] Submodules initialized"

# --- Step 3: Set up ~/.agents/ (skills) ---
echo ""
echo "--- Setting up skills ---"
mkdir -p "$HOME/.agents"

if [ -f "$SCRIPT_DIR/.agents/.skill-lock.json" ]; then
    cp "$SCRIPT_DIR/.agents/.skill-lock.json" "$HOME/.agents/.skill-lock.json"
    echo "[ok] Copied .skill-lock.json to ~/.agents/"
fi

# Recreate the skills symlink (points from .claude/skills -> ~/.agents/skills)
if [ ! -e "$CLAUDE_DIR/skills" ]; then
    ln -s "$HOME/.agents/skills" "$CLAUDE_DIR/skills"
    echo "[ok] Created skills symlink"
else
    echo "[ok] Skills symlink already exists"
fi

# --- Step 4: Install plugin marketplaces ---
echo ""
echo "--- Installing plugin marketplaces ---"

MARKETPLACES=(
    "anthropics/claude-plugins-official"
    "obra/superpowers-marketplace"
    "glittercowboy/taches-cc-resources"
    "NeoLabHQ/context-engineering-kit"
    "dvdsgl/claude-canvas"
    "thedotmack/claude-mem"
    "kepano/obsidian-skills"
    "anthropics/skills"
    "wshobson/agents"
)

for repo in "${MARKETPLACES[@]}"; do
    echo "  Adding marketplace: $repo"
    claude plugin marketplace add "$repo" 2>/dev/null || echo "  [skip] $repo (may already exist or claude not available)"
done
echo "[ok] Marketplaces configured"

# --- Step 5: Install user-scope plugins ---
echo ""
echo "--- Installing user-scope plugins ---"

# Format: plugin@marketplace
USER_PLUGINS=(
    "code-simplifier@claude-plugins-official"
    "taches-cc-resources@taches-cc-resources"
    "frontend-design@claude-plugins-official"
    "github@claude-plugins-official"
    "feature-dev@claude-plugins-official"
    "code-review@claude-plugins-official"
    "commit-commands@claude-plugins-official"
    "playwright@claude-plugins-official"
    "canvas@claude-canvas"
    "claude-code-setup@claude-plugins-official"
    "claude-md-management@claude-plugins-official"
    "explanatory-output-style@claude-plugins-official"
    "obsidian@obsidian-skills"
    "skill-creator@claude-plugins-official"
    "pyright-lsp@claude-plugins-official"
    "pr-review-toolkit@claude-plugins-official"
)

for plugin in "${USER_PLUGINS[@]}"; do
    name="${plugin%%@*}"
    echo "  Installing: $name"
    claude plugin install "$name" 2>/dev/null || echo "  [skip] $name (may already exist or claude not available)"
done
echo "[ok] Plugins installed"

# --- Step 6: Create required directories ---
echo ""
echo "--- Creating runtime directories ---"
for dir in cache sessions session-env shell-snapshots paste-cache file-history \
           plans backups debug telemetry config todos tasks; do
    mkdir -p "$CLAUDE_DIR/$dir"
done
mkdir -p "$CLAUDE_DIR/plugins/cache" "$CLAUDE_DIR/plugins/marketplaces" "$CLAUDE_DIR/plugins/repos"
echo "[ok] Runtime directories created"

# --- Done ---
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Manual steps remaining:"
echo "  1. Run 'claude' to authenticate (opens browser)"
echo "  2. Configure MCP servers if needed:"
echo "     claude mcp add <server-name> -- <command>"
echo "  3. Verify: claude /help"
