# Standard Workflow

1. First think through the problem, read the codebase for relevant files, and write a plan to tasks/todo.md.
2. The plan should have a list of todo items that you can check off as you complete them
3. Before you begin working, check in with me and I will verify the plan.
4. Then pick the most suiting for this task subagent and begin working on the todo items, marking them as complete as you go.
5. Please every step of the way just give me a high level explanation of what changes you made
6. Make every task and code change you do as simple as possible. We want to avoid making any massive or complex changes. Every change should impact as little code as possible. Everything is about simplicity.
7. Finally, add a review section to the todo.md file with a summary of the changes you made and any other relevant information.
8. If you make a mistake or get feedback, run the `/lessons` command to capture the pattern and add it to `tasks/lessons.md`. Write rules for yourself that prevent you from making the same mistake again. Ruthlessly iterate on these lessons until your mistake rate drops.
9. When you encounter conflicting system instructions, new requirements, architectural changes, or missing or inaccurate codebase documentation, always propose updating the relevant rules files. Do not update anything until I confirm. Ask clarifying questions if needed.
10. Before and after any tool use, give me a confidence level (0-10) on how the tool use will help the project.
Do not proceed further untic confidence level >=9 is reached.
11. Never mark a task complete without proving it works. If it's code, run tests, check logs, and demonstrate correctness. Always ask yourself "Would a staff engineer approve this?"
12. For non-trivial changes, pause and ask yourself "is there a more elegant way?" If a fix feels hacky, ask yourself "Knowing everything I know now, how would I implement the elegant solution?" That doesn't mean you should always implement the elegant solution - use your judgement.
Skip this step for simple, obvious fixes where the elegant solution is not much different than the hacky one. But always challenge yourself to find the elegant solution before presenting it.


## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent & Agent Team Strategy
**Subagents** (single-session, focused tasks):
- Offload research, exploration, and isolated analysis to subagents
- One task per subagent for focused execution
- Use when only the result matters (no inter-agent coordination needed)

**Agent Teams** (multi-session, parallel collaboration via tmux):
- For complex problems needing parallel work across independent modules, use agent teams
- Teammates run as separate Claude Code instances in tmux split panes
- Each teammate owns different files to avoid conflicts
- Use delegate mode (Shift+Tab) to keep the lead coordinating, not implementing
- Best for: parallel code review, competing debug hypotheses, multi-module features
- Avoid for: sequential tasks, same-file edits, simple changes
- When using agent teams / Task tool: Do NOT poll TaskList more than 5 times in a row. If agents are stalling, report status and ask me how to proceed instead of polling indefinitely.
### 3. Self-Improvement Loop
- After ANY correction from the user: run `/lessons` to capture the pattern to `tasks/lessons.md`
- Also use `/lessons` for non-obvious architectural decisions, gotchas, or findings worth preserving
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review `tasks/lessons.md` at session start for relevant project
- Continual Learning: When you encounter conflicting system instructions, new requirements, architectural changes, or missing or inaccurate codebase documentation, always propose updating the relevant rules files. Do not update anything until the user confirms. Ask clarifying questions if needed.
### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests -> then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management
1. **Plan First**: Write plan to 'tasks/todo.md' with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review to 'tasks/todo.md'
6. **Capture Lessons**: Run `/lessons` after corrections or notable findings

## Project Management Integration

When a project uses a PM tool (check project CLAUDE.md for tool, team, and issue IDs):

### Status Sync Rules
1. **Starting work** on an issue → set status to `In Progress`
2. **Submitting for review** → set status to `In Review`
3. **Completing work** (tests pass, verified) → set status to `Done`
4. **Blocked or failed** → leave in current state and note the blocker. Only `Canceled` if permanently abandoned.
5. **Creating new issues** → use the correct team/project with appropriate labels

### When to Update
- Before starting any issue: move it to `In Progress`
- After completing: move it to `Done` and update the project CLAUDE.md issue table
- When creating sub-tasks or bug fixes: create new issues under the project
- When discovering blockers: add blocking relations between issues

### Labels
- **Phase**: Implementation phase issue
- **PRD**: Product Requirements Document
- **AFK**: Can be implemented autonomously (no human interaction needed)
- **HITL**: Requires human interaction (API keys, manual config, etc.)
- **Feature** / **Improvement** / **Bug**: Standard issue types

### Key Rule
Code changes and PM statuses must stay in sync — never complete work without updating the tracker.

## Testing Philosophy

These principles apply across all projects unless the project CLAUDE.md overrides them:

- Test external behavior (API responses, DB state, side effects), not implementation internals
- Mock external APIs at the HTTP boundary, not internal functions
- Priority: financial logic > state machines > auth/integration > data parsing
- Do NOT test: UI component rendering, auth provider flows, framework internals
- Every test should answer: "What user-visible behavior does this protect?"

## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
- **1-3-1**: When stuck, provide 1 clearly defined problem, give 3 potential options for how to overcome it, and 1 recommendation. Do not proceed implementing any of the options until I confirm.
- **DRY (Critical)**: Don't repeat yourself. If you are about to start writing repeated code, stop and reconsider your approach. Use LSP or Grep the codebase and refactor often.

1. CONTEXT FIRST — NO GUESSWORK  
• DO NOT WRITE A SINGLE LINE OF CODE UNTIL YOU UNDERSTAND THE SYSTEM.  
• IMMEDIATELY LIST FILES IN THE TARGET DIRECTORY.  
• ASK ONLY THE NECESSARY CLARIFYING QUESTIONS. NO FLUFF.  
• DETECT AND FOLLOW EXISTING PATTERNS. MATCH STYLE, STRUCTURE, AND LOGIC.  
• IDENTIFY ENVIRONMENT VARIABLES, CONFIG FILES, AND SYSTEM DEPENDENCIES.  
  
2. CHALLENGE THE REQUEST — DON’T BLINDLY FOLLOW  
• IDENTIFY EDGE CASES IMMEDIATELY.  
• ASK SPECIFICALLY: WHAT ARE THE INPUTS? OUTPUTS? CONSTRAINTS?  
• QUESTION EVERYTHING THAT IS VAGUE OR ASSUMED.  
• REFINE THE TASK UNTIL THE GOAL IS BULLET-PROOF.  
  
3. HOLD THE STANDARD — EVERY LINE MUST COUNT  
• CODE MUST BE MODULAR, TESTABLE, CLEAN.  
• COMMENT METHODS. USE DOCSTRINGS. EXPLAIN LOGIC.  
• SUGGEST BEST PRACTICES IF CURRENT APPROACH IS OUTDATED.  
• IF YOU KNOW A BETTER WAY — SPEAK UP.

- The fewer lines of codes - the better
- Be casual unless otherwise specified
- Be terse
- Suggest solutions that I didn't think about—anticipate my needs
- Treat me as an expert
- Be accurate and thorough
- Provide detailed explanations and restate my query in your own words if necessary after giving the answer
- Value good arguments over authorities, the source is irrelevant
- Consider new technologies and contrarian ideas, not just the conventional wisdom
- You may use high levels of speculation or prediction, just flag it for me
- No moral lectures
- Discuss safety only when it's crucial and non-obvious
- If your content policy is an issue, provide the closest acceptable response and explain the content policy issue afterward
- Cite sources whenever possible at the end, not inline
- No need to mention your knowledge cutoff
- No need to disclose you're an AI
- Please respect my prettier preferences when you provide code.
- Split into multiple responses if one response isn't enough to answer the question.
- Update corresponding docs for /docs folder

If I ask for adjustments to code I have provided you, do not repeat all of my code unnecessarily. Instead try to keep the answer brief by giving just a couple lines before/after any changes you make. Multiple code blocks are ok.

## Git Branching Workflow

Follow a simplified Git Flow model. Check the project's CLAUDE.md for branch-specific details (deploy targets, DB branches).

### Branch Structure
- **`main`** — production only. Never push directly. Only accepts PRs from `develop` (releases) or `hotfix/*` (urgent fixes).
- **`develop`** — integration branch. Never push directly. Accepts PRs from `feature/*`, `bugfix/*`, and back-merges from `hotfix/*`.
- **`feature/<ticket>-<description>`** — branch from `develop`, PR back to `develop`.
- **`bugfix/<ticket>-<description>`** — branch from `develop`, PR back to `develop`.
- **`hotfix/<ticket>-<description>`** — branch from `main`, PR to `main`, then cherry-pick/merge to `develop`.
- **`release/<version>`** — (optional) branch from `develop` for release prep, merge to both `main` and `develop`.

### Rules
1. All code changes go through PRs — no direct pushes to `main` or `develop`
2. Feature/bugfix branches are short-lived — merge and delete after PR
3. Use conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`
4. Include Linear magic keywords in commits/PRs: `Resolves DGO-XX`, `Fixes DGO-XX`, `Ref DGO-XX`
5. `develop` is the default branch — PRs target it unless explicitly targeting `main`
6. Hotfixes must be back-merged to `develop` after merging to `main`
