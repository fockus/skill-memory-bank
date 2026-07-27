#!/usr/bin/env bats
# rules_resolve_* — svp-contract-test-loop C2, the two-mode rule resolver (Task 1).
#
# DISCOVERY collects every project rule source it finds and falls back to the
# bundled rules only when no project source exists. VALIDATION reads what the
# spec DECLARED (`- [<kind>] <path>` inside `## Quality DoD`, the format C5
# generates — the loop is closed) and fails LOUDLY on a declared source that is
# missing, because a silent fallback there would answer a question about the
# project's rules with somebody else's rules (REQ-017).
#
# Name convention (Eval red-anchor): every @test is named for the behaviour it
# pins, starting `rules_resolve_`, so `bats <missing-file>` — which emits
# `not ok 1 bats-gather-tests` with the SAME exit 1 as a real failure — cannot
# match the declared anchor `not ok [0-9]+ rules_resolve_project_source_wins`.

bats_require_minimum_version 1.5.0
load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-rules-resolve.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  BANK="$REPO/.memory-bank"
  mkdir -p "$BANK"
}

# spec_with <name> <quality-dod-body> — a spec dir whose design.md declares sources.
spec_with() {
  local d="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$d"
  {
    printf '# Design: %s\n\n## Architecture\n\nprose\n\n## Quality DoD\n\n' "$1"
    printf '%s\n' "$2"
    printf '\n## Risks\n\nmore prose\n'
  } > "$d/design.md"
  printf '%s\n' "$d"
}

# jq-free field readers: the contract fixes the JSON, so the tests read it as
# JSON rather than grepping the serialization.
jget() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$2"; }
paths_of() { printf '%s' "$1" | python3 -c 'import json,sys; print(" ".join(s["path"] for s in json.load(sys.stdin)["sources"]))'; }
kinds_of() { printf '%s' "$1" | python3 -c 'import json,sys; print(" ".join(s["kind"] for s in json.load(sys.stdin)["sources"]))'; }

# ─────────────────────────── discovery mode ─────────────────────────────────

@test "rules_resolve_project_source_wins" {
  # The anchor case: a project rule file must beat the bundled fallback.
  printf '# project rules\n' > "$REPO/RULES.md"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  assert_substring "$(paths_of "$output")" "RULES.md"
  [ "$(jget "$output" fallback_used)" = "false" ]
  # The bundled rules are NOT among the sources when a project source exists.
  refute_substring "$(paths_of "$output")" "rules/RULES.md"
}

@test "rules_resolve_project_source_wins_for_agents_md" {
  printf '# agents\n' > "$REPO/AGENTS.md"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(paths_of "$output")" = "AGENTS.md" ]
  [ "$(kinds_of "$output")" = "project" ]
  [ "$(jget "$output" fallback_used)" = "false" ]
}

@test "rules_resolve_collects_every_project_source_sorted" {
  # C2 says "all found", and NFR-003 says one input gives one byte-identical
  # output — so the set is complete and the order is by path, not by discovery.
  printf 'a\n' > "$REPO/RULES.md"
  printf 'b\n' > "$REPO/AGENTS.md"
  printf 'c\n' > "$BANK/RULES.md"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  # Sorted by path in LC_ALL=C byte order: '.' < 'A' < 'R'.
  [ "$(paths_of "$output")" = ".memory-bank/RULES.md AGENTS.md RULES.md" ]
  [ "$(kinds_of "$output")" = "project project project" ]
}

