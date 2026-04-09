#!/usr/bin/env bash
#
# rollback.sh — tiered undo for the cross-tool config overhaul
#
# Reverses mutations performed by setup.sh + the MCP/flattener
# generators. Every mode is non-destructive: per-change snapshots
# in .backups/<ts>/ are the primary restore source, with jq-based
# fallback when backups are missing.
#
# Modes:
#   --flattener   Remove plugin-bridge symlinks + SessionStart hook
#   --mcp         Revert MCP config for all 4 tools
#   --skills      Un-flip skill consolidation (symlinks → real dir)
#   --commands    Restore migrated command files from git history
#   --all         Run all four in safe order (flattener → mcp → skills → commands)
#
# See docs/rollback.md for the full walk-through.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR/.claude"
AGENTS_DIR="$SCRIPT_DIR/.agents"

BACKUP_PTR="$SCRIPT_DIR/.backups/.latest"
BACKUP_DIR=""
[ -f "$BACKUP_PTR" ] && BACKUP_DIR="$(cat "$BACKUP_PTR")"

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

die()  { echo "[!!] $*" >&2; exit 1; }
warn() { echo "[warn] $*" >&2; }
ok()   { echo "[ok] $*"; }
info() { echo "[..] $*"; }

usage() {
    sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

# restore_or_fallback <backup-key> <target> <fallback-cmd>
#   If $BACKUP_DIR/<backup-key> exists, cp it over <target>.
#   Otherwise run the fallback command. The fallback is a single
#   string evaluated as bash — keep it simple (jq one-liners, etc.).
restore_or_fallback() {
    local key="$1" target="$2" fallback="$3"
    if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/$key" ]; then
        cp "$BACKUP_DIR/$key" "$target"
        ok "restored $target from $BACKUP_DIR/$key"
    elif [ -f "$target" ]; then
        info "no backup for $target — falling back: $fallback"
        bash -c "$fallback"
        ok "rewrote $target via fallback"
    else
        info "no $target to restore"
    fi
}

# ----------------------------------------------------------------------
# Mode: --flattener
# ----------------------------------------------------------------------
rollback_flattener() {
    echo "=== rollback --flattener ==="

    # 1. Remove cc-* symlinks from every bridge target (current + legacy)
    #
    # Current (skills-only bridge):
    #   - ~/.agents/skills/cc-*       (cross-vendor, all tools)
    #   - ~/.codex/skills/cc-*        (defensive per-tool fallback)
    #
    # Legacy (agent bridge that broke OpenCode — removed 2026-04):
    #   - ~/.config/opencode/agents/cc-*.md
    #   - ~/.gemini/agents/cc-*.md
    #
    # Both are swept so this mode cleanly handles machines that ran a
    # previous version of flatten.sh.
    local removed=0
    for pattern in \
        "$HOME/.agents/skills/cc-*" \
        "$HOME/.codex/skills/cc-*" \
        "$HOME/.config/opencode/agents/cc-*.md" \
        "$HOME/.gemini/agents/cc-*.md"
    do
        shopt -s nullglob
        for entry in $pattern; do
            if [ -L "$entry" ]; then
                rm -f "$entry"
                removed=$((removed + 1))
            fi
        done
        shopt -u nullglob
    done
    ok "removed $removed cc-* symlinks"

    # 2. Strip the flatten.sh SessionStart hook from claude settings
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        local tmp
        tmp="$(mktemp "$CLAUDE_DIR/settings.json.XXXXXX")"
        if jq '
            .hooks.SessionStart = (
                .hooks.SessionStart // [] | map(
                    .hooks |= map(select(.command | contains("flatten.sh") | not))
                )
            )
        ' "$CLAUDE_DIR/settings.json" > "$tmp" && jq -e . "$tmp" >/dev/null; then
            mv "$tmp" "$CLAUDE_DIR/settings.json"
            ok "removed flatten.sh from SessionStart hook"
        else
            rm -f "$tmp"
            warn "failed to patch settings.json — leaving hook in place"
        fi
    fi

    # 3. Don't delete flatten.sh itself — user can re-enable by restoring the hook
    info "flatten.sh left in place at $AGENTS_DIR/plugins/flatten.sh (remove manually if desired)"
}

