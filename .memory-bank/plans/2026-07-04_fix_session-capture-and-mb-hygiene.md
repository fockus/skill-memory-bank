---
type: fix
scope: session-capture-and-mb-hygiene
created: 2026-07-04
status: queued
priority: HIGH
backlog: I-087
---

# Fix: Session-capture correctness + Memory-Bank drift hygiene

Closes the session-memory and MB-drift findings from the 2026-07-04 cross-project audit
(taskloom + swarmline), tracked as backlog **I-087**. Three tracks:

- **Track A — Session-capture correctness** (the capture pipeline writes corrupt/bloated
  session files: bullets land after `## Summary`, no length caps, service messages logged
  as turns). HIGH bugs first.
- **Track B — Drift & enforcement** (nothing keeps `.memory-bank/` in step with code commits;
  checklist/status rot; memsearch double-summarizes per turn).
- **Track C — One-off project remediation** (repair the two bloated session files, commit the
  dangling MB tails, prune/actualize taskloom + swarmline, remove stray project dirs).

All findings below were **confirmed against the current code at the cited lines on 2026-07-04**.
Live metrics were re-measured and may differ in magnitude from the audit snapshot (state moved
on); the fixes are deterministic and act on live state, so exact counts are informational.

## Goal

Make session capture produce **one bounded, well-formed `## Live log` per session** (no writes
after `## Summary`, hard caps on every field, no non-human turns), make MB drift **loud and
actionable** (a deterministic freshness check + documented auto-commit recipe + a checklist
auto-prune path), and **repair the existing damage** in taskloom and swarmline. After this work,
resumed sessions are re-summarized correctly, session files stay small enough for `/mb recall`
and the semantic index to stay useful, and a fresh agent reading `.memory-bank/` sees the true
project state.

## Constraints (apply by construction)

- **TDD-first**: every stage writes the failing test FIRST (bats under `hooks/tests/` or
  `tests/bats/`; pytest under `tests/pytest/` — mirror `tests/pytest/test_checklist_cap.py`),
  proving the bug, then the fix turns it green. No fix commit without a preceding red test.
- **Fail-safe hooks**: ANY error (missing dep, unresolved bank, bad stdin, git failure) → the
  hook prints `{}`/nothing and `exit 0`. A capture/drift hook must **never wedge or block a
  session**. This is the RULES.md "hooks fail open" invariant.
- **Design contract (token economy)**: defaults stay token-economical; expensive paths stay
  opt-in; **no default behaviour change is introduced without an opt-out env var**. Where a fix
  materially changes capture behaviour, ship a documented `MB_*` toggle mirroring the existing
  pattern (`MB_SESSION_CAPTURE`, `MB_SESSION_CHEATSHEET`, `MB_SESSION_STUB_GUARD`). The observable
  bullet format `- HH:MM — User: "…" · tools: … · files: … · <ok|err(N)>[ · +A/-B]` is a **public
  contract** consumed by downstream parsers — keep it byte-stable.
- **Dual-shell**: every changed script runs on bash 3.2 (macOS `/bin/bash`) AND bash 5.x (Linux).
  No `mapfile`, no `declare -A` in hot paths, no `${var^^}`; prefer `case`/`printf`/`awk`.
- **File budget**: no file exceeds 400 lines after the change; extract shared helpers into
  `hooks/lib/session-common.sh` rather than inlining. Reuse existing primitives: `sc_fm_get`
  / `sc_fm_set` (`hooks/lib/session-common.sh:45/67`), `sc_lock`/`sc_unlock` (`:96/119`),
  `sc_redact_secrets` (`:135`), `sc_build_summary_src` (`:160`), `mb_resolve_path`
  (`scripts/_lib.sh`).
- **No placeholders**: copy-paste-ready code, no TODO/`...`.
- **Static analysis**: `shellcheck` clean on every changed shell file; `ruff`/`black` clean on
  any touched python.

## Track ordering

HIGH capture bugs (A1, A2) first → MED capture (A3, A4, A7) → LOW capture (A5, A6) → drift &
enforcement (B1–B4, parallel) → one-off ops (C1, C2). **Track C consumes A7's repair tool and
should land after Track A** so repaired files are not immediately re-bloated by the old pipeline.

---

## Track A — Session-capture correctness

### Stage A1 — Stop appending bullets after `## Summary`; re-summarize resumed sessions (HIGH, bug 1)

**Complexity:** M · **~5 min** · **Zavisimosti:** — · **Agent:** developer (+ tester for red)
**Files:** `hooks/mb-session-turn.sh` (edit), `hooks/lib/session-common.sh` (add helper),
`hooks/tests/session-turn.bats` (extend, tests FIRST)

**Confirmed:** `hooks/mb-session-turn.sh:133` does
`printf -- '%s\n' "$bullet" | sc_redact_secrets >> "$SF"` — an unconditional append to the **end**
of the file, ignoring frontmatter `summarized`. When a session is resumed under the same
`session_id`, `mb-session-summarize.sh` has already appended a `## Summary` section, so new
bullets land **after** `## Summary`. `sc_build_summary_src` (`hooks/lib/session-common.sh:166-173`)
reads only the `## Live log` section and stops at the next `## ` heading, so those post-Summary
bullets are **invisible to any re-summary**; and `summarized:true` (`mb-session-end.sh:42`,
`mb-session-catchup.sh:72`) permanently blocks rebuild. Observed live: taskloom
`session/2026-06-22_2308_b4acaf96.md` = 137.9 KB, `## Live log` at line 13, `## Summary` at line
16, **358 bullets after Summary**, `summarized:true` — the Summary describes only turn 1.

**Design decision (chosen):** insert each new bullet **inside the `## Live log` section, before
`## Summary`** (append-to-end when no `## Summary` exists — the common fresh-session path is
unchanged), and when a bullet is added to an already-summarized file, **reset `summarized=false`**
(leave `judged` untouched) so the SessionStart lazy catch-up (`mb-session-catchup.sh`) rebuilds
the summary from the full Live log. Rationale vs. the alternative (append-only + a separate
"delta summary"): the Live-log-is-source-of-truth invariant already exists in
`sc_build_summary_src`; keeping all bullets in one contiguous Live log preserves that single
source of truth and needs no new summary-merge logic. Cost is bounded: **+1 Haiku re-summary per
resumed session**, and only via catch-up which is already capped at `MB_CATCHUP_MAX=2` per
session start. `judged` is deliberately not reset (avoids re-spending Sonnet).

