---
type: fix
scope: security-hardening
created: 2026-06-23
status: done
priority: HIGH
backlog: I-082
linked_report: reports/2026-06-23_codex-gpt5.5-skill-review.md
---

# Fix: Security Hardening

Closes the security findings raised in the codex/GPT-5.5 skill review
(`reports/2026-06-23_codex-gpt5.5-skill-review.md` §05), tracked as backlog **I-082**.

## Goal

The skill currently trusts repo-controlled inputs (project paths, `roadmap.md`
links, `.mbenv`/`.mb-config`, indexed paths, lock paths) and reflects secret/private
material back to disk and transcripts. This plan eliminates two BLOCKER remote-code-execution
paths (unquoted `bash -c`, `source` of repo-controlled env), six path-traversal /
protected-path-bypass MAJORs, and three secret/private leak MAJORs. After this work,
no untrusted string reaches a shell, no read/write escapes the active bank or repo
through `../` / symlinks / absolute paths, and `<private>` blocks plus secret values
never reach `session/*.md`, summaries, or the transcript.

All findings below were confirmed against the current code at the cited lines on 2026-06-23.
No UNCONFIRMED findings.

## Constraints (apply by construction)

- **TDD-first**: every stage writes the failing exploit/regression test FIRST (bats under
  `tests/bats/` or `hooks/tests/`), proving the issue, then the fix turns it green.
- **Dual-shell**: every changed script must run on bash 3.2 (macOS default) AND bash 5.x (Linux).
  No `mapfile`, no `declare -A` in hot paths, no `${var^^}`; prefer `case`/`printf`/`awk`.
- **File budget**: no file exceeds 400 lines after the change; extract a shared helper
  (`scripts/_lib.sh`, `hooks/lib/session-common.sh`) rather than inline-duplicating logic.
- **No placeholders**: copy-paste-ready code, no TODO/`...`.
- **Reuse existing primitives**: `mb_registry_lookup` (`scripts/_lib.sh:139`),
  `valid_pipeline_name` (`scripts/mb-pipeline.sh:355`), `abspath`/`abs` realpath helpers,
  `_lock_acquire`/`_lock_release` (`scripts/mb-handoff.sh:44/72`, `scripts/mb-flow-sync.sh:63/89`),
  `sc_redact_secrets` (`hooks/lib/session-common.sh:135`).
- BLOCKERs first (Stage 1), then traversal canonicalization (Stage 2), protected-path Bash
  coverage (Stage 3), private/secret leak (Stage 4). Stages are independent and may run in parallel,
  except Stage 2 introduces the shared `mb_canonical_under` helper that Stage 3 reuses → Stage 3
  depends on Stage 2's helper landing first.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1 — Kill remote code execution (BLOCKERs)

No untrusted string may reach a shell or `source`. Confirmed:
`hooks/_skill_root.sh:110-112` builds a `bash -c` string by interpolating `$lib`, `$agent`,
and `${MB_PROJECT_ROOT:-$cwd}` unquoted-against-injection (a project path containing `'`
breaks out of the single-quoted code string). `scripts/mb-plan-done.sh:379` does
`. "$MB_PATH/.mbenv"` — sourcing a repo-controlled file is arbitrary code execution.

- **Test FIRST** `tests/bats/test_security_skill_root_injection.bats`:
  - `test_skill_root_resolve_path_with_single_quote_no_exec` — set `MB_PROJECT_ROOT` to a temp dir
    whose name contains `'; touch "$PWD/PWNED"; '` (or `MB_PROJECT_ROOT="a'$(touch PWNED)'b"`),
    call `mb_hook_resolve_mb_path`, assert `PWNED` is NOT created and the function returns cleanly.
  - `test_skill_root_resolve_returns_registry_hit_in_process` — with a valid registry, assert the
    resolved bank path is still printed correctly (no regression).
- **Test FIRST** `tests/bats/test_security_mbenv_no_source.bats`:
  - `test_plan_done_mbenv_does_not_execute_code` — write `.memory-bank/.mbenv` containing
    `EVIL=$(touch "$BATS_TEST_TMPDIR/PWNED")` and a line `; touch PWNED2`, run `mb-plan-done.sh`,
    assert neither `PWNED` nor `PWNED2` exists.
  - `test_plan_done_mbenv_valid_keyvalue_is_loaded` — `.mbenv` with `MB_TEST_ROOTS=src test`,
    assert the value is exported/honored (parity with prior behavior for legitimate KEY=value).
  - `test_plan_done_mbenv_rejects_non_whitelist_key` — `.mbenv` with `PATH=/evil`, assert PATH unchanged.
