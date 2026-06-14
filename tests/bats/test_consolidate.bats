#!/usr/bin/env bats
# mb-consolidate.sh — /mb consolidate: fold OLD sessions + contiguous auto-capture
# progress STUBS into durable notes/ patterns + an archive, with ZERO LLM calls.
# Dry-run is the DEFAULT and writes NOTHING; --apply performs the (verbatim) moves.
# Covers spec tier1-graph-memory REQ-012, REQ-013, REQ-014 + Scenario 11.
#
# Invariants asserted here:
#   1. dry-run leaves the bank BYTE-IDENTICAL (sha256 of every file before == after).
#   2. --apply on a windowed fixture with shared files-touched → note(s) in the
#      5-15 line pattern format; windowed session files moved VERBATIM (sha256 of
#      the archived copy equals the pre-move sha256); a pointer line appended to
#      progress.md; _recent.md has no dangling refs to archived sessions.
#   3. REAL (non-stub) progress entries are NEVER moved by --apply (verbatim intact).
#   4. <2 windowed sessions / empty window → empty output, exit 0, bank unchanged.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-consolidate.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/session" "$MB/notes"

  # ── Two OLD sessions that SHARE files-touched (scripts/mb-foo.py) and overlap
  # lexically ("token leak fix"). They cluster → a recurring fact → a note. Both
  # are aged > 30 days via `touch -t` so they fall inside the default window. ───
  # NOTE: the Live-log bullets use the CURRENT live-log format written by
  # hooks/mb-session-turn.sh — with the trailing outcome + diffstat segments:
  #   - HH:MM — User: "<text>" · tools: <T> · files: <F> · <ok|err(N)>[ · +A/-B]
  # The ` · ok · +A/-B` tail MUST NOT leak into the parsed file list (finding #4).
  OLD_A="$MB/session/2026-01-02_1000_aaaaaaaa.md"
  cat > "$OLD_A" <<'EOF'
---
session_id: aaaaaaaa-0000-0000-0000-000000000001
started: 2026-01-02T10:00Z
branch: main
turns: 4
summarized: true
---

## Live log
- 10:00 — User: "fix the token leak in the foo extractor" · tools: Edit,Bash · files: scripts/mb-foo.py · ok · +12/-3

## Summary
### What changed
- Patched the token leak in scripts/mb-foo.py
### Decisions
- (none)
### Open questions
- (none)
### Files
- scripts/mb-foo.py
EOF

  OLD_B="$MB/session/2026-01-03_1100_bbbbbbbb.md"
  cat > "$OLD_B" <<'EOF'
---
session_id: bbbbbbbb-0000-0000-0000-000000000002
started: 2026-01-03T11:00Z
branch: main
turns: 6
summarized: true
---

## Live log
- 11:00 — User: "the token leak is back in foo, finish the fix" · tools: Edit,Bash · files: scripts/mb-foo.py · err(1) · +4/-1

## Summary
### What changed
- Completed the token leak fix in scripts/mb-foo.py
### Decisions
- (none)
### Open questions
- (none)
### Files
- scripts/mb-foo.py
EOF

  # An OLD session eeeeeeee that ALSO touches scripts/mb-foo.py → it clusters and
  # IS archived this run (its sid IS in the consolidated set). Its progress block,
  # however, carries an extra hand-written line → not a pure stub → the SHAPE check
  # (not the session-id filter) is the sole guard keeping it in progress.md (#3).
  OLD_E="$MB/session/2026-01-04_1200_eeeeeeee.md"
  cat > "$OLD_E" <<'EOF'
---
session_id: eeeeeeee-0000-0000-0000-000000000005
started: 2026-01-04T12:00Z
branch: main
turns: 3
summarized: true
---

## Live log
- 12:00 — User: "more on the token leak in foo" · tools: Edit · files: scripts/mb-foo.py · ok · +2/-0