- **Add helper** `sc_livelog_append <file> <text>` to `hooks/lib/session-common.sh`: if the file
  contains a `## Summary` (or any `## ` heading after `## Live log`), splice `<text>` in
  immediately **before** the first such heading via `awk` (bash-3.2 safe, atomic temp→mv, mirror
  `sc_fm_set`); otherwise append to EOF. `<text>` arrives already redacted by the caller.
- **Test FIRST** `hooks/tests/session-turn.bats` (new cases):
  - `test_turn_bullet_inserted_before_summary_when_summarized` — seed `$SF` with frontmatter
    `summarized: true`, a `## Live log` bullet, then `## Summary\n(text)`; fire the Stop hook for a
    new turn; assert the new bullet appears **before** the `## Summary` line and NOT after EOF.
  - `test_turn_resets_summarized_false_on_resumed_session` — same seed; after the hook assert
    frontmatter `summarized` is `false` and `judged` is **unchanged**.
  - `test_turn_fresh_session_still_appends_to_livelog` (regression) — no `## Summary` present →
    bullet count logic identical to today (`grep -c '^- '` increments by 1; `turns` bumped).
- **Fix** `hooks/mb-session-turn.sh:130-139`: build `bullet`, redact, then
  `sc_livelog_append "$SF" "$redacted_bullet"` (replace the `>> "$SF"` append). After the write,
  if `sc_fm_get "$SF" summarized` = `true`, call `sc_fm_set "$SF" summarized false`. Keep the
  dedup guard (`:123`) and `turns`/`last_turn` bumps.

**DoD:**
- [ ] New bullets on an already-summarized session land inside `## Live log`, never after `## Summary`.
- [ ] `summarized` flips to `false` on resumed append; `judged` untouched.
- [ ] Fresh-session append path byte-identical to prior behaviour (regression green).
- [ ] Tests: 3 new bats + existing `session-turn.bats` green; `shellcheck` clean; file ≤400 lines.

**Verification:**
```bash
cd /Users/fockus/Apps/skill-memory-bank
PATH="$PWD/.venv/bin:$PATH" bats hooks/tests/session-turn.bats
shellcheck hooks/mb-session-turn.sh hooks/lib/session-common.sh
```
**Edge cases:** file with multiple `## ` headings after Live log (splice before the FIRST);
`## Live log` present but empty; `summarized` key absent (treat as not-summarized, append to EOF).

---

### Stage A2 — Hard caps on bullet length and file list (HIGH, bug 2)

**Complexity:** S · **~4 min** · **Zavisimosti:** — · **Agent:** developer (+ tester)
**Files:** `hooks/mb-session-turn.sh` (edit), `hooks/tests/session-turn.bats` (extend, FIRST)

**Confirmed:** the bullet has no length cap. `files` is a comma-join of every touched
`file_path` (`extract-tools-files.sh:100-104`) with no count/length limit; a single turn produced
a **2348-char bullet listing ~25 absolute paths**. Combined with A1's runaway append this is what
grew the 137.9 KB file.

- **Cap the file list**: after `files` is read (`hooks/mb-session-turn.sh:59-63`), keep the first
  `MB_SESSION_MAX_FILES` (default **12**) comma-separated entries; if more, append ` +K more`
  (K = remainder). Basename-only is out of scope (keep paths for the parser contract); just cap
  count. Implement with `awk -F,` (bash-3.2 safe).
- **Cap the whole bullet**: after building `bullet` (`:130-132`), if its length exceeds
  `MB_SESSION_BULLET_MAX` (default **600**), truncate to the cap and append `…`. Preserve the
  leading `- HH:MM — User: "` prefix so the parser contract still matches.
- **Test FIRST** `hooks/tests/session-turn.bats`:
  - `test_turn_files_list_capped_with_more_suffix` — a fixture turn touching 25 files → bullet
    `files:` segment lists ≤12 entries and ends with ` +13 more`.
  - `test_turn_bullet_truncated_to_cap` — a very long user prompt fixture → bullet length
    ≤`MB_SESSION_BULLET_MAX` and ends with `…`; still starts with `- ` and `User: "`.
  - `test_turn_caps_are_opt_out` — set `MB_SESSION_MAX_FILES=999 MB_SESSION_BULLET_MAX=99999` →
    no truncation (opt-out honoured).

**DoD:**
- [ ] `files:` segment ≤`MB_SESSION_MAX_FILES` entries + accurate `+K more`.
- [ ] Bullet length ≤`MB_SESSION_BULLET_MAX`, ends with `…` on truncation, prefix intact.
- [ ] Both caps opt-out via env; defaults 12 / 600.
- [ ] Tests: 3 new bats green; `shellcheck` clean.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats hooks/tests/session-turn.bats
shellcheck hooks/mb-session-turn.sh
```
**Edge cases:** exactly `MB_SESSION_MAX_FILES` files (no `+K more`); `files=(none)` untouched;
multibyte prompt truncation (cut on bytes is acceptable — mark in comment; `sc_redact_secrets`
runs before length check so `[REDACTED]` is never split).

---

### Stage A3 — Raise user-prompt cap + ellipsis (MED, bug 3)

**Complexity:** S · **~3 min** · **Zavisimosti:** A2 (bullet cap compensates the larger prompt)
**Agent:** developer (+ tester)
**Files:** `hooks/lib/extract-tools-files.sh` (edit), `hooks/tests/session-turn.bats` or new
`hooks/tests/extract-tools-files.bats` (FIRST)

**Confirmed:** `hooks/lib/extract-tools-files.sh:70`
`user_text = " ".join((text_of(recs[last_user]) or "").split())[:200]` truncates the prompt to
**200 chars with no ellipsis**. Downstream Haiku summaries then report "user request was
truncated" and the Decisions section is often "(none)" although the full prompt is intact in the
jsonl — a pipeline defect, not a model defect.

- **Fix** `extract-tools-files.sh:67-71`: cap at `MB_SESSION_USER_MAX` (default **1000**) chars;
  when truncated, append `…` (single char). Read the env inside the python block via
  `os.environ.get("MB_SESSION_USER_MAX", "1000")` (pass it through — the script already runs
  under the hook's env).
- **Test FIRST** `hooks/tests/extract-tools-files.bats`:
  - `test_extract_user_capped_at_1000_with_ellipsis` — transcript with a 5000-char user text →
    `user=` line length ≤1001 and ends with `…`.
  - `test_extract_user_under_cap_unchanged` — short prompt → no `…`, exact text.
  - `test_extract_user_cap_env_override` — `MB_SESSION_USER_MAX=50` → cap honoured.

**DoD:**
- [ ] User text capped at `MB_SESSION_USER_MAX` (default 1000) with trailing `…` on truncation.
- [ ] Env override honoured; short prompts unchanged (no ellipsis).
- [ ] Compensated by A2 bullet cap so total bullet stays bounded.
- [ ] Tests: 3 new bats green; `ruff`/parse clean on the embedded python.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats hooks/tests/extract-tools-files.bats
shellcheck hooks/lib/extract-tools-files.sh
```
**Edge cases:** prompt exactly 1000 chars (no ellipsis); prompt with only whitespace (already
`None` → skipped by `text_of`).

