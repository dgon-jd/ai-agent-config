---
description: Complete a feature branch — tests, review, docs, commit, merge/PR, and PM-tool sync
---

# Finish Feature

Complete a feature branch with quality gates, documentation updates, and PM
tracking. Works across projects regardless of which PM tool (if any) they
use — reads the project's config, same workflow principles.

**Announce at start:** "Running /finish-feature — completing this branch
with tests, review, docs, commit, merge, and PM sync."

## Step 0: Discover PM tool and detect issue ID

Before anything else, figure out whether this project uses a PM tool and,
if so, which issue this branch belongs to.

1. **Read project `CLAUDE.md`** for a `## PM Tool` section (or
   `## Project Management`, `## Issue Tracker`). If not there, check
   `docs/` for `pm.md`, `project-management.md`, `workflow.md`.
2. Record the tool, prefix, closing keyword, state names, and how to call
   the tool (MCP server/tools or CLI) — same as `/start-feature`.
3. Get the current branch:
   ```bash
   git branch --show-current
   ```
4. **If PM configured:** try to extract the issue ID from the branch name
   using the configured prefix. Common patterns: `feature/{prefix}{id}-{slug}`,
   `{prefix}{id}-{slug}`, case-insensitive. If the branch doesn't contain an
   ID, ask the user for it. Store the canonical ID for use throughout.
5. **If PM = none:** skip all PM-specific steps (4a, 7). The rest of the
   workflow (tests, review, docs, commit, merge) still runs.

### Why this step matters

The PM tool governs two things downstream: the commit closing keyword
(Step 5) and the final status update (Step 7). Getting it wrong means
either a dangling issue or a broken commit reference. Resolve it once
here so the rest of the workflow is deterministic.

## Step 1: Run tests

Discover the test command in order of preference:

1. **`CLAUDE.md`** — look for an explicit test command section (e.g.
   `## Test Command: uv run pytest` or similar). The project's own doc
   trumps auto-detection.
2. **Auto-detect from project files**:
   - `package.json` with `scripts.test` → `pnpm test` / `npm test` /
     `yarn test` (pick the lockfile that exists: `pnpm-lock.yaml`,
     `yarn.lock`, `package-lock.json`)
   - `pyproject.toml` → `uv run pytest` if `uv.lock` exists, else `pytest`
   - `Cargo.toml` → `cargo test`
   - `go.mod` → `go test ./...`
   - `Makefile` with a `test` target → `make test`
3. If none of the above exist and nothing is documented, ask the user.

Run it. If tests fail, stop and fix them — do not proceed until green.
No `--no-verify`, no skipping failures.

## Step 2: Code review

Check whether a code-reviewer agent has already been run in this
conversation (look for its output in history).

- **If not yet run**: launch the project's preferred reviewer agent on
  the current diff (`git diff` + `git diff --cached`). Common choices:
  `pr-review-toolkit:code-reviewer`, `code-review:code-review`, or
  `comprehensive-review:code-reviewer`. Fix high-priority issues it
  finds. Re-run tests after fixes.
- **If already run**: note that review was already completed and skip.

## Step 3: Check environment example files

Scan changed files for new env-var references. Language-appropriate
patterns:

- JavaScript / TypeScript: `process.env.X`, `import.meta.env.X`
- Python: `os.getenv("X")`, `os.environ["X"]`, `os.environ.get("X")`,
  Pydantic `BaseSettings` fields
- Go: `os.Getenv("X")`
- Rust: `env::var("X")`, `std::env::var("X")`
- Shell: `$X`, `${X}`

Search the repo for `.env.example` (or `.env.sample`, `.env.dist`) files.
Monorepos may have several — handle them all. For each new env var
referenced in code but missing from the appropriate `.env.example`, add
it with a short descriptive comment and a placeholder value.

## Step 4: Update documentation

Read each file first, then make targeted edits. Don't add noise for
minor fixes — only update docs when there's a meaningful change.

### 4a: CLAUDE.md — issue status table (skip if PM = none)

If `CLAUDE.md` has an issue-status table (common locations:
`## Issue IDs`, `## Tickets`, `## PM Tracking`), update the row for the
current issue to the configured "done" state.

### 4b: CLAUDE.md — architecture sections

If the feature introduced new architecture patterns, API routes, data
structures, or changed existing documented behavior, update the relevant
sections. Common sections to check:

