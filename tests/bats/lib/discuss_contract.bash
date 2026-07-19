# discuss_contract.bash — prompt-contract harness for /mb discuss
# (svp-interview-upgrade design C9). The ONLY sanctioned way to assert the
# prompt contract of commands/discuss.md (and consumer prompt files) in this
# slice: section-scoped clause-ERE + a mandatory negation-mutation that proves
# the assertion catches a behaviour change, not word co-occurrence.
#
#   load 'lib/discuss_contract'
#
# Clause table — each normative clause is one 7-field record in the array
# MB_DISCUSS_CLAUSES (delimiter '|', so no field may contain a literal '|';
# EREs use character classes / single patterns instead of alternation):
#
#   <id>|<extractor>|<extractor-arg>|<clause-ERE>|<topic-anchor-ERE>|<negation-sed>|<REQ-ID>
#
# <extractor> ∈ {mb_section, mb_rule}. <topic-anchor-ERE> is what the clause is
# ABOUT; <clause-ERE> is what it PRESCRIBES (topic + modality + object) and is
# strictly stronger than the anchor — proven mechanically by
# assert_clause_load_bearing. Consumers (sibling tasks / other slices) register
# their own clauses AFTER `load` via `MB_DISCUSS_CLAUSES+=("<record>")`; the
# harness file is never edited by them and no second prompt-checker is created.

# Repo root, resolved from this file's location (tests/bats/lib/).
MB_DISCUSS_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MB_DISCUSS_REPO_ROOT="$(cd "$MB_DISCUSS_HARNESS_DIR/../../.." && pwd)"

# Clause registry — empty by default; each test file appends its own records.
if ! declare -p MB_DISCUSS_CLAUSES >/dev/null 2>&1; then
  MB_DISCUSS_CLAUSES=()
fi

# mb_section <file> <heading-ERE>
# Print the block from the UNIQUE heading whose text (after the leading #'s)
# matches <heading-ERE> down to the next heading of the same or higher level.
# Fence-aware: '#'-lines and rule-lines inside ``` code fences are content, not
# headings (templates.md embeds markdown headings inside fenced examples).
# Exit 1 with `section_absent` / `section_duplicated`.
mb_section() {
  awk -v pat="$2" '
    function level(line,   n) { n = 0; while (substr(line, n + 1, 1) == "#") n++; return n }
    function heading_text(line,   n, rest) {
      n = level(line); rest = substr(line, n + 1)
      sub(/^ +/, "", rest); sub(/ +$/, "", rest)
      return rest
    }
    { lines[NR] = $0 }
    END {
      infence = 0; count = 0
      for (i = 1; i <= NR; i++) {
        l = lines[i]
        if (l ~ /^[ \t]*```/) { infence = !infence; continue }
        if (infence) continue
        if (substr(l, 1, 1) == "#") {
          lv = level(l)
          if (lv >= 1 && lv <= 6 && heading_text(l) ~ ("^" pat "$")) {
            count++; sidx = i; slv = lv
          }
        }
      }
      if (count == 0) { print "section_absent"; exit 1 }
      if (count > 1) { print "section_duplicated"; exit 1 }
      print lines[sidx]
      infence = 0
      for (j = sidx + 1; j <= NR; j++) {
        lj = lines[j]
        if (lj ~ /^[ \t]*```/) { infence = !infence; print lj; continue }
        if (!infence && substr(lj, 1, 1) == "#") {
          ljlv = level(lj)
          if (ljlv >= 1 && ljlv <= 6 && ljlv <= slv) break
        }
        print lj
      }
      exit 0
    }
  ' "$1"
}

# mb_rule <file> <n>
# Print the grilling-rule block: from `^<n>\. \*\*` to the next `^[0-9]+\. \*\*`
# or the next heading (whichever comes first). Fence-aware.
# Exit 1 `rule_absent` / `rule_duplicated`.
#
# The rule number must be UNIQUE. Returning the first match let a second rule
# with the same number sit in the prompt inverting the first one — e.g. a rule 11
# saying generation may proceed with open topics — while every clause test on
# that rule stayed green, certifying a contract that contradicted REQ-002.
# Uniqueness is checked exactly like mb_section checks its headings.
mb_rule() {
  awk -v n="$2" '
    { lines[NR] = $0 }
    END {
      infence = 0; start = 0; count = 0
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /^[ \t]*```/) { infence = !infence; continue }
        if (infence) continue
        if (lines[i] ~ ("^" n "\\. \\*\\*")) { count++; if (count == 1) start = i }
      }
      if (count == 0) { print "rule_absent"; exit 1 }
      if (count > 1) { print "rule_duplicated"; exit 1 }
      print lines[start]
      infence = 0
      for (j = start + 1; j <= NR; j++) {
        lj = lines[j]
        if (lj ~ /^[ \t]*```/) { infence = !infence; print lj; continue }
        if (!infence) {
          if (lj ~ /^[0-9]+\. \*\*/) break
          if (substr(lj, 1, 1) == "#") break
        }
        print lj
      }
      exit 0
    }
  ' "$1"
}

