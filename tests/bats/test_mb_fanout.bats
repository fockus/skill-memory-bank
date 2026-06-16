#!/usr/bin/env bats
# Tests for scripts/mb-fanout.sh — the stateless, agent-invoked fan-out helper
# (dynamic-flow Phase 2 Task 9).
#
# Contract under test (REQ-DF-081/084/085, ADR-3):
#   - Takes N branch prompts + a per-agent sub-invoke command (`--cmd`), runs the
#     branches CONCURRENTLY via POSIX background jobs + a single `wait`, captures
#     each branch's stdout, parses it as JSON, and emits ONE aggregate JSON object.
#   - The branch PROMPT reaches `--cmd` ONLY through an exported env var
#     (MB_FANOUT_PROMPT / MB_FANOUT_BRANCH_INDEX) — never interpolated into the
#     command string, never eval'd (the security seam).
#   - Exit-code authority (fail-loud — ADR-3): 0 = every branch ran AND returned
#     valid JSON; 2 = ANY branch failed/non-JSON, OR a usage error, OR the
#     branch-count cap exceeded, OR the budget pre-check rejected the run. No exit 1.
#   - Stateless: a mktemp -d workspace, trap-cleaned; nothing persists in the bank.
#
# Determinism: `--cmd` is a stub that reads MB_FANOUT_PROMPT, so the exit
# trichotomy is exercised without real sub-agents.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FANOUT="$REPO_ROOT/scripts/mb-fanout.sh"
  BUDGET="$REPO_ROOT/scripts/mb-work-budget.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# A stub `--cmd` that echoes a JSON object embedding the branch prompt + index it
# received via the env vars. Exits 0. Proves the prompt arrived via env (not
# interpolation) and that each branch sees its own prompt. python3 json.dumps keeps
# the body valid even when a prompt contains quotes / control chars (the seam test).
ECHO_CMD='python3 -c "import json,os;print(json.dumps({\"prompt\":os.environ[\"MB_FANOUT_PROMPT\"],\"index\":int(os.environ[\"MB_FANOUT_BRANCH_INDEX\"])}))"'

# Under `run`, bats merges stdout+stderr into $output. The aggregate JSON is the
# single line that begins with `{`; isolate it from any `[mb-fanout] …` diagnostics.
json_line() {
  printf '%s\n' "$1" | grep -E '^\{' | head -n1
}

# ═══════════════════════════════════════════════════════════════
# Existence / help / usage
# ═══════════════════════════════════════════════════════════════

@test "fanout: script exists and is executable" {
  [ -f "$FANOUT" ]
  [ -x "$FANOUT" ]
}

@test "fanout: --help prints the exit contract and exits 0" {
  run bash "$FANOUT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--cmd"* ]]
  [[ "$output" == *"--branch"* ]]
}

@test "fanout: missing --cmd → exit 2 usage" {
  run bash "$FANOUT" "$TMPBANK" --branch "do a thing"
  [ "$status" -eq 2 ]
}