---

### Stage A4 — Filter non-human user messages (MED, bug 4)

**Complexity:** M · **~5 min** · **Zavisimosti:** — · **Agent:** developer (+ tester)
**Files:** `hooks/lib/extract-tools-files.sh` (edit), `hooks/tests/extract-tools-files.bats`
(extend, FIRST), fixture `hooks/tests/fixtures/transcript-task-notification.jsonl` (new)

**Confirmed:** `text_of` (`extract-tools-files.sh:48-60`) accepts any `type=="user"` non-`isMeta`
record with text content as a "real" user turn. Service payloads like
`<task-notification>…</task-notification>`, `<system-reminder>…`, `<command-name>…`,
`<local-command-stdout>…` are logged as turns. In the swarmline 106.4 KB file ~99% of turns are
this machine noise.

- **Fix** `extract-tools-files.sh` `text_of()`: after extracting the joined text, if the whole
  message (stripped) is wholly wrapped in one of the known non-human tags
  (`task-notification`, `system-reminder`, `command-name`, `command-message`,
  `local-command-stdout`, `command-args`) → return `None` (not a real turn). Detect via a small
  regex list; keep it conservative (whole-message wrappers only, so a human prompt that merely
  *mentions* `<system-reminder>` is not dropped). Also strip a leading
  `<command-name>…</command-name>` / `<local-command-stdout>…` prefix from otherwise-human text
  before the length cap.
- **Test FIRST** `hooks/tests/extract-tools-files.bats`:
  - `test_extract_skips_pure_task_notification_turn` — transcript whose last user record is
    `<task-notification>…</task-notification>` → `turn=`/`user=` fall back to the previous REAL
    user message, not the notification.
  - `test_extract_skips_system_reminder_only` — last user record is a bare `<system-reminder>` →
    skipped.
  - `test_extract_keeps_human_text_that_mentions_tag` — human prompt containing the literal word
    `system-reminder` in prose is kept (not dropped).

**DoD:**
- [ ] Whole-message service wrappers are not counted as turns (no bullet, dedup anchor points to
      the last REAL user message).
- [ ] Human prompts that merely mention a tag are preserved.
- [ ] Leading command-wrapper prefixes stripped from human text.
- [ ] Tests: 3 new bats + 1 fixture; embedded python parses clean.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats hooks/tests/extract-tools-files.bats
shellcheck hooks/lib/extract-tools-files.sh
```
**Edge cases:** a turn that is ONLY service messages (no prior human turn) → `user=` empty, and
A-track stub-guard (`mb-session-turn.sh:70`) already suppresses a contentless first-turn file.

---

### Stage A5 — Hard-cap `_recent.md` injection (LOW, bug 6)

**Complexity:** S · **~3 min** · **Zavisimosti:** — · **Agent:** developer (+ tester)
**Files:** `hooks/mb-session-start.sh` (edit), `hooks/tests/session-start-context.bats` (new or
extend, FIRST)

**Confirmed:** `hooks/mb-session-start.sh:18` `content="$(cat "$RECENT")"` and `:31`
`recent_block="$(printf '# Recent Sessions\n\n%s' "$content")"` inject `session/_recent.md` into
the model context with no hard cap. A bloated `_recent.md` silently inflates every session start.

- **Fix** `mb-session-start.sh:18`: cap `content` to the first `MB_RECENT_MAX_BYTES` (default
  **4000**) bytes; if truncated, append a `\n…[recent truncated]…` marker. Use `head -c` (bash-3.2
  safe). Opt-out with a large value.
- **Test FIRST** `hooks/tests/session-start-context.bats`:
  - `test_recent_injection_capped` — a 20 KB `_recent.md` → emitted `additionalContext` ≤ cap +
    small header and contains the truncation marker.
  - `test_recent_injection_small_unchanged` — a 200-byte `_recent.md` → injected verbatim, no marker.

**DoD:**
- [ ] `_recent.md` injection ≤`MB_RECENT_MAX_BYTES` (default 4000) + marker on truncation.
- [ ] Small files unchanged; hook still emits valid `SessionStart` JSON; fail-safe on missing jq.
- [ ] Tests: 2 new bats green; `shellcheck` clean.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats hooks/tests/session-start-context.bats
shellcheck hooks/mb-session-start.sh
```
**Edge cases:** empty `_recent.md` (existing early-exit at `:19` untouched); cap boundary exactly
at a UTF-8 char (acceptable; marker still appended).

---

### Stage A6 — Lower summarizer input-window default (LOW, bug 7)

**Complexity:** S · **~2 min** · **Zavisimosti:** — · **Agent:** developer (+ tester)
**Files:** `hooks/lib/session-common.sh` (edit), `hooks/tests/session-summarize.bats` (extend, FIRST)

**Confirmed:** `hooks/lib/session-common.sh:162`
`local MAX_CHARS="${MB_SUMMARY_MAX_CHARS:-200000}"` — the raw-transcript fallback feeds up to
**200 000 chars (~50K Haiku tokens)** to the summarizer. After A1–A4 the Live log is the primary
source and small; the 200K window only matters for the contentless-Live-log fallback, where it is
now oversized.

