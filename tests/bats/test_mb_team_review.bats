#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# mb-team-review.sh: team review cycles, gate over clean_when, external reviewer (design §8).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  R="$REPO_ROOT/scripts/mb-team-review.sh"
  W="$(mktemp -d)/with space"; mkdir -p "$W"
  TREE="$W/tree"; BANK="$W/proj/.memory-bank"; TD="$BANK/reports/demo"
  mkdir -p "$TREE/src/a" "$TREE/src/b" "$TD"
  git -C "$TREE" init -q . && git -C "$TREE" config user.email t@t && git -C "$TREE" config user.name t
  echo a >"$TREE/src/a/x.py"; git -C "$TREE" add -A && git -C "$TREE" commit -qm base
  BASE="$(git -C "$TREE" rev-parse HEAD)"
  echo b >"$TREE/src/b/y.py"; git -C "$TREE" add -A && git -C "$TREE" commit -qm work
  REV="$(git -C "$TREE" rev-parse HEAD)"
  printf 'team:\n  review:\n    enabled: true\n    max_cycles: 3\n' >"$W/pipeline.yaml"
  cat >"$TD/team.json" <<JSON
{"schema": 1, "topic": "demo", "title": "Demo team", "created": "2026-10-10T09:00:00Z",
 "goal": null, "plan": null, "tree": "$TREE", "mirror": null, "vcs": "git", "baseline": "$BASE",
 "brief": "reports/demo/brief.md", "known_red": [], "known_open": ["flaky recipe on Mac (environment)"],
 "tracks": [{"id": "A", "files": ["src/a/**"]}, {"id": "B", "files": ["src/b/**"]}],
 "reviews": [], "checkpoints": [], "commits": []}
JSON
}
teardown() { rm -rf "$(dirname "$W")"; }

rv() { bash "$R" "$1" --team "$TD/team.json" --mb "$BANK" --pipeline "${PIPE:-$W/pipeline.yaml}" "${@:2}"; }
master() { mkdir -p "$TD/review/cycle-$1"; cat >"$TD/review/cycle-$1/master.json"; }
dirty_master() {
  master 1 <<'JSON'
{"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 1, "medium": 1, "minor": 1},
 "issues": [
  {"id": "M-1", "severity": "major", "category": "logic", "file": "src/a/x.py", "line": 1, "message": "wrong branch", "owner": "A"},
  {"id": "M-2", "severity": "medium", "category": "tests", "file": "src/b/y.py", "line": 1, "message": "no test"},
  {"id": "M-3", "severity": "minor", "category": "code_rules", "file": "src/b/y.py", "line": 1, "message": "name"}],
 "previous_issues": []}
JSON
}
ext_dir() { echo "$TD/review/external-astra-cycle-$1"; }

@test "team review is off by default: start refuses with exit 3" {
  PIPE="$REPO_ROOT/references/pipeline.default.yaml" run rv start --cycle 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"team.review.enabled"* ]] || false
  [ ! -e "$TD/review" ]
}

@test "start writes the cycle brief: object, lenses with output paths, known open items" {
  run rv start --cycle 1 --range "$BASE..$REV"
  [ "$status" -eq 0 ]
  b="$TD/review/cycle-1/brief.md"
  [ "$output" = "$b" ]
  grep -qF "git diff $BASE $REV" "$b"
  grep -qF "$TD/review/cycle-1/logic.json" "$b"
  grep -qF "$TD/review/cycle-1/scalability.json" "$b"
  grep -qF "flaky recipe on Mac (environment)" "$b"
  grep -qF "src/a/**" "$b"
  grep -qF '"previous_issues"' "$b"
}

@test "start --lenses narrows the lens list and maps the quality alias" {
  run rv start --cycle 1 --lenses logic,quality
  [ "$status" -eq 0 ]
  b="$TD/review/cycle-1/brief.md"
  grep -qF "cycle-1/code_rules.json" "$b"
  run ! grep -qF "cycle-1/security.json" "$b"
  run rv start --cycle 2 --lenses nope
  [ "$status" -eq 2 ]
}

@test "start of the next cycle lists the previous medium+ issues to close" {
  dirty_master
  run rv start --cycle 2
  [ "$status" -eq 0 ]
  b="$TD/review/cycle-2/brief.md"
  grep -qF "M-1" "$b"; grep -qF "M-2" "$b"
  run ! grep -qF "M-3" "$b"
  grep -qF "$TD/review/cycle-1/master.json" "$b"
}