@test "fanout: zero branches → exit 2 usage" {
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD"
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# Happy path — N branches, all valid JSON
# ═══════════════════════════════════════════════════════════════

@test "fanout: N branches all return valid JSON → exit 0, aggregate has N ok branches" {
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" \
    --branch "alpha" --branch "beta" --branch "gamma"
  [ "$status" -eq 0 ]
  # One aggregate JSON object on stdout.
  echo "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["count"]==3, o
assert o["failed"]==0, o
assert o["ok"] is True, o
assert len(o["branches"])==3, o
for b in o["branches"]:
    assert b["ok"] is True, b
    assert b["error"] is None, b
'
}

@test "fanout: each branch receives its OWN prompt via env (no interpolation, no cross-talk)" {
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" \
    --branch "first-prompt" --branch "second-prompt"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
by_index={b["index"]:b for b in o["branches"]}
assert by_index[0]["result"]["prompt"]=="first-prompt", o
assert by_index[1]["result"]["prompt"]=="second-prompt", o
assert by_index[0]["result"]["index"]==0, o
assert by_index[1]["result"]["index"]==1, o
'
}

@test "fanout: a prompt with shell metacharacters is passed literally via env (security seam)" {
  # If the prompt were interpolated into --cmd or eval'd, these would break out.
  local marker="/tmp/mb_fanout_pwned_$$"
  rm -f "$marker"
  local nasty='$(touch '"$marker"'); `id`; "; rm -rf /'
  NASTY="$nasty" run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --branch "$nasty"
  [ "$status" -eq 0 ]
  # The injection NEVER ran (no marker file created).
  [ ! -e "$marker" ]
  # And the prompt arrived literally (quotes/`$()`/backticks intact).
  NASTY="$nasty" python3 -c '
import json,sys,os
o=json.loads(sys.stdin.read())
assert o["branches"][0]["result"]["prompt"]==os.environ["NASTY"], o
' <<<"$output"
}

@test "fanout: --branch-file reads a prompt from a file" {
  printf 'prompt-from-file' > "$TMPROOT/branch.txt"
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --branch-file "$TMPROOT/branch.txt"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["branches"][0]["result"]["prompt"]=="prompt-from-file", o
'
}

# ═══════════════════════════════════════════════════════════════
# Fail-loud — non-JSON / non-zero branch (REQ-DF-084, ADR-3)
# ═══════════════════════════════════════════════════════════════

@test "fanout: one branch returns NON-JSON → exit 2, that branch marked failed, others still present" {
  # Branch 0 emits garbage; branch 1 emits valid JSON. The valid one must NOT be
  # silently dropped, and the run must exit 2.
  local cmd='if [ "$MB_FANOUT_BRANCH_INDEX" = "0" ]; then printf "not json at all\n"; else printf "{\"ok\":1}\n"; fi'
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --branch "bad" --branch "good"
  [ "$status" -eq 2 ]
  [[ "$output" == *"FAILED"* ]]            # loud diagnostic present
  # The aggregate JSON is the single `{...}` line; isolate it from any diagnostics.
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["ok"] is False, o
assert o["count"]==2, o
assert o["failed"]==1, o
by={b["index"]:b for b in o["branches"]}
assert by[0]["ok"] is False, o
assert by[0]["error"] is not None, o
assert by[1]["ok"] is True, o            # no silent drop
'
}

@test "fanout: one branch exits non-zero → exit 2 with an error marker" {
  local cmd='if [ "$MB_FANOUT_BRANCH_INDEX" = "0" ]; then printf "{\"ok\":1}\n"; exit 7; else printf "{\"ok\":2}\n"; fi'
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --branch "boom" --branch "fine"
  [ "$status" -eq 2 ]
  [[ "$output" == *"FAILED"* ]]            # loud diagnostic present
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["ok"] is False, o
assert o["failed"]==1, o
by={b["index"]:b for b in o["branches"]}
assert by[0]["ok"] is False, o
assert by[0]["error"] is not None, o
assert "7" in by[0]["error"], o          # exit code surfaced in the marker
assert by[1]["ok"] is True, o
'
}

# ═══════════════════════════════════════════════════════════════
# Fail-loud — JSON validity BOUNDARY (a branch result must be a JSON OBJECT)
# Round-1 review: top-level non-object JSON (null/42/"x"/true/[..]) and invalid
# UTF-8 / empty / whitespace stdout must all be loud failures, never ok:true and
# never a crash/exit-1. The result element a downstream pattern reads is an OBJECT.
# ═══════════════════════════════════════════════════════════════

@test "fanout: a branch emitting bare 'null' is a FAILURE (non-object) → exit 2" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "null\n"' --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["ok"] is False, o
assert o["failed"]==1, o
assert o["branches"][0]["ok"] is False, o
assert o["branches"][0]["error"] is not None, o
'
}

@test "fanout: a branch emitting a bare number/array is a FAILURE (non-object) → exit 2" {
  local cmd='if [ "$MB_FANOUT_BRANCH_INDEX" = "0" ]; then printf "42\n"; else printf "[1,2]\n"; fi'
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --branch a --branch b
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["failed"]==2, o
assert all(b["ok"] is False for b in o["branches"]), o
'
}

@test "fanout: a valid JSON OBJECT branch is ok:true (regression guard)" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{\"v\":1}\n"' --branch a
  [ "$status" -eq 0 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["ok"] is True, o
assert o["branches"][0]["result"]=={"v":1}, o
'
}

@test "fanout: invalid UTF-8 stdout → loud failure (exit 2), aggregate still printed, NO exit 1" {
  # printf '\377' is a lone 0xFF byte — not valid UTF-8. The aggregator must NOT
  # crash (which would be exit 1 + no aggregate); it must mark the branch failed.
  run bash "$FANOUT" "$TMPBANK" --cmd "printf '\377'" --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["ok"] is False, o
assert o["branches"][0]["ok"] is False, o
assert o["branches"][0]["error"] is not None, o
'
}

@test "fanout: empty stdout (exit 0, no output) → loud failure → exit 2 (no silent drop)" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'true' --branch a --branch b
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["failed"]==2, o
assert all(b["ok"] is False for b in o["branches"]), o
'
}

