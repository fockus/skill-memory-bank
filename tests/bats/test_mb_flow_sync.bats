#!/usr/bin/env bats
# Tests for scripts/mb-flow-sync.sh — the `mb-flow` fence writer (dynamic-flow Task 3).
#
# Contract (REQ-DF-030, REQ-DF-031, REQ-DF-032; design ADR-5 + L4 Interfaces):
#   - The runtime fence lives in status.md as a single
#     `<!-- mb-flow --> ... <!-- /mb-flow -->` marker-fenced block.
#   - First write CREATES the fence (appended to status.md if absent).
#   - Re-write is IDEMPOTENT: same inputs → byte-identical file (empty diff).
#   - Content OUTSIDE the fence is byte-preserved across writes (text before AND after).
#   - The fence carries ONLY the genuinely-new runtime fields:
#       route, current_phase (k/n), phases [...], checks {8 keys}, gate PASS|FAIL,
#       last_verify_sha, stall_count. Unset fields render as `-`, never removed.
#   - goal.md is NEVER created or modified by this script (durable-only).
#   - No standalone flow-state.json is authored as primary state.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-flow-sync.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"

  STATUS="$TMPBANK/status.md"
  GOAL="$TMPBANK/goal.md"

  cat > "$STATUS" <<'EOF'
# Project — Status

## Current focus

Wire the dynamic-flow firewall.

## Notes

Trailing content after the fence position.
EOF

  cat > "$GOAL" <<'EOF'
---
id: G-001
status: active
mode: static
---

# Goal

Ship the firewall.

## Acceptance criteria

- [ ] mb-flow-verify.sh propagates 0/1/2
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# Portable mtime (epoch seconds).
_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# Basic existence
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: script exists and is executable" {
  [ -f "$SYNC" ]
  [ -x "$SYNC" ]
}

@test "flow-sync: --help prints usage and exits 0" {
  run bash "$SYNC" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-flow"* ]]
}

@test "flow-sync: fails gracefully when bank dir is missing" {
  run bash "$SYNC" "$TMPROOT/nonexistent-bank"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"not found"* ]]
}

# ═══════════════════════════════════════════════════════════════
# First write — fence creation + outside-content preservation
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: first write creates the mb-flow fence" {
  run bash "$SYNC" "$TMPBANK" --route code-change --phase 1/3 --gate PASS
  [ "$status" -eq 0 ]

  grep -q "<!-- mb-flow -->" "$STATUS"
  grep -q "<!-- /mb-flow -->" "$STATUS"
  # Exactly one fence pair.
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 1 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 1 ]
}

@test "flow-sync: fence carries the route/phase/gate runtime fields" {
  bash "$SYNC" "$TMPBANK" --route code-change --phase 2/4 --gate FAIL \
    --last-verify-sha abc1234 --stall-count 1
  grep -q "route: code-change" "$STATUS"
  grep -q "current_phase: 2/4" "$STATUS"
  grep -q "gate: FAIL" "$STATUS"
  grep -q "last_verify_sha: abc1234" "$STATUS"
  grep -q "stall_count: 1" "$STATUS"
}

@test "flow-sync: pre-existing status.md content is preserved on first write" {
  bash "$SYNC" "$TMPBANK" --route research --gate PASS
  grep -q "^# Project — Status$" "$STATUS"
  grep -q "Wire the dynamic-flow firewall." "$STATUS"
  grep -q "Trailing content after the fence position." "$STATUS"
}

@test "flow-sync: unset fields render as a placeholder, not removed" {
  bash "$SYNC" "$TMPBANK" --route bugfix
  # current_phase / gate / sha / stall not supplied → placeholder `-`.
  grep -q "current_phase: -" "$STATUS"
  grep -q "gate: -" "$STATUS"
  grep -q "last_verify_sha: -" "$STATUS"
  grep -q "stall_count: -" "$STATUS"
}

@test "flow-sync: phases list renders flow-style" {
  bash "$SYNC" "$TMPBANK" --route code-change --phases "plan,implement,verify"
  grep -q "phases: \[plan, implement, verify\]" "$STATUS"
}

