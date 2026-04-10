#!/usr/bin/env bash
set -euo pipefail

# Sync Claude Code plugin agents to OpenCode and Gemini agent directories.
# Translates frontmatter format per tool. Skips gsd-* agents (managed separately).
# Safe to re-run — overwrites previously synced files, never touches gsd-* files.

CLAUDE_PLUGIN_CACHE="$HOME/.claude/plugins/cache"
OPENCODE_AGENTS="$HOME/.config/opencode/agents"
GEMINI_AGENTS="$HOME/.gemini/agents"

mkdir -p "$OPENCODE_AGENTS" "$GEMINI_AGENTS"

# Clean previously synced plugin agents (contain "--" separator, not gsd-*)
find "$OPENCODE_AGENTS" -name "*--*.md" -delete 2>/dev/null || true
find "$GEMINI_AGENTS" -name "*--*.md" -delete 2>/dev/null || true

synced=0

# Find all plugin agent .md files
while IFS= read -r agent_file; do
  # Extract plugin name and agent name from path:
  # .../cache/{marketplace}/{plugin}/{version}/agents/{agent}.md
  # or .../cache/{marketplace}/{plugin}/{version}/skills/{skill}/agents/{agent}.md
  rel="${agent_file#"$CLAUDE_PLUGIN_CACHE"/}"
  plugin=$(echo "$rel" | cut -d/ -f2)
  agent_name=$(basename "$agent_file" .md)
  out_name="${plugin}--${agent_name}"

  # Extract description from frontmatter
  description=$(awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description: */, ""); print; exit}' "$agent_file")
  [ -z "$description" ] && description="Agent from $plugin plugin"

  # Extract body (everything after second ---)
  body=$(awk 'BEGIN{n=0} /^---$/{n++; if(n==2){found=1; next}} found{print}' "$agent_file")

  # Write OpenCode format
  cat > "${OPENCODE_AGENTS}/${out_name}.md" <<OPENCODE_EOF
---
description: ${description}
tools:
  read: true
  write: true
  edit: true
  bash: true
  grep: true
  glob: true
---
${body}
OPENCODE_EOF

  # Write Gemini format
  cat > "${GEMINI_AGENTS}/${out_name}.md" <<GEMINI_EOF
---
name: ${out_name}
description: ${description}
tools:
  - read_file
  - write_file
  - replace
  - run_shell_command
  - search_file_content
  - glob
---
${body}
GEMINI_EOF

  synced=$((synced + 1))

done < <(find "$CLAUDE_PLUGIN_CACHE" -path "*/agents/*.md" -type f 2>/dev/null)

echo "Synced $synced plugin agents to OpenCode and Gemini." >&2

# Hook-compatible output (continue the hook chain)
echo '{"continue": true}'