@test "rules_resolve_out_of_repo_bank_is_absolute_not_traversal" {
  # A bank registered with `--storage=global` lives outside the repo, so there
  # is no repo-relative name for it. A `../../..` chain here would render into a
  # generated spec and read as repo-relative; the absolute path is honest.
  local gbank="$BATS_TEST_TMPDIR/global-bank"
  mkdir -p "$gbank"
  printf 'global rules\n' > "$gbank/RULES.md"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$gbank" --json
  [ "$status" -eq 0 ]
  local p
  p="$(paths_of "$output")"
  refute_substring "$p" ".."
  case "$p" in /*) ;; *) printf 'expected an absolute path, got: %s\n' "$p"; false ;; esac
}

@test "rules_resolve_fallback_only_without_project" {
  # No project source anywhere -> the bundled rules appear, flagged as fallback.
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(paths_of "$output")" = "rules/RULES.md" ]
  [ "$(kinds_of "$output")" = "skill" ]
  [ "$(jget "$output" fallback_used)" = "true" ]
}

@test "rules_resolve_fallback_only_without_project_is_dropped_when_one_appears" {
  # Same fixture, one file added: the fallback must disappear, not accumulate.
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$(jget "$output" fallback_used)" = "true" ]
  printf '# project rules\n' > "$REPO/RULES.md"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(jget "$output" fallback_used)" = "false" ]
  [ "$(paths_of "$output")" = "RULES.md" ]
}

@test "rules_resolve_active_profile_is_listed" {
  printf '{"schema_version":1,"scope":"project","role":"qa"}\n' > "$BANK/rules-profile.json"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  assert_substring "$(kinds_of "$output")" "profile"
  assert_substring "$(paths_of "$output")" "rules-profile.json"
}

@test "rules_resolve_checker_is_the_existing_one" {
  # REQ-018: no new rule linter is introduced.
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(jget "$output" checker)" = '"scripts/mb-rules-check.sh"' ]
  [ -f "$REPO_ROOT/scripts/mb-rules-check.sh" ]
}

# ─────────────────────────── review rubric ──────────────────────────────────

@test "rules_resolve_review_rubric_is_rendered_in_author_order" {
  # R2-012: the rubric travels with the criterion, in the order the author wrote
  # it — a sorted or regrouped rubric would be a different document.
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  local first
  first="$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["review_rubric"][0])')"
  [ "$first" = "logic: Every EARS requirement has at least one assertion in tests" ]
}

@test "rules_resolve_review_rubric_empty_when_absent" {
  # Genuinely absent is the one case the contract calls empty.
  printf 'version: 1\nstage_pipeline: []\n' > "$BANK/pipeline.yaml"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(jget "$output" review_rubric)" = "[]" ]
}

@test "rules_resolve_review_rubric_malformed_fails_loudly" {
  # A rubric that is present but not a mapping must NOT degrade to []. The
  # reviewer and judge are handed this list without the file it came from, so a
  # silent empty rubric is a verdict rendered against a criterion nobody knew
  # was missing — REQ-017's rule applied to the rubric half of the block.
  printf 'version: 1\nreview_rubric: "not a mapping"\n' > "$BANK/pipeline.yaml"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "review_rubric_unreadable"
}

@test "rules_resolve_review_rubric_malformed_category_fails_loudly" {
  printf 'version: 1\nreview_rubric:\n  logic: "a bare string, not a list"\n' > "$BANK/pipeline.yaml"
  run --separate-stderr "$SCRIPT" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "review_rubric_unreadable"
}

# ─────────────────────────── validation mode ────────────────────────────────

@test "rules_resolve_missing_declared_source_exits_1" {
  local d
  d="$(spec_with specA '- [project] AGENTS.md')"
  # AGENTS.md deliberately absent from the repo.
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 1 ]
  [ "$output" = "" ]
  [ "$stderr" = "rule_source_missing=AGENTS.md" ]
}

@test "rules_resolve_missing_declared_source_exits_1_never_falls_back" {
  # REQ-017 is specifically about the SILENT fallback: the bundled rules exist,
  # so a resolver that fell back would exit 0 with a plausible answer.
  local d
  d="$(spec_with specB '- [project] RULES.md')"
  [ -f "$REPO_ROOT/rules/RULES.md" ]
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 1 ]
  [ "$output" = "" ]
  refute_substring "$stderr" "rules/RULES.md"
}

@test "rules_resolve_declared_source_present_exits_0" {
  printf '# project rules\n' > "$REPO/RULES.md"
  local d
  d="$(spec_with specC '- [project] RULES.md')"
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(paths_of "$output")" = "RULES.md" ]
  [ "$(jget "$output" fallback_used)" = "false" ]
}

@test "rules_resolve_declared_source_flag_without_spec" {
  printf '# project rules\n' > "$REPO/RULES.md"
  run --separate-stderr "$SCRIPT" --declared-source RULES.md --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(paths_of "$output")" = "RULES.md" ]
  run --separate-stderr "$SCRIPT" --declared-source NOPE.md --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 1 ]
  [ "$stderr" = "rule_source_missing=NOPE.md" ]
}

@test "rules_resolve_reads_the_c5_block_verbatim" {
  # The closed loop: C5 generates this exact block, C2 must read it. The rubric
  # bullets and the Checker line are NOT source declarations and must be ignored
  # rather than treated as malformed.
  printf '# project rules\n' > "$REPO/RULES.md"
  local d
  d="$(spec_with specD 'Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):
- [project] RULES.md
- [skill] rules/RULES.md

Review rubric (from `pipeline.yaml:review_rubric`):
- logic: Every EARS requirement has at least one assertion in tests
- security: No secrets in code

Checker: `bash scripts/mb-rules-check.sh --files <touched-files-csv> --out json` — no violations
on this item'"'"'s touched files.')"
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ]
  [ "$(paths_of "$output")" = "RULES.md rules/RULES.md" ]
  [ "$(kinds_of "$output")" = "project skill" ]
}

@test "rules_resolve_malformed_quality_dod_exits_2" {
  local d
  d="$(spec_with specE '- [wizard] RULES.md')"
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "quality_dod_malformed"
}

@test "rules_resolve_malformed_quality_dod_exits_2_on_empty_path" {
  local d
  d="$(spec_with specF '- [project]')"
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "quality_dod_malformed"
}

@test "rules_resolve_malformed_quality_dod_exits_2_on_absolute_path" {
  # A declared source is repo-relative by contract. An absolute path is outside
  # the grammar, and stat'ing an attacker-chosen absolute path answers "does
  # /etc/shadow exist" through the exit code. Grammar first, filesystem never.
  local d
  d="$(spec_with specG '- [project] /etc/passwd')"
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "quality_dod_malformed"
}

@test "rules_resolve_malformed_quality_dod_exits_2_on_traversal" {
  local d
  d="$(spec_with specH '- [project] ../../etc/passwd')"
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "quality_dod_malformed"
}

@test "rules_resolve_missing_quality_dod_section_exits_2" {
  local d="$BATS_TEST_TMPDIR/specI"
  mkdir -p "$d"
  printf '# Design\n\n## Architecture\n\nprose\n' > "$d/design.md"
  run --separate-stderr "$SCRIPT" --spec "$d" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
}

# ─────────────────────────── determinism / usage ────────────────────────────

@test "rules_resolve_json_is_stable" {
  # NFR-003: identical input, byte-identical output — the block's sha256 is what
  # makes implementer, reviewer and judge provably see the same criterion (C6).
  printf 'a\n' > "$REPO/RULES.md"
  printf 'b\n' > "$REPO/AGENTS.md"
  local one two
  one="$("$SCRIPT" --repo "$REPO" --mb "$BANK" --json)"
  two="$("$SCRIPT" --repo "$REPO" --mb "$BANK" --json)"
  [ "$one" = "$two" ]
  # And byte-identical, trailing newline included.
  "$SCRIPT" --repo "$REPO" --mb "$BANK" --json > "$BATS_TEST_TMPDIR/o1"
  "$SCRIPT" --repo "$REPO" --mb "$BANK" --json > "$BATS_TEST_TMPDIR/o2"
  cmp "$BATS_TEST_TMPDIR/o1" "$BATS_TEST_TMPDIR/o2"
}

@test "rules_resolve_json_is_stable_regardless_of_discovery_order" {
  # Creating the files in the opposite order must not change the output.
  printf 'b\n' > "$REPO/AGENTS.md"
  printf 'a\n' > "$REPO/RULES.md"
  local first
  first="$("$SCRIPT" --repo "$REPO" --mb "$BANK" --json)"
  rm -f "$REPO/AGENTS.md" "$REPO/RULES.md"
  printf 'a\n' > "$REPO/RULES.md"
  printf 'b\n' > "$REPO/AGENTS.md"
  [ "$("$SCRIPT" --repo "$REPO" --mb "$BANK" --json)" = "$first" ]
}

@test "rules_resolve_usage_error_exits_2" {
  run --separate-stderr "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  run --separate-stderr "$SCRIPT" --spec
  [ "$status" -eq 2 ]
  run --separate-stderr "$SCRIPT" --spec "$BATS_TEST_TMPDIR/no-such-spec" --repo "$REPO"
  [ "$status" -eq 2 ]
}

@test "rules_resolve_shellcheck_clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "rules_resolve_ignores_a_fenced_example_section: a template in a code block is not a section" {
  # references/templates.md documents the `## Quality DoD` skeleton inside a
  # fenced block, so a spec author who pastes it as an example next to the real
  # section has TWO literal matches. Scanning without fence-awareness read the
  # example as a second section and refused a perfectly valid design.md —
  # the same class already solved in mb_spec_validate_v2.py:220-227.
  printf '# Project rules\n' > "$REPO/AGENTS.md"
  spec="$REPO/.memory-bank/specs/demo"; mkdir -p "$spec"
  cat > "$spec/design.md" <<'EOF'
# Design: demo

Reference shape, quoted from references/templates.md:

```markdown
## Quality DoD

Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):
- [project] docs/EXAMPLE-ONLY.md
```

## Quality DoD

Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):
- [project] AGENTS.md
EOF
  run bash "$SCRIPT" --spec "$spec" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" "AGENTS.md"
  refute_substring "$output" "EXAMPLE-ONLY.md"
}

@test "rules_resolve_fenced_only_section_is_absent: an example alone declares nothing" {
  printf '# Project rules\n' > "$REPO/AGENTS.md"
  spec="$REPO/.memory-bank/specs/demo"; mkdir -p "$spec"
  cat > "$spec/design.md" <<'EOF'
# Design: demo

```markdown
## Quality DoD

- [project] docs/EXAMPLE-ONLY.md
```
EOF
  run bash "$SCRIPT" --spec "$spec" --repo "$REPO" --mb "$BANK" --json
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  assert_substring "$output" "section_absent"
}