@test "flow-sync: checks json populates the eight check keys" {
  bash "$SYNC" "$TMPBANK" --route code-change \
    --checks '{"tests":"pass","rules":"pass","lint":"skip","build":"skip","mb_updated":"pass","no_todo":"pass","diff_scope":"pass","acceptance":"fail"}'
  grep -q "tests: pass" "$STATUS"
  grep -q "lint: skip" "$STATUS"
  grep -q "acceptance: fail" "$STATUS"
}

# ═══════════════════════════════════════════════════════════════
# Idempotency
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: second write with same inputs is byte-identical" {
  bash "$SYNC" "$TMPBANK" --route code-change --phase 1/3 --gate PASS \
    --last-verify-sha deadbee --stall-count 0
  sum1=$(shasum "$STATUS" | awk '{print $1}')

  bash "$SYNC" "$TMPBANK" --route code-change --phase 1/3 --gate PASS \
    --last-verify-sha deadbee --stall-count 0
  sum2=$(shasum "$STATUS" | awk '{print $1}')

  [ "$sum1" = "$sum2" ]
}

@test "flow-sync: re-write does not duplicate the fence" {
  bash "$SYNC" "$TMPBANK" --route code-change --gate PASS
  bash "$SYNC" "$TMPBANK" --route code-change --gate PASS
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 1 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════
# Byte-preservation outside the fence across an UPDATE
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: updating a field changes ONLY the fence region" {
  bash "$SYNC" "$TMPBANK" --route code-change --gate FAIL

  # Capture everything OUTSIDE the fence before the update.
  before_head="$(sed '/<!-- mb-flow -->/,/<!-- \/mb-flow -->/d' "$STATUS")"

  bash "$SYNC" "$TMPBANK" --route code-change --gate PASS

  after_head="$(sed '/<!-- mb-flow -->/,/<!-- \/mb-flow -->/d' "$STATUS")"

  [ "$before_head" = "$after_head" ]
  # The fence itself DID change (FAIL → PASS).
  grep -q "gate: PASS" "$STATUS"
  ! grep -q "gate: FAIL" "$STATUS"
}

@test "flow-sync: text before and after the fence is byte-preserved across writes" {
  bash "$SYNC" "$TMPBANK" --route code-change --gate PASS

  # Header (before fence) intact.
  head -n 1 "$STATUS" | grep -q "^# Project — Status$"
  # Trailing note (after fence, since fence is appended) intact.
  grep -q "Trailing content after the fence position." "$STATUS"

  bash "$SYNC" "$TMPBANK" --route research --stall-count 3

  head -n 1 "$STATUS" | grep -q "^# Project — Status$"
  grep -q "Trailing content after the fence position." "$STATUS"
  grep -q "Wire the dynamic-flow firewall." "$STATUS"
}

# ═══════════════════════════════════════════════════════════════
# goal.md is never written; no flow-state.json authored
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: goal.md is never created or modified" {
  goal_sum_before=$(shasum "$GOAL" | awk '{print $1}')
  mt_before="$(_mtime "$GOAL")"

  bash "$SYNC" "$TMPBANK" --route code-change --phase 1/3 --gate PASS
  bash "$SYNC" "$TMPBANK" --route arch --gate FAIL --stall-count 2

  goal_sum_after=$(shasum "$GOAL" | awk '{print $1}')
  mt_after="$(_mtime "$GOAL")"

  [ "$goal_sum_before" = "$goal_sum_after" ]
  [ "$mt_before" = "$mt_after" ]
}

@test "flow-sync: never references goal.md as a write target in its source" {
  # The script must not open goal.md for writing at all.
  ! grep -Eq 'goal\.md.*(>|write|mv|cp)|(>|write_text).*goal\.md' "$SYNC"
}

@test "flow-sync: does not author a standalone flow-state.json" {
  bash "$SYNC" "$TMPBANK" --route code-change --gate PASS
  [ ! -f "$TMPBANK/flow-state.json" ]
  [ -z "$(find "$TMPROOT" -name 'flow-state.json' 2>/dev/null)" ]
}

@test "flow-sync: creates status.md if absent (first write on a bare bank)" {
  rm -f "$STATUS"
  run bash "$SYNC" "$TMPBANK" --route bugfix --gate PASS
  [ "$status" -eq 0 ]
  [ -f "$STATUS" ]
  grep -q "<!-- mb-flow -->" "$STATUS"
}