- **Fix** `session-common.sh:162`: lower the default to **60000** (`~15K tokens`). Keep the env
  override so anyone can restore 200000 explicitly (opt-in for the old behaviour).
- **Test FIRST** `hooks/tests/session-summarize.bats`:
  - `test_summary_src_default_window_60k` — with `MB_SUMMARY_MAX_CHARS` unset and an
    over-window transcript fallback, assert the SRC length ≤60000 and contains the existing
    `…[transcript truncated for summary]…` marker.
  - `test_summary_src_env_override_restores_200k` — `MB_SUMMARY_MAX_CHARS=200000` → old cap honoured.

**DoD:**
- [ ] Default `MB_SUMMARY_MAX_CHARS` = 60000; env override restores any value.
- [ ] Live-log path (primary) unaffected; only the raw-transcript fallback shrinks.
- [ ] Tests: 2 new/updated bats green; `shellcheck` clean.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats hooks/tests/session-summarize.bats
shellcheck hooks/lib/session-common.sh
```
**Edge cases:** existing summarize/judge tests that assert on the 200K default must be updated to
the new default or set the env explicitly (grep `MB_SUMMARY_MAX_CHARS` in `hooks/tests/` first).

---

### Stage A7 — Session-file bloat prune threshold + repair tool (MED, bug 5)

**Complexity:** L · **~5 min** · **Zavisimosti:** A1 (repair reuses the Live-log splice invariant)
**Agent:** developer (+ tester)
**Files:** `scripts/mb-session-repair.sh` (new), `scripts/mb-session-prune.sh` (edit),
`tests/bats/test_compact_sessions.bats` (extend, FIRST) or new `tests/bats/test_session_repair.bats`

**Confirmed:** `scripts/mb-session-prune.sh:51`
`if grep -qE 'User: "[^"]|tools: [A-Za-z]' "$f"` treats any file with substantive content as
"kept" and only archives contentless stubs — there is **no byte threshold**, so the 137.9 KB /
106.4 KB bloated files are never touched. A dedicated repair path is needed for files already
corrupted by the A1 bug.

- **New** `scripts/mb-session-repair.sh <session_file>` (idempotent, dry-run default, `--apply`):
  1. write a verbatim backup to `session/archive/pre-repair/<basename>.<ts>`;
  2. move every `- HH:MM — …` bullet that sits **after** `## Summary` back into `## Live log`
     (preserving order), leaving a single `## Summary` (or none) after Live log — reuse the A1
     `awk` splice logic (factor the shared awk into `sc_livelog_append` or a sibling helper so
     repair and the hook share one implementation — DRY);
  3. set frontmatter `summarized=false` (so catch-up rebuilds), leave `judged` as-is;
  4. re-cap over-long bullets to `MB_SESSION_BULLET_MAX` (parity with A2).
  Fail-safe: unresolved bank / missing file → message + exit 0.
- **Edit** `scripts/mb-session-prune.sh`: add a byte-threshold branch — files larger than
  `MB_SESSION_BLOAT_BYTES` (default **40000**) that also contain bullets after `## Summary` are
  reported as **repair candidates** (dry-run) and, on `--apply`, routed through
  `mb-session-repair.sh --apply`. Keep the existing stub-archival behaviour unchanged and default
  to dry-run.
- **Test FIRST** `tests/bats/test_session_repair.bats`:
  - `test_repair_moves_post_summary_bullets_into_livelog` — seed a file with 3 bullets after
    `## Summary`; after `--apply` all 3 are inside `## Live log` (before `## Summary`) and none
    remain after it; a `pre-repair` backup exists.
  - `test_repair_resets_summarized_false_keeps_judged` — assert `summarized:false`, `judged` unchanged.
  - `test_repair_is_idempotent` — second `--apply` makes no further change (byte-identical).
  - `test_prune_flags_bloated_file_over_threshold` — a 60 KB file with post-Summary bullets is
    listed as a repair candidate; a 5 KB clean file is not.

**DoD:**
- [ ] `mb-session-repair.sh` moves post-Summary bullets into Live log, resets `summarized=false`,
      backs up the original, re-caps bullets, is idempotent, and is dry-run by default.
- [ ] `mb-session-prune.sh` flags files >`MB_SESSION_BLOAT_BYTES` with post-Summary bullets and
      repairs them on `--apply`; stub-archival path unchanged.
- [ ] Tests: 4 new bats green; `shellcheck` clean; both scripts ≤400 lines; new script has +x bit.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_session_repair.bats tests/bats/test_compact_sessions.bats
shellcheck scripts/mb-session-repair.sh scripts/mb-session-prune.sh
test -x scripts/mb-session-repair.sh
```
**Edge cases:** file with NO `## Summary` (repair is a no-op, exit 0); multiple `## ` sections
after Summary (`## Auto-notes emitted` must be preserved as its own section, only `- ` bullets
moved); untracked session files (backup, never `rm`).

---

## Track B — Drift & enforcement

### Stage B1 — Deterministic MB-vs-code freshness check + surfacing (bug 8a)

**Complexity:** L · **~5 min** · **Zavisimosti:** — · **Agent:** developer (+ tester)
**Files:** `scripts/mb-freshness.sh` (new), `hooks/mb-session-start.sh` (edit — banner),
`settings/hooks.json` (edit — Stop nudge), adapter settings mirrors (see below),
`tests/bats/test_mb_freshness.bats` (new, FIRST)

**Confirmed:** no hook compares MB freshness to code. `MB_AUTO_COMMIT`
(`scripts/mb-auto-commit.sh:59`) is opt-in and wired nowhere; `session-end-autosave.sh:95-100`
appends only a placeholder to `progress.md`; the Stop nudge (`settings/hooks.json:119`) prints an
**unconditional** "run /mb done" recommendation every turn (noise, no specifics). Live taskloom:
last MB-touching commit `ddf9540`, HEAD `ff3381a`, **4 commits behind**, 7 dirty numstat + 9
untracked porcelain entries under `.memory-bank/` (audit snapshot observed 11 behind / 404 dirty
insertions; the check acts on live state).

