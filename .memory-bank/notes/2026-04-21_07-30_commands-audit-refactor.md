---
type: pattern
tags: [commands, refactor, frontmatter, aliases, safety-gates, stack-generic, memory-bank]
related_features: []
sprint: null
importance: high
created: 2026-04-21
---

# commands-audit-refactor
Date: 2026-04-21

## What was done
- Full audit of commands/ surfaced 7 systemic issues (broken frontmatter, duplicate /plan vs /mb plan, stack hardcoding, missing safety gates, /adr path conflict, weak $ARGUMENTS handling, codebase/ integration gap)
- Resolved via 10-stage plan in plans/done/2026-04-21_refactor_commands-audit-fixes.md
- 21 files, +906/-359, single commit d4a1abc

## New knowledge
- **Aliases pattern**: when two commands solve the same task (shell /plan and /mb plan), pick the short form as primary and make the prefixed form a thin delegator — users get the short path to the same sophisticated logic, mb.md stays discoverable
- **stack=unknown fallback is mandatory** — every command that detects a stack must have an explicit "ask the user" branch, otherwise it crashes on unknown repos
- **Destructive ops need y/N BEFORE the file write**, not just before the apply — users often accept the diff, realize it's wrong too late, and have to manually revert. Catching before write costs nothing and prevents disasters
- **Frontmatter drift is silent**: a file that opens with `# commentary` + `---` + `## description:` renders fine in Markdown but parses as ZERO YAML keys. Always validate head -1 == "---" and fence count == 2 as a gate before release
- **codebase/*.md docs are underused**: adding one grep per context-reading command (catchup, review, pr) gives reviewers and future sessions architectural context for free
