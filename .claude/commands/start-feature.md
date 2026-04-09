---
description: Kick off a new feature — discover PM tool, fetch issue, create branch, research, plan, track
argument-hint: <issue-id or feature-name>
---

# Start Feature

Kick off a new feature. If the project uses a PM tool, fetch the issue and
track it through that tool. If not, run as a pure git/plan workflow. Same
principles either way: understand before coding, write a plan, keep a paper
trail.

**Argument:** An issue identifier if the project uses a PM tool (e.g.
`DGO-57`, `PROJ-123`, `#5678`), or a short feature name (e.g. `add-dark-mode`)
if it doesn't. If omitted, ask the user.

**Announce at start:** "Running /start-feature <arg> — setting up branch,
researching, and planning."

## Step 0: Discover the PM tool (if any)

Before anything else, figure out whether this project uses a PM tool and
how to talk to it. The goal is to be explicit about it once, so every
downstream step can just read the config.

Search, in order:

1. **`CLAUDE.md` at the project root.** Look for a section titled `## PM Tool`,
   `## Project Management`, or `## Issue Tracker`.
2. **`docs/`** for files matching `pm.md`, `project-management.md`,
   `workflow.md`, or similar.
3. **Anywhere else CLAUDE.md points you** — some projects keep the config in
   a dedicated file.

The config should tell you some subset of:

- **Tool name** — Linear / Jira / Azure DevOps / GitHub Issues / etc.
- **How to call it** — which MCP server (`mcp__linear`, `mcp__atlassian`,
  `mcp__ado`, …) and which tools on it, or which CLI (`gh`, `jira`, `az`).
- **Issue prefix / format** — `DGO-`, `PROJ-`, bare numbers, `owner/repo#N`.
- **Branch format** — e.g. `feature/{id-lower}-{slug}`.
- **Commit closing keyword** — `Resolves`, `Fixes`, `Closes`, smart-commit
  format, etc.
- **State names** — what "in progress" and "done" are called (Linear's
  `In Progress`/`Done`, Jira's `In Progress`/`Done`, ADO's `Active`/`Closed`).

**Record what you found** in a short internal summary before proceeding, so
later steps can reference a consistent mental model. Something like:
`PM = Linear via mcp__linear; prefix=DGO-; close keyword=Resolves; done=Done`.

**If nothing is configured**, that's a valid outcome — say so explicitly and
set `PM = none`. Skip Steps 1, 2, 2b, and 7 below. Steps 3–6 and 8 still run
as a pure git workflow using the argument as the feature name.

### Why we do this first

Baking PM specifics into instructions makes the skill impossible to reuse.
Reading config once and then referring to it keeps the rest of the workflow
clean and lets the same skill work across Linear/Jira/ADO/none with zero
branching logic scattered through the steps.

## Step 1: Parse issue ID (skip if PM = none)

Normalize the argument to the tool's canonical format using the prefix from
the config. Accept common variants: upper/lower case, with/without the
separator, bare numbers (assume the configured prefix).

If no argument was given, ask: "Which issue should I start? (e.g. <example
from config>)".

## Step 2: Fetch issue details (skip if PM = none)

Use the MCP or CLI the config specified. The *operation* is always the same
("get full issue details"); the *call* depends on the tool.

Examples of what this looks like per tool — use whichever the config says:

- **Linear MCP** — `mcp__linear__get_issue(id: "DGO-57")`
- **Jira MCP (Atlassian)** — `mcp__atlassian__getJiraIssue(key: "PROJ-123")`
- **Azure DevOps MCP** — `mcp__ado__get_work_item(id: 5678)`
- **GitHub CLI** — `gh issue view 42 --repo owner/repo --json title,body,state,labels`

Extract and show the user:

- **Title**
- **Description** (the spec / requirements)
- **Status** — warn if already in a post-start state (In Progress / Done /
  Closed / etc., per the config)
- **Labels / tags** — Phase, AFK/HITL, Feature/Bug/Improvement, whatever
  the project uses
- **Blocked-by relations** — if any are still open, warn: "X is blocked by
  Y (still open). Proceed anyway?"
- **Milestone / Epic / Sprint** for context

## Step 2b: Move issue to "in progress" (skip if PM = none)

