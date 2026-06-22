---
type: sequence
scope: codex-remediation
created: 2026-06-23
status: active
priority: HIGH
covers: [I-082, I-083, I-084, I-085, I-086]
source: reports/2026-06-23_codex-gpt5.5-skill-review.md
---

# Execution Sequence — codex/GPT-5.5 remediation (I-082..I-086)

Master ordering for the 5 fix-plans produced from the 2026-06-23 codex review.
Each line item is its own plan (`plans/2026-06-23_*.md`); this file is the
dependency-resolved order + release mapping + the execution protocol that every
plan runs through. **Source of truth for sequence is this file.**

Baseline at authoring: **v5.1.0 shipped (PyPI + GitHub Release)**, `main` CI GREEN
(commits `3c16381`, `e04c4e7` fixed the post-release red — bats portability,
shellcheck 0.9.0, pytest CI-portability).

## Guiding principles

1. **Security & correctness before features.** Code-exec in shipped 5.1.0 is the top priority.
2. **Trust the gates before leaning on them.** I-083 makes `/mb done` / `/mb work` fail-closed; do it before we rely on the machine to land the rest.
3. **Fix the `/mb work` BLOCKER early.** I-085's empty-`--range`→whole-plan bug is dangerous *while we use `/mb work --range`* to execute these very plans → fix in the first wave.
4. **Respect cross-plan file overlaps** (see Dependencies below) so two plans don't fight over the same file.
5. **One landing at a time.** Only one plan carries `status: in_progress`; full suite green between landings.

## Dependencies (hard ordering constraints)

- **I-082 → I-085:** I-082 Stage 2 adds `mb_canonical_under` to `scripts/_lib.sh` and rewrites `mb-work-resolve.sh:109-115`; I-085 Stage 6 also edits `mb-work-resolve.sh:124` (bank-relative targets). I-082 lands first; I-085 builds on its helper.
- **I-086 → I-084:** I-086 hardens `mb-pipeline-validate.sh` (runtime-block schema + duplicate-key rejection) and unifies pipeline resolution; I-084's dispatcher leans on a validated, single-path pipeline config. I-086 lands first.
- **I-083 → {I-084, I-085, I-086}:** trustworthy verification gates should exist before we land the larger plans through `/mb work`.
- I-082 and I-083 are otherwise independent of each other (can be authored in parallel if needed, but land I-082 first for release urgency).

## Sequence

### Wave 1 — 5.1.1 hardening patch (URGENT)

| # | Plan | Backlog | Why here |
|---|------|---------|----------|
| 1 | `2026-06-23_fix_security-hardening.md` | I-082 | Code-exec + path traversal + `<private>` leak in **shipped 5.1.0**. Also delivers `mb_canonical_under` helper that I-085 reuses. |
| 2 | `2026-06-23_fix_verification-gates.md` | I-083 | Make `/mb done` tests-gate fail-closed (null/crash/bad-JSON) + multi-stack runner incl. bats, so every later landing is trustworthy. |
| 3 | `2026-06-23_fix_logic-correctness-portability.md` | I-085 | Empty-`--range`→whole-plan BLOCKER (makes `/mb work` safe), flow-route false negatives, base64/stat portability. Reuses I-082's canonical helper. |

→ **Release 5.1.1** (patch — all bug/security fixes). Push + tag on explicit go.

### Wave 2 — 5.2.0 dispatcher feature

| # | Plan | Backlog | Why here |
|---|------|---------|----------|
| 4 | `2026-06-23_fix_config-validation-docs.md` | I-086 | Validator runtime-block schema + duplicate-key rejection + single pipeline-resolution path + doc regen. Lead-in the dispatcher relies on. (Patch-worthy on its own; bundled here as 5.2.0 prep.) |
| 5 | `2026-06-23_feature_dispatcher-wiring-transports.md` | I-084 | The big one: wire `mb-agent-caps` into `/mb work`, make pi/opencode/codex executable end-to-end, ship usable default routing. New capability → minor bump. |

→ **Release 5.2.0** (minor — transports become executable). Push + tag on explicit go.

## Per-plan execution protocol (every plan)

Run via the governed engine — do **not** hand-edit around it:

```
/mb work <plan-path> --workflow codex-governed
  implement (Opus) → verify (plan-verifier) → DUAL review (codex gpt-5.5 + lead)
  → judge = mb-judge (GO / GO_WITH_BACKLOG / NO_GO) → bounded fix-cycle → done
```

- **TDD-first per stage:** failing bats/pytest proving the bug/exploit BEFORE the fix; green after.
- **Judge = `mb-judge`** (independent terminating gate — per the I-086a decision; never self-review GO after a fix-cycle).
- **Cross-environment (lesson from the 5.1.0 CI saga):** every shell change must pass **bash 3.2 (macOS) AND bash 5.x (Linux)**; verify pytest under **Python 3.11** (CI parity) before claiming green; run shellcheck against CI's pinned **0.9.0** behavior.
- **Before each commit:** re-check `git status` + `origin/main` (parallel-edits can land mid-session).
- **Landing checklist:** full pytest GREEN + full bats GREEN + rules-check 0 violations + traceability updated → move plan to `plans/done/` → flip backlog item to DONE with an outcome line → CI green on push.
- **Protected files** (`.github/workflows/**`, etc.): the verification-gates plan flags the CI-surface edit as needing **explicit approval** before applying.

## Verified facts baked into the plans (no live-binary unknowns left)

- **codex** enumeration = `codex debug models` (JSON `.models[].slug`) — verified vs live codex 0.137.0; run = `codex exec -m <model>`. (Current `codex --list-models`/`codex models` are wrong; `--bundled` is not a flag.)
- **pi** = `pi -p --no-session --model <provider/id[:thinking]>` (`--mode json`) — verified.
- **opencode** = `opencode run -m <provider/model>` (`--format json`, `--agent`) — verified.

## Decisions locked (2026-06-23, maintainer)

- **judge = `mb-judge` only** (delete `.memory-bank/pipeline.yaml:34` `{agent: main-agent}` + its stale comment).
- **`/mb reindex` → ADD** to the `commands/mb.md` router (keep README/SKILL); generated pytest enforces router↔docs consistency.

## Open (decide at execution time, low-risk)

- Whether to fold I-086 into 5.1.1 (it is mostly bug fixes) or keep it as 5.2.0 lead-in. Default: 5.2.0 prep.
- Full propagation of the duplicate-key-rejecting loader to all 13 `safe_load` callers — deferred follow-up backlog item (I-086 Stage 2 scopes it to the validate path).