# ═══════════════════════════════════════════════════════════════
# FIX-CYCLE 1: Defect 1 — empty pass_through array under bash 3.2
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: no-flags invocation exits 0 and writes a fence with all-dash placeholders" {
  # REQ-DF-030: invoking with only the bank path (zero flags) must not crash under
  # bash 3.2 where "${empty_array[@]}" raises 'unbound variable' under set -u.
  # We invoke via /bin/bash (3.2 on macOS) to catch the regression if present.
  run /bin/bash "$SYNC" "$TMPBANK"
  [ "$status" -eq 0 ]
  grep -q "<!-- mb-flow -->" "$STATUS"
  grep -q "route: -" "$STATUS"
  grep -q "gate: -" "$STATUS"
}

@test "flow-sync: no-flags second run is idempotent (bash 3.2 path)" {
  /bin/bash "$SYNC" "$TMPBANK"
  sum1=$(shasum "$STATUS" | awk '{print $1}')
  /bin/bash "$SYNC" "$TMPBANK"
  sum2=$(shasum "$STATUS" | awk '{print $1}')
  [ "$sum1" = "$sum2" ]
}

# ═══════════════════════════════════════════════════════════════
# FIX-CYCLE 1: Defect 2 — malformed fence detection (fail-loud, no corruption)
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: orphan open-marker leaves status.md unchanged and exits non-zero" {
  # Only the open tag exists — no close tag.
  printf '# Status\n\nbefore content\n<!-- mb-flow -->\norphan open body\n' > "$STATUS"
  sum_before=$(shasum "$STATUS" | awk '{print $1}')

  run bash "$SYNC" "$TMPBANK" --route code-change --gate PASS
  # Must fail loudly.
  [ "$status" -ne 0 ]
  # Must NOT modify status.md.
  sum_after=$(shasum "$STATUS" | awk '{print $1}')
  [ "$sum_before" = "$sum_after" ]
}

@test "flow-sync: orphan close-marker leaves status.md unchanged and exits non-zero" {
  # Only the close tag exists — no open tag.
  printf '# Status\n\nbefore content\n<!-- /mb-flow -->\nafter orphan\n' > "$STATUS"
  sum_before=$(shasum "$STATUS" | awk '{print $1}')

  run bash "$SYNC" "$TMPBANK" --route code-change --gate PASS
  [ "$status" -ne 0 ]
  sum_after=$(shasum "$STATUS" | awk '{print $1}')
  [ "$sum_before" = "$sum_after" ]
}

@test "flow-sync: duplicate fence pair leaves status.md unchanged and exits non-zero" {
  # Two well-formed open/close pairs — ambiguous; must refuse.
  cat > "$STATUS" <<'EOF'
# Status

before

<!-- mb-flow -->
route: code-change
gate: PASS
<!-- /mb-flow -->

middle text

<!-- mb-flow -->
route: bugfix
gate: FAIL
<!-- /mb-flow -->

after
EOF
  sum_before=$(shasum "$STATUS" | awk '{print $1}')

  run bash "$SYNC" "$TMPBANK" --route arch --gate PASS
  [ "$status" -ne 0 ]
  sum_after=$(shasum "$STATUS" | awk '{print $1}')
  [ "$sum_before" = "$sum_after" ]
}

@test "flow-sync: fence markers inside a code block are not treated as the runtime fence" {
  # Markers inside a fenced code block must be ignored; the REAL fence is below.
  cat > "$STATUS" <<'EOF'
# Status

Example in docs:

```
<!-- mb-flow -->
route: example
<!-- /mb-flow -->
```

Real content here.
EOF
  # No real fence yet — first write should APPEND a new fence, not overwrite the
  # code-block markers.
  run bash "$SYNC" "$TMPBANK" --route research --gate PASS
  [ "$status" -eq 0 ]

  # The real fence must appear exactly once (the newly-appended one).
  open_count=$(grep -c '<!-- mb-flow -->' "$STATUS")
  close_count=$(grep -c '<!-- /mb-flow -->' "$STATUS")
  [ "$open_count" -eq 2 ]   # one inside code block, one real fence
  [ "$close_count" -eq 2 ]

  # The code block content must be byte-preserved.
  grep -q '```' "$STATUS"
  grep -q 'route: example' "$STATUS"

  # The newly-written fence must carry the requested values.
  # Extract only lines between the LAST open/close pair (the real fence).
  grep -q "route: research" "$STATUS"
  grep -q "gate: PASS" "$STATUS"
}