## Summary
### What changed
- Touched the token leak area in scripts/mb-foo.py
### Files
- scripts/mb-foo.py
EOF

  # A RECENT session (inside the window's protected zone — NOT old) that must
  # never be archived nor clustered. Uses an unrelated file.
  NEW_C="$MB/session/2026-06-10_0900_cccccccc.md"
  cat > "$NEW_C" <<'EOF'
---
session_id: cccccccc-0000-0000-0000-000000000003
started: 2026-06-10T09:00Z
branch: main
turns: 2
summarized: true
---

## Live log
- 09:00 — User: "tweak the readme" · tools: Edit · files: README.md

## Summary
### What changed
- Edited README.md
EOF

  # Age the OLD sessions well beyond the 30-day default window; keep NEW_C fresh.
  touch -t 202601021000 "$OLD_A"
  touch -t 202601031100 "$OLD_B"
  touch -t 202601041200 "$OLD_E"
  touch -t 202606100900 "$NEW_C"

  # ── progress.md: a mix the splitter must classify EXACTLY (findings #1, #2, #3):
  #   - one REAL entry (immutable, never moves);
  #   - the two canonical hook stubs for the ARCHIVED sessions aaaaaaaa/bbbbbbbb
  #     (the ONLY blocks that may move — verbatim);
  #   - a stub for an UNRELATED/recent session dddddddd whose session file is NOT
  #     in the window → must NOT move even though it is a canonical stub (finding #1);
  #   - a date block that carries the Auto-capture heading PLUS extra real content →
  #     not a pure stub → must NOT move (finding #3).
  # The exact stub bytes mirror hooks/session-end-autosave.sh:95-100 verbatim.
  PROGRESS="$MB/progress.md"
  cat > "$PROGRESS" <<'EOF'
# Progress Log

## 2026-06-12 (real entry — token leak followup)

### Done
- A real, immutable entry that must never be moved or rewritten.

## 2026-01-02

### Auto-capture 2026-01-02 (session aaaaaaaa)
- Session ended without an explicit /mb done
- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized

## 2026-01-03

### Auto-capture 2026-01-03 (session bbbbbbbb)
- Session ended without an explicit /mb done
- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized

## 2026-06-11

### Auto-capture 2026-06-11 (session dddddddd)
- Session ended without an explicit /mb done
- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized

## 2026-01-04

### Auto-capture 2026-01-04 (session eeeeeeee)
- Session ended without an explicit /mb done
- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized
- Plus an extra hand-written line that makes this NOT a pure stub block.
EOF

  # A pre-existing _recent.md that references one of the soon-to-be-archived
  # sessions — after --apply it must carry NO dangling ref to an archived session.
  cat > "$MB/session/_recent.md" <<'EOF'
## 2026-01-02 10:00 (main) — aaaaaaaa
Patched the token leak in scripts/mb-foo.py

## 2026-06-10 09:00 (main) — cccccccc
Edited README.md
EOF
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# sha256 helper (macOS `shasum -a 256` / Linux `sha256sum`)
_sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || sha256sum "$1" | awk '{print $1}'; }

# Snapshot "path<TAB>sha256" for every regular file under the bank, sorted by path.
_bank_snapshot() {
  find "$MB" -type f | LC_ALL=C sort | while read -r f; do
    rel="${f#"$MB"/}"
    printf '%s\t%s\n' "$rel" "$(_sha "$f")"
  done
}

# ── Scenario 11 item 1: dry-run (DEFAULT) → bank is BYTE-IDENTICAL afterward ───
@test "consolidate: dry-run (default) writes NOTHING — bank byte-identical (REQ-012, Scenario 11)" {
  before="$(_bank_snapshot)"
  run bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  after="$(_bank_snapshot)"
  [ "$before" = "$after" ]
  # No mutation side effects whatsoever.
  [ ! -d "$MB/session/archive" ]
  [ ! -f "$MB/progress-archive.md" ]
  # No new note files were written (notes/ stays empty).
  [ -z "$(find "$MB/notes" -type f 2>/dev/null)" ]
}

