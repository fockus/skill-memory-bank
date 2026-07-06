#!/usr/bin/env bats
# mb-conflicts.sh — /mb conflicts: report memory entries with high lexical overlap
# AND opposing assertions as conflict candidates, with ZERO LLM calls. `--judge`
# confirms/rejects each candidate via one Sonnet call and prints a suggested
# [SUPERSEDED] marker — PRINT-ONLY, never writes to any bank file.
# Covers spec tier1-graph-memory REQ-022, REQ-023 + Scenario 12. `claude` is mocked.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-conflicts.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes"

  # ── Scenario 12: the Postgres → MongoDB ledger pair ────────────────────────
  # FAITHFUL to the spec's Scenario 12 GIVEN: "one note saying 'use Postgres for
  # the ledger' and a later note saying 'ledger moved to MongoDB'". No artificial
  # shared filler — the literal scenario sentences (in a normal note with a
  # heading) must be caught honestly. The SECOND carries a replacement marker
  # ("moved to"/"instead"), making the pair a conflict candidate.
  cat > "$MB/notes/2026-06-10_ledger-postgres.md" <<'EOF'
---
type: decision
created: 2026-06-10
---
# Ledger storage decision

Use Postgres for the ledger.
EOF

  cat > "$MB/notes/2026-06-11_ledger-mongodb.md" <<'EOF'
---
type: decision
created: 2026-06-11
---
# Ledger storage update

The ledger moved to MongoDB instead of Postgres.
EOF

  # Mock claude: record calls + capture the LAST prompt (for body-in-prompt
  # assertions) + emit a deterministic "CONFIRMED" judgement.
  STUB="$PROJECT/bin"; mkdir -p "$STUB"
  CALLS="$PROJECT/calls"
  PROMPT_CAP="$PROJECT/prompt.txt"
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > "$PROMPT_CAP"
echo "CONFIRMED"
EOF
  chmod +x "$STUB/claude"
  CLAUDE="$STUB/claude"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# md5 helper (macOS `md5 -q` / Linux `md5sum`)
_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" | awk '{print $1}'; }

# Snapshot md5 of every regular file under the bank (sorted by path).
_bank_md5() {
  find "$MB" -type f | LC_ALL=C sort | while read -r f; do _md5 "$f"; done
}

# ── Scenario 12: $0 pass finds the opposing pair, exits 0, NO claude call ──────
@test "conflicts: \$0 pass reports the Postgres/MongoDB pair with both paths, exit 0, no LLM (REQ-022, Scenario 12)" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  # NO claude invocation in the $0 pass
  [ ! -f "$CALLS" ]
  # both file paths reported as a candidate pair
  echo "$output" | grep -q 'ledger-postgres.md'
  echo "$output" | grep -q 'ledger-mongodb.md'
}

# ── <2 entries → empty output, exit 0 ─────────────────────────────────────────
@test "conflicts: fewer than two entries → empty output, exit 0" {
  rm -f "$MB/notes/2026-06-11_ledger-mongodb.md"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  [ ! -f "$CALLS" ]
  # no candidate pair printed
  ! echo "$output" | grep -q 'ledger-postgres.md'
}