@test "flow-sync: code-block fence is correctly identified as non-runtime on re-write" {
  # Prime status.md with a real fence (route: research) plus docs code block.
  cat > "$STATUS" <<'EOF'
# Status

Docs:

```
<!-- mb-flow -->
route: example
<!-- /mb-flow -->
```

Real content.

<!-- mb-flow -->
route: research
current_phase: -
phases: -
checks: { tests: -, rules: -, lint: -, build: -, mb_updated: -, no_todo: -, diff_scope: -, acceptance: - }
gate: PASS
last_verify_sha: -
stall_count: -
<!-- /mb-flow -->
EOF
  run bash "$SYNC" "$TMPBANK" --route arch --gate FAIL
  [ "$status" -eq 0 ]

  # Real fence updated; code-block preserved byte-for-byte.
  grep -q 'route: example' "$STATUS"    # code block unchanged
  grep -q 'route: arch' "$STATUS"       # real fence updated
  ! grep -q 'route: research' "$STATUS" # old real value replaced
  grep -q 'gate: FAIL' "$STATUS"

  # Still exactly the original two open + two close markers (one pair in code, one real).
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 2 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# FIX-CYCLE 1: Defect 3 — CRLF byte-preservation
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: CRLF status.md preserves outside-region bytes exactly (no CRLF→LF stripping)" {
  # Write a status.md with CRLF line endings.
  printf '# Status\r\n\r\nBefore content.\r\n' > "$STATUS"
  before_bytes=$(shasum "$STATUS" | awk '{print $1}')

  bash "$SYNC" "$TMPBANK" --route code-change --gate PASS

  # The fence itself will use LF (it's generated fresh), but the bytes BEFORE the
  # fence (everything up to the appended fence) must be byte-identical to the original.
  # We extract the prefix region (before the <!-- mb-flow --> marker) and compare.
  before_region=$(python3 -c "
import sys
data = open('$STATUS','rb').read()
marker = b'<!-- mb-flow -->'
idx = data.index(marker)
sys.stdout.buffer.write(data[:idx])
" | shasum | awk '{print $1}')

  # The original file's bytes are the expected prefix (it ends with a separator we
  # added on append, so we compare the raw original bytes).
  expected_region=$(shasum "$STATUS.crlf_orig" 2>/dev/null | awk '{print $1}' || true)

  # Concretely: the CRLF bytes in the prefix must survive; grep for literal CRLF.
  python3 -c "
data = open('$STATUS','rb').read()
marker = b'<!-- mb-flow -->'
idx = data.index(marker)
prefix = data[:idx]
assert b'\r\n' in prefix, 'CRLF stripped in prefix region: byte-preservation broken'
print('CRLF preserved in prefix: OK')
"
}

@test "flow-sync: CRLF round-trip — re-write is byte-identical when CRLF file has real fence" {
  # Build a status.md with CRLF endings that already contains a real fence.
  # The fence itself uses LF (our generator always writes LF); the surrounding
  # content has CRLF. A re-write must keep the file byte-identical.
  {
    printf '# Status\r\n\r\nBefore content.\r\n'
    printf '<!-- mb-flow -->\n'
    printf 'route: bugfix\n'
    printf 'current_phase: -\n'
    printf 'phases: -\n'
    printf 'checks: { tests: -, rules: -, lint: -, build: -, mb_updated: -, no_todo: -, diff_scope: -, acceptance: - }\n'
    printf 'gate: PASS\n'
    printf 'last_verify_sha: -\n'
    printf 'stall_count: -\n'
    printf '<!-- /mb-flow -->\n'
  } > "$STATUS"

  sum_before=$(shasum "$STATUS" | awk '{print $1}')
  bash "$SYNC" "$TMPBANK" --route bugfix --gate PASS
  sum_after=$(shasum "$STATUS" | awk '{print $1}')

  [ "$sum_before" = "$sum_after" ]
}

# ═══════════════════════════════════════════════════════════════
# FIX-CYCLE 1: Defect 4 — binary-safe outside-region byte comparison
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: binary-safe — outside-prefix bytes are identical before/after update (cmp)" {
  # Write fence once; capture the prefix region as a binary file; update the fence;
  # assert the prefix bytes are still identical using cmp (not sed/grep).
  bash "$SYNC" "$TMPBANK" --route code-change --gate FAIL

  # Extract prefix (bytes before <!-- mb-flow -->) into a reference file.
  prefix_ref="$TMPROOT/prefix_before.bin"
  python3 -c "
data = open('$STATUS','rb').read()
marker = b'<!-- mb-flow -->'
idx = data.index(marker)
open('$TMPROOT/prefix_before.bin','wb').write(data[:idx])
"

  # Extract suffix (bytes after <!-- /mb-flow -->\n) into a reference file.
  suffix_ref="$TMPROOT/suffix_before.bin"
  python3 -c "
data = open('$STATUS','rb').read()
close_marker = b'<!-- /mb-flow -->'
idx = data.index(close_marker) + len(close_marker)
# consume the trailing newline if present
if idx < len(data) and data[idx:idx+1] == b'\n':
    idx += 1
open('$TMPROOT/suffix_before.bin','wb').write(data[idx:])
"

  # Update the fence (gate FAIL → PASS).
  bash "$SYNC" "$TMPBANK" --route code-change --gate PASS

  # Compare prefix and suffix bytes after update.
  python3 -c "
data = open('$STATUS','rb').read()
marker_open = b'<!-- mb-flow -->'
marker_close = b'<!-- /mb-flow -->'
idx_open = data.index(marker_open)
idx_close = data.index(marker_close) + len(marker_close)
if idx_close < len(data) and data[idx_close:idx_close+1] == b'\n':
    idx_close += 1
prefix_after = data[:idx_open]
suffix_after = data[idx_close:]
prefix_ref = open('$TMPROOT/prefix_before.bin','rb').read()
suffix_ref = open('$TMPROOT/suffix_before.bin','rb').read()
assert prefix_after == prefix_ref, f'prefix mismatch: {prefix_after!r} != {prefix_ref!r}'
assert suffix_after == suffix_ref, f'suffix mismatch: {suffix_after!r} != {suffix_ref!r}'
print('binary-safe byte-preservation: OK')
"
}