- **Fix** `hooks/_skill_root.sh` (≈line 106-117): replace the `bash -c "...interpolated..."`
  block with an in-process source + quoted positional call:
  ```sh
  if [ -n "$lib" ] && [ -f "$lib" ]; then
    # shellcheck source=/dev/null
    if . "$lib" >/dev/null 2>&1; then
      hit="$(mb_registry_lookup "$agent" "${MB_PROJECT_ROOT:-$cwd}" 2>/dev/null || true)"
    fi
    ...
  fi
  ```
  Source `_lib.sh` into the current shell and pass `$agent` / `${MB_PROJECT_ROOT:-$cwd}` as
  quoted positional args — no shell-string assembly. (If polluting the hook's namespace is a
  concern, run the in-process call inside a `( ... )` subshell with positional args, still NOT a
  `bash -c` string.)
- **Fix** `scripts/mb-plan-done.sh:379`: replace `[ -f "$MB_PATH/.mbenv" ] && . "$MB_PATH/.mbenv"`
  with a whitelist `KEY=value` parser — no `source`. Add helper `mb_load_mbenv()` to
  `scripts/_lib.sh`:
  - read line-by-line; skip blanks and `#` comments;
  - accept only lines matching `^[A-Z][A-Z0-9_]*=` AND whose KEY is in an explicit allow-list
    (`MB_TEST_ROOTS`, plus any key already documented for `.mbenv`);
  - strip surrounding single/double quotes from the value; reject values containing `$`, backtick,
    `;`, `|`, `&`, newline (no command substitution survives);
  - `export "$KEY=$value"` for allow-listed keys only; warn-and-skip others.

**DoD:** both BLOCKER repros (`PWNED` files) fail to appear before the fix is impossible to
trigger; legitimate registry lookup and `MB_TEST_ROOTS` still work; `shellcheck` clean on both files.

---

<!-- mb-stage:2 -->
### Stage 2 — Path-traversal canonicalization (MAJORs)

Reads/links must stay inside the active bank (or repo for protected checks). Confirmed:
`scripts/mb-work-resolve.sh:110` does `abs "$BANK/$rel"` where `$rel` comes from a `(...)`
group in `roadmap.md` and may be `../../etc/passwd`; `abs()` realpaths it with no bound.
`scripts/mb-pipeline.sh:130-137` (`select_named_pipeline`, explicit `$requested` branch) joins
`$pdir/$requested.yaml` and `abspath`s it WITHOUT calling `valid_pipeline_name` (which exists at
line 355 but is only used by `cmd_new`), so `MB_PIPELINE=../../x` or `.mb-config` `pipeline=../../x`
selects YAML outside `<bank>/pipelines` → bypasses protected_paths/gates. `scripts/mb-context.sh:41`
`cat "$filepath"` follows symlinks (`status.md -> ~/.ssh/config`). `scripts/mb-search.sh:127`
`head -20 "$MB_PATH/$rel"` trusts `index.json` paths with no canonicalization.

- **Add shared helper** `mb_canonical_under <base> <candidate>` in `scripts/_lib.sh`
  (single source of truth, reused by Stages 2 & 3):
  - realpath `<candidate>` (via python3 `os.path.realpath`, matching existing `abs`/`abspath`);
  - realpath `<base>`;
  - if the canonical candidate equals base or has `base + "/"` as a strict prefix → print it, return 0;
    else print nothing, return 1. Reject absolute inputs and any input still containing `..` after
    canonicalization. Symlink-resolution is intrinsic to realpath.
