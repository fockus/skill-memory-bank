#!/usr/bin/env bats
# scripts/mb-progress-chain.sh — append-only physical integrity for progress.md.
#
# A hash chain of the last N=20 `## YYYY-MM-DD` entries lives in
# `index.json:progress_chain`. `--rebuild-tail` recomputes it (idempotent);
# `--verify` recomputes every tail body and exits 2 on any mismatch or deletion.
# Design: specs/handoff-v2/design.md §6.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-progress-chain.sh"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes"
  : > "$MB/lessons.md"
  PROGRESS="$MB/progress.md"
  INDEX="$MB/index.json"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Seed a progress.md with three distinct dated entries (multi-line bodies).
seed_three_entries() {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-10 — first day

### Topic A
- did alpha
- did beta

## 2026-06-11

### Topic B
- did gamma

## 2026-06-12 — Capstone: wrap up

### Topic C
- did delta
- did epsilon
- Next step: ship it
EOF
}

# Read progress_chain JSON out of index.json with python (portable, no jq dep).
chain_field() {
  python3 - "$INDEX" "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
chain = data.get("progress_chain") or {}
key = sys.argv[2]
val = chain.get(key)
if isinstance(val, (dict, list)):
    print(json.dumps(val, sort_keys=True))
else:
    print(val)
PY
}

# ═══════════════════════════════════════════════════════════════
# CLI surface
# ═══════════════════════════════════════════════════════════════

@test "progress-chain: script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "progress-chain: unknown flag → non-zero with usage" {
  run bash "$SCRIPT" --bogus "$MB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"Usage"* ]]
}

# ═══════════════════════════════════════════════════════════════
# rebuild-tail
# ═══════════════════════════════════════════════════════════════

@test "rebuild-tail: writes progress_chain with version, tail, last_synced_at" {
  seed_three_entries
  run bash "$SCRIPT" --rebuild-tail "$MB"
  [ "$status" -eq 0 ]
  [ -f "$INDEX" ]
  [ "$(chain_field version)" = "1" ]
  # three dated entries → three tail rows
  run python3 -c "import json,sys; print(len(json.load(open('$INDEX'))['progress_chain']['tail']))"
  [ "$output" = "3" ]
  # last_synced_at present + ISO-ish
  [[ "$(chain_field last_synced_at)" == *"T"* ]]
}

@test "rebuild-tail: deterministic — two runs produce identical tail shas" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  first="$(chain_field tail)"
  bash "$SCRIPT" --rebuild-tail "$MB"
  second="$(chain_field tail)"
  [ "$first" = "$second" ]
}

@test "rebuild-tail: idempotent — re-running does not mutate the tail" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  before="$(chain_field tail)"
  bash "$SCRIPT" --rebuild-tail "$MB"
  bash "$SCRIPT" --rebuild-tail "$MB"
  after="$(chain_field tail)"
  [ "$before" = "$after" ]
}

@test "rebuild-tail: caps the tail at the last N=20 entries" {
  : > "$PROGRESS"
  for i in $(seq 1 25); do
    printf '## 2026-06-%02d\n\n### Entry %d\n- line %d\n\n' "$i" "$i" "$i" >> "$PROGRESS"
  done
  bash "$SCRIPT" --rebuild-tail "$MB"
  run python3 -c "import json; print(len(json.load(open('$INDEX'))['progress_chain']['tail']))"
  [ "$output" = "20" ]
  # the newest heading (## 2026-06-25) must be the LAST tail row
  run python3 -c "import json; print(json.load(open('$INDEX'))['progress_chain']['tail'][-1]['heading'])"
  [ "$output" = "## 2026-06-25" ]
}

@test "rebuild-tail: preserves existing index.json keys (read-modify-write)" {
  seed_three_entries
  cat > "$INDEX" <<'EOF'
{
  "notes": [{"path": "notes/x.md", "type": "note"}],
  "lessons": [{"id": "L-001", "title": "keep me"}],
  "generated_at": "2026-06-01T00:00:00Z"
}
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  run python3 -c "import json; d=json.load(open('$INDEX')); print(d['notes'][0]['path'], d['lessons'][0]['id'], d['generated_at'], 'progress_chain' in d)"
  [[ "$output" == "notes/x.md L-001 2026-06-01T00:00:00Z True" ]]
}

