---
name: done
description: "Save a session summary to ~/.claude-done/ when wrapping up. Use when the user says /done, 'wrap up', 'save session notes', 'summarize this session', or wants to record what was accomplished."
---

# Done

Save a structured summary of the current session to `~/.claude-done/` for future reference.

## Workflow

### Step 1: Gather Metadata

Run these commands to collect metadata:

```bash
date +%Y-%m-%d
```

```bash
git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-branch"
```

The session ID is available from the current conversation context — use the full session ID.

### Step 2: Review the Conversation

Write the summary in the user's preferred language (match the language used in the system prompt or the language the user has been communicating in during this session).

Meticulously review the entire conversation, tracing the full arc of discussion, and identify:

- The main goal and what was accomplished
- Key decisions made and their reasoning
- Alternatives explored and why they were rejected
- Problems encountered during the session and how they were resolved
- Important questions raised (both resolved and unresolved)
- Files that were changed and why
- Logical next steps and follow-ups

### Step 3: Generate Title

Create a 3-5 word kebab-case title summarizing the session (e.g., `fix-token-refresh-logic`, `add-user-auth-flow`).

### Step 4: Write the Summary File

Create a file in Obsisian markdown format with the following content, replacing placeholders with the actual data:

**Diectory:** `/mnt/d/obsidian_vaults/SB/09\ -\ AI\ Sessions/`

**Filename format:** `{YYYY-MM-DD}_{branch}_{sessionId-full}_{kebab-case-title}.md`

- Replace `/` in branch names with `-`
- Example: `2026-02-18_feat-auth_a1b2c3d4_fix-token-refresh.md`

**File content template:**

```markdown
# {Natural Language Title}

**Date:** YYYY-MM-DD
**Branch:** branch-name
**Session:** full-session-id

## Summary
2-4 sentences describing the goal and outcome of this session.

## Key Decisions
- Decision and brief reasoning
- Alternatives considered and why they were rejected

## What Changed
- `file/path` — what changed and why

## Problems & Solutions
- Problem encountered — how it was resolved

## Questions Raised
- Important questions discussed, with answers if resolved
- Unresolved questions flagged for future sessions

## Next Steps
- [ ] Follow-up task
```

Omit any section that has no content. Do not include empty sections.

### Step 5: Confirm

After writing the file, tell the user the filename and a one-line summary of what was saved.