# assert_script_present <repo-relative-path>
# Fail (return 1, print `script_absent: <path>`) if the script is missing.
assert_script_present() {
  if [ ! -f "$MB_DISCUSS_REPO_ROOT/$1" ]; then
    echo "script_absent: $1"
    return 1
  fi
  return 0
}

# assert_tool_allowed <file> <tool>
# Fail (return 1) unless <tool> is a member of the `allowed-tools: [...]` array
# in the command file's YAML frontmatter. Binds a mandatory-capability prompt
# clause to the host permission it needs: a clause that demands subagent
# dispatch (Task) is unsatisfiable on an allowlist-honouring host if the array
# omits Task, even while the textual clause tests stay green.
assert_tool_allowed() {
  local file="$1" tool="$2" line
  line="$(sed -n 's/^allowed-tools:[ \t]*//p' "$file" | head -1)"
  if [ -z "$line" ]; then echo "allowed_tools_absent"; return 1; fi
  case ",$(printf '%s' "$line" | tr -d '[] ')," in
    *",$tool,"*) return 0 ;;
  esac
  echo "tool_not_allowed: $tool"
  return 1
}

# _mb_find_clause <id> — echo the registered record for <id>, else return 1.
_mb_find_clause() {
  local id="$1" rec
  for rec in "${MB_DISCUSS_CLAUSES[@]:-}"; do
    case "$rec" in
      "$id|"*) printf '%s\n' "$rec"; return 0 ;;
    esac
  done
  return 1
}

# assert_clause <file> <clause-id>
# Extract the clause block with its declared extractor and require EXACTLY ONE
# block line matching <clause-ERE>. Failure prints
# `clause=<id> req=<REQ> reason=absent|ambiguous` (or reason=unregistered).
assert_clause() {
  local file="$1" id="$2" rec
  rec="$(_mb_find_clause "$id")" || { echo "clause=$id reason=unregistered"; return 1; }
  local cid ext arg cere tere nsed req
  IFS='|' read -r cid ext arg cere tere nsed req <<EOF
$rec
EOF
  local block rc
  block="$("$ext" "$file" "$arg")"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "clause=$id req=$req reason=absent"; return 1; fi
  local m
  m="$(printf '%s\n' "$block" | grep -Ec -- "$cere" || true)"
  if [ "$m" -eq 0 ]; then echo "clause=$id req=$req reason=absent"; return 1; fi
  if [ "$m" -gt 1 ]; then echo "clause=$id req=$req reason=ambiguous"; return 1; fi
  return 0
}

# assert_clause_load_bearing <file> <clause-id>
# Anti-vacuity gate. Apply <negation-sed> to a copy of <file>, then require BOTH:
#   1. assert_clause on the mutant FAILS with the same <id> (else reason=vacuous);
#   2. the mutant block still matches <topic-anchor-ERE> (else
#      reason=mutation_removed_topic).
# Together these prove clause-ERE ⊋ topic-anchor-ERE: a bare clause
# (clause-ERE == topic-anchor-ERE) cannot pass under any mutation.
assert_clause_load_bearing() {
  local file="$1" id="$2" rec
  rec="$(_mb_find_clause "$id")" || { echo "clause=$id reason=unregistered"; return 1; }
  local cid ext arg cere tere nsed req
  IFS='|' read -r cid ext arg cere tere nsed req <<EOF
$rec
EOF
  local mut
  mut="$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/mb-clause-mut.XXXXXX")"
  sed -E "$nsed" "$file" > "$mut"
  if assert_clause "$mut" "$id" >/dev/null 2>&1; then
    rm -f "$mut"; echo "clause=$id reason=vacuous"; return 1
  fi
  local block rc
  block="$("$ext" "$mut" "$arg")"; rc=$?
  rm -f "$mut"
  if [ "$rc" -ne 0 ]; then echo "clause=$id reason=mutation_removed_topic"; return 1; fi
  if ! printf '%s\n' "$block" | grep -Eq -- "$tere"; then
    echo "clause=$id reason=mutation_removed_topic"; return 1
  fi
  return 0
}