- **New** `scripts/mb-freshness.sh [--porcelain] [--stop-nudge] [--banner] [mb_path]`
  (deterministic, always exit 0, fail-safe):
  - resolve repo root + bank; compute `behind` =
    `git rev-list --count "$(git log -1 --format=%H -- <bank>)"..HEAD`, and `dirty` =
    (numstat lines + untracked porcelain lines) under the bank prefix;
  - `--porcelain` prints `behind=<N> dirty=<M>`; default prints a human report;
  - `--stop-nudge` prints the nudge **only when** `behind >= MB_DRIFT_WARN_COMMITS` (default **5**)
    OR `dirty >= MB_DRIFT_WARN_DIRTY_LINES` (default **50**), with the concrete numbers and the
    exact remediation command (`bash scripts/mb-auto-commit.sh --force` or `/mb done`); silent when fresh;
  - `--banner` emits a one-line `# Memory Bank freshness` block for SessionStart injection under
    the same thresholds; empty when fresh.
  - Not inside a git repo / no bank / git failure → prints nothing, exit 0.
- **Wire (model-visible, token-economical)** `hooks/mb-session-start.sh`: when
  `MB_FRESHNESS_BANNER` != `off` (default on), prepend `mb-freshness.sh --banner` output to the
  injected `ctx` (once per session, only when over threshold — mirrors the existing
  `MB_SESSION_CHEATSHEET` opt-out pattern, so the default-on banner is contract-consistent).
- **Wire (human-facing, net noise reduction)** `settings/hooks.json` Stop block: replace the
  unconditional recommendation echo (`:119`) with
  `~/.claude/hooks/mb-freshness.sh --stop-nudge # [memory-bank-skill]` — silent when fresh, so the
  default becomes *quieter*, not noisier. Update the adapter settings mirrors that ship the same
  Stop block (`grep -rl 'Recommendation: /mb done' settings/ adapters/ install.sh .cursor/`), and
  keep the change fail-safe (script exits 0 on any error).
- **Test FIRST** `tests/bats/test_mb_freshness.bats` (mirror the temp-repo pattern of
  `tests/bats/test_drift_plan_vs_git.bats`):
  - `test_freshness_reports_commits_behind` — commit code twice after the last MB commit →
    `--porcelain` prints `behind=2`.
  - `test_freshness_counts_dirty_bank_lines` — dirty + untracked files under `.memory-bank/` →
    `dirty>=` expected count.
  - `test_stop_nudge_silent_when_fresh` — bank committed at HEAD, clean → `--stop-nudge` prints nothing.
  - `test_stop_nudge_fires_over_threshold` — `MB_DRIFT_WARN_COMMITS=1` with 2 behind → nudge printed
    WITH the number and the remediation command.
  - `test_freshness_fail_safe_outside_repo` — run in a non-git dir → exit 0, no output.

**DoD:**
- [ ] `mb-freshness.sh` computes `behind`/`dirty` deterministically, exit 0 always, fail-safe outside git.
- [ ] `--stop-nudge` silent when fresh, specific (numbers + command) when over threshold.
- [ ] SessionStart banner default-on, opt-out `MB_FRESHNESS_BANNER=off`, empty when fresh.
- [ ] `settings/hooks.json` + adapter mirrors updated; the always-on echo is gone.
- [ ] Tests: 5 new bats green; `shellcheck` clean; new script +x.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_freshness.bats
shellcheck scripts/mb-freshness.sh hooks/mb-session-start.sh
python3 -c 'import json,sys; json.load(open("settings/hooks.json"))'  # settings still valid JSON
grep -rl 'Recommendation: /mb done' settings/ adapters/ install.sh .cursor/ || echo "no stale echo left"
```
**Edge cases:** bank never committed (`git log -- <bank>` empty → treat `behind` as total commit
count, still deterministic); detached HEAD (report behind=unknown, no crash); shallow clone.

---

### Stage B2 — Document MB auto-commit + governed-pipeline actualization recipe (bug 8b)

**Complexity:** S · **~4 min** · **Zavisimosti:** B1 (recipe references the freshness check)
**Agent:** developer (docs)
**Files:** `SKILL.md` (edit), `references/session-memory.md` or `docs/concepts/session-memory.md`
(edit), `commands/done.md` (edit), `tests/pytest/test_docs_consistency*.py` or a focused doc test (FIRST)

**Confirmed:** `MB_AUTO_COMMIT` exists and is safe (gated, MB-only staging, never pushes,
`scripts/mb-auto-commit.sh`) but is documented nowhere as a recipe; governed `/mb work` stage
commits do not actualize MB.

- **Document** in SKILL.md + session-memory doc:
  - the exact enable recipe: `export MB_AUTO_COMMIT=1` (or per-invocation
    `bash scripts/mb-auto-commit.sh --force`) — semantics: commits ONLY `.memory-bank/`, skips when
    source is dirty / mid-rebase / detached HEAD, never pushes;
  - a `/mb done` note that it already calls the auto-commit path, and that `mb-freshness.sh`
    (B1) is the drift alarm;
  - a `pipeline.yaml` recipe fragment showing how a governed `/mb work` run can append an MB
    actualization + `mb-auto-commit.sh --force` step so stage commits carry the checklist/STATUS update.
- **Test FIRST** a focused doc test (mirror `tests/pytest/test_changelog_no_orphan_section.py`
  style): assert SKILL.md mentions `MB_AUTO_COMMIT` and the session-memory doc references
  `mb-freshness.sh`, so the recipe cannot silently drift out of the docs.

**DoD:**
- [ ] SKILL.md + session-memory doc contain the copy-paste `MB_AUTO_COMMIT` recipe and the
      `mb-freshness.sh` reference.
- [ ] `commands/done.md` notes the auto-commit + freshness relationship.
- [ ] pipeline.yaml actualization fragment is copy-paste ready.
- [ ] Doc test green; no unavailable commands referenced.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/ -k 'docs or changelog or skill' -q
grep -n 'MB_AUTO_COMMIT' SKILL.md
```
**Edge cases:** keep docs consistent across `SKILL.md`, `commands/`, adapter guidance (RULES.md
Documentation Rules) — grep for other mentions before editing.

---

### Stage B3 — Checklist auto-prune hook + "checklist = TODO only" rule (bug 9)

