#!/usr/bin/env bash
# mb-interview-artifact-check.sh — deterministic structural validator for the
# /mb discuss interview artifacts (svp-interview-upgrade design C8, NFR-002).
# No LLM: plan/transcript structure is proven by script.
#
# Usage:
#   mb-interview-artifact-check.sh plan <file> [--require-closed]
#   mb-interview-artifact-check.sh transcript <file> [--require-inherited] [--legacy-live-fixture]
#
# `plan` mode validates <bank>/tmp/interview-plan-<topic>.md against contract C2:
# required headings in order, checkbox-only bullets under Topics / Discovered,
# and (with --require-closed) zero open `- [ ]` items.
#
# `transcript` mode validates context/<topic>-interview.md against the C4 grammar
# (rules 1–8). --require-inherited demands a `## Унаследовано` section before
# `## Q&A`. --legacy-live-fixture relaxes the strict answer/rejected rules to
# legacy file-level semantics and is allowed ONLY for the two frozen regression
# fixtures.
#
# stdout : `artifact=ok|invalid open_topics=<N>` (open_topics only for plan, else 0)
# stderr : one `<file>:<line>:<reason>` per finding, sorted by (line, reason-order).
#          Usage errors print exactly `error=usage`; an unreadable file prints
#          exactly `<file>:0:unreadable`; both leave stdout empty. A forbidden
#          --legacy-live-fixture prints `<file>:0:legacy_fixture_forbidden`.
# exit   : 0 valid (closed too, under --require-closed) · 1 invalid / open ·
#          2 usage / read error.

set -euo pipefail

# Resolve this script's own physical directory through its FULL symlink chain
# (portable — no realpath on bare macOS): otherwise a symlinked invocation from
# an attacker tree would make REPO_ROOT — and thus the legacy-fixture whitelist —
# resolve inside that tree (fixture spoofing).
_mb_resolve_self_dir() {
  local src="$1" dir
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd)"
    src="$(readlink "$src")"
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  cd -P "$(dirname "$src")" 2>/dev/null && pwd
}
SCRIPT_DIR="$(_mb_resolve_self_dir "$0")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage_error() { printf 'error=usage\n' >&2; exit 2; }

# canon_path <path> — physical absolute path of an EXISTING file (dir realpath +
# basename). Returns 1 when the path does not exist, so a spoofed basename in a
# different directory can never masquerade as a frozen regression fixture.
canon_path() {
  local p="$1" d b
  [ -e "$p" ] || return 1
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
  b="$(basename "$p")"
  printf '%s/%s\n' "$d" "$b"
}

MODE="${1:-}"
[ -n "$MODE" ] || usage_error
shift

FILE=""
REQUIRE_CLOSED=0
REQUIRE_INHERITED=0
LEGACY_FIXTURE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --require-closed) REQUIRE_CLOSED=1 ;;
    --require-inherited) REQUIRE_INHERITED=1 ;;
    --legacy-live-fixture) LEGACY_FIXTURE=1 ;;
    --*) usage_error ;;
    *)
      [ -z "$FILE" ] || usage_error
      FILE="$1"
      ;;
  esac
  shift
done
[ -n "$FILE" ] || usage_error

case "$MODE" in
  plan)
    [ "$REQUIRE_INHERITED" -eq 0 ] || usage_error
    [ "$LEGACY_FIXTURE" -eq 0 ] || usage_error
    ;;
  transcript)
    [ "$REQUIRE_CLOSED" -eq 0 ] || usage_error
    if [ "$LEGACY_FIXTURE" -eq 1 ]; then
      # Legacy relaxation is allowed ONLY for the two frozen regression
      # fixtures, matched by canonical path — never by basename, so a renamed
      # copy or a publication candidate cannot borrow the weaker grammar.
      _fc="$(canon_path "$FILE")" || _fc=""
      _f1="$(canon_path "$REPO_ROOT/.memory-bank/context/sdd-vision-pipeline-interview.md")" || _f1=""
      _f2="$(canon_path "$REPO_ROOT/.memory-bank/context/svp-interview-upgrade-interview.md")" || _f2=""
      if [ -z "$_fc" ] || { [ "$_fc" != "$_f1" ] && [ "$_fc" != "$_f2" ]; }; then
        printf '%s:0:legacy_fixture_forbidden\n' "$FILE" >&2; exit 2
      fi
    fi
    ;;
  *)
    usage_error
    ;;
