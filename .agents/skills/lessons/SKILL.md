---
description: Capture a lesson learned to tasks/lessons.md — corrections, findings, or architectural decisions
argument-hint: [description of the lesson to capture]
---

You are capturing a lesson learned for this project. Lessons persist across sessions and help avoid repeating mistakes.

## Input

The user provided this context: $ARGUMENTS

If $ARGUMENTS is empty, scan the recent conversation for:
1. Corrections the user made ("no", "don't", "stop", "wrong", "actually")
2. Architectural decisions or findings discussed
3. Non-obvious patterns or gotchas discovered
Then ask the user which finding(s) to capture.

## Process

1. **Read** `tasks/lessons.md` (create if missing with a `# Lessons Learned` header)
2. **Check for duplicates** — if a similar lesson already exists, update it instead of adding a new one
3. **Format the new lesson** as:

```
## [Short descriptive title]

**Problem:** What went wrong or what was discovered
**Solution/Rule:** What to do (or not do) going forward
**Context:** Why this matters (link to specific code/files if relevant)
```

4. **Append** the lesson to `tasks/lessons.md`
5. **Confirm** to the user what was saved, in one line

## Rules

- Keep lessons actionable and specific — no vague advice
- Include file paths or code references when relevant
- Group related lessons under existing headings if they fit
- One lesson per invocation unless the user specifies multiple