**Complexity:** M · **~5 min** · **Zavisimosti:** — · **Agent:** developer (+ tester)
**Files:** `hooks/session-end-autosave.sh` (edit — add gated autoprune) OR new
`hooks/mb-checklist-autoprune.sh` + `settings/hooks.json` SessionEnd wiring, `SKILL.md` /
templates (edit — rule), `tests/bats/test_compact_checklist.bats` (extend, FIRST)

**Confirmed:** `scripts/mb-checklist-prune.sh:26` hard-cap = 120 lines but `:188` only **warns**;
it is invoked solely from `/mb done` / `mb-plan-done` / `mb-compact`. Live: taskloom checklist
**901 lines**, swarmline **680** (repo skill's own checklist is 216 → also over the 120 cap that
`tests/pytest/test_checklist_cap.py` asserts). The checklist duplicates progress (commit hashes,
test counts).

- **Add a gated SessionEnd autoprune** (new `hooks/mb-checklist-autoprune.sh`, registered in
  `settings/hooks.json` SessionEnd, OR appended to `session-end-autosave.sh`): when
  `MB_CHECKLIST_AUTOPRUNE=on` (**default off** — honours the "no default behaviour change without
  opt-in" contract; the collapse mutates user data, so it stays opt-in even though it is
  non-destructive: it only collapses completed `plans/done`-linked sections and writes a `.bak`)
  AND `checklist.md` exceeds the 120-line cap, run
  `mb-checklist-prune.sh --apply` under a lock, fail-safe (any error → exit 0). Never runs while
  `MB_CHECKLIST_AUTOPRUNE` is unset.
- **Add the rule** to SKILL.md + the checklist template: *"checklist.md = open TODO only;
  execution detail (commit hashes, test counts, closeouts) goes to progress.md. Completed sections
  collapse to a one-line `plans/done` link."*
- **Test FIRST** `tests/bats/test_compact_checklist.bats`:
  - `test_autoprune_runs_when_enabled_and_over_cap` — `MB_CHECKLIST_AUTOPRUNE=on`, a 200-line
    checklist with collapsible done sections → after the hook the file is collapsed and a `.bak` exists.
  - `test_autoprune_noop_when_disabled` — env unset → file untouched (default behaviour preserved).
  - `test_autoprune_noop_under_cap` — enabled but ≤120 lines → no change.
  - `test_autoprune_fail_safe_on_missing_checklist` — no checklist → exit 0, no error.

**DoD:**
- [ ] Autoprune runs only when `MB_CHECKLIST_AUTOPRUNE=on` AND over the 120-line cap; default off.
- [ ] Runs under a lock, fail-safe, writes a `.bak`, and only collapses `plans/done`-linked sections.
- [ ] SKILL.md + checklist template carry the "TODO-only" rule.
- [ ] Tests: 4 new bats green; `shellcheck` clean; `settings/hooks.json` valid JSON.

**Verification:**
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_compact_checklist.bats
shellcheck hooks/mb-checklist-autoprune.sh 2>/dev/null || shellcheck hooks/session-end-autosave.sh
python3 -c 'import json; json.load(open("settings/hooks.json"))'
```
**Edge cases:** concurrent SessionEnd (lock prevents double-apply); protected `## ⏳ In flight` /
`## ⏭ Next planned` blocks are never collapsed (already handled by the prune script).

---

### Stage B4 — Disable memsearch per-turn summarize (bug 10, config + doc)

**Complexity:** S · **~2 min** · **Zavisimosti:** — · **Agent:** developer (ops + docs)
**Files:** `~/.memsearch/config.toml` (ops edit — user config, NOT a repo file),
`references/session-memory.md` or memory-stack decision doc (edit)

**Confirmed (decision):** memory-stack decision is "MB primary, memsearch secondary". memsearch's
Stop-hook calls Haiku on **every turn** (`summarize.enabled=true` in `~/.memsearch/config.toml`),
duplicating MB's per-session Haiku spend.

- **Ops**: set `summarize.enabled = false` under `[summarize]` (or the equivalent key — verify the
  live schema with `grep -n summarize ~/.memsearch/config.toml` first) in
  `~/.memsearch/config.toml`; leave memsearch **search** enabled. This is a user config edit, not a
  protected repo file (`.env`/CI/Docker patterns do not apply).