esac

if [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  printf '%s:0:unreadable\n' "$FILE" >&2
  exit 2
fi

# Emit findings (F <line> <order> <reason>) to a temp file, sort by (line,order),
# render <file>:<line>:<reason>, and decide validity + exit code.
render_findings() {
  # $1 = parse output; $2 = open_count
  local parse="$1" open_count="$2" ff
  ff="$(mktemp "${TMPDIR:-/tmp}/mb-artifact-find.XXXXXX")"
  printf '%s\n' "$parse" | sed -n 's/^F //p' >> "$ff"
  if [ -s "$ff" ]; then
    sort -k1,1n -k2,2n "$ff" | while read -r ln _order reason; do
      [ -n "$reason" ] || continue
      printf '%s:%s:%s\n' "$FILE" "$ln" "$reason" >&2
    done
    rm -f "$ff"
    printf 'artifact=invalid open_topics=%d\n' "$open_count"
    return 1
  fi
  rm -f "$ff"
  printf 'artifact=ok open_topics=%d\n' "$open_count"
  return 0
}

run_plan() {
  local parse open_count
  parse="$(
    awk '
      { lines[NR] = $0 }
      function scan_section(start,   j) {
        if (start == 0) return
        for (j = start + 1; j <= NR; j++) {
          if (lines[j] ~ /^## /) return
          if (lines[j] ~ /^[-*+][ \t]/) {
            if (lines[j] ~ /^- \[[ xX]\][ \t]+[^ \t]/) {
              if (lines[j] ~ /^- \[ \]/) printf "O %d\n", j
            } else if (lines[j] ~ /^- \[[ xX]\][ \t]*$/) {
              printf "F %d 3 empty_topic\n", j
            } else {
              printf "F %d 3 bad_bullet\n", j
            }
          }
        }
      }
      END {
        h_inh = 0; h_top = 0; h_dis = 0
        for (i = 1; i <= NR; i++) {
          l = lines[i]
          if (h_inh == 0 && l ~ /^## Inherited decisions \(do not re-ask\)[ \t]*$/) { h_inh = i; continue }
          if (h_top == 0 && l ~ /^## Topics[ \t]*$/) { h_top = i; continue }
          if (h_dis == 0 && l ~ /^## Discovered mid-interview[ \t]*$/) { h_dis = i; continue }
        }
        if (h_inh == 0) printf "F 0 1 missing_section\n"
        if (h_top == 0) printf "F 0 1 missing_section\n"
        if (h_dis == 0) printf "F 0 1 missing_section\n"
        if (h_inh > 0 && h_top > 0 && h_dis > 0) {
          if (h_top < h_inh) printf "F %d 2 section_out_of_order\n", h_top
          if (h_dis < h_top) printf "F %d 2 section_out_of_order\n", h_dis
        }
        scan_section(h_top)
        scan_section(h_dis)
      }
    ' "$FILE"
  )"
  open_count="$(printf '%s\n' "$parse" | grep -c '^O ' || true)"
  if [ "$REQUIRE_CLOSED" -eq 1 ] && [ "$open_count" -gt 0 ]; then
    parse="$parse
$(printf '%s\n' "$parse" | sed -n 's/^O \([0-9]*\)$/F \1 4 open_topics/p')"
  fi
  render_findings "$parse" "$open_count"
}

run_transcript() {
  local parse
  parse="$(
    awk -v reqinh="$REQUIRE_INHERITED" -v legacy="$LEGACY_FIXTURE" '
      function isdate(s,   y, m, d, dim) {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
        y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
        if (m < 1 || m > 12) return 0
        dim = 31
        if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
        else if (m == 2) { dim = 28; if ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)) dim = 29 }
        if (d < 1 || d > dim) return 0
        return 1
      }
      function next_boundary(start,   j) {
        for (j = start + 1; j <= NR; j++) {
          if (raw[j] ~ /^\*\*Q[0-9]+/) return j
          if (raw[j] ~ /^\*\*Финальный гейт/) return j
          if (raw[j] ~ /^## /) return j
        }
        return NR + 1
      }
      function round_of(line,   s) {
        if (match(line, /круг [0-9]+/)) { s = substr(line, RSTART, RLENGTH); sub(/круг /, "", s); return s + 0 }
        return -1
      }
      function has_answer(bs, be, qn,   j, apat) {
        # C4 rule 5: `^**A<N>.** ` — required space separator + non-blank content.
        apat = "^\\*\\*A" qn "\\.\\*\\*[ \t]+[^ \t]"
        for (j = bs; j <= be; j++) {
          if (raw[j] ~ apat) return 1
          if (legacy == "1" && raw[j] ~ /Ответ голосом \(суть\): «[^»]+»/) return 1
          if (legacy == "1" && raw[j] ~ /пользователь: «[^»]+»/) return 1
        }
        return 0
      }
      function answer_line(bs, be, qn,   j, apat) {
        # First strict answer-marker line in the block (0 if none) — the point
        # from which rejected-alternatives are honoured (rule 7, answer part).
        apat = "^\\*\\*A" qn "\\.\\*\\*[ \t]+[^ \t]"
        for (j = bs; j <= be; j++) if (raw[j] ~ apat) return j
        return 0
      }
      function has_decision(bs, be,   j) {
        for (j = bs; j <= be; j++) if (raw[j] ~ /\*\*([A-Za-z0-9]+-)?D-[0-9][0-9]+\*\*/) return 1
        return 0
      }
      function has_rejected(bs, be,   j) {
        for (j = bs; j <= be; j++) if (raw[j] ~ /(Отклонено|Rejected):[ \t]*[^ \t]/) return 1
        return 0
      }
      { raw[NR] = $0 }
      END {
        qa_count = 0; qa_line = 0; second_qa = 0; inh_line = 0; rej_section = 0; inline_rej = 0
        for (i = 1; i <= NR; i++) {
          if (raw[i] ~ /^## Q&A[ \t]*$/) { qa_count++; if (qa_count == 1) qa_line = i; else if (qa_count == 2) second_qa = i }
          if (inh_line == 0 && raw[i] ~ /^## Унаследовано/) inh_line = i
          if (raw[i] ~ /^## Отклонённые альтернативы/) rej_section = 1
          if (raw[i] ~ /(Отклонено|Rejected):[ \t]*[^ \t]/) inline_rej = 1
        }

        # 1. title
        ti = 0
        for (i = 1; i <= NR; i++) { if (raw[i] !~ /^[ \t]*$/) { ti = i; break } }
        tl = 1; if (ti > 0) tl = ti
        if (ti > 0 && raw[ti] ~ /^# Interview transcript: .+ \([^,)]+(,[^)]*)?\)$/) {
          match(raw[ti], /\([^,)]+/)
          head = substr(raw[ti], RSTART + 1, RLENGTH - 1)
          if (!isdate(head)) print "F " ti " 2 bad_date"
        } else {
          print "F " tl " 1 missing_title"
        }

        # 2. Q&A section
        if (qa_count == 0) print "F 1 3 missing_qa_section"
        if (qa_count >= 2) print "F " second_qa " 4 duplicate_qa_section"

        # 3. inherited
        if (reqinh == "1") {
          if (inh_line == 0) print "F 1 5 missing_inherited"
          else if (qa_line > 0 && inh_line > qa_line) print "F " inh_line " 6 inherited_after_qa"
        }

        # 4. collect Q-lines and gate-lines. A line that opens like a marker
        #    (`**Q<n>` / `**Финальный гейт`) but breaks the exact template form
        #    is flagged as malformed and never counted as a valid block.
        # C4 rule 4 Q marker: `^**Q<N>( (<tag>))?.** ` — the `(<tag>)` is OPTIONAL
        # (so `**Q1.** q?` is valid), and content after the required space is
        # mandatory (empty question rejected).
        nq = 0
        for (i = 1; i <= NR; i++) {
          if (raw[i] ~ /^\*\*Q[0-9]/) {
            if (raw[i] !~ /^\*\*Q[0-9]+( \([^)]*\))?\.\*\*[ \t]+[^ \t]/) { print "F " i " 8 q_malformed"; continue }
            nq++; qidx[nq] = i
            s = raw[i]; sub(/^\*\*Q/, "", s)
            d = ""; k = 1
            while (k <= length(s) && substr(s, k, 1) ~ /[0-9]/) { d = d substr(s, k, 1); k++ }
            qnum[nq] = d + 0
          }
        }
        # C4 rule 8 gate marker: `^**Финальный гейт(, круг <M>)?.** ` — only an
        # optional numeric round may follow; arbitrary text → gate_malformed.
        ng = 0
        for (i = 1; i <= NR; i++) {
          if (raw[i] ~ /^\*\*Финальный гейт/) {
            if (raw[i] !~ /^\*\*Финальный гейт(, круг [0-9]+)?\.\*\*[ \t]+[^ \t]/) { print "F " i " 13 gate_malformed"; continue }
            ng++; gidx[ng] = i
          }
        }

        if (nq == 0) print "F 1 7 no_questions"
        if (nq > 0 && qnum[1] != 1) print "F " qidx[1] " 7 q_number_not_one"

        # 5-7. per Q-block
        prev = 0
        for (k = 1; k <= nq; k++) {
          bs = qidx[k]; be = next_boundary(bs) - 1
          if (qnum[k] == prev) print "F " bs " 9 q_number_duplicate"
          else if (qnum[k] < prev) print "F " bs " 8 q_number_out_of_order"
          prev = qnum[k]
          if (!has_answer(bs, be, qnum[k])) print "F " bs " 10 answer_missing"
          hasdec = has_decision(bs, be)
          if (!hasdec) print "F " bs " 11 decision_missing"
          if (legacy != "1" && hasdec) {
            aline = answer_line(bs, be, qnum[k])
            rstart = (aline > 0 ? aline : bs)
            # Rejected token is honoured only from the answer line onward, so a
            # `Rejected:` embedded in the QUESTION cannot satisfy the rule.
            if (!has_rejected(rstart, be)) print "F " bs " 12 rejected_alternatives_missing"
          }
        }
        if (legacy == "1" && !rej_section && !inline_rej && nq > 0) print "F 1 12 rejected_alternatives_missing"

        # 8. gates
        if (ng == 0) print "F 1 13 missing_final_gate"
        prevm = 0
        for (g = 1; g <= ng; g++) {
          gs = gidx[g]; ge = next_boundary(gs) - 1
          gotans = 0
          for (j = gs; j <= ge; j++) if (raw[j] ~ /^\*\*Ответ\.\*\*[ \t]+[^ \t]/) gotans = 1
          if (!gotans) print "F " gs " 14 gate_answer_missing"
          if (ng >= 2) {
            m = round_of(raw[gs])
            if (m < 0) print "F " gs " 15 gate_round_missing"
            else {
              if (m <= prevm) print "F " gs " 16 gate_round_out_of_order"
              prevm = m
            }
          }
        }
      }
    ' "$FILE"
  )"
  render_findings "$parse" 0
}

case "$MODE" in
  plan) run_plan ;;
  transcript) run_transcript ;;
esac
