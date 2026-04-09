#!/usr/bin/env bash
set -euo pipefail

# Claude Code Config - Bootstrap Script
# Run this on a new machine after cloning the repo.
#
# Extended for the cross-tool overhaul (rosy-brewing-bee): shares
# skills via ~/.agents/skills across Claude Code, Codex, OpenCode,
# and Gemini CLI. See docs/forward.md for the full walk-through.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR/.claude"
AGENTS_DIR="$SCRIPT_DIR/.agents"

echo "=== Claude Code Config Setup ==="
echo "Repo: $SCRIPT_DIR"
echo ""

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

# snapshot_config: copy every file we might mutate into a timestamped
# backup dir under $SCRIPT_DIR/.backups/<ISO>/. Writes the path to
# .backups/.latest so rollback.sh can find the most recent snapshot.
# No-op on re-runs within the same second — but a fresh timestamped dir
# is created each invocation otherwise, so you accumulate history.
snapshot_config() {
    local ts backup_dir
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    backup_dir="$SCRIPT_DIR/.backups/$ts"
    mkdir -p "$backup_dir"

    # Silently skip files that don't exist yet (e.g. fresh machine
    # that hasn't launched a given tool). `|| true` keeps `set -e`
    # happy while still propagating real cp errors via stderr.
    cp "$HOME/.claude.json"                     "$backup_dir/claude.json"            2>/dev/null || true
    cp "$HOME/.codex/config.toml"               "$backup_dir/codex-config.toml"      2>/dev/null || true
    cp "$HOME/.config/opencode/opencode.json"   "$backup_dir/opencode.json"          2>/dev/null || true
    cp "$HOME/.gemini/settings.json"            "$backup_dir/gemini-settings.json"   2>/dev/null || true
    cp "$CLAUDE_DIR/settings.json"              "$backup_dir/claude-settings.json"   2>/dev/null || true
    cp "$HOME/.agents/.skill-lock.json"         "$backup_dir/agents-skill-lock.json" 2>/dev/null || true

    echo "$backup_dir" > "$SCRIPT_DIR/.backups/.latest"
    echo "[ok] Config snapshot: $backup_dir"
}

# link_or_warn <target> <source>: ensure <target> is a symlink pointing at <source>.
# - already correct → no-op
# - symlink elsewhere → error + exit (user must resolve manually)
# - real file/dir → rename to .pre-migration + create symlink
# - missing → create symlink
link_or_warn() {
    local target="$1" source="$2"
    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" = "$source" ]; then
            echo "[ok] $target already → $source"
            return 0
        else
            echo "[!!] $target is a symlink to $(readlink "$target") (expected $source)"
            echo "     Fix manually: rm '$target' && re-run $0"
            return 1
        fi
    elif [ -e "$target" ]; then
        echo "[mv] $target is a real file/dir — moving to ${target}.pre-migration"
        mv "$target" "${target}.pre-migration"
        ln -s "$source" "$target"
        echo "[ok] Created symlink: $target -> $source"
    else
        ln -s "$source" "$target"
        echo "[ok] Created symlink: $target -> $source"
    fi
}

# ----------------------------------------------------------------------
# Step 1: Create ~/.claude symlink
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# Step 2: Initialize git submodules (legacy _agents + PRPs)
# ----------------------------------------------------------------------
echo ""
echo "--- Initializing submodules (_agents, PRPs) ---"
cd "$SCRIPT_DIR"
git submodule update --init --recursive
echo "[ok] Submodules initialized"

# ----------------------------------------------------------------------
# Step 3: Pre-change snapshot
# ----------------------------------------------------------------------
echo ""
echo "--- Taking pre-change config snapshot ---"
snapshot_config

# ----------------------------------------------------------------------
# Step 3b: Skill consolidation
#   - $REPO/.agents/skills/ becomes the canonical skill tree
#   - ~/.agents/skills → $REPO/.agents/skills (symlink)
#   - ~/.agents/.skill-lock.json → $REPO/.agents/.skill-lock.json (symlink)
#   - ~/.claude/skills → ../.agents/skills (relative, portable)
# ----------------------------------------------------------------------
echo ""
echo "--- Skill consolidation ---"
mkdir -p "$HOME/.agents"
mkdir -p "$AGENTS_DIR/skills"

# 3b.1: ~/.agents/skills → $AGENTS_DIR/skills
if [ -L "$HOME/.agents/skills" ]; then
    if [ "$(readlink "$HOME/.agents/skills")" = "$AGENTS_DIR/skills" ]; then
        echo "[ok] ~/.agents/skills already → $AGENTS_DIR/skills"
    else
        echo "[!!] ~/.agents/skills is a symlink to $(readlink "$HOME/.agents/skills") (expected $AGENTS_DIR/skills)"
        echo "     Fix manually: rm ~/.agents/skills && re-run $0"
        exit 1
    fi
elif [ -d "$HOME/.agents/skills" ]; then
    # Real dir — migrate content into repo, then flip to symlink.
    echo "[mv] ~/.agents/skills is a real dir — rsyncing into $AGENTS_DIR/skills"
    rsync -a "$HOME/.agents/skills/" "$AGENTS_DIR/skills/"
    if diff -rq "$HOME/.agents/skills/" "$AGENTS_DIR/skills/" > /dev/null 2>&1; then
        mv "$HOME/.agents/skills" "$HOME/.agents/skills.pre-migration"
        ln -s "$AGENTS_DIR/skills" "$HOME/.agents/skills"
        echo "[ok] Migrated skills into repo; old dir kept as ~/.agents/skills.pre-migration"
    else
        echo "[!!] diff mismatch between ~/.agents/skills and $AGENTS_DIR/skills — aborting"
        exit 1
    fi