- **Doc**: record the rationale in the repo's memory-stack/session-memory reference so the decision
  is discoverable ("MB owns per-session summaries; memsearch is search-only to avoid duplicate
  Haiku spend").

**DoD:**
- [ ] `~/.memsearch/config.toml` has memsearch summarize disabled; search still works
      (`memsearch` query returns results after the change).
- [ ] Repo doc records the "MB primary / memsearch search-only" decision.
- [ ] No repo test regressions (config change is external; doc test green if one exists).

**Verification:**
```bash
grep -n 'summarize' ~/.memsearch/config.toml
# after edit: run a memsearch query to confirm search still returns results
```
**Edge cases:** memsearch not installed (skip the ops edit, still land the doc); key name differs
across memsearch versions (verify before editing — do not guess).

---

## Track C — One-off project remediation (ops)

> Ops stages operate on OTHER repos (`/Users/fockus/Apps/taskloom`,
> `/Users/fockus/Apps/swarmline`). They consume **A7's repair tool** and the fixed pipeline
> (A1–A4). Each MB commit follows the git policy: MB-only staging, honest message, never push.

### Stage C1 — taskloom remediation

**Complexity:** M · **~5 min** · **Zavisimosti:** A1, A2, A7 · **Agent:** developer (ops)
**Files (taskloom repo):** `.memory-bank/checklist.md`, `.memory-bank/progress.md`,
`.memory-bank/session/2026-06-22_2308_b4acaf96.md`; stray dirs under `~/.claude/projects/`

**Confirmed:** taskloom is 4 commits behind the last MB-touching commit with dirty+untracked MB
entries (audit snapshot: 11 behind / 404 dirty insertions); the closed stage **E7 / AUD-06a**
still shows ⬜ in the checklist; the 137.9 KB bloated session file; stray empty project dir
`~/.claude/projects/-Users-fockus-Apps-taskloom--memory-bank-specs` (0 jsonl).

- Repair the bloated session file: `bash scripts/mb-session-repair.sh --apply <137KB file>` (from
  the skill repo, targeting taskloom's bank), verify it shrinks and `summarized:false`.
- Actualize `E7 / AUD-06a`: flip its checklist item to ✅ and append the closeout to
  `progress.md` (append-only) referencing HEAD `ff3381a`.
- Run `bash scripts/mb-checklist-prune.sh --apply --mb /Users/fockus/Apps/taskloom/.memory-bank`
  (brings the 901-line checklist under cap).
- Commit the dangling MB tail: `MB_AUTO_COMMIT=1 bash scripts/mb-auto-commit.sh --mb <taskloom bank>`
  (MB-only, honest `chore(mb):` message, no push).
- Remove the stray empty project dir
  `~/.claude/projects/-Users-fockus-Apps-taskloom--memory-bank-specs` after confirming
  `find … -name '*.jsonl' | wc -l` is 0.

**DoD:**
- [ ] taskloom session file repaired (<40 KB, bullets inside Live log, `summarized:false`, backup kept).
- [ ] E7/AUD-06a ✅ in checklist + progress closeout appended (referencing `ff3381a`).
- [ ] Checklist under the 120-line cap after prune.
- [ ] Dangling MB changes committed as an MB-only `chore(mb)` commit (verified `git status` clean
      for `.memory-bank/`); nothing pushed.
- [ ] Stray `…-memory-bank-specs` dir removed (0 jsonl confirmed first).

**Verification:**
```bash
cd /Users/fockus/Apps/taskloom
wc -c .memory-bank/session/2026-06-22_2308_b4acaf96.md   # < 40000
wc -l .memory-bank/checklist.md                          # <= 120
git status --porcelain -- .memory-bank/                  # empty after commit
git log -1 --format='%h %s' -- .memory-bank/
```
**Edge cases:** if source files are dirty, `mb-auto-commit.sh` refuses to bundle — stage MB
manually with an MB-only `git add .memory-bank/`; never sweep source into a `chore(mb)` commit.

---

### Stage C2 — swarmline remediation

**Complexity:** L · **~5 min** · **Zavisimosti:** A1, A2, A7 · **Agent:** developer (ops)
**Files (swarmline repo):** `.memory-bank/status.md`, `.memory-bank/checklist.md`,
`.memory-bank/progress.md` (+ new `progress.archive.md`), `.memory-bank/BACKLOG.md` (+ extracted
issue/ADR files), `.memory-bank/session/2026-06-30_2045_7a5b0e51.md`; stray dirs under
`~/.claude/projects/`

**Confirmed:** swarmline `status.md` says Epic C "waiting for go" though it is closed 9/9 in HEAD;
checklist 680 lines; `progress.md` 260.5 KB (March verify-boilerplate ≈27%); `BACKLOG.md`
201.9 KB with multi-KB inline RESOLVED items (I-066, I-072) and ADR-004/006/007; the 106.4 KB
bloated session file; stray empty project dirs
`…-swarmline--memory-bank`, `…-swarmline--memory-bank-plans`, `…-swarmline--memory-bank-reports`
(all 0 jsonl).

- Actualize `status.md`: mark Epic C closed 9/9, refresh the "focus" line to current HEAD reality.
- Repair the bloated session file: `bash scripts/mb-session-repair.sh --apply <106KB file>`.
- Run `bash scripts/mb-checklist-prune.sh --apply --mb /Users/fockus/Apps/swarmline/.memory-bank`.
- Archive the March verify-boilerplate sections of `progress.md` into `progress.archive.md`
  (move, not delete — progress.md stays append-only for live entries; the archive keeps history).
- Extract RESOLVED multi-KB items (I-066, I-072) and ADR-004/006/007 out of `BACKLOG.md` into
  dedicated files (`.memory-bank/backlog/` or `notes/`), leaving one-line references in BACKLOG.md.
- Commit the MB tail: MB-only `chore(mb)` commit (no push).
- Remove the three stray empty project dirs after confirming 0 jsonl each.

**DoD:**
- [ ] `status.md` reflects Epic C closed 9/9 + current focus.
- [ ] swarmline session file repaired (<40 KB, backup kept).
- [ ] Checklist under the 120-line cap after prune.
- [ ] `progress.md` March boilerplate moved to `progress.archive.md` (live progress.md smaller,
      history preserved, no live entries rewritten).
- [ ] I-066, I-072, ADR-004/006/007 extracted from BACKLOG.md into dedicated files with references left behind.
- [ ] MB tail committed (MB-only `chore(mb)`), `git status` clean for `.memory-bank/`; nothing pushed.
- [ ] Three stray `…-swarmline--memory-bank*` dirs removed (0 jsonl confirmed).

**Verification:**
```bash
cd /Users/fockus/Apps/swarmline
wc -c .memory-bank/session/2026-06-30_2045_7a5b0e51.md   # < 40000
wc -l .memory-bank/checklist.md                          # <= 120
wc -c .memory-bank/progress.md .memory-bank/BACKLOG.md   # both materially smaller
grep -c 'Epic C' .memory-bank/status.md
git status --porcelain -- .memory-bank/                  # empty after commit
```
**Edge cases:** `progress.md` is append-only — **move** historical sections to the archive file,
never rewrite or reorder live entries; keep monotonic IDs intact when extracting I-/ADR- items.

---

## Verification (full)

```bash
cd /Users/fockus/Apps/skill-memory-bank

# Track A — capture correctness
PATH="$PWD/.venv/bin:$PATH" bats \
  hooks/tests/session-turn.bats \
  hooks/tests/extract-tools-files.bats \
  hooks/tests/session-start-context.bats \
  hooks/tests/session-summarize.bats \
  tests/bats/test_session_repair.bats tests/bats/test_compact_sessions.bats

# Track B — drift & enforcement
PATH="$PWD/.venv/bin:$PATH" bats \
  tests/bats/test_mb_freshness.bats tests/bats/test_compact_checklist.bats
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/ -k 'docs or changelog or skill or checklist_cap' -q

# Static analysis on every changed shell file
shellcheck \
  hooks/mb-session-turn.sh hooks/lib/session-common.sh hooks/lib/extract-tools-files.sh \
  hooks/mb-session-start.sh scripts/mb-session-prune.sh scripts/mb-session-repair.sh \
  scripts/mb-freshness.sh hooks/session-end-autosave.sh

# settings JSON still valid after Stop/SessionEnd rewiring
python3 -c 'import json; json.load(open("settings/hooks.json"))'

# Full structured run (RULES.md preferred)
PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json

# Dual-shell smoke
bash --version; /bin/bash -c 'echo bash3.2-path-ok'
```

## DoD (plan-level)

- [ ] **A1** resumed-session bullets land inside `## Live log`; `summarized` reset to false; `judged` untouched.
- [ ] **A2** bullet + file-list caps (12 / 600) with `+K more` and `…`; opt-out envs.
- [ ] **A3** user prompt cap raised to 1000 + ellipsis; env override.
- [ ] **A4** whole-message service wrappers no longer counted as turns; human prose preserved.
- [ ] **A5** `_recent.md` injection hard-capped (4000 bytes) + marker.
- [ ] **A6** `MB_SUMMARY_MAX_CHARS` default lowered to 60000; env restores old value.
- [ ] **A7** `mb-session-repair.sh` + prune byte-threshold; idempotent; backups; ≤400 lines each.
- [ ] **B1** `mb-freshness.sh` deterministic behind/dirty; Stop nudge drift-gated; SessionStart banner opt-out.
- [ ] **B2** `MB_AUTO_COMMIT` + governed-pipeline actualization recipe documented + doc-tested.
- [ ] **B3** opt-in checklist autoprune SessionEnd hook + "checklist = TODO only" rule.
- [ ] **B4** memsearch per-turn summarize disabled; decision documented.
- [ ] **C1** taskloom: session repaired, E7/AUD-06a actualized, checklist pruned, MB committed, stray dir removed.
- [ ] **C2** swarmline: status actualized, session repaired, checklist pruned, progress/BACKLOG archived+split, MB committed, stray dirs removed.
- [ ] Every stage has a failing test committed BEFORE its fix (TDD evidence in git history).
- [ ] All new bats/pytest pass on bash 3.2 AND bash 5.x; existing suites green (no regressions).
- [ ] `shellcheck` clean on all changed shell files; every changed file ≤400 lines.
- [ ] All new caps/toggles have opt-out env vars (design-contract compliance); every hook is fail-safe (exit 0 on error).
- [ ] Backlog **I-087** flipped to done; `progress.md` appended; `checklist.md` updated.

## Dependency graph

```
A1 ──┬─────────────► A7 ──► C1
     │                └───► C2
A2 ──┘  (A7 reuses A1 splice; C1/C2 reuse A7 + fixed pipeline A1–A4)
A3  (needs A2 cap)   A4    A5    A6      B1    B2(needs B1)   B3    B4
```

## Parallelization

| Phase | Stages | Agents |
|-------|--------|--------|
| 1 | A1, A2, A4, A5, A6, B1, B3, B4 | dev-1, dev-2, dev-3, tester |
| 2 | A3 (after A2), A7 (after A1), B2 (after B1) | dev-1, dev-2 |
| 3 | C1, C2 (after A1/A2/A7) | dev-1 (ops), dev-2 (ops) |

## Potential merge conflicts

- `hooks/mb-session-turn.sh` — A1 + A2 both edit it → sequence A1 then A2 (or one dev owns the file).
- `hooks/lib/session-common.sh` — A1 (helper) + A6 (default) → distinct regions, low risk; land A1 first.
- `hooks/lib/extract-tools-files.sh` — A3 + A4 both edit the python block → one dev owns both, land A3 then A4.
- `settings/hooks.json` — B1 (Stop) + B3 (SessionEnd) → distinct blocks, but re-validate JSON after both.
- `SKILL.md` — B2 + B3 both add rules → distinct sections; land sequentially.

## Stage summary (DoD status)

| Stage | Track | Bug | Priority | Complexity | Depends | DoD |
|-------|-------|-----|----------|-----------|---------|-----|
| A1 | A | 1 | HIGH | M | — | ⬜ |
| A2 | A | 2 | HIGH | S | — | ⬜ |
| A3 | A | 3 | MED | S | A2 | ⬜ |
| A4 | A | 4 | MED | M | — | ⬜ |
| A5 | A | 6 | LOW | S | — | ⬜ |
| A6 | A | 7 | LOW | S | — | ⬜ |
| A7 | A | 5 | MED | L | A1 | ⬜ |
| B1 | B | 8a | HIGH | L | — | ⬜ |
| B2 | B | 8b | MED | S | B1 | ⬜ |
| B3 | B | 9 | MED | M | — | ⬜ |
| B4 | B | 10 | MED | S | — | ⬜ |
| C1 | C | ops | MED | M | A1,A2,A7 | ⬜ |
| C2 | C | ops | MED | L | A1,A2,A7 | ⬜ |

## Checklist (copy into checklist.md)

- ⬜ I-087 A1: Stop appends into Live log + reset `summarized` on resumed sessions (HIGH, bug 1)
- ⬜ I-087 A2: bullet + file-list hard caps `+K more`/`…` (HIGH, bug 2)
- ⬜ I-087 A3: user-prompt cap 1000 + ellipsis (bug 3)
- ⬜ I-087 A4: filter non-human `<task-notification>`/`<system-reminder>` turns (bug 4)
- ⬜ I-087 A5: `_recent.md` injection hard-cap (bug 6)
- ⬜ I-087 A6: lower `MB_SUMMARY_MAX_CHARS` default to 60000 (bug 7)
- ⬜ I-087 A7: `mb-session-repair.sh` + prune byte-threshold (bug 5)
- ⬜ I-087 B1: `mb-freshness.sh` MB-vs-code drift check + Stop nudge + SessionStart banner (bug 8a)
- ⬜ I-087 B2: document `MB_AUTO_COMMIT` + governed-pipeline actualization recipe (bug 8b)
- ⬜ I-087 B3: opt-in checklist autoprune SessionEnd hook + "TODO-only" rule (bug 9)
- ⬜ I-087 B4: disable memsearch per-turn summarize + document decision (bug 10)
- ⬜ I-087 C1: taskloom remediation (repair/actualize/prune/commit/cleanup)
- ⬜ I-087 C2: swarmline remediation (status/repair/prune/archive/split/commit/cleanup)