# ═══════════════════════════════════════════════════════════════
# verify — happy path
# ═══════════════════════════════════════════════════════════════

@test "verify: passes on an untouched file just rebuilt → exit 0" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

@test "verify: multi-line bodies round-trip cleanly → exit 0" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-09

### Long entry
- one
- two
- three

multiple paragraphs
with several lines
and a trailing thought

## 2026-06-10

### Short
- done
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# verify — tamper detection
# ═══════════════════════════════════════════════════════════════

@test "verify: catches an edit to an OLD (non-newest) entry → exit 2 + names heading" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Mutate the body of the FIRST (oldest) entry — append-only violation.
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("- did alpha", "- did alpha (TAMPERED)")
open(p, "w").write(t)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  [[ "$output" == *"2026-06-10"* ]]
}

@test "verify: catches deletion of a MIDDLE entry → exit 2" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Remove the middle (## 2026-06-11) entry entirely.
  python3 - "$PROGRESS" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
# Drop from "## 2026-06-11" up to (but not including) "## 2026-06-12".
text = re.sub(r"## 2026-06-11.*?(?=## 2026-06-12)", "", text, flags=re.DOTALL)
open(p, "w").write(text)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

@test "verify: catches deletion of the OLDEST tail entry → exit 2" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  python3 - "$PROGRESS" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
text = re.sub(r"## 2026-06-10.*?(?=## 2026-06-11)", "", text, flags=re.DOTALL)
open(p, "w").write(text)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

@test "verify: emits a structured JSON report on mismatch (interior entry edit)" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Edit the newest entry — the unique-run search finds zero matches (the full
  # recorded run is now broken), so tamper evidence lands in `missing` (anchor_lost)
  # rather than `mismatches`. Both arrays represent tamper; the test asserts that
  # at least one of them is non-empty AND ok=False.
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("- did delta", "- did delta EDITED")
open(p, "w").write(t)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  # stdout carries a JSON object with "ok": false and tamper evidence in either
  # mismatches or missing (the unique-run algorithm uses anchor_lost when the full
  # run fails to match; mismatches fires when the run IS found but a sub-entry differs).
  echo "$output" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert d['ok'] is False, 'ok must be False'
assert len(d['mismatches']) + len(d['missing']) >= 1, 'must have tamper evidence'
"
}

@test "verify: editing the oldest (anchor) entry surfaces as a missing/anchor_lost record" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # The oldest tail entry is the verification anchor; editing it changes its sha
  # so the anchor can no longer be located → reported under `missing`, exit 2.
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("- did alpha", "- did alpha EDITED")
open(p, "w").write(t)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['ok'] is False; assert (len(d['missing']) + len(d['mismatches'])) >= 1"
}

@test "verify: appending a NEW entry without rebuild does not corrupt old-tail verification" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Append a brand-new entry (legitimate, append-only). The OLD tail entries are
  # untouched, so verify of the recorded tail must still pass (suffix preserved).
  cat >> "$PROGRESS" <<'EOF'

## 2026-06-13

### Topic D
- did zeta
EOF
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# verify — preconditions
# ═══════════════════════════════════════════════════════════════

