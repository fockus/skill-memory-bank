#!/usr/bin/env bats

# S2 review hardening for mb-spec-validate.sh — findings [11]-[16], [19], [20],
# [22]. Each @test names the finding it locks down and mutates exactly ONE thing
# off the shared valid baseline so the failure is attributable.
#
# Fixture helpers shared via lib/spec_validate_fixture.bash.

load 'lib/spec_validate_fixture'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-spec-validate.sh"
  TMPDIR="$(mktemp -d)"
  SPECS="$TMPDIR/specs"
  mkdir -p "$SPECS"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# _set_eval <dir> <eval-payload-after-the-em-dash-cmd>
# Rewrites BOTH tasks.md and design.md Eval lines so the byte-identity gate
# stays satisfied while only the command under test changes.
_set_eval() {
  local dir="$1" cmd="$2"
  python3 - "$dir" "$cmd" "$DASH" <<'PY'
import sys, pathlib
d, cmd, dash = sys.argv[1], sys.argv[2], sys.argv[3]
rest = "red: demo assertion fails; exit: 1; output~: `not ok [0-9]+ demo_persist`"
payload = f"**Eval:** `{cmd}` {dash} {rest}"
t = pathlib.Path(d) / "tasks.md"
t.write_text("\n".join(
    payload if ln.startswith("**Eval:**") else ln
    for ln in t.read_text(encoding="utf-8").splitlines()
) + "\n", encoding="utf-8")
g = pathlib.Path(d) / "design.md"
# design nests the same payload one level deep — indentation is the only
# permitted difference (CPR-D compares the payload raw).
g.write_text("\n".join(
    ("  " + payload) if "**Eval:**" in ln else ln
    for ln in g.read_text(encoding="utf-8").splitlines()
) + "\n", encoding="utf-8")
PY
}

# ── [11] Eval target containment ─────────────────────────────────────────────

@test "hardening: an Eval target escaping the repo via '..' is rejected (review [11])" {
  dir="$(mkbase demo)"
  _set_eval "$dir" "bash ../outside/check.sh"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "repo-relative\|escape"
}

@test "hardening: a plain repo-relative Eval target still passes (review [11] control)" {
  dir="$(mkbase demo)"
  _set_eval "$dir" "bash tests/inside/check.sh"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── [12] design↔tasks Eval identity ──────────────────────────────────────────

@test "hardening: a design Eval differing from tasks by real bytes is rejected (review [12])" {
  dir="$(mkbase demo)"
  # design says `pytest -q`, tasks say `bats ...` — normalization used to hide
  # nothing here, but backticks/spacing differences did; use a spacing delta.
  python3 - "$dir" <<'PY'
import sys, pathlib
g = pathlib.Path(sys.argv[1]) / "design.md"
txt = g.read_text(encoding="utf-8")
# double the space after the Eval label: same tokens, different bytes.
txt = txt.replace("**Eval:** `bats", "**Eval:**  `bats")
g.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CPR-D"
}

@test "hardening: tasks carrying Evals while design declares none is rejected (review [12])" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
g = pathlib.Path(sys.argv[1]) / "design.md"
keep = [ln for ln in g.read_text(encoding="utf-8").splitlines()
        if "**Eval:**" not in ln and not ln.startswith("- **T")]
g.write_text("\n".join(keep) + "\n", encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CPR-D"
}

# ── [13] Seams block presence ────────────────────────────────────────────────

@test "hardening: a v2 spec with Eval but no Seams block is rejected (review [13])" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
g = pathlib.Path(sys.argv[1]) / "design.md"
out, skip = [], False
for ln in g.read_text(encoding="utf-8").splitlines():
    if ln.strip().startswith("**Seams:**"):
        skip = True
        continue
    if skip and ln.strip().startswith("- "):
        continue
    skip = False
    out.append(ln)
g.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "REQ-051\|C9"
}

