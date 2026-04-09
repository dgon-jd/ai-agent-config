#!/usr/bin/env bash
#
# .agents/plugins/flatten.sh — bridge Claude Code plugin content to other tools
#
# Walks ~/.claude/plugins/installed_plugins.json, finds each installed
# plugin's bundled `skills/` and `agents/` subdirs, and creates
# `cc-<plugin-slug>-<name>` symlinks in the locations the other tools
# natively scan:
#
#     Content       Symlink location                         Consumers
#     ------------  ---------------------------------------- -------------------
#     Plugin skill  ~/.agents/skills/cc-<slug>-<name>        Claude/Codex/OpenCode/Gemini
#                   (directory symlink)                      (via .agents/skills/ alias)
#     Plugin agent  ~/.config/opencode/agents/cc-*.md        OpenCode only
#                   ~/.gemini/agents/cc-*.md                 Gemini only
#
# Codex has no agent-roster concept, so plugin agents don't reach it.
# Skills reach all four tools via the `.agents/skills/` cross-vendor convention.
#
# Symlink targets are absolute paths into the plugin cache (version-pathed).
# This means:
#   - They're machine-specific → must be gitignored (.agents/skills/cc-*/)
#   - They break on plugin updates → the script also sweeps and removes
#     stale `cc-*` entries whose targets no longer exist, and is designed
#     to run from a Claude Code SessionStart hook to self-heal.
#
# The script is idempotent: re-running it produces the same symlink set.
# Only broken or missing links are touched; existing correct links are
# left alone.

set -euo pipefail

PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"
SKILLS_DIR="$HOME/.agents/skills"
OPENCODE_AGENTS="$HOME/.config/opencode/agents"
GEMINI_AGENTS="$HOME/.gemini/agents"

if [ ! -f "$PLUGINS_JSON" ]; then
    echo "[skip] $PLUGINS_JSON not found — no plugins to flatten"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "[!!] jq required but not found" >&2
    exit 1
fi

mkdir -p "$SKILLS_DIR" "$OPENCODE_AGENTS" "$GEMINI_AGENTS"

# ----------------------------------------------------------------------
# Collect target → source pairs
# ----------------------------------------------------------------------

# We can't use bash associative arrays across function boundaries cleanly,
# so collect wanted-link pairs as newline-delimited records in temp files.
# Each line: <link-path>\t<source-path>
wanted_skills=$(mktemp)
wanted_opencode_agents=$(mktemp)
wanted_gemini_agents=$(mktemp)
trap 'rm -f "$wanted_skills" "$wanted_opencode_agents" "$wanted_gemini_agents"' EXIT

skills_added=0
agents_added=0
collisions=0

# Use the latest-installed version of each plugin (last entry in the array).
while IFS=$'\t' read -r plugin install_path; do
    # Skip if the install path doesn't exist (plugin was removed mid-update)
    [ -d "$install_path" ] || continue

    # plugin slug: "developer-essentials@claude-code-workflows" → "developer-essentials"
    plugin_slug="${plugin%%@*}"

    # --- Skills: directory-level symlink ---
    if [ -d "$install_path/skills" ]; then
        for skill_dir in "$install_path/skills"/*/; do
            [ -d "$skill_dir" ] || continue
            [ -f "${skill_dir}SKILL.md" ] || continue
            skill_name="$(basename "$skill_dir")"
            link="$SKILLS_DIR/cc-${plugin_slug}-${skill_name}"
            # Remove trailing slash from source for cleaner readlink output
            src="${skill_dir%/}"
            printf '%s\t%s\n' "$link" "$src" >> "$wanted_skills"
            skills_added=$((skills_added + 1))
        done
    fi

    # --- Agents: per-file symlinks ---
    if [ -d "$install_path/agents" ]; then
        for agent_file in "$install_path/agents"/*.md; do
            [ -f "$agent_file" ] || continue
            agent_name="$(basename "$agent_file" .md)"
            base="cc-${plugin_slug}-${agent_name}.md"
            printf '%s\t%s\n' "$OPENCODE_AGENTS/$base" "$agent_file" >> "$wanted_opencode_agents"
            printf '%s\t%s\n' "$GEMINI_AGENTS/$base" "$agent_file" >> "$wanted_gemini_agents"
            agents_added=$((agents_added + 1))
        done
    fi
done < <(jq -r '.plugins | to_entries[] | .key as $k | .value[-1] | [$k, .installPath] | @tsv' "$PLUGINS_JSON")

# ----------------------------------------------------------------------
# Sync symlinks: create/refresh wanted links, remove stale cc-* entries
# ----------------------------------------------------------------------

# sync_links <wanted-file> <parent-dir> <link-pattern>
#   Creates or refreshes every link listed in wanted-file, then removes
#   any cc-* entry in parent-dir that's not in the wanted list.
sync_links() {
    local wanted="$1" parent="$2" pattern="$3"

    # Collision detection: if the same link path appears twice in wanted,
    # the second one wins. Warn.
    if [ -s "$wanted" ]; then
        local dupes
        dupes=$(cut -f1 "$wanted" | sort | uniq -d)
        if [ -n "$dupes" ]; then
            echo "[warn] symlink collisions in $parent:" >&2
            echo "$dupes" | sed 's|^|       |' >&2
            collisions=$((collisions + $(echo "$dupes" | wc -l)))
        fi
    fi

    # Create/refresh
    while IFS=$'\t' read -r link src; do
        [ -z "$link" ] && continue
        if [ "$(readlink "$link" 2>/dev/null || true)" != "$src" ]; then
            ln -sfn "$src" "$link"
        fi
    done < "$wanted"

    # Sweep stale cc-* entries. We only own entries matching cc-* — leave
    # everything else alone.
    if [ -d "$parent" ]; then
        shopt -s nullglob
        for existing in "$parent"/$pattern; do
            [ -L "$existing" ] || continue
            # Is this link in the wanted list?
            if ! grep -qF "$(printf '%s\t' "$existing")" "$wanted" 2>/dev/null; then
                rm -f "$existing"
            fi
        done
        shopt -u nullglob
    fi
}

sync_links "$wanted_skills"         "$SKILLS_DIR"      'cc-*'
sync_links "$wanted_opencode_agents" "$OPENCODE_AGENTS" 'cc-*.md'
sync_links "$wanted_gemini_agents"   "$GEMINI_AGENTS"   'cc-*.md'

echo "[ok] flatten.sh: ${skills_added} plugin skills → ~/.agents/skills/cc-*"
echo "[ok] flatten.sh: ${agents_added} plugin agents → {opencode,gemini}/agents/cc-*.md"
[ "$collisions" -gt 0 ] && echo "[warn] $collisions symlink collisions (see above)"
exit 0
