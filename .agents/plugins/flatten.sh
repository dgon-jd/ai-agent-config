#!/usr/bin/env bash
#
# .agents/plugins/flatten.sh — bridge Claude Code plugin skills to other tools
#
# Walks ~/.claude/plugins/installed_plugins.json, finds each installed
# plugin's bundled `skills/` subdir, and creates directory-level
# `cc-<plugin-slug>-<skill>` symlinks into the locations the other tools
# natively scan for skills:
#
#     Symlink location                   Consumers
#     ---------------------------------- --------------------------------
#     ~/.agents/skills/cc-<slug>-<name>  Claude / OpenCode / Gemini / (Codex)
#                                        via the .agents/skills/ vendor-
#                                        neutral convention (agentskills.io)
#     ~/.codex/skills/cc-<slug>-<name>   Codex, as a defensive fallback
#                                        since codex-cli 0.118.0 may not
#                                        walk ~/.agents/skills/ reliably
#
# Symlink targets are absolute paths into the plugin cache (version-pathed).
# That means:
#   - They're machine-specific → must be gitignored (.agents/skills/cc-*/)
#   - They break on plugin updates → this script also sweeps stale cc-*
#     entries whose targets no longer exist. It re-runs as a Claude Code
#     SessionStart hook so plugin-update churn self-heals.
#
# The script is idempotent: re-running produces the same symlink set.
# Only missing or broken links are touched; existing correct links are
# left alone.
#
# ## Why we DON'T bridge plugin agents anymore
#
# Previous versions of this script also created per-file cc-*.md symlinks
# in ~/.config/opencode/agents/ and ~/.gemini/agents/ pointing at plugin
# agents/*.md files. This broke OpenCode hard:
#
#     Configuration is invalid at ~/.config/opencode/agents/cc-feature-dev-code-architect.md
#     ↳ Invalid input: expected record, received string tools
#     ↳ Invalid hex color format color
#
# Claude plugin agent frontmatter uses formats OpenCode and Gemini don't
# understand: `tools: Glob, Grep, LS, …` as a comma-separated string (vs
# OpenCode's record `{glob: true, grep: true}`) and `color: green` as a
# named color (vs hex `#22c55e`). Since symlinks can't rewrite the
# target's frontmatter, the two formats are fundamentally incompatible.
#
# Plugin skills, by contrast, only need `name` + `description` in their
# SKILL.md frontmatter, which IS a cross-vendor standard. Plugin skills
# bridge cleanly; plugin agents don't. Codex has no agent-roster concept
# at all, so it was always excluded from the agent bridge.
#
# If you want plugin agent functionality in OpenCode or Gemini, author
# a tool-native agent in their own config directory. The agents/ dirs
# in each tool are still per-tool and untouched by this bridge.

set -euo pipefail

PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"
AGENTS_SKILLS="$HOME/.agents/skills"
CODEX_SKILLS="$HOME/.codex/skills"

if [ ! -f "$PLUGINS_JSON" ]; then
    echo "[skip] $PLUGINS_JSON not found — no plugins to flatten"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "[!!] jq required but not found" >&2
    exit 1
fi

mkdir -p "$AGENTS_SKILLS"
# Codex skills dir exists only if codex has been launched at least once;
# skip creating it so we don't materialize a codex config tree on machines
# without codex installed. Instead we check for existence before writing.
CODEX_ENABLED=0
[ -d "$HOME/.codex" ] && { mkdir -p "$CODEX_SKILLS"; CODEX_ENABLED=1; }

# ----------------------------------------------------------------------
# Collect wanted target → source pairs
# ----------------------------------------------------------------------

wanted_agents_skills=$(mktemp)
wanted_codex_skills=$(mktemp)
trap 'rm -f "$wanted_agents_skills" "$wanted_codex_skills"' EXIT

skills_added=0
collisions=0

# Use the latest-installed version of each plugin (last entry in the array).
while IFS=$'\t' read -r plugin install_path; do
    [ -d "$install_path" ] || continue

    # plugin slug: "developer-essentials@claude-code-workflows" → "developer-essentials"
    plugin_slug="${plugin%%@*}"

    # Skills: directory-level symlinks
    if [ -d "$install_path/skills" ]; then
        for skill_dir in "$install_path/skills"/*/; do
            [ -d "$skill_dir" ] || continue
            [ -f "${skill_dir}SKILL.md" ] || continue
            skill_name="$(basename "$skill_dir")"
            base="cc-${plugin_slug}-${skill_name}"
            src="${skill_dir%/}"

            printf '%s\t%s\n' "$AGENTS_SKILLS/$base" "$src" >> "$wanted_agents_skills"
            if [ "$CODEX_ENABLED" -eq 1 ]; then
                printf '%s\t%s\n' "$CODEX_SKILLS/$base" "$src" >> "$wanted_codex_skills"
            fi
            skills_added=$((skills_added + 1))
        done
    fi
done < <(jq -r '.plugins | to_entries[] | .key as $k | .value[-1] | [$k, .installPath] | @tsv' "$PLUGINS_JSON")

# ----------------------------------------------------------------------
# Sync symlinks
# ----------------------------------------------------------------------

# sync_links <wanted-file> <parent-dir> <glob-pattern>
sync_links() {
    local wanted="$1" parent="$2" pattern="$3"

    # Collision detection: same link path listed twice
    if [ -s "$wanted" ]; then
        local dupes
        dupes=$(cut -f1 "$wanted" | sort | uniq -d)
        if [ -n "$dupes" ]; then
            echo "[warn] symlink collisions in $parent:" >&2
            echo "$dupes" | sed 's|^|       |' >&2
            collisions=$((collisions + $(echo "$dupes" | wc -l)))
        fi
    fi

    # Create or refresh wanted links
    while IFS=$'\t' read -r link src; do
        [ -z "$link" ] && continue
        if [ "$(readlink "$link" 2>/dev/null || true)" != "$src" ]; then
            ln -sfn "$src" "$link"
        fi
    done < "$wanted"

    # Sweep stale cc-* entries. We only own entries matching the pattern —
    # leave everything else alone.
    if [ -d "$parent" ]; then
        shopt -s nullglob
        for existing in "$parent"/$pattern; do
            [ -L "$existing" ] || continue
            if ! grep -qF "$(printf '%s\t' "$existing")" "$wanted" 2>/dev/null; then
                rm -f "$existing"
            fi
        done
        shopt -u nullglob
    fi
}

sync_links "$wanted_agents_skills" "$AGENTS_SKILLS" 'cc-*'
if [ "$CODEX_ENABLED" -eq 1 ]; then
    sync_links "$wanted_codex_skills" "$CODEX_SKILLS" 'cc-*'
fi

echo "[ok] flatten.sh: ${skills_added} plugin skills → ~/.agents/skills/cc-*"
if [ "$CODEX_ENABLED" -eq 1 ]; then
    echo "[ok] flatten.sh: ${skills_added} plugin skills → ~/.codex/skills/cc-* (defensive fallback)"
fi
[ "$collisions" -gt 0 ] && echo "[warn] $collisions symlink collisions (see above)"

# ----------------------------------------------------------------------
# Also run sync-agents.sh to bridge plugin agents (with frontmatter
# rewriting) to OpenCode and Gemini. This is a separate script because
# agents need per-tool format transformation — unlike skills which use
# the portable SKILL.md standard and can be symlinked as-is.
# ----------------------------------------------------------------------
SYNC_AGENTS="$(dirname "$0")/sync-agents.sh"
if [ -x "$SYNC_AGENTS" ]; then
    "$SYNC_AGENTS"
fi

exit 0