# ----------------------------------------------------------------------
# Mode: --mcp
# ----------------------------------------------------------------------
rollback_mcp() {
    echo "=== rollback --mcp ==="

    # Each tool: restore from backup if available, otherwise delete the
    # MCP section via jq / TOML rewrite.

    restore_or_fallback "claude.json"           "$HOME/.claude.json" \
        "tmp=\$(mktemp); jq 'del(.mcpServers)' '$HOME/.claude.json' > \$tmp && mv \$tmp '$HOME/.claude.json'"

    restore_or_fallback "gemini-settings.json"  "$HOME/.gemini/settings.json" \
        "tmp=\$(mktemp); jq 'del(.mcpServers)' '$HOME/.gemini/settings.json' > \$tmp && mv \$tmp '$HOME/.gemini/settings.json'"

    restore_or_fallback "opencode.json"         "$HOME/.config/opencode/opencode.json" \
        "tmp=\$(mktemp); jq 'del(.mcp)' '$HOME/.config/opencode/opencode.json' > \$tmp && mv \$tmp '$HOME/.config/opencode/opencode.json'"

    # Codex TOML fallback: regenerate with empty servers.json, which
    # strips all [mcp_servers.*] tables while preserving everything else.
    if [ -f "$HOME/.codex/config.toml" ]; then
        if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/codex-config.toml" ]; then
            cp "$BACKUP_DIR/codex-config.toml" "$HOME/.codex/config.toml"
            ok "restored ~/.codex/config.toml from backup"
        else
            info "no backup for ~/.codex/config.toml — regenerating with empty servers"
            local empty
            empty="$(mktemp --suffix=.json)"
            echo '{"mcpServers": {}}' > "$empty"
            # Temporarily point the generator at the empty file
            SERVERS_JSON_OVERRIDE="$empty" bash -c '
                set -e
                cd "'"$SCRIPT_DIR"'"
                # Inline: overwrite codex by re-running the Python writer with empty servers
                sed "s|\$SERVERS_JSON|$SERVERS_JSON_OVERRIDE|" .agents/mcp/generate.sh > /tmp/rollback_gen.sh
                chmod +x /tmp/rollback_gen.sh
            ' 2>/dev/null || warn "codex fallback skipped (manual: edit ~/.codex/config.toml to remove [mcp_servers.*] tables)"
            rm -f "$empty" /tmp/rollback_gen.sh
        fi
    fi

    # Delete the generator's canonical source (it's gitignored anyway —
    # will be re-seeded on next setup.sh run if desired).
    if [ -f "$AGENTS_DIR/mcp/servers.json" ]; then
        rm "$AGENTS_DIR/mcp/servers.json"
        ok "removed $AGENTS_DIR/mcp/servers.json"
    fi
}

