---
type: fix
topic: hermes-soul-brick
status: done
depends_on: []
parallel_safe: false
linked_specs: []
qa: off — small tier
created: 2026-11-20
---
# Plan: fix — hermes-soul-brick

**Baseline commit:** ee5cfce4a46b16b8c6cd8d3ef7787472073abd2a

## Context

**Problem:** hermes-plugins roadmap Wave 0 (backlog I-012 there) blocks soul-composer. The Hermes memory-bank plugin (`hermes/memory-bank/__init__.py`) writes its rules block straight into `$HERMES_HOME/SOUL.md` (`_sync_soul_rules`, lines ~214-245), so a composer-built SOUL would get a second writer; its section cap `SECTION_CAP = 6000` (line 28) is above Hermes' 4000-chars-per-plugin-section limit (`agent/system_prompt.py:87`, 8000 total); `hermes` is missing from `KNOWN_AGENTS` in `scripts/mb_pipeline_validate_blocks.py:207`, so a pipeline with `agents: [hermes]` fails validation.

**Expected result:** soul-composer can take the memory-bank rules as a provider brick through `render_soul_brick() -> str`; the plugin never rewrites a SOUL.md that carries the composer header `<!-- soul-composer: build <hash> -->`; the plugin section fits 4000 chars; `hermes` is a known code agent.

**Related files:**
- `hermes/memory-bank/__init__.py`, `tests/pytest/test_hermes_plugin.py`
- `scripts/mb_pipeline_validate_blocks.py` and its existing pipeline-validation tests
- Contract source: `~/Apps/hermes-plugins/.memory-bank/specs/soul-composer/{requirements,design,tasks}.md` (REQ-005, scenario "providers skip their own sync", Task on provider bricks)

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: memory-bank as a soul-composer provider for Hermes

**Files:** `hermes/memory-bank/__init__.py`, `tests/pytest/test_hermes_plugin.py`, `scripts/mb_pipeline_validate_blocks.py`, the existing pytest file that covers pipeline `agents:` validation

**What to do:**
- `render_soul_brick() -> str` (module-level, public): returns the same rules block `_rules_block()` renders, markers included, so the composer gets byte-identical text to what the plugin writes today; `_sync_soul_rules` reuses it (one source).
- `_sync_soul_rules`: if SOUL.md starts with the composer header (`<!-- soul-composer: build ` at the first line), write nothing — the composer is the single writer (REQ-005). Without the header the behaviour stays exactly as today.
- `SECTION_CAP = 4000` (Hermes per-section limit); the section still truncates to it.
- Add `"hermes"` to `KNOWN_AGENTS`.

**Testing (TDD — tests BEFORE implementation):**
- `test_render_soul_brick_returns_rules_block_with_markers`: text starts with `<!-- mb-rules:start -->`, ends with `<!-- mb-rules:end -->`, contains `## Key rules`, has no `**Language**` line, and equals the block `register()` writes into a plain SOUL.md.
- `test_soul_sync_with_composer_header_writes_nothing`: SOUL.md beginning with `<!-- soul-composer: build abc123 -->` keeps bytes and mtime after `register()`.
- `test_memory_bank_section_fits_the_plugin_budget` tightened: `len(text) <= 4000` asserted as a literal, not via `plugin.SECTION_CAP`.
- Pipeline validation: a pipeline with `agents: [hermes]` validates clean; an unknown agent still fails.

**DoD (Definition of Done):**
- [x] `render_soul_brick()` exists and returns the marker-wrapped rules block identical to what the plugin syncs into a header-less SOUL.md
- [x] a SOUL.md with the composer header is never rewritten by the plugin; header-less behaviour unchanged (existing SOUL tests pass)
- [x] plugin section is at most 4000 chars
- [x] `agents: [hermes]` passes pipeline validation, unknown agents still rejected
- [x] `python3 -m pytest -q tests/pytest/test_hermes_plugin.py` and the touched pipeline-validation tests pass
- [x] `ruff check hermes/memory-bank scripts/mb_pipeline_validate_blocks.py tests/pytest/test_hermes_plugin.py` clean

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture
<!-- /mb-stage:1 -->

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Live Hermes profiles lose the rules block | L | Header-less SOUL keeps today's sync; only a composer-built SOUL is skipped, and the composer pulls the same block via `render_soul_brick()` |
| 4000 cap cuts useful section text | M | Section already truncates; test asserts the cap, content order keeps the head first |