@test "fanout: whitespace-only stdout → loud failure → exit 2" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "   \n"' --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["branches"][0]["ok"] is False, o
'
}

# Round-6 review: Python's json.loads accepts the NON-standard constants NaN /
# Infinity / -Infinity. Such output is NOT valid JSON to a strict parser, and an
# aggregate containing them is itself invalid — they must be loud failures, and
# the aggregate must always be strict-valid JSON.
@test "fanout: a branch emitting NaN is a FAILURE → exit 2 AND a strict-valid aggregate" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{\"v\":NaN}\n"' --branch a
  [ "$status" -eq 2 ]
  # The emitted aggregate must be STRICT JSON (no NaN/Infinity tokens).
  json_line "$output" | python3 -c '
import json,sys
o=json.loads(sys.stdin.read(), parse_constant=lambda s:(_ for _ in ()).throw(ValueError(s)))
assert o["branches"][0]["ok"] is False, o
assert o["failed"]==1, o
'
}

@test "fanout: a branch emitting Infinity is a FAILURE → exit 2" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{\"v\":Infinity}\n"' --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.loads(sys.stdin.read(), parse_constant=lambda s:(_ for _ in ()).throw(ValueError(s)))
assert o["branches"][0]["ok"] is False, o
'
}

@test "fanout: an overflowing float literal (1e9999 → inf) is a FAILURE → exit 2 AND aggregate present" {
  # Round-7 review: parse_constant only catches the NaN/Infinity TOKENS; a numeric
  # literal that overflows to inf via parse_float slipped through to ok:true, then
  # json.dumps(allow_nan=False) raised and the aggregate was LOST (exit 2, empty).
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{\"v\":1e9999}\n"' --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.loads(sys.stdin.read(), parse_constant=lambda s:(_ for _ in ()).throw(ValueError(s)))
assert o["branches"][0]["ok"] is False, o
assert o["failed"]==1, o
'
}

@test "fanout: a negative overflowing float (-1e9999 → -inf) is a FAILURE → exit 2, aggregate present" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{\"v\":-1e9999}\n"' --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["branches"][0]["ok"] is False, o
'
}

@test "fanout: finite floats (1.5, 1e300) are NOT over-rejected → ok:true" {
  local cmd='if [ "$MB_FANOUT_BRANCH_INDEX" = "0" ]; then printf "{\"v\":1.5}\n"; else printf "{\"v\":1e300}\n"; fi'
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --branch a --branch b
  [ "$status" -eq 0 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["ok"] is True, o
assert all(b["ok"] is True for b in o["branches"]), o
'
}

@test "fanout: nested overflow {\"a\":[1e9999]} is a FAILURE → exit 2, aggregate present" {
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{\"a\":[1e9999]}\n"' --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["branches"][0]["ok"] is False, o
'
}

@test "fanout: a 5000-digit integer literal is a FAILURE → exit 2, aggregate present (no lost aggregate)" {
  # Python 3.11+ caps int<->str conversion; json.loads raises → caught as non-JSON.
  local f="$TMPROOT/bigint.txt"
  python3 -c 'open(__import__("sys").argv[1],"w").write("{\"v\":"+"9"*5000+"}")' "$f"
  run bash "$FANOUT" "$TMPBANK" --cmd "cat '$f'" --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["branches"][0]["ok"] is False, o
'
}

@test "fanout: pathologically deep branch JSON → loud failure (exit 2), aggregate present, NO exit 1" {
  # RecursionError (or any parser exception) must not crash the aggregator.
  local cmd='python3 -c "print(chr(91)*20000 + chr(93)*20000)"'
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --branch a
  [ "$status" -eq 2 ]
  json_line "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["branches"][0]["ok"] is False, o
'
}

# ═══════════════════════════════════════════════════════════════
# Concurrency — branches run in parallel, not serialized
# ═══════════════════════════════════════════════════════════════

@test "fanout: branches run CONCURRENTLY (4 branches each sleeping ~1s finish well under 4s)" {
  local cmd='sleep 1; printf "{\"slept\":1}\n"'
  local start end elapsed
  start="$(date +%s)"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" \
    --branch a --branch b --branch c --branch d
  end="$(date +%s)"
  [ "$status" -eq 0 ]
  elapsed=$((end - start))
  # Serial would be ~4s; concurrent should be ~1s. Generous bound (<3s) avoids flake.
  [ "$elapsed" -lt 3 ]
}

# ═══════════════════════════════════════════════════════════════
# Branch-count cap — fail BEFORE spawning
# ═══════════════════════════════════════════════════════════════

@test "fanout: --max-branches exceeded → exit 2 BEFORE spawning (no side effects)" {
  # A --cmd that would create a sentinel file if it ever ran.
  local sentinel="$TMPROOT/spawned"
  local cmd='printf "{}\n" > '"$sentinel"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --max-branches 2 \
    --branch a --branch b --branch c
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

# ═══════════════════════════════════════════════════════════════
# Budget pre-check — fail BEFORE spawning when N×cost > remaining
# ═══════════════════════════════════════════════════════════════

@test "fanout: tracked budget too small for N×cost → exit 2 BEFORE spawning" {
  # total=100, spent=0 → remaining 100. 3 branches × 50 = 150 > 100 → reject.
  bash "$BUDGET" init 100 --mb "$TMPBANK"
  local sentinel="$TMPROOT/spawned_budget"
  local cmd='printf "{}\n" > '"$sentinel"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --cost-per-branch 50 \
    --branch a --branch b --branch c
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

@test "fanout: tracked budget large enough → runs normally (exit 0)" {
  # total=100000, 3 × 50 = 150 ≤ 100000 → ok.
  bash "$BUDGET" init 100000 --mb "$TMPBANK"
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --cost-per-branch 50 \
    --branch a --branch b --branch c
  [ "$status" -eq 0 ]
}

@test "fanout: NO budget tracked → budget check is a no-op, run proceeds (exit 0)" {
  # No `budget init`; --cost-per-branch given but nothing to check against.
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --cost-per-branch 999999 \
    --branch a --branch b
  [ "$status" -eq 0 ]
}

@test "fanout: a TRACKED-but-CORRUPT budget must fail-CLOSED (exit 2), never fail-open" {
  # Round-2 review: a .work-budget.json that EXISTS but is unreadable (status
  # exits non-zero) was being treated as "no budget tracked" → fanout spawned.
  # A tracked-but-inconclusive budget MUST refuse to spawn (exit 2), distinct
  # from the genuine no-budget no-op (no state file at all).
  printf '{"total":100,"spent":"bad","warn_at_percent":80,"stop_at_percent":100}\n' \
    > "$TMPBANK/.work-budget.json"
  local sentinel="$TMPROOT/spawned_corrupt"
  local cmd='printf "{}\n" > '"$sentinel"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" \
    --cost-per-branch 9223372036854775807 --branch a
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

@test "fanout: state path is a DIRECTORY → inconclusive, fail-CLOSED (exit 2), no spawn" {
  # Round-3 review: `[ -f ]` is false for a non-regular path → was treated as
  # "no budget" → fail-open spawn. A state path that EXISTS in any form but is
  # not a regular readable file is INCONCLUSIVE → exit 2.
  mkdir -p "$TMPBANK/.work-budget.json"   # a directory, not a file
  local sentinel="$TMPROOT/spawned_dirstate"
  local cmd='printf "{}\n" > '"$sentinel"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" \
    --cost-per-branch 9223372036854775807 --branch a
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

@test "fanout: state path is a DANGLING SYMLINK → inconclusive, fail-CLOSED (exit 2), no spawn" {
  ln -s /nonexistent/nope "$TMPBANK/.work-budget.json"
  local sentinel="$TMPROOT/spawned_dangling"
  local cmd='printf "{}\n" > '"$sentinel"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" \
    --cost-per-branch 9223372036854775807 --branch a
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

@test "fanout: tracked budget whose status emits NO total=/spent= → exit 2 (never exit 1)" {
  # Round-3 review: under set -euo pipefail a grep no-match exited 1 BEFORE the
  # intended inconclusive exit 2. A tracked-but-unparseable status must be a
  # loud exit 2, never the forbidden exit 1.
  printf '{}' > "$TMPBANK/.work-budget.json"   # regular file → "tracked"
  local fake="$TMPROOT/fakebudget.sh"
  printf '#!/usr/bin/env bash\necho "WARNING only"\nexit 0\n' > "$fake"
  chmod +x "$fake"
  local sentinel="$TMPROOT/spawned_nofields"
  local cmd='printf "{}\n" > '"$sentinel"
  MB_BUDGET_BIN="$fake" run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" \
    --cost-per-branch 5 --branch a
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

@test "fanout: a malformed status token (total=100=garbage) is inconclusive → exit 2, no spawn" {
  # Round-4 review: `cut -d= -f2` turned `total=100=garbage` into `100`, so a
  # malformed tracked-budget status fell through and spawned. Only an EXACT
  # `total=<digits>` whole token is a valid field; anything else is inconclusive.
  printf '{}' > "$TMPBANK/.work-budget.json"
  local fake="$TMPROOT/fakebudget2.sh"
  printf '#!/usr/bin/env bash\necho "total=100=garbage spent=0"\nexit 0\n' > "$fake"
  chmod +x "$fake"
  local sentinel="$TMPROOT/spawned_malformed_token"
  local cmd='printf "{}\n" > '"$sentinel"
  MB_BUDGET_BIN="$fake" run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" \
    --cost-per-branch 100 --branch a
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

@test "fanout: a LONG budget status must not SIGPIPE-abort the parser (no exit 141/1)" {
  # Round-5 review: an `awk ... {exit}` early-exit made the upstream `printf|tr`
  # take SIGPIPE under pipefail → the script aborted with 141 instead of the
  # contracted 0/2. A status whose noise exceeds the pipe buffer must still parse
  # cleanly (total=100, spent=0 → need 5 ≤ 100 → spawn), never crash.
  printf '{}' > "$TMPBANK/.work-budget.json"
  local fake="$TMPROOT/fakebudget_long.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "total=100 "\n'
    printf 'awk "BEGIN{for(i=0;i<100000;i++)printf \\"x \\"}"\n'
    printf 'printf "spent=0\\n"\n'
    printf 'exit 0\n'
  } > "$fake"
  chmod +x "$fake"
  MB_BUDGET_BIN="$fake" run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" \
    --cost-per-branch 5 --branch a
  [ "$status" -eq 0 ]
}

@test "fanout: an unwritable TMPDIR (mktemp fails) → exit 2, never a bare exit 1" {
  # Round-5 review: `WORKDIR="$(mktemp -d ...)"` under set -e aborted with exit 1
  # when TMPDIR was unusable. A workspace-creation failure must be the loud 2.
  TMPDIR=/no/such/dir run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{}\n"' --branch a
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# Round-6 review: whole-file exit-code authority — only 0/2 may reach the caller
# ═══════════════════════════════════════════════════════════════

@test "fanout: --branch-file that exists but is unreadable (chmod 000) → exit 2 usage, not 1" {
  local f="$TMPROOT/secret.txt"
  printf 'p' > "$f"
  chmod 000 "$f"
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{}\n"' --branch-file "$f"
  chmod 644 "$f"   # restore so teardown can clean up
  [ "$status" -eq 2 ]
}

@test "fanout: an absurdly long --max-branches digit string → exit 2 usage, not a Python crash" {
  local big
  big="$(python3 -c 'print("9"*5000)')"
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{}\n"' --branch a --max-branches "$big" --dry-run
  [ "$status" -eq 2 ]
}

@test "fanout: an absurdly long --cost-per-branch digit string → exit 2 usage" {
  local big
  big="$(python3 -c 'print("9"*5000)')"
  run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{}\n"' --branch a --cost-per-branch "$big"
  [ "$status" -eq 2 ]
}

@test "fanout: python3 missing on --dry-run → exit 2, never a bare 127" {
  local stub="$TMPROOT/stubbin"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 127\n' > "$stub/python3"
  chmod +x "$stub/python3"
  PATH="$stub:$PATH" run bash "$FANOUT" "$TMPBANK" --cmd 'printf "{}\n"' --branch a --dry-run
  [ "$status" -eq 2 ]
}

@test "fanout: python3 missing on aggregation → exit 2 AND a strict fallback aggregate (no lost aggregate)" {
  # Round-8 review: when python3 itself is unusable at the aggregation step, the
  # aggregate-always contract still holds — bash emits a strict fallback object
  # marking EVERY branch ok:false, so no branch is silently dropped (REQ-DF-084).
  local stub="$TMPROOT/stubbin2"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 127\n' > "$stub/python3"
  chmod +x "$stub/python3"
  PATH="$stub:$PATH" run bash "$FANOUT" "$TMPBANK" \
    --cmd 'printf "{\"v\":1}\n"' --branch a --branch b
  [ "$status" -eq 2 ]
  # The aggregate must be PRESENT and strict-valid even though python3 is broken.
  # Parse it with a DIFFERENT tool (the test's own real python via $BATS env) —
  # here we just assert the JSON line exists and represents both branches failed.
  local agg
  agg="$(json_line "$output")"
  [ -n "$agg" ]
  [[ "$agg" == *'"count":2'* ]]
  [[ "$agg" == *'"failed":2'* ]]
  [[ "$agg" == *'"ok":false'* ]]
}

@test "fanout: a TMPDIR containing a single quote still trap-cleans its workspace (no leak)" {
  local weird="$TMPROOT/a'b"
  mkdir -p "$weird"
  TMPDIR="$weird" run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --branch a
  [ "$status" -eq 0 ]
  # No mb-fanout workspace must survive under the weird TMPDIR. `find` takes the
  # path as a single quoted arg, so the embedded ' can't corrupt the check.
  run find "$weird" -maxdepth 1 -name 'mb-fanout*'
  [ -z "$output" ]
}

@test "fanout: a HUGE --cost-per-branch must NOT overflow into a fail-OPEN spawn" {
  # Round-1 review: bash $((N*cost)) wrapped negative for a 2^63-1 cost, bypassing
  # the pre-check and SPAWNING. With remaining=100, N×huge ≫ 100 → MUST reject (2)
  # and spawn nothing. Arithmetic must be arbitrary-precision (Python), not bash.
  bash "$BUDGET" init 100 --mb "$TMPBANK"
  local sentinel="$TMPROOT/spawned_overflow"
  local cmd='printf "{}\n" > '"$sentinel"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" \
    --cost-per-branch 9223372036854775807 --branch a --branch b
  [ "$status" -eq 2 ]
  [ ! -e "$sentinel" ]
}

@test "fanout: a leading-zero --cost-per-branch (08) is decimal, not an octal crash" {
  # Round-1 review: bash $(( ... 08 ... )) raised 'value too great for base' (a
  # would-be exit 1). Treated as decimal 8 in Python: 2×8=16 ≤ 100000 → run (exit 0).
  bash "$BUDGET" init 100000 --mb "$TMPBANK"
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --cost-per-branch 08 \
    --branch a --branch b
  [ "$status" -eq 0 ]
  # And NOT because a bash octal arithmetic error was swallowed.
  [[ "$output" != *"value too great for base"* ]]
}

# ═══════════════════════════════════════════════════════════════
# --dry-run — validate + print plan, spawn nothing
# ═══════════════════════════════════════════════════════════════

@test "fanout: --dry-run prints a plan JSON, spawns NOTHING, exit 0" {
  local sentinel="$TMPROOT/spawned_dry"
  local cmd='printf "{}\n" > '"$sentinel"
  run bash "$FANOUT" "$TMPBANK" --cmd "$cmd" --dry-run \
    --branch a --branch b
  [ "$status" -eq 0 ]
  [ ! -e "$sentinel" ]
  echo "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o.get("dry_run") is True, o
assert o.get("count")==2, o
'
}

# ═══════════════════════════════════════════════════════════════
# Statelessness — nothing persists in the bank
# ═══════════════════════════════════════════════════════════════

@test "fanout: leaves NO state/journal file behind in the bank after a run" {
  before="$(ls -a "$TMPBANK" | sort)"
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --branch a --branch b
  [ "$status" -eq 0 ]
  after="$(ls -a "$TMPBANK" | sort)"
  [ "$before" = "$after" ]
  # No fanout-named artifact anywhere under the bank.
  run bash -c "ls -A '$TMPBANK' | grep -i fanout || true"
  [ -z "$output" ]
}

@test "fanout: leaves NO mktemp workspace behind after a run (trap-cleaned)" {
  # Count TMPDIR entries matching a fanout workspace before/after.
  run bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --branch a
  [ "$status" -eq 0 ]
  run bash -c "ls -d \${TMPDIR:-/tmp}/mb-fanout* 2>/dev/null || true"
  [ -z "$output" ]
}

# ═══════════════════════════════════════════════════════════════
# bash-3.2 portability — runs under /bin/bash
# ═══════════════════════════════════════════════════════════════

@test "fanout: runs under /bin/bash (bash-3.2 class)" {
  run /bin/bash "$FANOUT" "$TMPBANK" --cmd "$ECHO_CMD" --branch a --branch b
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert o["count"]==2, o
'
}