# ── Threshold respected: a low-overlap pair is NOT reported ────────────────────
@test "conflicts: a below-threshold (low-overlap) pair is not reported (REQ-022)" {
  rm -f "$MB"/notes/*.md
  # Two notes with a negation marker but almost no shared vocabulary → Jaccard < 0.4.
  cat > "$MB/notes/a.md" <<'EOF'
# Caching layer
We added a Redis cache in front of the catalog service for product reads.
EOF
  cat > "$MB/notes/b.md" <<'EOF'
# Deployment runbook
The blue-green rollout instead uses Kubernetes canary weights per region.
EOF
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  # the unrelated pair must NOT be flagged as a conflict
  ! echo "$output" | grep -q 'a.md.*b.md'
  ! echo "$output" | grep -Eq '(a|b)\.md'
}

# ── --judge with stubbed claude → confirm + a [SUPERSEDED] marker, PRINT-ONLY ──
@test "conflicts: --judge confirms a candidate and prints a [SUPERSEDED] marker; bank is byte-identical (REQ-023)" {
  before="$(_bank_md5)"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  # one Sonnet call for the one candidate pair
  [ -f "$CALLS" ]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
  # judgement + suggested marker in the format from references/metadata.md
  echo "$output" | grep -qi 'CONFIRMED'
  echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}-[0-9]{2}-[0-9]{2} -> [^]]+\]'
  # PRINT-ONLY: every bank file byte-identical before/after
  after="$(_bank_md5)"
  [ "$before" = "$after" ]
}

# ── --judge rejection path: a rejected candidate prints no marker ─────────────
@test "conflicts: --judge rejection prints no [SUPERSEDED] marker, bank untouched (REQ-023)" {
  # Stub claude to REJECT.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat >/dev/null
echo "REJECTED"
EOF
  chmod +x "$STUB/claude"
  before="$(_bank_md5)"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'REJECTED'
  ! echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}'
  after="$(_bank_md5)"
  [ "$before" = "$after" ]
}

# ── --judge without a claude binary → hint + $0 candidates still printed, exit 0
@test "conflicts: --judge without claude prints a hint, still lists \$0 candidates, exit 0 (REQ-023)" {
  before="$(_bank_md5)"
  run env CLAUDE="$PROJECT/nope-claude" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  # hint mentions claude
  echo "$output" | grep -qi 'claude'
  # the deterministic $0 candidates are still printed
  echo "$output" | grep -q 'ledger-postgres.md'
  echo "$output" | grep -q 'ledger-mongodb.md'
  # no marker (no judge ran), bank untouched
  ! echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}'
  after="$(_bank_md5)"
  [ "$before" = "$after" ]
}

# ── --threshold override is honoured (a high threshold suppresses the pair) ────
@test "conflicts: a high --threshold suppresses the Postgres/MongoDB pair, exit 0" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --threshold 0.99
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'ledger-postgres.md'
}

# ── Blocker 1: the LITERAL Scenario 12 sentences pass at the DEFAULT threshold ─
# Faithful to the spec GIVEN ("use Postgres for the ledger" / "ledger moved to
# MongoDB"), with NO artificial shared filler. The default detector must catch it.
@test "conflicts: the literal Scenario 12 sentences are flagged at the default threshold (REQ-022, Scenario 12)" {
  rm -f "$MB"/notes/*.md
  cat > "$MB/notes/2026-06-10_ledger-a.md" <<'EOF'
# Ledger storage decision

Use Postgres for the ledger.
EOF
  cat > "$MB/notes/2026-06-11_ledger-b.md" <<'EOF'
# Ledger storage update

The ledger moved to MongoDB.
EOF
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  [ ! -f "$CALLS" ]
  echo "$output" | grep -q 'ledger-a.md'
  echo "$output" | grep -q 'ledger-b.md'
}

# ── Blocker 2: progress.md is NEWEST-FIRST — the conflicting fact lives in the
# newest entry, beyond the oldest-10 window the buggy slice would read. ─────────
@test "conflicts: a conflict in the NEWEST progress.md entry of a newest-first file is detected (REQ-022)" {
  rm -f "$MB"/notes/*.md
  # A note establishes the original fact.
  cat > "$MB/notes/2026-01-01_ledger.md" <<'EOF'
# Ledger storage decision

Use Postgres for the ledger.
EOF
  # progress.md: title block + >10 older filler entries (newest-first) + a NEWEST
  # entry at the TOP carrying the replacement fact about the ledger.
  {
    echo "# Project — Progress Log"
    echo ""
    echo "## 2026-12-31 (ledger migration)"
    echo ""
    echo "The ledger moved to MongoDB instead of Postgres."
    echo ""
    for n in $(seq 12 -1 1); do
      printf '## 2026-02-%02d (routine work)\n\nUnrelated catalog and shipping refactors for sprint %d.\n\n' "$n" "$n"
    done
  } > "$MB/progress.md"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ledger.md'
  echo "$output" | grep -qi 'progress.md'
}

# ── Blocker 3: --judge prompt carries the ACTUAL progress entry BODY, not a
# '(progress.md recent entry)' placeholder. ────────────────────────────────────
@test "conflicts: --judge prompt for a progress.md candidate contains the entry body text (REQ-023)" {
  rm -f "$MB"/notes/*.md
  cat > "$MB/notes/2026-01-01_ledger.md" <<'EOF'
# Ledger storage decision

Use Postgres for the ledger storage.
EOF
  {
    echo "# Project — Progress Log"
    echo ""
    echo "## 2026-12-31 (ledger migration)"
    echo ""
    echo "The ledger storage moved to MongoDB UNIQUEMARKER instead of Postgres."
  } > "$MB/progress.md"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  [ -f "$PROMPT_CAP" ]
  # the real progress body text reached the judge prompt (no placeholder)
  grep -q 'UNIQUEMARKER' "$PROMPT_CAP"
  ! grep -q 'progress.md recent entry' "$PROMPT_CAP"
}

# ── Blocker 4: --judge is capped to avoid unbounded O(n^2) Sonnet calls ────────
@test "conflicts: --judge caps candidates at MB_CONFLICTS_MAX_CANDIDATES and prints a truncation notice (REQ-023)" {
  rm -f "$MB"/notes/*.md
  # Build many mutually-overlapping notes (each carries a replacement marker) so
  # the candidate count far exceeds a small cap.
  for i in $(seq 1 8); do
    cat > "$MB/notes/svc-$i.md" <<EOF
# Ledger storage decision $i

Use Postgres for the ledger. The ledger moved to backend $i instead.
EOF
  done
  run env CLAUDE="$CLAUDE" MB_CONFLICTS_MAX_CANDIDATES=3 bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  [ -f "$CALLS" ]
  # exactly cap judge calls, not the full O(n^2) set
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 3 ]
  # a truncation notice is printed when the cap bites
  echo "$output" | grep -qi 'truncat\|cap'
}

# ── Blocker 5a: dated pair → suggested marker targets the OLDER entry ──────────
@test "conflicts: --judge marker targets the OLDER (superseded) entry for a dated pair (REQ-023)" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'CONFIRMED'
  # the OLDER note (2026-06-10 postgres) is the one marked [SUPERSEDED ...],
  # pointing to the NEWER (2026-06-11 mongodb).
  marker_line="$(echo "$output" | grep -E 'SUPERSEDED' | head -n1)"
  echo "$marker_line" | grep -q 'mongodb'
  # the marked-up target named just before the marker is the older postgres note
  echo "$output" | grep -B1 'SUPERSEDED' | grep -q 'ledger-postgres.md'
}

# ── Blocker 5b: undatable pair → marker printed WITHOUT a named target ─────────
@test "conflicts: --judge prints no marker target when entry ordering is unknown (REQ-023)" {
  rm -f "$MB"/notes/*.md
  # Two notes with NO date in filename and NO date frontmatter → ordering unknown.
  cat > "$MB/notes/ledger-x.md" <<'EOF'
# Ledger storage decision

Use Postgres for the ledger.
EOF
  cat > "$MB/notes/ledger-y.md" <<'EOF'
# Ledger storage update

The ledger moved to MongoDB instead of Postgres.
EOF
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'CONFIRMED'
  # no SUPERSEDED marker line naming a concrete target; instead an explicit
  # "ordering unknown" note.
  ! echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}-[0-9]{2}-[0-9]{2} -> '
  echo "$output" | grep -qi 'order\|unknown\|cannot determine'
}

# ── Round-2 Blocker 1: a judge returning EMPTY/garbage for one candidate must
# fail-open (degrade to "unknown — no verdict") and KEEP going, not abort the
# whole --judge run under `set -euo pipefail`. ──────────────────────────────────
@test "conflicts: --judge degrades on an empty/garbage verdict and still judges the rest, exit 0 (REQ-023)" {
  rm -f "$MB"/notes/*.md
  # Two overlapping ledger candidates so two judge calls happen. The stub emits
  # EMPTY output on its FIRST invocation (transient model error) and a valid
  # CONFIRMED on its SECOND — proving the run survives the empty verdict.
  cat > "$MB/notes/2026-06-10_ledger-a.md" <<'EOF'
# Ledger storage decision A

Use Postgres for the ledger.
EOF
  cat > "$MB/notes/2026-06-11_ledger-b.md" <<'EOF'
# Ledger storage update B

The ledger moved to MongoDB instead of Postgres.
EOF
  cat > "$MB/notes/2026-06-12_ledger-c.md" <<'EOF'
# Ledger storage update C

The ledger no longer uses Postgres; it moved to MongoDB.
EOF
  # Stateful stub: first call → empty stdout (garbage/transient error), every
  # later call → CONFIRMED. Counter file in $PROJECT.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat >/dev/null
n="\$(cat "$PROJECT/n" 2>/dev/null || echo 0)"
n=\$((n + 1))
echo "\$n" > "$PROJECT/n"
if [ "\$n" -eq 1 ]; then
  exit 0          # empty verdict — must NOT abort the script
fi
echo "CONFIRMED"  # subsequent candidates judged normally
EOF
  chmod +x "$STUB/claude"
  before="$(_bank_md5)"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  # the whole run survives the empty verdict
  [ "$status" -eq 0 ]
  # more than one candidate was judged (run did not abort after the empty one)
  [ -f "$CALLS" ]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -ge 2 ]
  # the empty/garbage verdict is surfaced as an explicit no-verdict, not a crash
  echo "$output" | grep -qi 'no verdict\|unknown'
  # at least one later candidate was CONFIRMED (run continued past the empty one)
  echo "$output" | grep -qi 'CONFIRMED'
  # PRINT-ONLY: bank untouched
  after="$(_bank_md5)"
  [ "$before" = "$after" ]
}

# ── Round-2 Blocker 2: real progress.md NESTS `###` subsections inside dated
# `## YYYY-MM-DD` entries. The newest-10 window must count TOP-LEVEL `## ` entries
# only — nested `###` must NOT consume window slots or strip the parent date. ────
@test "conflicts: nested ### subsections stay inside the parent ## entry; conflict in the last subsection keeps the parent date (REQ-022)" {
  rm -f "$MB"/notes/*.md
  # A note establishes the original fact.
  cat > "$MB/notes/2026-01-01_ledger.md" <<'EOF'
# Ledger storage decision

Use Postgres for the ledger storage.
EOF
  # progress.md, newest-first: the NEWEST dated entry (## 2026-06-12) contains 12
  # ### subsections; the conflicting ledger fact lives in the LAST subsection. If
  # the parser split on ### too, those 12 subsections would (a) flood the newest-10
  # window — pushing the parent body's conflict out — and (b) lose the 2026-06-12
  # date (→ spurious "ordering unknown"). Splitting on top-level ## only keeps the
  # whole entry as ONE dated block, so the conflict in the last subsection is read
  # together with the parent's date.
  {
    echo "# Project — Progress Log"
    echo ""
    echo "## 2026-06-12 (ledger migration)"
    echo ""
    for s in $(seq 1 11); do
      printf '### Subsection %d\n\nRoutine work.\n\n' "$s"
    done
    printf '### Subsection 12\n\nThe ledger storage moved to MongoDB instead of Postgres.\n\n'
    # Older real entries below — also nested, must not interfere.
    echo "## 2026-05-01 (earlier work)"
    echo ""
    echo "### Done"
    echo ""
    echo "Routine cleanup."
  } > "$MB/progress.md"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  # the conflict in the LAST subsection of the newest entry is still detected
  echo "$output" | grep -q 'ledger.md'
  echo "$output" | grep -qi 'progress.md'
  # CONFIRMED with the parent date resolved → a concrete [SUPERSEDED] target,
  # NOT the "ordering unknown" degrade path.
  echo "$output" | grep -qi 'CONFIRMED'
  echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}-[0-9]{2}-[0-9]{2} -> '
  ! echo "$output" | grep -qi 'ordering unknown'
}

@test "conflicts: a fenced '## ' snippet inside a progress entry is NOT split into a fake undated entry (REQ-022)" {
  rm -f "$MB"/notes/*.md
  cat > "$MB/notes/2026-01-01_ledger.md" <<'EOF'
# Ledger storage

Use Postgres for the ledger storage.
EOF
  # The NEWEST progress entry embeds a fenced snippet whose line starts with "## ".
  # A naive top-level split would treat that snippet line as a new (undated) entry,
  # stealing the conflict body's date → spurious "ordering unknown". Fence-aware
  # splitting keeps the whole dated entry (heading + fence + conflict) intact.
  {
    echo "# Project — Progress Log"
    echo ""
    echo "## 2026-06-12 ledger"
    echo ""
    echo '```md'
    echo "## x"
    echo '```'
    echo ""
    echo "The ledger storage moved to MongoDB instead of Postgres."
    echo ""
    echo "## 2026-05-01 earlier"
    echo ""
    echo "Routine cleanup."
  } > "$MB/progress.md"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ledger.md'
  echo "$output" | grep -qi 'progress.md'
  # The fenced snippet did not become a fake entry: the conflict keeps its parent
  # 2026-06-12 date → a concrete [SUPERSEDED] target, never "ordering unknown".
  echo "$output" | grep -qi 'CONFIRMED'
  echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}-[0-9]{2}-[0-9]{2} -> '
  ! echo "$output" | grep -qi 'ordering unknown'
}

@test "conflicts: a tilde line inside a backtick fence does NOT close it early; inner '## ' stays in the parent (REQ-022)" {
  rm -f "$MB"/notes/*.md
  cat > "$MB/notes/2026-01-01_ledger.md" <<'EOF'
# Ledger storage

Use Postgres for the ledger storage.
EOF
  # CommonMark fences close only on the SAME delimiter char. A `~~~` line inside a
  # ``` fence is body, not a close — so the `## ` after it is still inside the fence
  # and must NOT become a fake undated entry (which would steal the conflict's date).
  {
    echo "# Project — Progress Log"
    echo ""
    echo "## 2026-06-12 ledger"
    echo ""
    echo '```'
    echo "~~~"
    echo "## x"
    echo "~~~"
    echo '```'
    echo ""
    echo "The ledger storage moved to MongoDB instead of Postgres."
    echo ""
    echo "## 2026-05-01 earlier"
    echo ""
    echo "Routine cleanup."
  } > "$MB/progress.md"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'CONFIRMED'
  echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}-[0-9]{2}-[0-9]{2} -> '
  ! echo "$output" | grep -qi 'ordering unknown'
}

@test "conflicts: a triple-backtick example inside a 4-backtick fence does NOT close it early; inner '## ' stays in the parent (REQ-022)" {
  rm -f "$MB"/notes/*.md
  cat > "$MB/notes/2026-01-01_ledger.md" <<'EOF'
# Ledger storage

Use Postgres for the ledger storage.
EOF
  # A closing fence must be at least as long as the opener. A 3-backtick line inside
  # a 4-backtick fence is body, not a close — so the `## ` inside stays in the parent
  # dated entry rather than splitting into a fake undated one.
  {
    echo "# Project — Progress Log"
    echo ""
    echo "## 2026-06-12 ledger"
    echo ""
    echo '````'
    echo '```'
    echo "## x"
    echo '```'
    echo '````'
    echo ""
    echo "The ledger storage moved to MongoDB instead of Postgres."
    echo ""
    echo "## 2026-05-01 earlier"
    echo ""
    echo "Routine cleanup."
  } > "$MB/progress.md"
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'CONFIRMED'
  echo "$output" | grep -Eq '\[SUPERSEDED: [0-9]{4}-[0-9]{2}-[0-9]{2} -> '
  ! echo "$output" | grep -qi 'ordering unknown'
}

# --- I-085 Stage 4: portable base64 decode + finite threshold ---

@test "conflicts: --judge decodes entry bodies portably into the prompt" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --judge
  [ "$status" -eq 0 ]
  [ -f "$PROMPT_CAP" ]
  grep -q 'Use Postgres for the ledger' "$PROMPT_CAP"
  grep -q 'ledger moved to MongoDB' "$PROMPT_CAP"
}

@test "conflicts: --threshold nan rejected" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --threshold nan
  [ "$status" -eq 64 ]
}

@test "conflicts: --threshold inf rejected" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --threshold inf
  [ "$status" -eq 64 ]
}

@test "conflicts: --threshold out of range rejected" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --threshold 1.5
  [ "$status" -eq 64 ]
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --threshold -0.1
  [ "$status" -eq 64 ]
}

@test "conflicts: --threshold valid accepted" {
  run env CLAUDE="$CLAUDE" bash "$SCRIPT" "$MB" --threshold 0.4
  [ "$status" -eq 0 ]
}