@test "gate: a cycle with findings exits 1 and groups fixes by owner track" {
  dirty_master
  run rv gate --cycle 1
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json, sys
g = json.load(sys.stdin)
assert g["verdict"] == "fixes_needed", g
assert g["fixes"] == {"A": ["M-1"], "B": ["M-2"]}, g["fixes"]
assert g["actions"] == ["fix A", "fix B"], g["actions"]
assert g["counts"]["minor"] == 1 and g["clean_when"]["medium"] == 0
'
}

@test "gate: fix then a clean cycle with every previous issue resolved exits 0" {
  dirty_master
  run rv gate --cycle 1; [ "$status" -eq 1 ]
  master 2 <<'JSON'
{"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 0, "medium": 0, "minor": 2},
 "issues": [{"id": "M-4", "severity": "minor", "category": "code_rules", "file": "src/a/x.py", "line": 1, "message": "nit"},
            {"id": "M-5", "severity": "minor", "category": "code_rules", "file": "src/b/y.py", "line": 1, "message": "nit"}],
 "previous_issues": [{"id": "M-1", "status": "resolved", "evidence": "x.py:1"},
                     {"id": "M-2", "status": "resolved", "evidence": "test_y.py:3"}]}
JSON
  run rv gate --cycle 2
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
g = json.load(sys.stdin)
assert g["verdict"] == "clean" and g["actions"] == [] and g["fixes"] == {}, g
'
}

@test "gate: a cycle without the status of a previous medium+ issue is broken input (exit 2)" {
  dirty_master
  master 2 <<'JSON'
{"verdict": "APPROVED", "counts": {"blocker": 0, "major": 0, "minor": 0}, "issues": [],
 "previous_issues": [{"id": "M-1", "status": "resolved", "evidence": "x.py:1"}]}
JSON
  run rv gate --cycle 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"M-2"* ]]
}

@test "gate: a previous issue still open keeps the cycle dirty and goes back to its owner" {
  dirty_master
  master 2 <<'JSON'
{"verdict": "APPROVED", "counts": {"blocker": 0, "major": 0, "minor": 0}, "issues": [],
 "previous_issues": [{"id": "M-1", "status": "unresolved", "evidence": "still wrong"},
                     {"id": "M-2", "status": "resolved", "evidence": "test_y.py:3"}]}
JSON
  run rv gate --cycle 2
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json, sys
g = json.load(sys.stdin)
assert g["previous_open"] == ["M-1"] and g["fixes"] == {"A": ["M-1"]}, g
'
}

@test "gate: one medium finding fails the default clean_when; a declared medium limit passes it" {
  master 1 <<'JSON'
{"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 0, "medium": 1, "minor": 0},
 "issues": [{"id": "M-9", "severity": "medium", "category": "logic", "file": "src/b/y.py", "line": 1, "message": "edge"}],
 "previous_issues": []}
JSON
  run rv gate --cycle 1
  [ "$status" -eq 1 ]
  [[ "$output" == *'"B": ["M-9"]'* ]] || false
  printf 'team:\n  review:\n    enabled: true\n    clean_when: {blocker: 0, major: 0, medium: 1}\n' >"$W/p2.yaml"
  PIPE="$W/p2.yaml" run rv gate --cycle 1
  [ "$status" -eq 0 ]
}

@test "gate: malformed or missing master is exit 2" {
  run rv gate --cycle 1
  [ "$status" -eq 2 ]
  master 1 <<<'{"verdict": "APPROVED", "counts": '
  run rv gate --cycle 1
  [ "$status" -eq 2 ]
  master 1 <<<'{"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 1, "minor": 0}, "issues": [{"severity": "major", "category": "x", "file": "a", "line": 1, "message": "no id"}]}'
  run rv gate --cycle 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"id"* ]]
}

@test "gate: max_cycles reached without a clean cycle stops for the user" {
  printf 'team:\n  review:\n    enabled: true\n    max_cycles: 1\n' >"$W/p1.yaml"
  dirty_master
  PIPE="$W/p1.yaml" run rv gate --cycle 1
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json, sys
g = json.load(sys.stdin)
assert g["actions"] == ["stop_human review-cycles"], g["actions"]
'
}