- **Test FIRST** `tests/bats/test_security_path_traversal.bats`:
  - `test_work_resolve_rejects_dotdot_active_plan_link` — `roadmap.md` active-plans block with
    `(../../../../etc/passwd)`; run `mb-work-resolve.sh` (empty target); assert exit != 0 and the
    out-of-bank path is NOT printed. BEFORE: path printed. AFTER: rejected.
  - `test_work_resolve_accepts_canonical_plan_under_bank` — link to `plans/foo.md` (exists);
    assert it resolves (no regression).
  - `test_pipeline_select_rejects_dotdot_name` — `MB_PIPELINE=../../evil` with an `evil.yaml`
    planted outside `<bank>/pipelines`; assert `mb-pipeline.sh path` does NOT select it (return 3 /
    not-found). Repeat for `.mb-config` `pipeline=../../evil`.
  - `test_pipeline_select_accepts_valid_name` — `MB_PIPELINE=governed` with
    `pipelines/governed.yaml`; assert selected (no regression).
  - `test_context_skips_symlinked_status` — `status.md` is a symlink to a file outside the bank
    (e.g. `$BATS_TEST_TMPDIR/secret`); run `mb-context.sh`; assert the secret content is NOT in
    stdout and a skip warning is emitted on stderr.
  - `test_search_tag_rejects_dotdot_index_path` — craft `index.json` with a note `path` of
    `../../../../etc/hostname`; run `mb-search.sh --tag X`; assert out-of-bank content NOT printed.
- **Fix** `scripts/mb-work-resolve.sh` (line 109-115): accept only canonical paths matching
  `$BANK/plans/*.md` or `$BANK/specs/*/tasks.md`. Replace `abs_path=$(abs "$BANK/$rel")` with
  `abs_path=$(mb_canonical_under "$BANK" "$BANK/$rel")` then additionally assert the result matches
  one of the two allowed shapes (case-glob); reject absolute `$rel` and any `..` outright.
- **Fix** `scripts/mb-pipeline.sh` `select_named_pipeline` (line 130): in the explicit `$requested`
  branch, `valid_pipeline_name "$requested" || return 3` BEFORE the path-join; then verify
  `mb_canonical_under "$pdir" "$pdir/$requested.yaml"` succeeds. Apply the same
  `valid_pipeline_name` + `mb_canonical_under` guard to the `.mb-config` branch (line 170,
  `$cfgname`) so the config pointer can't escape `$pdir` either.
- **Fix** `scripts/mb-context.sh` (line 37-44): before `cat`, reject symlinks
  (`[ -L "$filepath" ] && { warn; continue; }`) and require the realpath to be a regular file under
  `$MB_PATH` via `mb_canonical_under "$MB_PATH" "$filepath"`. Apply to the active-plans `find` loop
  too (skip symlinked plan files).
- **Fix** `scripts/mb-search.sh` (line 124-129, tag mode): for each indexed `$rel`, compute
  `safe=$(mb_canonical_under "$MB_PATH" "$MB_PATH/$rel")` and `continue` (skip) when it fails;
  `head -20 "$safe"` only on success.

**DoD:** every traversal/symlink repro fails to read out-of-bank data after the fix; all
"accepts valid" regression tests pass; `valid_pipeline_name` is enforced on every pipeline-name
entry point.

---

<!-- mb-stage:3 -->
### Stage 3 — Protected-path Bash coverage + glob bypass (MAJORs)

Depends on Stage 2's `mb_canonical_under` helper. Confirmed:
`scripts/mb-work-protected-check.sh:138-139` matches each candidate with `rx.match(f)` (the raw,
possibly-absolute path) OR `rx.match(os.path.basename(f))`. An absolute path like
`/abs/repo/ci/deploy.sh` does NOT match the glob `ci/**` (anchored `^`), and basename fallback only
saves `.env`/`Dockerfile`-style single-segment names — so `ci/**` and `.github/workflows/**` are
bypassable via absolute paths. `hooks/mb-protected-paths-guard.sh:31-34` only fires on `Write|Edit`;
a `Bash` command using `tee`, `sed -i`, or `>` redirect into `.env`/`ci/**`/`*.pem` is never checked
(`hooks/block-dangerous.sh:67-71` only blocks `~/.ssh|~/.gnupg|~/.aws/credentials` redirects).

- **Test FIRST** `tests/bats/test_security_protected_abspath.bats`:
  - `test_protected_check_matches_absolute_ci_path` — `pipeline.yaml` with `protected_paths: [ci/**]`;
    candidate `"$repo/ci/deploy.sh"` (absolute); assert exit 1 (matched). BEFORE: exit 0 (bypass).
  - `test_protected_check_matches_absolute_github_workflow` — candidate
    `"$repo/.github/workflows/release.yml"` vs glob `.github/workflows/**`; assert exit 1.
  - `test_protected_check_still_matches_basename_env` — candidate `/anywhere/.env`; assert exit 1
    (no regression).
  - `test_protected_check_allows_unprotected_path` — candidate `src/app.py`; assert exit 0.