# ── Scenario 11 item 1b: dry-run still REPORTS the cluster it would consolidate ─
@test "consolidate: dry-run names the cluster/candidate it would create, exit 0 (REQ-012)" {
  run bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  # the shared file that links the two old sessions is surfaced in the plan
  echo "$output" | grep -q 'mb-foo.py'
}

# ── Scenario 11 item 2: --apply → note in 5-15 lines + verbatim session moves ──
@test "consolidate: --apply creates a 5-15 line note, moves sessions verbatim, appends a pointer (REQ-013, REQ-014, Scenario 11)" {
  # Pre-move checksums of the windowed session files (must survive the move byte-for-byte).
  sha_a="$(_sha "$OLD_A")"
  sha_b="$(_sha "$OLD_B")"

  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]

  # (a) a note candidate was written to notes/ …
  note_count="$(find "$MB/notes" -name '*.md' -type f | wc -l | tr -d ' ')"
  [ "$note_count" -ge 1 ]
  # … in the 5-15 line pattern format (every emitted note is within [5,15] lines).
  while IFS= read -r note; do
    [ -n "$note" ] || continue
    lines="$(wc -l < "$note" | tr -d ' ')"
    [ "$lines" -ge 5 ]
    [ "$lines" -le 15 ]
  done < <(find "$MB/notes" -name '*.md' -type f)

  # (b) the windowed session files were MOVED VERBATIM into session/archive/.
  [ -d "$MB/session/archive" ]
  [ ! -f "$OLD_A" ]
  [ ! -f "$OLD_B" ]
  arch_a="$MB/session/archive/$(basename "$OLD_A")"
  arch_b="$MB/session/archive/$(basename "$OLD_B")"
  [ -f "$arch_a" ]
  [ -f "$arch_b" ]
  # byte-for-byte identical content after the move (checksum equality).
  [ "$(_sha "$arch_a")" = "$sha_a" ]
  [ "$(_sha "$arch_b")" = "$sha_b" ]

  # (c) the RECENT session was left in place (not archived).
  [ -f "$NEW_C" ]
  [ ! -f "$MB/session/archive/$(basename "$NEW_C")" ]

  # (d) a pointer line per consolidated batch was appended to progress.md, naming
  # the archive file.
  grep -q 'progress-archive.md' "$PROGRESS"

  # (e) _recent.md rebuilt with NO dangling ref to an archived session id.
  [ -f "$MB/session/_recent.md" ]
  ! grep -q 'aaaaaaaa' "$MB/session/_recent.md"
}

# ── Scenario 11 item 2b: contiguous progress STUBS move VERBATIM to the archive ─
@test "consolidate: --apply moves contiguous auto-capture stubs verbatim to progress-archive.md (REQ-013)" {
  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  # the archive file now exists and carries the verbatim stub headings.
  [ -f "$MB/progress-archive.md" ]
  grep -q '### Auto-capture 2026-01-02 (session aaaaaaaa)' "$MB/progress-archive.md"
  grep -q '### Auto-capture 2026-01-03 (session bbbbbbbb)' "$MB/progress-archive.md"
  # the stubs are GONE from progress.md (moved, not duplicated).
  ! grep -q '### Auto-capture 2026-01-02 (session aaaaaaaa)' "$PROGRESS"
  ! grep -q '### Auto-capture 2026-01-03 (session bbbbbbbb)' "$PROGRESS"
}

