---
name: prd-to-linear-issues
description: >-
  Break a PRD into independently-grabbable Linear issues using tracer-bullet vertical slices.
  Use when user wants to convert a PRD to Linear issues, create implementation tickets in Linear,
  break down a PRD into work items for Linear, or mentions "Linear issues from PRD". Also use
  when the user says things like "create Linear tickets", "break this into Linear tasks",
  "turn this PRD into issues", or "plan this work in Linear" — even if they don't say "PRD"
  explicitly, if they have a requirements document or spec and want Linear issues from it.
---

# PRD to Linear Issues

Break a PRD into independently-grabbable Linear issues using vertical slices (tracer bullets).

This skill uses Linear's MCP tools (`save_issue`, `get_issue`, `search`, `get_document`, etc.) to read PRDs and create issues directly in Linear with proper dependencies, labels, and project associations.

## Process

### 1. Locate the PRD

Ask the user where the PRD lives. It could be:

- **A Linear issue** — fetch with `get_issue` using the issue identifier (e.g. `ENG-42`)
- **A Linear document** — fetch with `get_document` using the document ID or slug
- **A local file** — read from the filesystem
- **Already in conversation context** — the user may have pasted it or discussed it earlier

If the user gives a Linear issue identifier, fetch it with `get_issue`. If they mention a document title, use `search` with `type: "document"` to find it, then `get_document` to read it.

### 2. Discover workspace context

Before drafting slices, gather the context needed to create well-formed issues:

- **Team**: Ask which team the issues should belong to. If the project's CLAUDE.md or conversation already names a team, confirm it. Use `list_teams` if the user isn't sure.
- **Project** (optional): Ask if issues should be added to a Linear project. Use `list_projects` if needed.
- **Labels**: Check what labels exist with `list_issue_labels`. If the workspace uses labels like `Phase`, `Feature`, `Bug`, `AFK`, `HITL`, note them for later. Do NOT create new labels without asking.
- **Existing issues**: Use `list_issues` filtered by project to see what already exists, so you avoid duplicating work that's already tracked.

### 3. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current architecture. This helps you write slices that align with actual file boundaries and integration points.

### 4. Draft vertical slices

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end — NOT a horizontal slice of one layer.

Slices may be classified as:
- **AFK** — can be implemented autonomously without human interaction (preferred)
- **HITL** — requires human interaction such as an architectural decision, design review, API key setup, or manual configuration

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Consider Linear's sub-issue pattern: if a slice naturally decomposes into 2-3 small tasks within the same layer, those can be sub-issues rather than separate top-level issues
</vertical-slice-rules>

### 5. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: AFK / HITL
- **Priority**: Urgent(1) / High(2) / Normal(3) / Low(4)
- **Estimate**: suggested story points if the team uses estimates
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?
- Should any be assigned to a specific project or milestone?
- What priority distribution looks right?

Iterate until the user approves the breakdown.

### 6. Create the Linear issues

For each approved slice, create a Linear issue using the `save_issue` MCP tool.

**Create issues in dependency order** (blockers first) so that you can wire up real `blockedBy` relations using the returned issue identifiers.

For each issue, call `save_issue` with:

```
save_issue(
  title: "...",
  team: "<team-name-or-id>",
  description: "<markdown body — see template below>",
  priority: <1-4>,
  labels: ["Phase", "AFK" or "HITL", ...any relevant labels],
  project: "<project-name-or-id if applicable>",
  estimate: <story-points if team uses estimates>,
  blockedBy: ["<identifier of blocking issue>"],  // only after blockers are created
)
```

After each issue is created, note its returned identifier (e.g. `DGO-15`) so you can reference it in subsequent `blockedBy` fields.

<issue-body-template>
## Parent PRD

Link to or identify the source PRD (Linear issue identifier, document title, or file path).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation. Reference specific sections of the parent PRD rather than duplicating content.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Dependencies

Populated automatically via Linear's `blockedBy` relation. Additional context on why the dependency exists goes here if not obvious.

## User stories addressed

Reference by number from the parent PRD:

- User story 3
- User story 7
</issue-body-template>

### 7. Summary

After all issues are created, present a summary table:

| # | Identifier | Title | Type | Priority | Blocked by |
|---|-----------|-------|------|----------|------------|
| 1 | DGO-15 | ... | AFK | Normal | — |
| 2 | DGO-16 | ... | HITL | High | DGO-15 |

If the issues were added to a project, mention it. If the project's CLAUDE.md tracks Linear issue IDs, offer to update it.

Do NOT close, modify, or change the status of the parent PRD issue/document.

## Tips

- **Use `blockedBy` not markdown links** — Linear's native dependency tracking is superior to text references. It shows up in the issue sidebar, enables dependency views, and integrates with automation.
- **Prefer labels over title prefixes** — instead of "[AFK] Fix auth", use a clean title "Fix auth" with an `AFK` label. Labels are filterable and show in views.
- **Story points are optional** — only include `estimate` if the team actually uses estimates (check existing issues or ask).
- **Sub-issues for internal decomposition** — if a vertical slice has 2-3 obvious sub-tasks that are too small to be independent slices, create them as sub-issues using `parentId` rather than top-level issues. But keep this shallow — avoid nesting sub-issues more than one level deep.
- **Don't over-classify priority** — if everything is "High", nothing is. Use Normal as the default and only escalate for genuinely urgent or high-impact work.
