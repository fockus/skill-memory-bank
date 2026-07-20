---
description: Turn a raw request plus attached documents into a validated one-page brief under briefs/<topic>/
allowed-tools: [Bash, Read, Write, AskUserQuestion]
---

# /mb brief <topic> [--request <text> | --request-file <path>] [--input <path>]… [--auto]

Formalize a raw request into a one-page brief stored with its sources, so the work
enters the pipeline already shaped: `brief → discuss → sdd → work`.

This command is deliberately NOT an interview. `/mb discuss` owns the deep
elicitation; briefing asks at most a handful of questions and only when it has to.

## When to use

At the very start, when the request is a paragraph of prose plus a pile of
documents and nobody has written down what the work actually is. Skip it when the
request is already one clear sentence — go straight to `/mb discuss`.

## Arguments

- `<topic>` — matches `[a-z0-9][a-z0-9-]*`. Anything else is `error=usage`, exit 2,
  before anything is written.
- `--request <text>` — the request inline.
- `--request-file <path>` — the request read from a file.
- `--input <path>` — repeatable; a source document to scan and copy into `inputs/`.
- `--auto` — skip the clarifying-question gate and infer on best effort.

There is no overwrite or re-publish flag in MVP. Re-formalizing is done on a new
`<topic>`, or after the user deletes `briefs/<topic>/` by hand.

## Pre-flight

Resolve the skill bundle root once and invoke **every** bundled helper through it — the working directory during `/mb brief` is the user's project, so a bare relative `scripts/mb-…` call either exits 127 or runs somebody else's script:

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}"   # memory-bank skill bundle root
[ -f "$SKILL_DIR/scripts/mb-brief.sh" ] || {
  echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

Never derive the root from `$0`: in an executable-Markdown snippet `$0` is the shell, not this file.

## Request source

Exactly one source of request text is used, and the rule is enforced before any
candidate file is written.

- Passing both `--request` and `--request-file` is `error=usage`, exit 2; when neither flag is given, the request is only the text of the user message that carried the invocation.
- A `--request` whose value has no non-whitespace character is `error=request_empty` before the candidate is written, exit 2.
- A `--request-file` that is missing, a symlink, a directory or contains `..` is `error=request_unreadable path=<p>` before the candidate is written, exit 2.
- A `--request-file` whose contents have no non-whitespace character is `error=request_empty path=<p>`, likewise before the candidate is written.

## Light questions

Read the request and every `--input` first, then decide whether anything is
genuinely unclear.

- Ask no more than five clarifying questions, and only when the essence or the goal cannot be extracted from the request and its inputs, and `--auto` was not passed, and always before generating the brief.
- Ask only about the essence and the goal — what exactly is being asked for and what impact it should have. Scope, design, sequencing and edge cases belong to `/mb discuss`; asking them here duplicates the interview.
- When the essence and the goal are clear from the request and its inputs, the question step is skipped and the brief is generated immediately.
- `--auto` always skips the question gate and requires a non-empty `assumptions_note` naming what was assumed in place of the answers.
- Without `--auto` the `assumptions_note` key must be absent; the helper refuses either mismatch with `brief=blocked reason=invalid`.

## Generation

Write the brief in full before touching the helper.

- The complete brief text — frontmatter plus all nine sections — is written to the candidate `<bank>/tmp/brief-<topic>.candidate.md` before `"$SKILL_DIR/scripts/mb-brief.sh" create` is invoked; the helper validates and publishes, and never fills a template in.
- Use the one-pager template in `references/templates.md`. Target 60–100 lines;
  over 120 the validator warns. A brief that grows into a PRD has failed at its job.
- Attachments lists every copied source as a relative link `inputs/<basename>`, in
  the order the `--input` flags were given, percent-encoded per RFC 3986
  (space → `%20`, `#` → `%23`). With no sources the section body is exactly `- None`.
- The `inputs:` frontmatter list, the Attachments links and the `--input` arguments
  must describe the same set of files; the helper refuses any divergence.

## Publication

- `"$SKILL_DIR/scripts/mb-brief.sh" create --mb <bank> --topic <topic> --candidate <path> [--input <path>]… [--auto]` is the only path that publishes a brief; writing into `briefs/` directly is forbidden, as is editing the brief after publication.
- The helper's outcomes are reported to the user verbatim and never suppressed or
  reinterpreted:
  - `brief=created path=briefs/<topic>/brief.md` — done.
  - `brief=blocked reason=secret` — a source carries a credential. Remove or redact
    it in the SOURCE, or mark the finding line with `<!-- mb-secret-ok -->`, then run
    the command again. Never copy the source by hand.
  - `brief=blocked reason=scan_unsupported` — a source cannot be inspected (binary,
    unreadable, unsupported type). Convert it, exclude it, or drop it, then run the
    command again. There is no override.
  - `brief=blocked reason=exists` — the topic already has a brief. Pick another topic.
  - `brief=blocked reason=invalid` — the candidate failed C1 or the inputs invariant.
    Fix the candidate named on the last `candidate=` line and re-run; the analysis
    does not need repeating.
- On any blocked outcome the candidate is kept at the path given by the trailing
  `candidate=` line. Reuse it rather than regenerating the brief.

## Handoff

- After a successful publish, report what was created, then offer the next stage.
- The final line of the output is exactly `/mb discuss <topic>` — nothing after it,
  so the user can run it straight from the transcript.

`/mb discuss` picks the brief up on its own: its Phase 0 reads the manifest from
`"$SKILL_DIR/scripts/mb-brief.sh" context --mb <bank> --topic <topic>`.

## Output structure

```
briefs/<topic>/
  brief.md        # frontmatter + the nine sections
  inputs/         # scanned copies of the --input sources (omitted when there are none)
```