# ── finding #2 + #6: the moved stub bytes AND the surviving real bytes are exact ─
# A byte-preserving splitter must (a) move the archived stub blocks byte-for-byte
# and (b) leave every kept (real) entry byte-identical. We capture exact pre-apply
# sha256 of the canonical stub block bytes and of the real-entry bytes, then assert
# the archive slice contains the former verbatim and progress.md the latter.
@test "consolidate: --apply preserves moved-stub bytes and surviving real bytes exactly (REQ-013, finding #2/#6)" {
  # Exact bytes of the two movable stub blocks (heading line through the 2nd bullet),
  # taken from the live progress.md fixture so the comparison is byte-true.
  expected_stub_a="$(printf '## 2026-01-02\n\n### Auto-capture 2026-01-02 (session aaaaaaaa)\n- Session ended without an explicit /mb done\n- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized\n')"
  expected_stub_b="$(printf '## 2026-01-03\n\n### Auto-capture 2026-01-03 (session bbbbbbbb)\n- Session ended without an explicit /mb done\n- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized\n')"

  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  [ -f "$MB/progress-archive.md" ]

  # (a) the archive carries each moved block VERBATIM (exact multi-line substring).
  archive_body="$(cat "$MB/progress-archive.md")"
  case "$archive_body" in
    *"$expected_stub_a"*) : ;;
    *) echo "archive missing verbatim stub A" >&2; false ;;
  esac
  case "$archive_body" in
    *"$expected_stub_b"*) : ;;
    *) echo "archive missing verbatim stub B" >&2; false ;;
  esac

  # (b) the surviving progress.md keeps the real entry's bytes byte-identical.
  expected_real="$(printf '## 2026-06-12 (real entry — token leak followup)\n\n### Done\n- A real, immutable entry that must never be moved or rewritten.\n')"
  kept_body="$(cat "$PROGRESS")"
  case "$kept_body" in
    *"$expected_real"*) : ;;
    *) echo "kept progress.md mangled the real entry bytes" >&2; false ;;
  esac
}