## Gate (plan success criterion)

All Stage 1 DoD bullets ticked by `/mb work`, plan-verifier PASS, full pytest of the touched files green.

## Astra review round 1

Review of 2e5b8ad (gpt-6.2-astra xhigh): CHANGES_REQUESTED, 3 blocker / 6 major / 1 minor. Fixes are in `hermes/memory-bank/__init__.py`, the new `hermes/memory-bank/soul.py` (SOUL-file mechanics, keeps `__init__.py` under 300 lines), `hooks/mb-session-start-context.sh`, `tests/pytest/test_hermes_plugin.py`, `tests/bats/test_mb_session_start_handoff.bats`. A session-scoped guard in the pytest file fails the run if the real `~/.hermes/SOUL.md` changes (mtime + size); every SOUL test uses a tmp `HERMES_HOME`.

Red = the new tests run against the committed plugin (scratch copy plus a 10-line interface shim for `_sync_soul_rules(path)` and `on_session_start`): 27 failed / 16 passed. Bats red = the committed hook. Green = the fixed tree.

| # | Sev | Fix | Red (committed code) | Green |
|---|-----|-----|----------------------|-------|
| 1 | blocker | TOCTOU: render first, then `flock(LOCK_EX)` on `<SOUL.md>.lock` (0600, same folder); under it re-read, re-check the header, abort when the bytes changed. Lock contract in `soul.py` docstring | `test_soul_changed_while_rendering_is_not_overwritten[composer-publishes,user-edits]` (stale write won), `test_soul_sync_waits_for_the_shared_lock` (wrote under a held lock) | pass |
| 2 | blocker | no write through a symlink / non-regular file (`O_NOFOLLOW`, `O_NONBLOCK`, `fstat`); `mkstemp` 0600 in the same folder, `fsync`, `os.replace`, original mode kept | `test_soul_symlink_is_not_written_through`, `test_failed_soul_write_keeps_the_previous_file` (ENOSPC on fsync), `test_soul_rewrite_keeps_its_mode_and_leaves_no_temp_file` | pass (+ FIFO case, green before and after) |
| 3 | blocker | insert only with no markers; replace only one ordered pair, each on its own line; else untouched + one warning, never raises | `test_soul_with_ambiguous_markers_is_left_alone_with_one_warning[lone-start,lone-end,reversed(IndexError),duplicates,start-inline,end-inline]` | pass |
| 4 | major | header = full regex on the first physical line, BOM and space/tab indent allowed | `test_soul_with_composer_header_is_never_written[bom,indented]`, `test_soul_without_a_full_first_line_header_still_syncs[incomplete-prefix,unclosed]` | pass |
| 5 | major | `_script(check=True)` raises on non-zero exit; `render_soul_brick()` raises without `## Key rules`; the sync keeps the old file | `test_failed_rules_render_raises_and_keeps_soul[exit-3,empty]` (DID NOT RAISE) | pass |
| 6 | major | `register()` renders nothing; `on_session_start` starts one daemon thread per process, SOUL path resolved in the caller's context | `test_register_defers_the_soul_sync_to_the_first_session_start` (render ran in register) | pass |
| 7 | major | bytes end to end: prefix/suffix kept byte-for-byte, block uses the file's line ending, invalid UTF-8 skipped; identity test vs an independently built block on `read_bytes()` | `test_soul_bytes_outside_the_block_are_kept[crlf-replace,crlf-insert]`, `test_soul_with_invalid_utf8_is_skipped_and_the_plugin_still_registers` (UnicodeDecodeError) | pass; `test_render_soul_brick_bytes_match_an_independently_built_block` and `[bom-replace]` pass on both |
| 8 | major | scripts run with `cwd=SKILL_ROOT`, `PYTHONSAFEPATH=1`, `PYTHONPATH=SKILL_ROOT` | `test_scripts_ignore_modules_planted_in_cwd_and_pythonpath` (planted pathlib/json/re imported) | pass |
| 9 | major | `_trusted()` rejects mode `& 0o022` on the folder and the bank | `test_bank_in_a_shared_writable_folder_is_not_trusted[folder-0o775,bank-0o775]` | pass |
| 10 | minor | hook: capsule and the 2500 hard cap cut by jq (characters in any locale); `SECTION_CAP` 4000 → 3000 so memory-bank still renders beside llm-wiki at 4000 + the teammates lane at 600 (Hermes 8000 total) | bats `multibyte capsule over the cap…`, `…hard cap… in the C locale` (U+FFFD); pytest `test_memory_bank_section_fits_the_plugin_budget` (8913 > 8000), `test_multibyte_bank_section_from_the_real_hook_is_whole_and_fits` | pass |

