# Track B — OpenSpec round-trip: decision draft (master-completion Stage 8, first half)

Files: /Users/fockus/Apps/skill-memory-bank/.memory-bank/context/openspec-adapter.md (only file edited): new section `## Round-trip (AGR-101)`, plus short pointers on D-01, the hard constraint, the out-of-scope line and OQ-1. No code, no tests, nothing staged.

Tests: n/a. This is a design-only stage with no code change, so it has no red→green step. Every claim about current behaviour cites a file and line in the section's "What the code does today" list (capability lost parse.py:135-148; kind lost convert.py:437-440/358-360/487-495; RENAMED not emitted on first import convert.py:372-383; _flatten convert.py:66-68; Covers/Role convert.py:529-530 and lost on re-import :261-264; OpenSpec ticks ignored convert.py:239-241/267-271; whole-file rewrite mb-openspec.py:331-344; resolver mb-work-resolve.sh:242-252, mb_work_source.py:16-18/42-68).

Recommended design in one paragraph: sync and export work per unit (a requirement keyed by cap and name, a task item keyed by its N.M id, proposal Why/What Changes, OpenSpec design.md). A committed sidecar `specs/<topic>/openspec-sync.json` stores per-unit `os` and `mb` hashes. A three-way check per unit reports conflicts, and any conflict means nothing is written. `sync` writes only the bank. `export` is a dry-run by default and splices only changed units into `openspec/changes/<id>/`, so an unedited round-trip is byte-identical and no raw text has to be stored. REQ-IDs never go into OpenSpec files. A meta line `<!-- openspec: cap=…; kind=… -->` sits before the existing anchor. Existing imports migrate by "adopt baseline" inside sync. `/mb work <change-id>` imports or syncs first through a new `mb-openspec.sh resolve`, and offers a dry-run export at the end.

Remaining: the owner answers the questions below, then the orchestrator records them as an AGR; the second half of Stage 8 (import markers, parser capability field, `--normalize` in the usage text) and Stages 9-10 then follow these answers.

Follow-ups:
- (Low) Answer 4 drops the `--force` that plan Stage 9 lists. If the owner agrees, Stage 9's text needs that edit (orchestrator-owned plan).
- (Low) Recommendation 6 adds a new committed file per imported topic. Check it against `mb-spec-validate.sh` when Stage 8 code lands.
- (Low) `_demote_headings` (convert.py:462-464) cannot be reversed for `######` headings. This only matters when a user edits the OpenSpec design notes in the bank.
- (Low) A rename made on the OpenSpec side without a RENAMED delta still retires the old REQ-ID, which is the cost of answer 3.

Questions for the orchestrator (owner decisions, verbatim from the context doc):

### Decisions for the owner

1. Conflict rule: per-unit three-way (B), all-or-nothing write on any conflict, resolved by converging edits or `sync --take openspec|bank`? **Recommended: yes.** Alternative: whole-change hashes (A).
2. `sync` writes only the bank and only prints "run export" when our side is ahead; only `export --write` touches OpenSpec? **Recommended: yes.**
3. REQ-IDs in OpenSpec files: strip (B) / HTML comments (A) / map file (C)? **Recommended: strip.**
4. Drop `--force` on export (refuse on OpenSpec drift and point to `sync`)? **Recommended: yes**; the plan text lists `--force`.
5. Text going back: per unit; unchanged units keep OpenSpec bytes, edited units send the bank text, and `--normalize` text goes back only after a user edit (C)? **Recommended: yes.**
6. Import markers: meta line `<!-- openspec: cap=…; kind=… -->` before the existing anchor, plus committed `specs/<topic>/openspec-sync.json` for per-unit hashes? **Recommended: yes.** Alternative: git-ignored sidecar under `.index/`, which gives false conflicts on a fresh clone.
7. Task identity keyed on the `N.M` id, with a text fallback, and `Covers`/`Role` treated as bank-only after first import? **Recommended: yes.**
8. Migration of existing imports: adopt baseline inside `sync` (B) / plain re-import (A) / explicit `migrate` (C)? **Recommended: adopt baseline.**
9. A bank-side deletion of an imported requirement or task: show it in the dry-run, but write it to OpenSpec only with `export --allow-delete`? **Recommended: yes.**
10. `/mb work <change-id>`: import-or-sync first, stop on conflict, dry-run export at the end and ask before `--write` (A)? **Recommended: yes.**
11. `export --new` in Stage 9 with the guards above (A), or defer (B)? **Recommended: A.**

STATUS: DONE
