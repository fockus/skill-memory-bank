---
description: End session — actualize core MB files, create a note, append to progress
allowed-tools: [Bash, Read, Edit, Write, Task]
---

Canonical session-end command. `/mb done` is an alias that dispatches here.

> **Storage note.** Resolve the active bank path through `mb_resolve_path` (in `scripts/_lib.sh`). Bank may be local (`./.memory-bank/`), global (`<agent_config>/memory-bank/projects/<id>/.memory-bank/`, registered via `--storage=global`), or legacy (`.claude-workspace`). All `mb-*` scripts called below already respect the resolver — pass `--mb <resolved-path>` when needed. If `[MEMORY BANK: ABSENT]`, this command is a no-op except for surfacing the absent state.

Set `SKILL_DIR` to the absolute directory containing the loaded `SKILL.md` (or use `MB_SKILLS_ROOT`), and `MB_AGENT` to the current host id for global registry lookup. Keep cwd at the project. Include this setup in the same shell invocation as each command below.

<!-- mb-runtime:setup -->
```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:?Set SKILL_DIR from the loaded skill path}}"
source "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path)"
if [ ! -d "$BANK" ]; then
  echo "[MEMORY BANK: ABSENT]"
  exit 0
fi
BANK="$(cd "$BANK" && pwd -P)"
export MB_PATH="$BANK"
```

## 0. Mandatory done-gates (runs even without a plan)

Run the gate set first — these are mandatory whether or not a plan was active:

```bash
bash "$SKILL_DIR/scripts/mb-done-gates.sh" --mb "$BANK" --dir "$PWD"
```

It runs three independent checks in sequence (each emits a structured JSON line):

1. **Tests** — dispatches the test runner (scope=touched if a baseline commit is inferable, else scope=full). `not_applicable` (no stack detected) counts as PASS with a logged WARN.
2. **Rules (deterministic)** — `scripts/mb-rules-check.sh` on the working tree; a CRITICAL violation fails the gate.
3. **Placeholders** — `scripts/mb-rules-check.sh --placeholders-only` scans staged + uncommitted source for `TODO|FIXME|XXX|...|pseudocode`; any hit fails the gate. The deny list is configurable via `pipeline.yaml:done_placeholders.deny`.

**Exit semantics:** exit `0` only when every required gate passes. On any failure the script **exits `2`** and `/mb done` must stop — do not close the session.

**Force override** — `bash "$SKILL_DIR/scripts/mb-done-gates.sh" --mb "$BANK" --dir "$PWD" --force --reason "<one-line>"`:

- `--reason` is mandatory when forcing; the script refuses `--force` without it (non-zero exit, no mutation).
- On a forced run with failures the script appends `### NOTE: /mb done --force — gates failed: <gates>: <reason>` to `progress.md` under today's `## YYYY-MM-DD` heading (creating the heading if absent), writes the failure detail to `<bank>/tmp/done-gate-failure-<ts>.json`, then exits `0` so the close can proceed on the record.
- Config lives in `pipeline.yaml:done_gates` (`enabled`, `required`, `allow_force`). When `allow_force: false`, `--force` is rejected outright.

If gates pass (or are forced), continue with the rest of this flow.

## 0b. If work followed a plan or spec — verify first

If this session followed a plan or spec tasks, run `/mb verify <exact source path>` before proceeding. Pass the explicit session target or current run's `source_path` through the `commands/mb.md` verify resolver. A spec-only run requires verification even when `<bank>/plans/` is empty. Never select an unrelated plan by modification time. Fix CRITICAL issues; surface WARNINGs to the user.

## 1. Run MB Manager `action: done`

Invoke the MB Manager subagent (prompt: `<SKILL_DIR>/agents/mb-manager.md`) with `action: done`. Pass the full description of the current session's work, verification evidence, the exact plan/spec source, absolute `BANK`, and `SKILL_DIR`. Require all reads/writes and child commands to use that bank, with `MB_PATH` exported in each shell. A global bank remains outside the repository; never create a local shadow bank.

`action: done` is a first-class flow (documented in the prompt). The subagent runs them in order:

1. **Actualize core files** — `checklist.md` (⬜→✅ + new items), `progress.md` (APPEND-ONLY entry), plus `status.md` / `research.md` / `lessons.md` / `backlog.md` / `roadmap.md` when the session genuinely changed them.
2. **Create a note** via `bash "$SKILL_DIR/scripts/mb-note.sh" "<topic>"` with YAML frontmatter (`type`, `tags`, `importance`, `created`) + "What was done" + "New knowledge" sections.
3. **Close a plan** (if the verified source is a completed plan) via `bash "$SKILL_DIR/scripts/mb-plan-done.sh" "$VERIFIED_PLAN"` — flips `⬜→✅` in checklist, moves the file to `plans/done/`, clears the active-plan block. For a spec source, retain `specs/<topic>/tasks.md` and update its verified tasks; do not archive it as a plan or close a different plan.
4. **Compact checklist** — `bash "$SKILL_DIR/scripts/mb-checklist-prune.sh" --apply --mb "$BANK"` — folds each plan's per-stage blocks into one v2 block and moves closed plans (and fully-✅ `plans/done/`-linked sections) verbatim into `progress.md`. Enforces the cap declared in the `checklist.md` header (`MB_CHECKLIST_MAX_LINES` → `.mb-config` `checklist_max_lines=` → 100); **exit 3** means live work does not fit — pause or close plans, never trim it. Idempotent.
5. **Enforce the core-file caps** — `bash "$SKILL_DIR/scripts/mb-core-cap.sh" fix --mb "$BANK"` — composes `mb-status-rotate.sh --apply` (dated `## ` sections of `status.md` past the newest 3 → `progress.md` as `## [status archive] …`) and `mb-checklist-prune.sh --apply`, then re-checks the hard line caps (`status.md` ≤ 60, `checklist.md` ≤ 100 — AGR-043). Exit 1 = still over: dispatch MB Manager `action: actualize --strict`. Exit 3 = live plans do not fit: an owner decision (pause or close plans), never a trim. Idempotent; nothing leaves a core file before it is verified in `progress.md`.
6. **Touch `<bank>/.session-lock`** — signals the SessionEnd auto-capture hook that manual close happened.
7. **Regenerate `index.json`** via `python3 "$SKILL_DIR/scripts/mb-index-json.py" "$BANK"`.
8. **Auto-commit `.memory-bank/` (opt-in)** — `bash "$SKILL_DIR/scripts/mb-auto-commit.sh" --mb "$BANK"` — runs only when `MB_AUTO_COMMIT=1` is set in the environment. Refuses to commit when source files outside `.memory-bank/` are dirty, during rebase/merge/cherry-pick, or on detached HEAD. Subject derives from the last `### ` heading in `progress.md`. Never pushes — push is an explicit user action. The complementary drift alarm is `mb-freshness.sh` (Stop nudge + SessionStart banner): it is what tells you the bank fell behind when `MB_AUTO_COMMIT` is *not* enabled and you skipped `/mb done`.
9. **Report** — list which files changed, note path, plan closure, prune verdict, index regen, session-lock touch, auto-commit SHA (when committed).

Conflict resolution (also in the prompt): trust `mb-metrics.sh --run` over `status.md` metrics; trust `checklist.md` over closed plans in `plans/done/`; `progress.md` is APPEND-ONLY; trust active plan file over `roadmap.md` focus line; trust `experiments/EXP-NNN.md` over `research.md` status.

## 2. Report

Return a compact summary:

- Files updated (checklist / progress / STATUS / RESEARCH / lessons / BACKLOG as applicable)
- Note path + frontmatter summary (type, tags, importance)
- Plan closure (which plan moved to `done/`, if any)
- `index.json` regeneration confirmation
- `.session-lock` touched

## Lightweight mode (without MB Manager)

If the user wants a quick close without subagent overhead — for trivial sessions with no plan, no metrics changes, and no architectural output — a minimal flow is acceptable:

1. Update `checklist.md` directly — flip completed items
2. Append a short `progress.md` entry
3. `touch "$BANK/.session-lock"`

For anything non-trivial, default to the MB Manager flow above.