# ── finding #2 (strengthened): PROVE byte-identity with `cmp` on real file slices ─
# The previous regression compared `$(cat …)` substrings, which strips trailing
# newlines and cannot see non-ASCII / backslash / no-final-newline mangling. This
# rebuilds progress.md with the hard cases — Cyrillic + emoji, backslashes, and NO
# trailing newline — and asserts, byte-for-byte via `cmp`:
#   (a) the surviving (stub-free) progress.md PREFIX == the original real-entry bytes;
#   (b) the archived stub slice bytes == the original stub bytes;
#   (c) a non-windowed / impure block is left untouched.
@test "consolidate: --apply is byte-identical (cmp on slices: Cyrillic+emoji, backslash, no-final-newline) (REQ-013, finding #2)" {
  # Build the exact-bytes building blocks in temp files (so we can `cmp` later).
  real_bytes="$BATS_TEST_TMPDIR/real.bytes"
  stub_a_bytes="$BATS_TEST_TMPDIR/stub_a.bytes"
  impure_bytes="$BATS_TEST_TMPDIR/impure.bytes"

  # Real entry: Cyrillic + emoji + literal backslashes; this block must survive verbatim.
  printf '## 2026-06-12 (правка 🚀 C:\\Users\\x — regex \\d+)\n\n### Done\n- готово ✅ \\n literal\n' > "$real_bytes"
  # Canonical movable stub for the archived session aaaaaaaa (mirrors hook bytes).
  printf '## 2026-01-02\n\n### Auto-capture 2026-01-02 (session aaaaaaaa)\n- Session ended without an explicit /mb done\n- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized\n' > "$stub_a_bytes"
  # Impure block: canonical heading PLUS an extra hand-written line → must NOT move.
  printf '## 2026-06-11\n\n### Auto-capture 2026-06-11 (session dddddddd)\n- Session ended without an explicit /mb done\n- Summary auto-captured to session/ (searchable via /mb recall); core files were not actualized\n- extra C:\\path line keeps this impure\n' > "$impure_bytes"

  # Assemble progress.md = real + stub_a + impure, then strip the single trailing
  # newline so the file ends WITHOUT a final newline (the no-final-newline path on
  # the LAST block). `head -c` is byte-exact (unlike `$(…)`, which strips newlines).
  cat "$real_bytes" "$stub_a_bytes" "$impure_bytes" > "$PROGRESS"
  total="$(wc -c < "$PROGRESS")"
  head -c "$((total - 1))" "$PROGRESS" > "$PROGRESS.tmp"
  mv "$PROGRESS.tmp" "$PROGRESS"
  # The impure block now lacks its final newline; reflect that in the expected bytes.
  imp_total="$(wc -c < "$impure_bytes")"
  head -c "$((imp_total - 1))" "$impure_bytes" > "$impure_bytes.nonl"
  mv "$impure_bytes.nonl" "$impure_bytes"

  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  [ -f "$MB/progress-archive.md" ]

  # (a)+(c) the surviving progress.md begins with EXACTLY real_bytes+impure_bytes —
  # one byte-true `cmp` of the whole kept prefix (catches a stray injected/normalized
  # terminator anywhere in the real OR impure block, which a per-block slice misses).
  real_len="$(wc -c < "$real_bytes")"
  impure_len="$(wc -c < "$impure_bytes")"
  prefix_len="$((real_len + impure_len))"
  cat "$real_bytes" "$impure_bytes" > "$BATS_TEST_TMPDIR/expected_prefix"
  head -c "$prefix_len" "$PROGRESS" > "$BATS_TEST_TMPDIR/kept_prefix.slice"
  cmp "$BATS_TEST_TMPDIR/kept_prefix.slice" "$BATS_TEST_TMPDIR/expected_prefix"
  # The 4 bytes immediately after the prefix must be EXACTLY the appended pointer's
  # start: '\n## ' = 0a 23 23 20. A stray injected/normalized terminator at the
  # impure-block boundary would show up here as '\n\n##' (0a 0a 23 23) instead.
  boundary="$(tail -c "+$((prefix_len + 1))" "$PROGRESS" | head -c 4 | od -An -tx1 | tr -d ' \n')"
  [ "$boundary" = "0a232320" ]

  # (b) the archived stub slice equals the original stub bytes EXACTLY. The archive
  # is a fixed 4-line header followed by the moved block(s); locate the stub by
  # finding its byte offset and cmp the exact-length slice.
  stub_len="$(wc -c < "$stub_a_bytes")"
  off="$(LC_ALL=C grep -abo '## 2026-01-02' "$MB/progress-archive.md" | head -1 | cut -d: -f1)"
  [ -n "$off" ]
  tail -c "+$((off + 1))" "$MB/progress-archive.md" | head -c "$stub_len" \
    > "$BATS_TEST_TMPDIR/archived_stub.slice"
  cmp "$BATS_TEST_TMPDIR/archived_stub.slice" "$stub_a_bytes"

  # (c) the impure / non-windowed block was NEVER copied into the archive.
  ! grep -q 'extra C:.path line keeps this impure' "$MB/progress-archive.md"
}

# ── finding #1: a canonical stub for a NON-windowed (recent/unrelated) session is
# NEVER moved — applying one old cluster must not archive an unrelated stub. ──────
@test "consolidate: --apply leaves stubs of non-windowed sessions in place (finding #1)" {
  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  # session dddddddd is recent / not in the consolidated set → its stub stays put.
  grep -q '### Auto-capture 2026-06-11 (session dddddddd)' "$PROGRESS"
  # … and was NOT copied into the archive.
  [ -f "$MB/progress-archive.md" ]
  ! grep -q '### Auto-capture 2026-06-11 (session dddddddd)' "$MB/progress-archive.md"
}