Dry run (read-only) of the new sync on the live `~/.hermes/SOUL.md`: regular UTF-8 file, no composer header, one marker pair; the update equals the current bytes, so nothing will be written.

## Astra review round 2

Re-review of the round-1 fixes (gpt-6.2-astra xhigh): CHANGES_REQUESTED, 1 blocker / 4 major / 5 minor; prior issues 2, 3, 5, 6, 8, 9, 10 fixed, 1, 4, 7 partial. Touched: `hermes/memory-bank/soul.py`, `hermes/memory-bank/__init__.py`, `hooks/mb-session-start-context.sh`, `tests/pytest/test_hermes_plugin.py`, `tests/bats/test_mb_session_start_handoff.bats`. Red = the new test against the round-1 tree; where the only failure was a missing name, a throwaway variant showed the behavioural failure. Green = this tree.

| Sev | Finding | Fix | Red (round-1 tree) | Green |
|-----|---------|-----|--------------------|-------|
| blocker | Hermes' SOUL editor (`web_routers/profiles.py:935`, `atomic_write_text`, no lock) saving after our last read is overwritten | Publication is an atomic name exchange (`renamex_np(RENAME_SWAP)` / `renameat2(RENAME_EXCHANGE)` via ctypes), not `os.replace`. The displaced file lands at the temp name and is the backup: if its (dev, ino, mtime_ns, size) is not the stat read under the lock, it is swapped straight back with a warning. A file that is neither the one read nor ours is never deleted. No exchange on the platform or file system means no write. Writer contract in the `soul.py` docstring, so soul-composer's `subagents/orchestrator.py` follows it | `test_editor_save_while_the_plugin_publishes_wins` (save at the temp fsync: plugin bytes won); throwaway variant injecting the save around `os.replace`: plugin bytes won | pass, plus `test_editor_save_at_the_publishing_rename_is_put_back` (save right before the rename) and `test_soul_is_not_replaced_where_names_cannot_be_exchanged` |
| major | First session after install or update gets the old rules: Hermes builds and caches the prompt (`conversation_loop.py:918`) before `on_session_start` (`:934`) | `register()` starts the daemon sync thread (it returns at once, no subprocess in `register`). `on_session_start` repeats the start, keyed by SOUL path, so it acts only after a failed start or a busy lock | `test_register_returns_before_the_render_and_the_first_prompt_has_the_new_block` (first prompt read `Intro.` only); `test_soul_sync_follows_the_profile_hermes_binds` (alpha not synced at register) | pass |
| major | Test fixture set only `HERMES_HOME`; a context-bound Hermes profile outranks it | `load_plugin()` pins `_hermes_home` to `tmp_path/profile` before any `register()` and asserts it. The session guard now covers `~/.hermes/SOUL.md` and `~/.hermes/profiles/*/SOUL.md` (inode, mtime_ns, size). Real ContextVar profile choice is tested separately with two tmp profiles | `test_soul_tests_never_reach_a_profile_bound_by_hermes` with the unpinned fixture: the bound "live" profile was written | pass |
| major | Replace kept only the mode bits: a different group for 0640, a 0444 file replaced | `os.access(W_OK)` on the original, without truncating. `fchown` (owner, group) then `fchmod` on the temp fd before the write and fsync. If owner or group cannot be kept: original left, warning | `test_read_only_soul_is_not_replaced`, `test_soul_rewrite_keeps_its_group` (gid 101 → 20), `test_soul_whose_group_cannot_be_kept_is_left_alone` | pass |
| major | Hook passed `CONTEXT` as one jq argument: a long status line hits E2BIG and the session gets no context | `printf '%s' "$CONTEXT" \| jq -Rs '{additional_context: .[:2500]}'` | bats `a status line longer than the argument limit…` (2 MiB line): status 126 | pass, exact 2500-char prefix |
| minor | `fdopen` before `fstat`: a directory raised and leaked the fd; a first-read OSError escaped `sync()` | `fstat(fd)` first, fd closed in `finally` on every path, OSError handled over the whole read | `test_soul_directory_is_left_alone_without_leaking_a_descriptor` (IsADirectoryError) | pass |
| minor | Started flag set before path resolution and `Thread.start()` | Path added to the started set only after `start()` returns, under the lock; start errors are logged | `test_failed_sync_thread_start_is_retried_by_the_next_session` (RuntimeError escaped `register`) | pass; `test_concurrent_session_starts_run_one_sync` passed before and after (regression guard) |
| minor | Unbounded `LOCK_EX`; existing lock file not checked | `LOCK_EX\|LOCK_NB` polled for `LOCK_TIMEOUT` (10 s); a timeout leaves the path for the next session start. The open lock file must be regular, owned by this user, and `mode & 0o077 == 0`; it is never deleted | `test_busy_lock_is_given_up_and_the_next_session_retries` (throwaway: thread still waiting after 5 s); `test_lock_file_others_can_open_is_not_trusted[0644,0666]` | pass |
| minor | A block right after a leading BOM was "ambiguous" | The position right after a leading UTF-8 BOM counts as a line start | `test_soul_bytes_outside_the_block_are_kept[block-right-after-bom]` (exact bytes after two syncs) | pass |
| minor | Header matched as a prefix: text after `-->` was taken for a header | `fullmatch` on the whole first physical line (BOM, leading or trailing space/tab, CR allowed) | `test_soul_without_a_full_first_line_header_still_syncs[text-after-header]` | pass |

