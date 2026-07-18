#!/usr/bin/env bash
# mb-estimate-check.sh — deterministic validator for the /mb discuss size
# estimate (svp-interview-upgrade design C1, NFR-002). Reads the context
# frontmatter `estimated_tokens` block, checks its structure, and compares the
# spec total against the configured budget. No LLM, no PyYAML dependency.
#
# Usage:
#   mb-estimate-check.sh <context-file> [--spec-budget <positive-int>]
#
# Thresholds (D-13; one integer formula for any budget):
#   near_lower = floor(spec_budget * 9 / 10)
#   total < near_lower              → estimate=ok    (exit 0)
#   near_lower <= total <= budget   → estimate=near  (exit 0, advisory)
#   total > budget                  → estimate=over  (exit 1)
#
# stdout : `estimate=<ok|near|over|missing|malformed> spec.total=<N> spec_budget=<N>`
#          (empty on usage / unreadable).
# stderr : usage → `error=usage`; unreadable → `<file>:0:unreadable`;
#          missing → `<file>:0:estimated_tokens:missing`;
#          malformed → one `<file>:<line>:<field>:malformed` per finding,
#          sorted by ascending <line>.
# exit   : 0 ok/near · 1 over · 2 missing/malformed/unreadable/usage.

set -euo pipefail

usage_error() { printf 'error=usage\n' >&2; exit 2; }

FILE=""
SPEC_BUDGET=1000000
while [ "$#" -gt 0 ]; do
  case "$1" in
    --spec-budget)
      [ "$#" -ge 2 ] || usage_error
      SPEC_BUDGET="$2"
      shift
      ;;
    --*) usage_error ;;
    *)
      [ -z "$FILE" ] || usage_error
      FILE="$1"
      ;;
  esac
  shift
done
[ -n "$FILE" ] || usage_error

# --spec-budget must be a positive integer.
case "$SPEC_BUDGET" in
  ''|*[!0-9]*) usage_error ;;
esac
[ "$SPEC_BUDGET" -gt 0 ] || usage_error

if [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  printf '%s:0:unreadable\n' "$FILE" >&2
  exit 2
fi

# Parse + validate in awk. Emits:
#   status=<ok|near|over|missing|malformed>
#   total=<N>
#   M <line> <field>            (one per malformed finding)
parse="$(
  awk -v budget="$SPEC_BUDGET" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function num(line, key,   v) {
      if (match(line, key ":[ \t]*[0-9]+")) {
        v = substr(line, RSTART, RLENGTH)
        sub(key ":[ \t]*", "", v)
        return v + 0
      }
      return -1
    }
    { raw[NR] = $0 }
    END {
      ncat = split("shell_scripts prompt_changes python_modules test_files docs_pages external_integrations", order, " ")

      has_et = 0; et_line = 0
      for (i = 1; i <= NR; i++) {
        if (raw[i] ~ /^estimated_tokens:[ \t]*$/) { has_et = 1; et_line = i; break }
      }
      if (!has_et) { print "status=missing"; print "total=0"; exit }

      region_end = NR
      for (i = et_line + 1; i <= NR; i++) {
        l = raw[i]
        if (l ~ /^---[ \t]*$/) { region_end = i - 1; break }
        if (l ~ /^[^ \t]/ && l !~ /^[ \t]*$/) { region_end = i - 1; break }
        region_end = i
      }

      total_val = -1; total_line = 0
      for (k = 1; k <= ncat; k++) { found[order[k]] = 0; cline[order[k]] = 0 }

      for (i = et_line + 1; i <= region_end; i++) {
        l = raw[i]
        if (l ~ /^[ \t]+total:/) {
          v = l; sub(/^[ \t]+total:[ \t]*/, "", v); v = trim(v)
          total_line = i
          if (v ~ /^[0-9]+$/) { total_val = v + 0 } else { total_val = -2 }
          continue
        }
        for (k = 1; k <= ncat; k++) {
          cat = order[k]
          if (l ~ ("^[ \t]+" cat ":[ \t]*\\{")) {
            found[cat] = 1; cline[cat] = i
            cval[cat] = num(l, "count")
            uval[cat] = num(l, "unit_tokens")
            sval[cat] = num(l, "subtotal")
          }
        }
      }

      nf = 0; sum = 0; sum_ok = 1
      for (k = 1; k <= ncat; k++) {
        cat = order[k]
        bad = 0
        if (!found[cat]) { bad = 1 }
        else if (cval[cat] < 0 || uval[cat] < 0 || sval[cat] < 0) { bad = 1 }
        else if (sval[cat] != cval[cat] * uval[cat]) { bad = 1 }
        if (bad) {
          nf++; mline[nf] = cline[cat]; mfield[nf] = cat
          sum_ok = 0
        } else {
          sum += sval[cat]
        }
      }

      pt = 0
      if (total_val >= 0) { pt = total_val }

      if (total_val == -1) {
        nf++; mline[nf] = et_line; mfield[nf] = "total"
      } else if (total_val == -2) {
        nf++; mline[nf] = total_line; mfield[nf] = "total"
      } else if (sum_ok && total_val != sum) {
        nf++; mline[nf] = total_line; mfield[nf] = "total"
      }

      if (nf > 0) {
        print "status=malformed"
        print "total=" pt
        for (k = 1; k <= nf; k++) { print "M " mline[k] " " mfield[k] }
        exit
      }

      near_lower = int(budget * 9 / 10)
      if (total_val < near_lower) { st = "ok" }
      else if (total_val <= budget) { st = "near" }
      else { st = "over" }
      print "status=" st
      print "total=" total_val
    }
  ' "$FILE"
)"

status="$(printf '%s\n' "$parse" | sed -n 's/^status=//p' | head -1)"
etotal="$(printf '%s\n' "$parse" | sed -n 's/^total=//p' | head -1)"

case "$status" in
  ok|near)
    printf 'estimate=%s spec.total=%s spec_budget=%s\n' "$status" "$etotal" "$SPEC_BUDGET"
    exit 0
    ;;
  over)
    printf 'estimate=over spec.total=%s spec_budget=%s\n' "$etotal" "$SPEC_BUDGET"
    exit 1
    ;;
  missing)
    printf 'estimate=missing spec.total=0 spec_budget=%s\n' "$SPEC_BUDGET"
    printf '%s:0:estimated_tokens:missing\n' "$FILE" >&2
    exit 2
    ;;
  malformed)
    printf 'estimate=malformed spec.total=%s spec_budget=%s\n' "$etotal" "$SPEC_BUDGET"
    printf '%s\n' "$parse" | sed -n 's/^M //p' | sort -k1,1n | while read -r ln fld; do
      [ -n "$fld" ] || continue
      printf '%s:%s:%s:malformed\n' "$FILE" "$ln" "$fld" >&2
    done
    exit 2
    ;;
  *)
    usage_error
    ;;
esac