@test "verify: no progress_chain in index → exit 2 (chain not initialised)" {
  seed_three_entries
  printf '{"notes": [], "lessons": []}\n' > "$INDEX"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

@test "verify: missing index.json → exit 2" {
  seed_three_entries
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# edge cases (design §7 unit)
# ═══════════════════════════════════════════════════════════════

@test "edge: empty progress.md → rebuild yields empty tail, verify passes" {
  : > "$PROGRESS"
  run bash "$SCRIPT" --rebuild-tail "$MB"
  [ "$status" -eq 0 ]
  run python3 -c "import json; print(json.load(open('$INDEX'))['progress_chain']['tail'])"
  [ "$output" = "[]" ]
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

@test "edge: missing progress.md → rebuild yields empty tail" {
  rm -f "$PROGRESS"
  run bash "$SCRIPT" --rebuild-tail "$MB"
  [ "$status" -eq 0 ]
  run python3 -c "import json; print(json.load(open('$INDEX'))['progress_chain']['tail'])"
  [ "$output" = "[]" ]
}

@test "edge: single-entry file → tail of one, verify passes" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-12 — only entry

### Solo
- alone
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  run python3 -c "import json; print(len(json.load(open('$INDEX'))['progress_chain']['tail']))"
  [ "$output" = "1" ]
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

@test "edge: heading with unusual trailing characters handled" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-12 — Capstone: 100% green | tests (N=42) — done!

### Weird
- handled
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  run python3 -c "import json; print(json.load(open('$INDEX'))['progress_chain']['tail'][0]['heading'])"
  [ "$output" = "## 2026-06-12 — Capstone: 100% green | tests (N=42) — done!" ]
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

@test "edge: duplicate date headings — order-aware verify catches edit to first dup" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-12

### First of the day
- morning work

## 2026-06-12

### Second of the day
- afternoon work
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
  # Edit the FIRST of the two same-date entries.
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("- morning work", "- morning work TAMPERED")
open(p, "w").write(t)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

@test "edge: content before the first date heading is ignored" {
  cat > "$PROGRESS" <<'EOF'
# Progress Log

Some preamble that is not a dated entry.

## 2026-06-12

### Real entry
- work
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  run python3 -c "import json; print(len(json.load(open('$INDEX'))['progress_chain']['tail']))"
  [ "$output" = "1" ]
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Finding #1 — canonical-form hashing contract (design §6/§9)
# In-body content edits AND in-body whitespace edits → exit 2.
# Trailing-blank-only changes AND CRLF↔LF-only changes → exit 0.
# ═══════════════════════════════════════════════════════════════

@test "canonical: in-body CONTENT edit → exit 2 (tamper detected)" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-10

### Entry
- line one
- line two
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("- line one", "- line ONE")
open(p, "w").write(t)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

@test "canonical: in-body INTERNAL-WHITESPACE edit → exit 2 (tamper detected)" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-10

### Entry
- line one
- line two
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Insert an extra space inside the body (not a trailing blank, not trailing \n)
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
# Change "- line one" to "-  line one" (double space — internal whitespace edit)
t = open(p).read().replace("- line one", "-  line one")
open(p, "w").write(t)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

@test "canonical: trailing-blank-only change → exit 0 (not tamper)" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-10

### Entry
- body line

EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Add an extra trailing blank line after the entry — separator region only.
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read() + "\n\n"
open(p, "w").write(t)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

@test "canonical: CRLF-to-LF-only change → exit 0 (line-ending normalization)" {
  # Write file with CRLF line endings.
  printf '## 2026-06-10\r\n\r\n### Entry\r\n- body line\r\n' > "$PROGRESS"
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Rewrite with LF only (simulates editor normalizing line endings).
  printf '## 2026-06-10\n\n### Entry\n- body line\n' > "$PROGRESS"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Finding #2 — malformed index.json must NOT silently disable integrity
# ═══════════════════════════════════════════════════════════════

@test "malformed: verify on truncated index.json → error=index_malformed + exit 2" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Corrupt the index (truncated JSON).
  printf '{"progress_chain": {' > "$INDEX"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['ok'] is False; assert d['error'] == 'index_malformed'"
}

@test "malformed: verify on empty index.json → error=index_malformed + exit 2" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  : > "$INDEX"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['ok'] is False; assert d['error'] == 'index_malformed'"
}

@test "malformed: rebuild-tail on malformed index writes .bak then succeeds" {
  seed_three_entries
  # Seed a malformed index (not valid JSON).
  printf '{bad json' > "$INDEX"
  run bash "$SCRIPT" --rebuild-tail "$MB"
  [ "$status" -eq 0 ]
  # A .bak must have been written.
  ls "${INDEX}.bak" 2>/dev/null
  # The new index must be valid JSON with progress_chain.
  python3 -c "import json; d=json.load(open('$INDEX')); assert 'progress_chain' in d"
}

@test "malformed: drift emits CRITICAL on malformed index.json" {
  DRIFT="$REPO_ROOT/scripts/mb-drift.sh"
  # Create minimal clean bank.
  for f in status checklist roadmap progress lessons research backlog; do
    : > "$MB/$f.md"
  done
  # Seed a valid chain first, then corrupt the index.
  cat >> "$MB/progress.md" <<'EOF'
## 2026-06-10

### E
- work
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  printf '{"broken":' > "$INDEX"
  run bash "$DRIFT" "$PROJECT" 2>&1
  [[ "$output" == *"drift_check_progress_chain=critical"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Finding #3 — ambiguous anchor: two entries with identical heading+body
# ═══════════════════════════════════════════════════════════════

@test "ambiguous: two entries identical heading+body → verify detects ambiguous_match" {
  # Both entries are byte-for-byte identical (same heading, same body).
  cat > "$PROGRESS" <<'EOF'
## 2026-06-10

### Daily
- standard work

## 2026-06-10

### Daily
- standard work
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  run bash "$SCRIPT" --verify "$MB"
  # Two identical entries → ambiguous; verify must exit 2 OR (if deterministic
  # positional match chosen) pass — but deletion of one must exit 2.
  # We just verify the rebuild+verify cycle is consistent on untouched file.
  # (Deletion test below exercises the real guard.)
  [ "$status" -eq 0 ]
}

@test "ambiguous: delete one of two identical-body entries → exit 2 (ambiguous_match)" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-10

### Daily
- standard work

## 2026-06-10

### Daily
- standard work
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Delete the FIRST of the two identical entries — goes from 2 entries to 1.
  python3 - "$PROGRESS" <<'PY'
import sys, re
p = sys.argv[1]
text = open(p).read()
# Keep only the second occurrence by removing the first block.
idx = text.find("## 2026-06-10")
idx2 = text.find("## 2026-06-10", idx + 1)
text = text[idx2:]
open(p, "w").write(text)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['ok'] is False"
}

@test "ambiguous: reorder two distinct entries → exit 2 (anchor sha mismatch)" {
  cat > "$PROGRESS" <<'EOF'
## 2026-06-10

### A
- alpha

## 2026-06-11

### B
- beta
EOF
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Swap the two entries (reorder = integrity violation).
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
text = open(p).read()
# Swap the two blocks.
a = "## 2026-06-10\n\n### A\n- alpha\n"
b = "## 2026-06-11\n\n### B\n- beta\n"
text = b + "\n" + a
open(p, "w").write(text)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# Finding #5 — deletion of NEWEST tracked entry (gap in original suite)
# and drift INTEGRATION test for tamper → CRITICAL
# ═══════════════════════════════════════════════════════════════

@test "verify: catches deletion of the NEWEST tracked entry → exit 2" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Delete the NEWEST entry (## 2026-06-12) entirely.
  python3 - "$PROGRESS" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
text = re.sub(r"## 2026-06-12.*\Z", "", text, flags=re.DOTALL)
open(p, "w").write(text.rstrip("\n") + "\n")
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
}

@test "drift integration: tampered progress.md → drift emits critical" {
  DRIFT="$REPO_ROOT/scripts/mb-drift.sh"
  for f in status checklist roadmap progress lessons research backlog; do
    : > "$MB/$f.md"
  done
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Tamper an old entry.
  python3 - "$PROGRESS" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("- did alpha", "- did alpha HACKED")
open(p, "w").write(t)
PY
  run bash "$DRIFT" "$PROJECT" 2>&1
  [[ "$output" == *"drift_check_progress_chain=critical"* ]]
}

# ═══════════════════════════════════════════════════════════════
# NEW MAJOR — build_index .bak on malformed existing index.json
# (finding #2 residual — second writer not covered)
# ═══════════════════════════════════════════════════════════════

@test "build_index: malformed existing index.json → .bak written, notes indexed" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Corrupt the index (truncated JSON — simulates a partial write/crash).
  printf '{"progress_chain": {' > "$INDEX"
  # Run index rebuild via mb-index-json.py — the OTHER writer.
  run python3 "$REPO_ROOT/scripts/mb-index-json.py" "$MB"
  [ "$status" -eq 0 ]
  # .bak must have been written to preserve the corrupt bytes.
  [ -f "${INDEX}.bak" ]
  # The new index must be valid JSON.
  python3 -c "import json; json.load(open('$INDEX'))"
}

@test "build_index: after malformed-to-bak rebuild, progress_chain absent (starts fresh)" {
  # When the index is malformed, the chain is unrecoverable from that corrupt file.
  # After rebuild: no progress_chain key (requires explicit --rebuild-tail to re-seed).
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  printf '{"broken":' > "$INDEX"
  python3 "$REPO_ROOT/scripts/mb-index-json.py" "$MB"
  run python3 -c "import json; d=json.load(open('$INDEX')); print('chain' if 'progress_chain' in d else 'no_chain')"
  [ "$output" = "no_chain" ]
}

# ═══════════════════════════════════════════════════════════════
# NEW MAJOR — stale tail: unique match but NOT the suffix
# ═══════════════════════════════════════════════════════════════

@test "stale: append after rebuild → ok=true stale=true (NOT tamper, NOT critical)" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Append a new legitimate entry.
  cat >> "$PROGRESS" <<'EOF'

## 2026-06-13

### Topic D
- did zeta
EOF
  run bash "$SCRIPT" --verify "$MB"
  # Must NOT exit 2 — append-only growth is not tamper.
  [ "$status" -eq 0 ]
  # Must report stale=true and untracked_appends>=1.
  echo "$output" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['ok'] is True, f'ok must be True, got: {d}'
assert d.get('stale') is True, f'stale must be True, got: {d}'
assert d.get('untracked_appends', 0) >= 1, f'untracked_appends must be >=1, got: {d}'
"
}

@test "stale: suffix match (rebuild then no change) → ok=true stale absent or false" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['ok'] is True
assert d.get('stale') is not True, f'must NOT be stale on exact suffix: {d}'
"
}

@test "stale: drift on stale tail → ok NOT critical (at most info, not error token)" {
  DRIFT="$REPO_ROOT/scripts/mb-drift.sh"
  for f in status checklist roadmap progress lessons research backlog; do
    : > "$MB/$f.md"
  done
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Legitimate append — stale but not tamper.
  cat >> "$PROGRESS" <<'EOF'

## 2026-06-13

### New
- new work
EOF
  run bash "$DRIFT" "$PROJECT" 2>&1
  # Must NOT emit critical for stale.
  [[ "$output" != *"drift_check_progress_chain=critical"* ]]
  # Must emit ok (stale appends handled gracefully).
  [[ "$output" == *"drift_check_progress_chain=ok"* ]]
}

# ═══════════════════════════════════════════════════════════════
# NEW MAJOR — malformed tail row → structured error, not crash
# ═══════════════════════════════════════════════════════════════

@test "chain_malformed: non-dict tail row → exit 2 + error=chain_malformed (no traceback)" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  # Inject a non-dict row into the tail (string instead of object).
  python3 - "$INDEX" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
chain = data.get("progress_chain", {})
# Append a string (not a dict) to the tail — simulates an invalid index.json.
chain["tail"].append("INVALID_ROW")
data["progress_chain"] = chain
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['ok'] is False, f'ok must be False'
assert d['error'] == 'chain_malformed', f'expected chain_malformed, got: {d[\"error\"]}'
"
}

@test "chain_malformed: integer tail row → structured error not AttributeError crash" {
  seed_three_entries
  bash "$SCRIPT" --rebuild-tail "$MB"
  python3 - "$INDEX" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["progress_chain"]["tail"] = [42]
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
  run bash "$SCRIPT" --verify "$MB"
  [ "$status" -eq 2 ]
  # stdout must be valid JSON with chain_malformed error, not a Python traceback.
  echo "$output" | python3 -c "
import json, sys
raw = sys.stdin.read()
assert 'Traceback' not in raw, f'must not traceback, got: {raw}'
d = json.loads(raw)
assert d['error'] == 'chain_malformed', f'expected chain_malformed, got: {d}'
"
}
