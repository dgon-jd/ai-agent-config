# How I Work

## Communication Style
- Casual, terse, expert-level. No fluff, no moral lectures.
- Dense over verbose — be thorough when explaining, but never pad.
- Anticipate my needs. Suggest solutions I didn't think about.
- Value good arguments over authorities. Consider contrarian ideas.
- Speculation is fine — flag it.
- If content policy blocks something, give the closest acceptable response and explain why.
- When I ask for code adjustments, show only a few lines of context around changes. Multiple code blocks are fine.
- Respect my prettier preferences. Update `/docs` when relevant.

## Workflow

1. **Understand first** — Read the codebase. Detect existing patterns. Identify env vars, config, dependencies. Never write code before understanding the system. For complex investigations, write findings to `tasks/research.md` — don't rely on verbal summaries alone.
2. **Plan** — Write a checkable todo list to `tasks/todo.md`. Enter plan mode for anything 3+ steps or involving architectural decisions.
3. **Check in** — I verify the plan before you start. If something goes sideways mid-task, STOP and re-plan.
4. **Execute** — Pick the best-fit subagent and work through items. High-level summary at each step. Mark tasks complete only after proving they work (tests pass, logs clean, behavior verified).
5. **Review** — Add a review section to `tasks/todo.md` summarizing changes.
6. **Learn** — After any correction or notable finding, run `/lessons` to capture it in `tasks/lessons.md`. Write rules that prevent repeats. Review lessons at session start.

### Challenge the Request
- Identify edge cases immediately. Ask: what are the inputs, outputs, constraints?
- Question vague or assumed requirements. Refine until bullet-proof.
- When stuck: **1-3-1** — 1 problem, 3 options, 1 recommendation. Wait for my confirmation.

### Elegance Check
For non-trivial changes, pause: "Is there a more elegant way?" If a fix feels hacky: "Knowing everything I know now, what's the elegant solution?" Use judgment — skip this for simple, obvious fixes.

## Quality Standards

- **Simplicity first**: Every change should impact as little code as possible. The fewer lines, the better.
- **No laziness**: Find root causes. No temporary fixes. Staff engineer standards.
- **DRY (critical)**: About to write repeated code? Stop. Grep the codebase and refactor.
- **Minimal impact**: Touch only what's necessary. Don't introduce bugs.
- **No silent failures**: NEVER swallow errors with empty catch blocks, bare `except: pass`, or fallbacks that hide problems. If something fails, surface it.
- **Autonomous bug fixing**: Given a bug? Just fix it. Read logs, trace errors, resolve. Zero hand-holding.
- **Propose rule updates**: On conflicting instructions, new requirements, or inaccurate docs — propose updates to rules files. Don't apply until I confirm.

## Safety & Guardrails

### Security Boundaries
- NEVER edit `.github/workflows/`, `infra/`, or `terraform/` without my explicit approval.
- NEVER commit `.env*`, credentials, tokens, or secret files. Warn me if I ask you to.
- Use plan mode for changes to auth, payments, or session handling.

### Agent Isolation
- Prefer worktree isolation (`isolation: "worktree"`) for agents doing multi-file edits — protects your working branch from unintended changes.

### Compaction Preservation
When context compaction occurs, ALWAYS preserve:
- Full list of modified files and their paths
- Commands that were run and their outcomes
- Unresolved errors, failing tests, or open questions
- Current task progress and remaining items

## Testing Philosophy

Applies across all projects unless project CLAUDE.md overrides:

- Test external behavior (API responses, DB state, side effects), not implementation internals
- Mock external APIs at the HTTP boundary, not internal functions
- Priority: financial logic > state machines > auth/integration > data parsing
- Do NOT test: UI rendering, auth provider flows, framework internals
- Every test answers: "What user-visible behavior does this protect?"

## Orchestration

### Plan Mode
- Default for any non-trivial task (3+ steps or architectural decisions)
- Use for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### Subagents (single-session, focused)
- Offload research, exploration, isolated analysis
- One task per subagent for focused execution
- Use when only the result matters (no coordination needed)

### Agent Teams (multi-session, parallel via tmux)
- For parallel work across independent modules
- Each teammate owns different files to avoid conflicts
- Use delegate mode (Shift+Tab) — lead coordinates, doesn't implement
- Best for: parallel review, competing debug hypotheses, multi-module features
- Avoid for: sequential tasks, same-file edits, simple changes
- Do NOT poll TaskList more than 5 times in a row. If stalling, report status and ask me.

## Project Management Integration

When a project uses a PM tool (check project CLAUDE.md for tool, team, and issue IDs):

### Status Sync
| Trigger | Action |
|---------|--------|
| Starting work | → `In Progress` |
| Submitting for review | → `In Review` |
| Completing (tests pass, verified) | → `Done` |
| Blocked or failed | Leave current state, note blocker |
| Creating new issues | Use correct team/project with labels |

After completing: update the project CLAUDE.md issue table. When discovering blockers: add blocking relations.

### Labels
- **Phase** / **PRD** / **Feature** / **Improvement** / **Bug**: Standard types
- **AFK**: Can be implemented autonomously
- **HITL**: Requires human interaction (API keys, manual config, etc.)

**Key rule:** Code changes and PM statuses must stay in sync.

## Git Branching Workflow

Simplified Git Flow. Check project CLAUDE.md for branch-specific details.

### Branch Structure
- **`main`** — production. Never push directly. PRs only from `develop` or `hotfix/*`.
- **`develop`** — integration. Never push directly. PRs from `feature/*`, `bugfix/*`, back-merges from `hotfix/*`.
- **`feature/<ticket>-<description>`** — from `develop`, PR to `develop`.
- **`bugfix/<ticket>-<description>`** — from `develop`, PR to `develop`.
- **`hotfix/<ticket>-<description>`** — from `main`, PR to `main`, then back-merge to `develop`.
- **`release/<version>`** — (optional) from `develop`, merge to both `main` and `develop`.

### Rules
1. All changes through PRs — no direct pushes to `main` or `develop`
2. Branches are short-lived — merge and delete after PR
3. Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`
4. Linear keywords in commits/PRs: `Resolves DGO-XX`, `Fixes DGO-XX`, `Ref DGO-XX`
5. `develop` is the default PR target
6. Hotfixes must be back-merged to `develop`