Deviation from the orchestrator's blocker recipe (a hard-link backup before `os.replace`): a hard link captures SOUL.md only when it is made. A save that lands between that link and `os.replace` is displaced by the replace and gone, with no trace for an after-the-fact check. `test_editor_save_at_the_publishing_rename_is_put_back` shows that case. With the exchange, the displaced file itself is the backup, so the post-publication check and restore are exact.

Render time: `render_soul_brick()` takes 0.20–0.24 s here. Hermes' log (`~/.hermes/logs/agent.log`) shows 16–66 s from the last plugin registration to the first API call of the next session (the 10–15 s API latency included), so in practice the thread finishes before the first prompt build. Known limits:
- A session whose first prompt is built within the ~0.2 s render after plugin load (a scripted one-shot right at start) still reads the previous SOUL.md for that one session.
- The swap-back is exact for one concurrent save. Two lockless saves inside the same few microseconds keep the later one at the hidden temp name, with a warning that names it.
- POSIX/macOS ACLs and extended attributes are not carried to the new inode (Hermes' own `atomic_write_text` drops them too). The live SOUL.md has no ACL, only the system `com.apple.provenance` xattr.

Read-only dry run on the live `~/.hermes/SOUL.md`: regular, 0644, owned by the user, writable, no composer header; the update equals the current bytes, so nothing is written. The `SOUL.md.lock` will be created 0600 on the next Hermes start.

## Judge verdict and fix (2026-11-20)

- Judge (opus, AGR-010): NO_GO on one blocker — after a swap-back the temp name could hold an inode the Hermes TUI rewrote in place between the two exchanges, and `_publish` unlinked it (user edit lost).
- Fix (orchestrator, TDD): red `test_tui_save_between_the_two_exchanges_is_never_deleted` (the TUI save was deleted) → green; after any swap-back the displaced copy is always kept and its path logged; `test_editor_save_while_the_plugin_publishes_wins` and `..._at_the_publishing_rename_is_put_back` now expect the kept copy. soul.py docstring rule 3 updated. 60 passed, ruff clean.
- Per the judge: with this fixed the result is GO_WITH_BACKLOG; backlog: second-exchange failure discoverability, mode/uid/gid in identity, ACL skip, cold-start first prompt, transient render retry, jq-apple UTF-8 at 4096-byte boundaries, 0444 test under root, first-start concurrency test.