- Data flow / pipeline
- Key data structures
- Environment variables
- API routes / endpoints
- Database schema

Only update for meaningful changes — minor fixes don't need doc updates.

### 4c: README.md (if applicable)

Update `README.md` if any of these apply:

- New packages/dirs → project structure section
- New user-facing features → features list
- New env vars or dependencies → setup instructions
- Has an implementation-status checklist → update it

### 4d: tasks/todo.md

If `tasks/todo.md` has a section for the current feature, add a `## Review`
section summarizing:

- What changed (files and their purpose)
- Key decisions made
- Net code impact (added/removed/changed)

## Step 5: Stage and commit

Stage the changes (code + docs). Create a commit with:

- A **conventional commit** header (`feat:`, `fix:`, `refactor:`, `docs:`,
  `chore:`, `test:`)
- **Closing keyword** from the PM config, if configured
- The co-author line

Format:

```
<type>: <concise description>[ (ID)]

<optional body with key details>

<closing-keyword> <ID>          # only if PM is configured

Co-Authored-By: Claude <noreply@anthropic.com>
```

Per-tool closing keyword examples (use whichever the config says):

- **Linear**: `Resolves DGO-57` (also `Fixes`, `Closes` work)
- **Jira**: `PROJ-123` is usually enough for smart-commits, or use
  whatever transitions the project has configured
- **GitHub Issues**: `Fixes #42`, `Closes #42`
- **Azure DevOps**: `AB#5678` (for work-item linking)

Use a HEREDOC for the commit message so newlines and quoting are preserved.
Stage specific files by name when possible — avoid `git add -A`/`git add .`
which can grab sensitive files by accident.

## Step 6: Present merge options

Ask the user exactly these three options:

```
Ready to integrate. What would you like to do?

1. Merge into <integration-branch> locally (merge + delete branch)
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
```

The integration branch is whatever `CLAUDE.md` says to merge into
(commonly `develop` in Git Flow projects, `main` in trunk-based ones).
If unclear, default to `develop` if it exists, else `main`.

### Option 1: Merge locally

```bash
git checkout <integration-branch>
git pull origin <integration-branch>
git merge <feature-branch>
<test-command>             # verify after merge
git branch -d <feature-branch>
git push origin <integration-branch>
```

If merge conflicts occur, resolve them and re-run tests before completing.

### Option 2: Push and create PR

```bash
git push -u origin <feature-branch>
gh pr create --base <integration-branch> --title "..." --body "..."
```

Include in the PR body:

- Summary bullets of what changed
- The closing keyword with the issue ID (if PM configured)
- A test plan checklist

### Option 3: Keep as-is

Report the branch status and stop. Don't clean up.

## Step 7: Update the PM tool's state (skip if PM = none)

After a successful merge (Option 1) or PR creation (Option 2), update the
issue to the configured "done" state.

For Option 3 (keep as-is), set it to the configured "in review" state
instead — the work isn't merged but it's ready for review.

How to call it depends on the configured tool:

- **Linear MCP** — `mcp__linear__save_issue(id: "DGO-57", state: "Done")`
- **Jira MCP (Atlassian)** — `mcp__atlassian__editJiraIssue(key: "PROJ-123", fields: {status: "Done"})` (or transition API)
- **Azure DevOps MCP** — `mcp__ado__update_work_item(id: 5678, state: "Closed")`
- **GitHub Issues CLI** — `gh issue close 42 --repo owner/repo` (closing
  via commit keyword is usually enough; this is belt-and-suspenders)

Skip this step entirely if no PM tool is configured.

## Step 8: Cleanup (if working in a git worktree)

```bash
git worktree list | grep $(git branch --show-current)
```

If you're in a worktree and chose Option 1 or 2, remove it after the
merge/push is complete. For Option 3, preserve the worktree.

## Checklist summary

At the end, print a summary the user can glance at:

```
/finish-feature complete:
- [x] Tests passed
- [x] Code reviewed
- [x] .env.example checked
- [x] CLAUDE.md updated (status + architecture)      # adjust per what ran
- [x] README.md updated
- [x] tasks/todo.md updated
- [x] Committed: <hash>[ (<closing-keyword> <ID>)]
- [x] <Merged to <branch> / PR #N created / Branch kept>
- [x] PM: <tool> <id> → <done-state>                  # only if PM configured
```