- **Test FIRST** `hooks/tests/protected-bash-guard.bats`:
  - `test_bash_guard_blocks_tee_into_env` — feed PreToolUse JSON for `Bash` with
    `command: "tee .env <<<X"`; assert decision is `ask`/block (matched).
  - `test_bash_guard_blocks_sed_inplace_protected` — `command: "sed -i s/a/b/ ci/deploy.sh"`;
    assert matched.
  - `test_bash_guard_blocks_redirect_into_pem` — `command: "echo k > secret.pem"`; assert matched.
  - `test_bash_guard_allows_plain_read_command` — `command: "cat README.md"`; assert allow (exit 0).
- **Fix** `scripts/mb-work-protected-check.sh` (python block, line 133-141): canonicalize each
  candidate, derive the repo root (git toplevel of the candidate's dir, falling back to bank parent),
  and match the **repo-relative** path against each glob, plus the existing basename fallback. So
  absolute `/repo/ci/x` becomes `ci/x` before `rx.match`. Keep basename match for single-segment
  patterns like `.env`/`Dockerfile`.
- **Fix** `hooks/mb-protected-paths-guard.sh` (line 30-37): extend the `case "$TOOL"` to also handle
  `Bash`. For `Bash`, read `.tool_input.command`, extract write targets via a new parser
  `extract_write_targets()` (add to the hook or a tiny shared lib) covering:
  `> file`, `>> file`, `tee [-a] file...`, `sed -i ... file`, `cp/mv ... dest`, `install ... dest`,
  `dd of=file`, `truncate file`. Route each extracted target through `mb-work-protected-check.sh`;
  if any matches, emit the same `ask`/deny decision the Write/Edit path uses. Reuse
  `mb_canonical_under` to normalize targets before checking.

**DoD:** absolute-path protected files are caught for `ci/**` and `.github/workflows/**`; `Bash`
write-into-protected commands trigger the guard; legitimate reads and unprotected writes pass;
`shellcheck` clean.

---

<!-- mb-stage:4 -->
### Stage 4 — Private/secret leak prevention (MAJORs)

Confirmed: `hooks/mb-session-turn.sh:128-133` and `hooks/lib/session-common.sh:135-153`
(`sc_redact_secrets`) redact API-key *tokens* but do NOT strip `<private>...</private>` blocks
before the bullet is written to `session/*.md` or fed to the LLM summarizer (`sc_build_summary_src`,
line 160+, only redacts secrets). `hooks/file-change-log.sh:127-133` greps secret-shaped lines and
prints the **entire matched line** (`$SECRETS`, including the value) to stderr → transcript leak.

- **Add shared sanitizer** `sc_strip_private` to `hooks/lib/session-common.sh` (next to
  `sc_redact_secrets`): read stdin, remove every `<private>...</private>` span (multi-line aware) →
  replace with `[PRIVATE]`. Implement with `awk` (state machine across the open/close markers) for
  bash-3.2 portability — NOT GNU-sed `-z`. Then compose: session text must pass through BOTH
  `sc_strip_private` and `sc_redact_secrets` before any persist/summary.
- **Test FIRST** `hooks/tests/session-private-strip.bats`:
  - `test_session_turn_strips_private_before_persist` — user message containing
    `<private>SECRET-XYZ</private>`; run the turn hook; assert `session/*.md` contains `[PRIVATE]`
    and NOT `SECRET-XYZ`. BEFORE: `SECRET-XYZ` present.
  - `test_summary_src_strips_private` — `sc_build_summary_src` over a session file with a
    `<private>` block; assert the emitted SRC has no private content (so the LLM summarizer/judge
    never sees it).
  - `test_session_turn_still_redacts_api_key` — message with `sk-` token; assert `[REDACTED]`
    (no regression to existing redaction).
- **Test FIRST** `tests/bats/test_security_file_change_log_no_secret_value.bats`:
  - `test_file_change_log_redacts_secret_value` — write a `.py` file with
    `api_key = "supersecretvalue12345"`; run the PostToolUse hook; assert stderr contains the
    `file:line` + var name but NOT `supersecretvalue12345`. BEFORE: full line printed.
  - `test_file_change_log_still_warns_on_secret_presence` — assert a WARNING is still emitted
    (detection preserved, only the value is redacted).
- **Fix** `hooks/mb-session-turn.sh:130-133`: pipe the bullet through `sc_strip_private` before
  `sc_redact_secrets` (e.g. `... | sc_strip_private | sc_redact_secrets >> "$SF"`). Apply the same
  composition wherever raw user/transcript text is persisted in the turn/end/summarize hooks.
- **Fix** `hooks/lib/session-common.sh` `sc_build_summary_src` (line 160+): run the assembled SRC
  through `sc_strip_private` (in addition to the existing redaction) before returning, so summaries
  and the judge never receive private blocks.
- **Fix** `hooks/file-change-log.sh:126-133`: change the grep to emit only `file:LINE var [REDACTED]`.
  Use `grep -nEi ...` to keep line numbers, then for each hit print `"$FILE_PATH:$lineno  $varname  [REDACTED]"`
  (extract the var name with `awk`/`sed`, drop everything after `=`). Never echo `$SECRETS` verbatim.

**DoD:** `<private>` content never reaches `session/*.md`, summaries, or the judge; secret VALUES
never reach stderr/transcript while detection warnings are preserved; existing API-key redaction
regression tests still pass.

---

## Verification

Run all new + existing security-adjacent tests on both shells:

```bash
cd /Users/fockus/Apps/skill-memory-bank

# Stage 1 — RCE
bats tests/bats/test_security_skill_root_injection.bats
bats tests/bats/test_security_mbenv_no_source.bats

# Stage 2 — traversal
bats tests/bats/test_security_path_traversal.bats

# Stage 3 — protected paths
bats tests/bats/test_security_protected_abspath.bats
bats hooks/tests/protected-bash-guard.bats

# Stage 4 — private/secret leak
bats hooks/tests/session-private-strip.bats
bats tests/bats/test_security_file_change_log_no_secret_value.bats

# Regression — nothing existing breaks
bats tests/bats/test_lib.bats tests/bats/test_mb_config.bats tests/bats/test_hooks.bats
bats hooks/tests/session-turn.bats
bats tests/bats/test_file_change_log_perms.bats

# Static analysis on every changed shell file (BLOCKER + MAJOR scope)
shellcheck hooks/_skill_root.sh scripts/mb-plan-done.sh scripts/_lib.sh \
  scripts/mb-work-resolve.sh scripts/mb-pipeline.sh scripts/mb-context.sh \
  scripts/mb-search.sh scripts/mb-work-protected-check.sh \
  hooks/mb-protected-paths-guard.sh hooks/mb-session-turn.sh \
  hooks/lib/session-common.sh hooks/file-change-log.sh

# Dual-shell smoke (macOS bash 3.2 must be present at /bin/bash)
bash --version   # 5.x path
/bin/bash -c 'echo bash3.2-path-ok'
```

### Manual exploit repro — BEFORE (must fire) and AFTER (must be neutralized)

```bash
# --- Stage 1a: bash -c injection via project path (hooks/_skill_root.sh:110) ---
# BEFORE:
mkdir -p "/tmp/mb x'\$(touch /tmp/PWNED)'y/.." 2>/dev/null
MB_PROJECT_ROOT="/tmp/a'\$(touch /tmp/PWNED1)'b" bash -c '
  . hooks/_skill_root.sh; mb_hook_resolve_mb_path >/dev/null 2>&1'
test -e /tmp/PWNED1 && echo "BEFORE: VULNERABLE (PWNED1 created)"
# AFTER: rerun → /tmp/PWNED1 must NOT exist.

# --- Stage 1b: .mbenv source RCE (scripts/mb-plan-done.sh:379) ---
# BEFORE: write .memory-bank/.mbenv => 'EVIL=$(touch /tmp/PWNED2)'  then run mb-plan-done.sh
# expect /tmp/PWNED2 created. AFTER: /tmp/PWNED2 must NOT exist; MB_TEST_ROOTS still honored.

# --- Stage 2a: roadmap active-plan ../ link (mb-work-resolve.sh:110) ---
# BEFORE: roadmap mb-active-plans block => '- foo (../../../../etc/passwd)'
#   scripts/mb-work-resolve.sh  → prints /etc/passwd. AFTER: exit!=0, nothing printed.

# --- Stage 2b: MB_PIPELINE ../ (mb-pipeline.sh:130) ---
# BEFORE: plant /tmp/evil.yaml; MB_PIPELINE=../../../../tmp/evil scripts/mb-pipeline.sh path
#   → selects /tmp/evil.yaml. AFTER: not selected (return 3).

# --- Stage 2c: symlinked status.md (mb-context.sh:41) ---
# BEFORE: ln -sf ~/.ssh/config .memory-bank/status.md; scripts/mb-context.sh → prints ssh config.
#   AFTER: skipped with warning, content not shown.

# --- Stage 2d: index.json ../ path (mb-search.sh:127) ---
# BEFORE: craft note path '../../../../etc/hostname'; scripts/mb-search.sh --tag X → prints it.
#   AFTER: skipped.

# --- Stage 3a: absolute protected path (mb-work-protected-check.sh:138) ---
# BEFORE: scripts/mb-work-protected-check.sh "$PWD/ci/deploy.sh"  (glob ci/**) → exit 0 (BYPASS).
#   AFTER: exit 1 (matched).

# --- Stage 3b: Bash write into protected (mb-protected-paths-guard.sh:31) ---
# BEFORE: echo '{"tool_name":"Bash","tool_input":{"command":"tee .env <<<x"}}' \
#   | hooks/mb-protected-paths-guard.sh → exit 0 (no decision). AFTER: ask/deny emitted.

# --- Stage 4a: <private> leak into session (mb-session-turn.sh:128) ---
# BEFORE: user message '<private>SECRET-XYZ</private>' → grep -r SECRET-XYZ .memory-bank/session
#   finds it. AFTER: only [PRIVATE]; SECRET-XYZ absent.

# --- Stage 4b: secret value to stderr (file-change-log.sh:127) ---
# BEFORE: edit a .py with api_key="supersecretvalue12345"; PostToolUse hook stderr shows the value.
#   AFTER: stderr shows file:line + var + [REDACTED]; value absent.
```

## DoD

- [x] **Stage 1**: `hooks/_skill_root.sh` resolves the bank with NO `bash -c` string (in-process
      source + quoted positional `mb_registry_lookup` call); `mb-plan-done.sh` loads `.mbenv` via a
      whitelist `KEY=value` parser with NO `source`; both RCE repros (`/tmp/PWNED*`) cannot be
      triggered; `MB_TEST_ROOTS` and registry lookup still work.
- [x] **Stage 2**: `mb_canonical_under` added to `scripts/_lib.sh`; `mb-work-resolve.sh` accepts only
      `$BANK/plans/*.md` | `$BANK/specs/*/tasks.md`; `mb-pipeline.sh` enforces `valid_pipeline_name`
      + bank-bounded realpath on every name entry (flag, `MB_PIPELINE`, `.mb-config`);
      `mb-context.sh` rejects symlinks and out-of-bank files; `mb-search.sh` canonicalizes every
      indexed path; all four `../`/symlink repros fail to exfil.
- [x] **Stage 3**: `mb-work-protected-check.sh` matches absolute paths against `ci/**` and
      `.github/workflows/**` via repo-relative canonicalization; `mb-protected-paths-guard.sh`
      inspects `Bash` commands and routes extracted write targets (`>`,`>>`,`tee`,`sed -i`,`cp/mv`,
      `dd of=`,`install`,`truncate`) through the checker; legitimate reads/unprotected writes pass.
- [x] **Stage 4**: `sc_strip_private` added and applied before persist in `mb-session-turn.sh` and
      before summary in `sc_build_summary_src`; `file-change-log.sh` emits `file:line var [REDACTED]`
      only; `<private>` content and secret VALUES never reach disk/transcript; detection warnings
      and existing API-key redaction preserved.
- [x] Every stage has a failing test committed BEFORE its fix (TDD evidence in git history).
- [x] All new bats pass on bash 3.2 (macOS) AND bash 5.x; existing suites green (no regressions).
- [x] `shellcheck` clean on all 12 changed shell files; no file exceeds 400 lines.
- [x] Each of the 11 exploits has a documented BEFORE (fires) / AFTER (neutralized) repro that was
      actually run.
- [x] Backlog **I-082** flipped to done; report `reports/2026-06-23_codex-gpt5.5-skill-review.md` §05
      cross-referenced; `progress.md` appended; `checklist.md` updated.

## Checklist (copy into checklist.md)

- ⬜ I-082 Stage 1: RCE — no `bash -c` string + no `.mbenv` source (BLOCKER)
- ⬜ I-082 Stage 2: path-traversal canonicalization (`mb_canonical_under`) across resolve/pipeline/context/search
- ⬜ I-082 Stage 3: protected-path absolute-path match + Bash write-target coverage
- ⬜ I-082 Stage 4: `<private>` strip + secret-value redaction in session/file-change-log