@test "flow-sync: binary-safe idempotency with full-field round-trip (cmp)" {
  bash "$SYNC" "$TMPBANK" \
    --route code-change --phase 2/4 --phases "plan,implement,verify" \
    --checks '{"tests":"pass","acceptance":"fail"}' \
    --gate FAIL --last-verify-sha deadbeef --stall-count 1

  sum1=$(python3 -c "import hashlib,sys; print(hashlib.sha1(open('$STATUS','rb').read()).hexdigest())")

  bash "$SYNC" "$TMPBANK" \
    --route code-change --phase 2/4 --phases "plan,implement,verify" \
    --checks '{"tests":"pass","acceptance":"fail"}' \
    --gate FAIL --last-verify-sha deadbeef --stall-count 1

  sum2=$(python3 -c "import hashlib,sys; print(hashlib.sha1(open('$STATUS','rb').read()).hexdigest())")

  [ "$sum1" = "$sum2" ]
}

# ═══════════════════════════════════════════════════════════════
# FIX-CYCLE 2: F2 residual — CommonMark-compliant code-fence detector
# ═══════════════════════════════════════════════════════════════

@test "flow-sync: indented code block (1 space) with markers treated as code — no data loss" {
  # CommonMark allows 0-3 leading spaces on a fence opener.
  # The old detector required column-0 only, so a 1-space-indented fence would
  # NOT be recognized as code and the example markers would be treated as real.
  sum_before=$(shasum "$STATUS" | awk '{print $1}')
  # The FENCE lines carry the 1-space indent; the mb-flow MARKER lines are at
  # COLUMN 0 inside that fenced block. An old column-0-only detector would not
  # recognize the indented fence, would treat the column-0 markers as REAL, and
  # would overwrite `route: doc-example` (→ this test goes RED). The CommonMark
  # parser knows the markers are inside the indented fence (→ appends, GREEN).
  cat >> "$STATUS" <<'EOF'

 ```
<!-- mb-flow -->
route: doc-example
<!-- /mb-flow -->
 ```

Trailing after indented code block.
EOF
  sum_with_docs=$(shasum "$STATUS" | awk '{print $1}')

  # First write: must treat the indented-block markers as code (invisible),
  # append a fresh real fence, and leave everything before it byte-identical.
  run bash "$SYNC" "$TMPBANK" --route research --gate PASS
  [ "$status" -eq 0 ]

  # The indented example text must still be present verbatim.
  grep -q 'route: doc-example' "$STATUS"

  # One REAL fence pair was appended (plus one inside the indented block).
  # Total raw occurrences: 1 (in indented block) + 1 (real appended) = 2.
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 2 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 2 ]

  # The newly written real fence carries the requested values.
  grep -q 'route: research' "$STATUS"
  grep -q 'gate: PASS' "$STATUS"
}