# ── finding #3: a date block that has the Auto-capture heading PLUS real content is
# NOT a pure stub and must NEVER move (data-loss guard). ──────────────────────────
@test "consolidate: --apply never moves a block that has the stub heading PLUS extra real content (finding #3)" {
  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  # the eeeeeeee block has an extra hand-written line → not a pure stub → stays.
  grep -q '### Auto-capture 2026-01-04 (session eeeeeeee)' "$PROGRESS"
  grep -q 'Plus an extra hand-written line that makes this NOT a pure stub block.' "$PROGRESS"
  ! grep -q '### Auto-capture 2026-01-04 (session eeeeeeee)' "$MB/progress-archive.md"
}

# ── Scenario 11 item 3: REAL progress entries are NEVER moved by --apply ───────
@test "consolidate: --apply NEVER moves a real (non-stub) progress entry (REQ-013, append-only)" {
  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  # the real entry survives verbatim in progress.md …
  grep -q '## 2026-06-12 (real entry — token leak followup)' "$PROGRESS"
  grep -q 'A real, immutable entry that must never be moved or rewritten.' "$PROGRESS"
  # … and was NOT copied into the archive.
  [ -f "$MB/progress-archive.md" ]
  ! grep -q 'A real, immutable entry that must never be moved or rewritten.' "$MB/progress-archive.md"
}

# ── Scenario 11 item 4: <2 windowed sessions → empty output, exit 0, no writes ─
@test "consolidate: fewer than two windowed sessions → empty output, exit 0, bank unchanged (REQ-012)" {
  # Drop old sessions so only one remains in the window → nothing to consolidate.
  rm -f "$OLD_B" "$OLD_E"
  before="$(_bank_snapshot)"
  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  after="$(_bank_snapshot)"
  [ "$before" = "$after" ]
  [ ! -d "$MB/session/archive" ]
  [ ! -f "$MB/progress-archive.md" ]
}

# ── Empty window (everything recent) → exit 0, no writes even with --apply ─────
@test "consolidate: no sessions older than the window → empty output, exit 0, no writes (REQ-012)" {
  # Make ALL old sessions recent again → empty window.
  touch "$OLD_A" "$OLD_B" "$OLD_E"
  before="$(_bank_snapshot)"
  run bash "$SCRIPT" "$MB" --apply
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  after="$(_bank_snapshot)"
  [ "$before" = "$after" ]
}

# ── --days override narrows/widens the window deterministically ────────────────
@test "consolidate: --days 9999 widens nothing past truly-recent sessions; a huge window still spares the recent session (REQ-012)" {
  run bash "$SCRIPT" "$MB" --days 9999
  [ "$status" -eq 0 ]
  # with a 9999-day window NOTHING is old enough → empty output, no writes.
  [ -z "$output" ]
  [ ! -d "$MB/session/archive" ]
}

# ── -h/--help prints the header and exits 0 ───────────────────────────────────
@test "consolidate: --help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'consolidate'
  echo "$output" | grep -qi 'apply'
}

# ── unknown option → exit 64 ──────────────────────────────────────────────────
@test "consolidate: an unknown option exits 64" {
  run bash "$SCRIPT" "$MB" --bogus
  [ "$status" -eq 64 ]
}

# ── dispatch dir-safety: a RELATIVE bank path from a non-repo CWD must target the
# caller's bank, NOT the repo root. The Python passes `cd "$REPO_ROOT"` for
# `python3 -m`; the bank path must be made absolute against the caller's CWD first,
# else a relative resolver result silently plans the wrong directory (Codex r3). ──
@test "consolidate: relative bank path from a non-repo CWD targets the caller's bank, not the repo root" {
  cd "$PROJECT"                       # caller CWD = project dir, NOT the repo root
  run bash "$SCRIPT" ".memory-bank"   # relative bank path (dry-run default)
  [ "$status" -eq 0 ]
  # The plan must reference THIS temp bank's windowed sessions (unique id aaaaaaaa);
  # without the absolute-path normalization it would resolve against the repo bank,
  # which has no such session, and this assertion would fail.
  [[ "$output" == *"Consolidation plan"* ]]
  [[ "$output" == *"aaaaaaaa"* ]]
}