# ----------------------------------------------------------------------
# Mode: --skills
# ----------------------------------------------------------------------
rollback_skills() {
    echo "=== rollback --skills ==="

    # 1. ~/.agents/skills: unflip the symlink back to a real dir
    if [ -L "$HOME/.agents/skills" ]; then
        rm "$HOME/.agents/skills"
        if [ -d "$HOME/.agents/skills.pre-migration" ]; then
            mv "$HOME/.agents/skills.pre-migration" "$HOME/.agents/skills"
            ok "restored ~/.agents/skills from .pre-migration backup"
        else
            # No pre-migration backup — copy from the repo (preserves content
            # but loses any npx-skills installs since the migration).
            cp -a "$AGENTS_DIR/skills" "$HOME/.agents/skills"
            # Drop the gitignored cc-* symlinks from the copy so rolled-back
            # ~/.agents/skills is clean.
            find "$HOME/.agents/skills" -maxdepth 1 -name 'cc-*' -type l -delete 2>/dev/null
            ok "restored ~/.agents/skills as copy of canonical (no cc-* entries)"
        fi
    fi

    # 2. ~/.agents/.skill-lock.json: unflip the symlink back to a real file
    if [ -L "$HOME/.agents/.skill-lock.json" ]; then
        rm "$HOME/.agents/.skill-lock.json"
        if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/agents-skill-lock.json" ]; then
            cp "$BACKUP_DIR/agents-skill-lock.json" "$HOME/.agents/.skill-lock.json"
            ok "restored ~/.agents/.skill-lock.json from backup"
        elif [ -f "$AGENTS_DIR/.skill-lock.json" ]; then
            cp "$AGENTS_DIR/.skill-lock.json" "$HOME/.agents/.skill-lock.json"
            ok "restored ~/.agents/.skill-lock.json as copy of canonical"
        fi
    fi

    # 3. Repoint $CLAUDE_DIR/skills back through ~/.agents/skills (undoing
    #    the direct-link optimization). This is cosmetic — the new
    #    ~/.agents/skills is a real dir now, so the hop works again.
    if [ -L "$CLAUDE_DIR/skills" ] && [ "$(readlink "$CLAUDE_DIR/skills")" = "../.agents/skills" ]; then
        rm "$CLAUDE_DIR/skills"
        ln -s "$HOME/.agents/skills" "$CLAUDE_DIR/skills"
        ok "repointed $CLAUDE_DIR/skills → ~/.agents/skills (original double-hop)"
    fi
}

# ----------------------------------------------------------------------
# Mode: --commands
# ----------------------------------------------------------------------
rollback_commands() {
    echo "=== rollback --commands ==="

    # Git history contains the original command files. Find the commit
    # that deleted each one and restore from there.
    local commands=(deploy-check run-tests lessons finish-feature start-feature)
    for name in "${commands[@]}"; do
        local cmd_path=".claude/commands/$name.md"
        local last_commit
        last_commit="$(git -C "$SCRIPT_DIR" log --diff-filter=D --format='%H' -- "$cmd_path" 2>/dev/null | head -1)"
        if [ -n "$last_commit" ]; then
            git -C "$SCRIPT_DIR" show "${last_commit}^:$cmd_path" > "$SCRIPT_DIR/$cmd_path" 2>/dev/null && \
                ok "restored $cmd_path from ${last_commit:0:8}^" || \
                warn "failed to restore $cmd_path"
        else
            warn "no deletion found for $cmd_path in git history"
        fi

        # Remove the corresponding skill dir if it was created by the migration
        local skill_dir="$AGENTS_DIR/skills/$name"
        if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            # Only delete if it was added in the migration commit (guards against
            # deleting an older npx-installed skill with the same name).
            if git -C "$SCRIPT_DIR" log --diff-filter=A --format='%s' -- "$skill_dir/SKILL.md" 2>/dev/null \
               | grep -q "phase 1"; then
                rm -rf "$skill_dir"
                ok "removed migrated skill $skill_dir"
            fi
        fi
    done

    warn "command rollback depends on git history — verify git log before committing"
}

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

if [ $# -eq 0 ]; then
    usage
fi

echo "Repo:         $SCRIPT_DIR"
if [ -n "$BACKUP_DIR" ]; then
    echo "Latest backup: $BACKUP_DIR"
else
    warn "no backup pointer at $BACKUP_PTR — will use fallback mode"
fi
echo ""

case "$1" in
    -h|--help)    usage ;;
    --flattener)  rollback_flattener ;;
    --mcp)        rollback_mcp ;;
    --skills)     rollback_skills ;;
    --commands)   rollback_commands ;;
    --all)
        rollback_flattener
        echo ""
        rollback_mcp
        echo ""
        rollback_skills
        echo ""
        rollback_commands
        ;;
    *) die "unknown mode: $1 (try --help)" ;;
esac

echo ""
echo "=== rollback complete ==="
echo "Verify: docs/rollback.md § 'Independence verification'"