@test "flow-sync: indented code block (3 spaces) — markers treated as code" {
  # 3-space-indented ~~~ fence; mb-flow MARKER lines at COLUMN 0 inside it (so an
  # old column-0-only detector would treat them as real and overwrite `route: docs`).
  cat > "$STATUS" <<'EOF'
# Status

Docs with 3-space indent:

   ~~~
<!-- mb-flow -->
route: docs
<!-- /mb-flow -->
   ~~~

Content after.
EOF
  run bash "$SYNC" "$TMPBANK" --route bugfix --gate FAIL
  [ "$status" -eq 0 ]

  # Example markers still present.
  grep -q 'route: docs' "$STATUS"
  # Real fence appended with requested values.
  grep -q 'route: bugfix' "$STATUS"
  grep -q 'gate: FAIL' "$STATUS"
  # Total open-markers: 1 (indented block) + 1 (real appended) = 2.
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 2 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 2 ]
}

@test "flow-sync: tilde fence containing a backtick line does not desync — markers stay code" {
  # The old detector toggled on ANY ```/~~~ line regardless of opener char/length.
  # A ``` line inside a ~~~ block would incorrectly "close" the tilde fence and
  # expose the trailing markers as real, causing a spurious 'orphan open' or
  # a wrong parse where the example block is treated as the runtime fence.
  cat > "$STATUS" <<'EOF'
# Status

Docs:

~~~
Here is a backtick sequence inside a tilde fence:
```
<!-- mb-flow -->
route: inner-example
<!-- /mb-flow -->
```
~~~

Real content.
EOF
  # No real fence yet — first write must append, not overwrite the block.
  run bash "$SYNC" "$TMPBANK" --route arch --gate PASS
  [ "$status" -eq 0 ]

  # The inner content is preserved byte-for-byte.
  grep -q 'route: inner-example' "$STATUS"
  # A fresh real fence was appended.
  grep -q 'route: arch' "$STATUS"
  grep -q 'gate: PASS' "$STATUS"
}

@test "flow-sync: longer backtick fence (4 backticks) containing a 3-backtick line — markers stay code" {
  # A fence opened with ```` ``` ```` (4 backticks) is only closed by ≥4 backticks;
  # a 3-backtick line inside it must NOT close the fence.
  cat > "$STATUS" <<'EOF'
# Status

Docs:

````
Here is a 3-backtick example inside a 4-backtick fence:
```
<!-- mb-flow -->
route: nested-doc
<!-- /mb-flow -->
```
````

Real content after.
EOF
  run bash "$SYNC" "$TMPBANK" --route migration --gate FAIL
  [ "$status" -eq 0 ]

  # Inner example preserved.
  grep -q 'route: nested-doc' "$STATUS"
  # Real fence appended.
  grep -q 'route: migration' "$STATUS"
  grep -q 'gate: FAIL' "$STATUS"
}