# ── [14] unresolved local Blocked-by ─────────────────────────────────────────

@test "hardening: a Blocked-by naming a non-existent local task is rejected (review [14])" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8")
txt = txt.replace("**Role:** backend", "**Role:** backend\n**Blocked-by:** 99", 1)
t.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "99"
}

# ── [15] cross-spec Blocked-by cycle ─────────────────────────────────────────

@test "hardening: a cross-spec Blocked-by cycle a#1 <-> b#1 is detected (review [15])" {
  da="$(mkbase alpha)"
  db="$(mkbase beta)"
  python3 - "$da" "beta#1" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8")
txt = txt.replace("**Role:** backend", f"**Role:** backend\n**Blocked-by:** {sys.argv[2]}", 1)
t.write_text(txt, encoding="utf-8")
PY
  python3 - "$db" "alpha#1" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8")
txt = txt.replace("**Role:** backend", f"**Role:** backend\n**Blocked-by:** {sys.argv[2]}", 1)
t.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$da"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "cycle"
}

# ── [16] docs/config task needs a structural Eval ────────────────────────────

@test "hardening: a docs-only task with a behavioural Eval is rejected (review [16], REQ-049)" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8")
txt = txt.replace("**Role:** backend", "**Role:** backend\n**Scope:** docs/**", 1)
t.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "REQ-049"
}

@test "hardening: a docs-only task with a structural (file-presence) Eval passes (review [16])" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8")
txt = txt.replace("**Role:** backend", "**Role:** backend\n**Scope:** docs/**", 1)
t.write_text(txt, encoding="utf-8")
PY
  _set_eval "$dir" "test -f docs/guide.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── [19] staged candidate resolves cross-spec deps against <bank>/specs ──────

@test "hardening: staged tmp/sdd candidate resolves cross-spec Blocked-by in <bank>/specs (review [19])" {
  local bank="$TMPDIR/.memory-bank"
  mkdir -p "$bank/specs" "$bank/tmp/sdd"
  SPECS="$bank/specs" mkbase existing >/dev/null
  local staged="$bank/tmp/sdd/demo"
  mkdir -p "$staged"
  SPECS="$bank/tmp/sdd" mkbase demo >/dev/null
  python3 - "$staged" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8")
txt = txt.replace("**Role:** backend", "**Role:** backend\n**Blocked-by:** existing#1", 1)
t.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$staged" "$bank"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── [20] roles come from the pipeline roles table ────────────────────────────

@test "hardening: the pipeline default role 'planner' is accepted (review [20])" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8").replace("**Role:** backend", "**Role:** planner", 1)
t.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "hardening: the pipeline default role 'researcher' is accepted (review [20])" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8").replace("**Role:** backend", "**Role:** researcher", 1)
t.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "hardening: a role absent from the pipeline roles table is still rejected (review [20])" {
  dir="$(mkbase demo)"
  python3 - "$dir" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1]) / "tasks.md"
txt = t.read_text(encoding="utf-8").replace("**Role:** backend", "**Role:** wizard", 1)
t.write_text(txt, encoding="utf-8")
PY
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "C8.3"
}

# ── [22] --require-tests resolves the real checkout ──────────────────────────

@test "hardening: --require-tests scans the real checkout for a non-adjacent bank (review [22])" {
  local checkout="$TMPDIR/checkout"
  local bank="$TMPDIR/elsewhere/global-bank"
  mkdir -p "$checkout/tests" "$bank/specs"
  ( cd "$checkout" && git init -q . && git config user.email t@t && git config user.name t )
  SPECS="$bank/specs" mkbase demo >/dev/null
  # Scan fixture, not a test: --require-tests only greps files for REQ-IDs.
  printf '# coverage marker consumed by the REQ scan: REQ-001\n' > "$checkout/tests/test_demo.py"
  cd "$checkout" || return 1
  run bash "$VALIDATE" --require-tests "$bank/specs/demo" "$bank"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