Using the state name the config specifies for "in progress". Again, the
operation is fixed, the call depends on the tool:

- **Linear** — `mcp__linear__save_issue(id: "DGO-57", state: "In Progress")`
- **Jira** — `mcp__atlassian__editJiraIssue(key: "PROJ-123", ...)`
- **ADO** — `mcp__ado__update_work_item(id: 5678, state: "Active")`

## Step 3: Create the feature branch

Derive the branch name:

- **If PM configured:** use the branch format from the config, substituting
  the issue ID (lowercased if the config says so) and a slug from the issue
  title. Default format if the config doesn't specify one:
  `feature/<id-lower>-<slug>`.
- **If PM = none:** use `feature/<slug-from-argument>`.

Slug rules: lowercase, replace spaces and punctuation with hyphens, drop
anything non-alphanumeric, trim to ~50 chars.

```bash
# Detect the project's main branch (prefer 'develop' if it exists, else 'main'
# or whatever CLAUDE.md says is the integration branch)
MAIN_BRANCH=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' || echo main)
git checkout "$MAIN_BRANCH"
git pull origin "$MAIN_BRANCH"
git checkout -b <derived-branch-name>
```

Examples:

- Linear, DGO-57 "Candidate CV Upload & Scoring" →
  `feature/dgo-57-candidate-cv-upload-scoring`
- Jira, PROJ-123 "Add SSO login" →
  `feature/proj-123-add-sso-login`
- No PM, arg `add-dark-mode` →
  `feature/add-dark-mode`

## Step 4: Label the terminal (nice-to-have)

```bash
echo -ne "\033]0;<id-or-name>: <short-title>\007"
```

Skip on environments where this doesn't apply (Cowork, web).

## Step 5: Research phase

Understanding before coding. Nothing in this step writes files to the repo.

### 5a: Explore the codebase

Launch the Explore subagent (or use Grep/Read directly for small codebases)
to find:

- Which files/modules this feature will touch
- Existing patterns the feature should follow
- Similar features already in the repo that can serve as templates

### 5b: Check external docs (if needed)

If the issue mentions unfamiliar libraries, APIs, or framework features,
pull up-to-date docs via `ref_search_documentation` or `WebSearch`. Common
triggers: new dependencies, third-party APIs (Stripe, Resend, Langfuse…),
framework features not yet used in the repo.

Skip this if the work is purely internal logic with established patterns.

### 5c: Check CLAUDE.md for relevant context

Read `CLAUDE.md` for architecture decisions, data structures, and
conventions that relate to this feature. The plan needs to account for
these — e.g. "credit system uses atomic CTEs", "pipeline callbacks decouple
from DB", "Dnipro must stay on Yasno provider".

## Step 6: Write the plan to `tasks/todo.md`

Structured plan in the project's format:

```markdown
# <ID-or-name>: <Title>

## Summary

<1–3 sentences on what this feature does and why>

## Key Decisions

| Question         | Answer                         |
| ---------------- | ------------------------------ |
| <decision point> | <chosen approach + reasoning>  |

## Tasks

- [ ] 1. <first task — smallest meaningful unit of work>
- [ ] 2. <second task>
- [ ] ...
```

Guidelines:

- Each task is a single, testable unit of work.
- Order by dependency (schema → API → UI).
- Include test-writing tasks alongside implementation.
- Flag HITL (needs user input) vs AFK (autonomous).
- Prefer many small tasks over a few large ones.

## Step 7: Create the in-session task list

Use `TaskCreate` to mirror the plan into the session's task tracker, so
progress is visible as work proceeds. One `TaskCreate` per plan item.

## Step 8: Present the plan for approval

Show the user a concise summary:

```
/start-feature <arg> ready:

Branch: <branch-name>
PM:     <tool> <id> → <in-progress-state>        # only if PM configured
Plan:   tasks/todo.md (<N> tasks)

<brief summary of approach>

Key decisions that need your input:
- <any HITL items or architectural choices>

Ready to begin implementation?
```

Wait for confirmation before starting implementation. The user may want to
adjust the plan, add constraints, or change the approach.

## Pairing with `/finish-feature`

When implementation is done, run `/finish-feature` to: run tests, code
review, update docs, commit with the project's closing keyword, merge/PR,
and (if configured) update the PM tool to `done`.