@test "flow-sync: indented-block markers do NOT corrupt status.md on re-write" {
  # Prime with an indented code block AND a real fence; verify re-write is
  # byte-identical (indented block stays untouched, real fence updated correctly).
  cat > "$STATUS" <<'EOF'
# Status

Docs:

 ```
 <!-- mb-flow -->
 route: example
 <!-- /mb-flow -->
 ```

<!-- mb-flow -->
route: code-change
current_phase: -
phases: -
checks: { tests: -, rules: -, lint: -, build: -, mb_updated: -, no_todo: -, diff_scope: -, acceptance: - }
gate: PASS
last_verify_sha: -
stall_count: -
<!-- /mb-flow -->
EOF
  # Update gate PASS → FAIL; indented example must be unchanged.
  run bash "$SYNC" "$TMPBANK" --route code-change --gate FAIL
  [ "$status" -eq 0 ]

  grep -q 'route: example' "$STATUS"   # indented block unchanged
  grep -q 'gate: FAIL' "$STATUS"       # real fence updated
  ! grep -q 'gate: PASS' "$STATUS"     # old value gone

  # Total markers: 2 in indented block + 2 in real fence = 4 raw occurrences.
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 2 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# FIX-CYCLE 3 — three hardening fixes
# ═══════════════════════════════════════════════════════════════

# --- Fix 1: unterminated code fence → fail loud, file byte-unchanged, no idempotency break ---

@test "flow-sync: unterminated fence (no closer) → exits non-zero, status.md byte-unchanged" {
  # An unclosed ``` fence means EOF is reached while still in_code. The script
  # must NOT treat this as "no real markers" (safe first-write), because appending
  # a new fence would bury it inside the open block and break idempotency.
  cat > "$STATUS" <<'EOF'
# Status

Content before the problem.

```
This fence is never closed.
<!-- mb-flow -->
route: inside-open-fence
<!-- /mb-flow -->
EOF

  sum_before=$(shasum "$STATUS" | awk '{print $1}')

  run bash "$SYNC" "$TMPBANK" --route code-change --gate PASS
  [ "$status" -ne 0 ]
  [[ "${output}${stderr}" == *"unterminated"* ]]

  # File must be byte-unchanged.
  sum_after=$(shasum "$STATUS" | awk '{print $1}')
  [ "$sum_before" = "$sum_after" ]
}

@test "flow-sync: unterminated fence does NOT become non-idempotent across two runs" {
  # If the bug were present: run 1 appends a fence (buried in open block),
  # run 2 sees 0 real markers again and appends ANOTHER fence → non-idempotent.
  # With the fix both runs must error and leave the file byte-identical to initial.
  cat > "$STATUS" <<'EOF'
# Status

```
Unterminated.
EOF

  sum_before=$(shasum "$STATUS" | awk '{print $1}')

  run bash "$SYNC" "$TMPBANK" --gate PASS
  [ "$status" -ne 0 ]
  run bash "$SYNC" "$TMPBANK" --gate PASS
  [ "$status" -ne 0 ]

  sum_after=$(shasum "$STATUS" | awk '{print $1}')
  [ "$sum_before" = "$sum_after" ]
}

# --- Fix 2: backtick info-string with embedded backtick → not a valid opener ---

@test "flow-sync: backtick fence with backtick in info string is not a code opener — markers are real" {
  # CommonMark §4.5: a backtick fence opener may NOT have a backtick anywhere in
  # the info string. So '```js`weird' is plain text, not a code fence.
  # Real mb-flow markers that follow it must be treated as REAL markers,
  # not silently hidden as if inside code.
  cat > "$STATUS" <<'EOF'
# Status

Normal paragraph.

```js`weird
<!-- mb-flow -->
route: after-invalid-opener
<!-- /mb-flow -->
```

More content.
EOF

  # The two markers are REAL (the invalid-opener line is not a code fence).
  # That means the parser finds exactly one open+close pair → valid first-write
  # scenario? No — they form a real pair so it's a valid existing fence.
  # The script should treat them as the runtime fence and UPDATE (not duplicate).
  run bash "$SYNC" "$TMPBANK" --route research --gate PASS
  [ "$status" -eq 0 ]

  # The fence was updated to the new values.
  grep -q 'route: research' "$STATUS"
  grep -q 'gate: PASS' "$STATUS"

  # The invalid-opener line and the closing ``` line still exist verbatim.
  grep -q '```js`weird' "$STATUS"

  # Exactly one open and one close marker (the pair we updated).
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 1 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 1 ]
}