else
    ln -s "$AGENTS_DIR/skills" "$HOME/.agents/skills"
    echo "[ok] Created symlink: ~/.agents/skills -> $AGENTS_DIR/skills"
fi

# 3b.2: ~/.agents/.skill-lock.json → $AGENTS_DIR/.skill-lock.json
if [ -L "$HOME/.agents/.skill-lock.json" ]; then
    if [ "$(readlink "$HOME/.agents/.skill-lock.json")" = "$AGENTS_DIR/.skill-lock.json" ]; then
        echo "[ok] ~/.agents/.skill-lock.json already → repo"
    fi
elif [ -f "$HOME/.agents/.skill-lock.json" ]; then
    # Detect drift between local copy and repo before flipping to symlink.
    # If local is newer or different, overwrite repo first so we don't lose
    # recent skill installs that haven't been committed yet.
    if [ -f "$AGENTS_DIR/.skill-lock.json" ] && \
       ! cmp -s "$HOME/.agents/.skill-lock.json" "$AGENTS_DIR/.skill-lock.json"; then
        echo "[warn] local .skill-lock.json differs from repo — copying local into repo"
        cp "$HOME/.agents/.skill-lock.json" "$AGENTS_DIR/.skill-lock.json"
        echo "       review with: git -C $SCRIPT_DIR diff .agents/.skill-lock.json"
    elif [ ! -f "$AGENTS_DIR/.skill-lock.json" ]; then
        cp "$HOME/.agents/.skill-lock.json" "$AGENTS_DIR/.skill-lock.json"
    fi
    rm "$HOME/.agents/.skill-lock.json"
    ln -s "$AGENTS_DIR/.skill-lock.json" "$HOME/.agents/.skill-lock.json"
    echo "[ok] Flipped ~/.agents/.skill-lock.json to symlink"
elif [ -f "$AGENTS_DIR/.skill-lock.json" ]; then
    ln -s "$AGENTS_DIR/.skill-lock.json" "$HOME/.agents/.skill-lock.json"
    echo "[ok] Created symlink: ~/.agents/.skill-lock.json -> repo"
fi

# 3b.3: $CLAUDE_DIR/skills → ../.agents/skills (relative, portable)
#
# Any pre-existing absolute-path symlink (e.g. → ~/.agents/skills) gets
# replaced with a relative link inside the repo so the tree is portable
# across machines and git-trackable.
if [ -L "$CLAUDE_DIR/skills" ]; then
    current="$(readlink "$CLAUDE_DIR/skills")"
    if [ "$current" = "../.agents/skills" ]; then
        echo "[ok] $CLAUDE_DIR/skills already → ../.agents/skills"
    else
        echo "[mv] $CLAUDE_DIR/skills → $current — repointing to ../.agents/skills"
        rm "$CLAUDE_DIR/skills"
        (cd "$CLAUDE_DIR" && ln -s ../.agents/skills skills)
    fi
elif [ ! -e "$CLAUDE_DIR/skills" ]; then
    (cd "$CLAUDE_DIR" && ln -s ../.agents/skills skills)
    echo "[ok] Created $CLAUDE_DIR/skills -> ../.agents/skills"
fi

# ----------------------------------------------------------------------
# Step 3c: Warn about unmigrated .claude/commands/*.md
#
# The cross-tool overhaul collapses custom commands into skills (one
# canonical format that all four tools can load). If old-style command
# files still exist in .claude/commands/, flag them for manual
# migration. Plugin-managed subdirs like gsd/ are left alone.
# ----------------------------------------------------------------------
echo ""
echo "--- Checking for unmigrated commands ---"
if [ -d "$CLAUDE_DIR/commands" ]; then
    stale=$(find "$CLAUDE_DIR/commands" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
    if [ -n "$stale" ]; then
        echo "[warn] Old-style custom commands still exist under .claude/commands/:"
        echo "$stale" | sed 's|^|       |'
        echo "       Consider migrating them to .agents/skills/<name>/SKILL.md"
        echo "       (see docs/forward.md § Command → skill migration)"
    else
        echo "[ok] No stale command files in .claude/commands/"
    fi
fi

# ----------------------------------------------------------------------
# Step 4: Install plugin marketplaces (Claude Code only)
# ----------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
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
        claude plugin marketplace add "$repo" 2>/dev/null || echo "  [skip] $repo (may already exist)"
    done
    echo "[ok] Marketplaces configured"

    # ------------------------------------------------------------------
    # Step 5: Install user-scope plugins
    # ------------------------------------------------------------------
    echo ""
    echo "--- Installing user-scope plugins ---"

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
        claude plugin install "$name" 2>/dev/null || echo "  [skip] $name (may already exist)"
    done
    echo "[ok] Plugins installed"
else
    echo ""
    echo "[skip] claude CLI not installed — skipping marketplace & plugin install"
fi

# ----------------------------------------------------------------------
# Step 6: Create runtime directories
# ----------------------------------------------------------------------
echo ""
echo "--- Creating runtime directories ---"
for dir in cache sessions session-env shell-snapshots paste-cache file-history \
           plans backups debug telemetry config todos tasks; do
    mkdir -p "$CLAUDE_DIR/$dir"
done
mkdir -p "$CLAUDE_DIR/plugins/cache" "$CLAUDE_DIR/plugins/marketplaces" "$CLAUDE_DIR/plugins/repos"
echo "[ok] Runtime directories created"

# ----------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Manual steps remaining:"
echo "  1. Run 'claude' to authenticate (opens browser)"
echo "  2. MCP setup is handled by .agents/mcp/generate.sh (coming in Phase 2)"
echo "  3. Verify: claude /help"