@test "gate: an issue in a file no track owns is listed as unowned" {
  master 1 <<'JSON'
{"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 1, "major": 0, "minor": 0},
 "issues": [{"id": "M-7", "severity": "blocker", "category": "security", "file": "docs/x.md", "line": 2, "message": "leak"}],
 "previous_issues": []}
JSON
  run rv gate --cycle 1
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json, sys
g = json.load(sys.stdin)
assert g["unowned"] == ["M-7"] and g["actions"] == ["stop_human review-unowned"], g
'
}

@test "external: the prompt names the commit, read-from-commit rule, known open items and both schemas" {
  dirty_master
  run rv external --name astra --cycle 2 --rev "$REV"
  [ "$status" -eq 0 ]
  p="$(ext_dir 2)/prompt.md"
  [ "$output" = "$p" ]
  grep -qF "Commit under review: $REV; baseline: $BASE" "$p"
  grep -qF "git show $REV:<path>" "$p"
  grep -qF "not from the working tree" "$p"
  grep -qF "flaky recipe on Mac (environment)" "$p"
  grep -qF "findings.json" "$p"; grep -qF '"severity": "blocker|major|medium|minor"' "$p"
  grep -qF "prior-closure.json" "$p"; grep -qF '"status": "closed|open|partial"' "$p"
  grep -qF "M-1" "$p"
  run ! grep -qF "M-3" "$p"
  run ! grep -qF "{{" "$p"
}

@test "ingest: valid findings are merged into the cycle master and saved as an aspect report" {
  dirty_master
  rv external --name astra --cycle 1 --rev "$REV" >/dev/null
  d="$(ext_dir 1)"
  echo '[{"id": "A1-1", "severity": "major", "lens": "security", "file": "src/b/y.py", "line": 1, "scenario": "secret logged", "fix": "mask"}]' >"$d/findings.json"
  echo '[]' >"$d/prior-closure.json"
  run rv ingest --name astra --cycle 1
  [ "$status" -eq 0 ]
  [ -f "$TD/review/cycle-1/external-astra.json" ]
  run rv gate --cycle 1
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json, sys
g = json.load(sys.stdin)
assert g["counts"]["major"] == 2, g["counts"]
assert g["fixes"]["B"] == ["M-2", "A1-1"], g["fixes"]
'
  # Idempotent: a second ingest does not duplicate the finding.
  run rv ingest --name astra --cycle 1; [ "$status" -eq 0 ]
  run python3 -c "import json; m=json.load(open('$TD/review/cycle-1/master.json')); print(sum(i['id']=='A1-1' for i in m['issues']))"
  [ "$output" = "1" ]
}

@test "ingest: a finding without file, line or severity is rejected with exit 2" {
  rv external --name astra --cycle 1 --rev "$REV" >/dev/null
  d="$(ext_dir 1)"; echo '[]' >"$d/prior-closure.json"
  for bad in \
    '[{"id": "x", "severity": "major", "lens": "logic", "line": 1, "scenario": "s"}]' \
    '[{"id": "x", "severity": "major", "lens": "logic", "file": "a", "scenario": "s"}]' \
    '[{"id": "x", "lens": "logic", "file": "a", "line": 1, "scenario": "s"}]' \
    '[{"id": "x", "severity": "low", "lens": "logic", "file": "a", "line": 1, "scenario": "s"}]' \
    '[{"id": "x", "severity": "major"'; do
    echo "$bad" >"$d/findings.json"
    run rv ingest --name astra --cycle 1
    [ "$status" -eq 2 ]
  done
  [ ! -e "$TD/review/cycle-1/external-astra.json" ]
}

@test "ingest: prior-closure must cover every earlier medium+ finding with a valid status" {
  dirty_master
  rv external --name astra --cycle 2 --rev "$REV" >/dev/null
  d="$(ext_dir 2)"; echo '[]' >"$d/findings.json"
  echo '[{"id": "M-1", "status": "closed", "evidence": "x.py:1"}]' >"$d/prior-closure.json"
  run rv ingest --name astra --cycle 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"M-2"* ]] || false
  echo '[{"id": "M-1", "status": "closed", "evidence": "x.py:1"}, {"id": "M-2", "status": "gone", "evidence": "?"}]' >"$d/prior-closure.json"
  run rv ingest --name astra --cycle 2
  [ "$status" -eq 2 ]
  echo '[{"id": "M-1", "status": "closed", "evidence": "x.py:1"}, {"id": "M-2", "status": "partial", "evidence": "y.py:1"}]' >"$d/prior-closure.json"
  run rv ingest --name astra --cycle 2
  [ "$status" -eq 0 ]
}