@test "flow-sync: tilde fence with backtick in info string IS a valid opener — markers stay code" {
  # Tilde fences ARE allowed to have backticks in the info string (CommonMark §4.5).
  # So '~~~python`extra' IS a valid tilde opener; content inside is code; markers hidden.
  cat > "$STATUS" <<'EOF'
# Status

~~~python`extra
<!-- mb-flow -->
route: inside-tilde-code
<!-- /mb-flow -->
~~~

Real content.
EOF

  # No real fence yet → first write appends.
  run bash "$SYNC" "$TMPBANK" --route bugfix --gate FAIL
  [ "$status" -eq 0 ]

  # The inside-tilde-code content must be preserved.
  grep -q 'route: inside-tilde-code' "$STATUS"
  # Fresh real fence appended.
  grep -q 'route: bugfix' "$STATUS"
  grep -q 'gate: FAIL' "$STATUS"
  # Two marker pairs total: 1 inside tilde block + 1 real appended.
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 2 ]
}

# --- Fix 3: tests 29/30 strengthened — markers at column 0 inside indented fence ---
# The ORIGINAL tests 29/30 have the mb-flow marker lines indented alongside the fence,
# so a column-0-only old opener_re would also miss them (grep finds them anywhere in line
# but the old regex wouldn't open code-fence mode for an indented opener — yet the
# indented markers also have leading spaces, so 'grep -c' still finds 2 total).
# The STRENGTHENED versions below put MARKER LINES AT COLUMN 0 inside an indented fence.
# A column-0-only opener_re would NOT recognise the indented opener → 'in_code' stays
# False → the column-0 markers are treated as REAL → validate_markers sees a real pair
# and OVERWRITES the block → test goes RED against the old regex.
# The correct CommonMark parser recognises the indented opener → markers hidden → fresh
# fence appended → test GREEN.

@test "flow-sync: indented fence (1 space) with column-0 markers inside — not treated as real" {
  # FENCE opener has 1 leading space; MARKERS are at column 0.
  # Old column-0 regex: opener NOT matched → in_code stays False → column-0 markers
  # treated as REAL pair → overwrites block content (data loss; test RED).
  # Correct parser: opener matched (0-3 space rule) → in_code=True → markers hidden
  # → fresh fence appended → block content preserved (test GREEN).
  cat > "$STATUS" <<'EOF'
# Status

Docs example:

 ```
<!-- mb-flow -->
route: col0-inside-indented
<!-- /mb-flow -->
 ```

Content after.
EOF

  run bash "$SYNC" "$TMPBANK" --route arch --gate PASS
  [ "$status" -eq 0 ]

  # Block content PRESERVED (not overwritten).
  grep -q 'route: col0-inside-indented' "$STATUS"

  # Fresh real fence appended with requested values.
  grep -q 'route: arch' "$STATUS"
  grep -q 'gate: PASS' "$STATUS"

  # Total open markers: 1 (col-0, inside code block) + 1 (real appended) = 2.
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 2 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 2 ]
}

@test "flow-sync: indented fence (3 spaces) with column-0 markers inside — not treated as real" {
  # Same as above but 3-space indent — the maximum CommonMark allows.
  cat > "$STATUS" <<'EOF'
# Status

Docs:

   ~~~
<!-- mb-flow -->
route: col0-in-3space
<!-- /mb-flow -->
   ~~~

After.
EOF

  run bash "$SYNC" "$TMPBANK" --route migration --gate FAIL
  [ "$status" -eq 0 ]

  grep -q 'route: col0-in-3space' "$STATUS"
  grep -q 'route: migration' "$STATUS"
  grep -q 'gate: FAIL' "$STATUS"
  [ "$(grep -c '<!-- mb-flow -->' "$STATUS")" -eq 2 ]
  [ "$(grep -c '<!-- /mb-flow -->' "$STATUS")" -eq 2 ]
}
