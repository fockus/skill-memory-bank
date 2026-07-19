# shellcheck shell=bash
# mb-estimate-lib.sh — sourced parsers for mb-estimate-check.sh: the context-file
# C1 parser (python3, strict + exact integers) and the spec/candidate C3 parser
# (awk). Both live here so the CLI dispatcher stays small and every file is ≤400
# lines (S1 review, fix-cycle 2). Not executed standalone.

# mb_estimate_lib_context <budget> <file>
# Context-file C1 parser. Emits: `status=<ok|near|over|missing|malformed>`,
# `total=<N>`, and one `M <line> <field>` per malformed finding.
#
# STRICT state machine (S1 review r2, findings [11] and [16]). estimated_tokens
# is honoured ONLY as a top-level key inside the first YAML frontmatter, and it
# must appear EXACTLY ONCE: the old parser searched descendants at any depth for
# `total:` / `breakdown:`, so an `estimated_tokens.wrapper.total/breakdown` block
# validated as estimate=ok, and it silently took the FIRST of several top-level
# sections, so a valid zero-valued section followed by an over-budget or
# malformed one also passed.
#
# The direct children of estimated_tokens are exactly `total` and `breakdown`,
# each once. `breakdown:` carries exactly the six known categories as its own
# direct children, each once, each an inline `{count,unit_tokens,subtotal}` map
# with those exact field names. Any unknown key, duplicate, extra nesting level,
# or wrong value shape → malformed.
#
# Arithmetic is exact Python integer arithmetic, never awk doubles: with
# count 9007199254740993 and unit 1, awk rounded both sides of
# `subtotal == count * unit_tokens` to the same double and accepted an
# inconsistent product as merely over-budget instead of malformed.
mb_estimate_lib_context() {
  python3 - "$1" "$2" <<'PY'
import re
import sys

budget = int(sys.argv[1])
path = sys.argv[2]

CATEGORIES = [
    "shell_scripts", "prompt_changes", "python_modules",
    "test_files", "docs_pages", "external_integrations",
]

try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read().split("\n")
except OSError:
    sys.stdout.write("status=missing\ntotal=0\n")
    sys.exit(0)

# `raw` is 0-indexed; every reported line number is 1-based.
lines = [l.rstrip("\r") for l in raw]
findings = []          # (line, field)


def indent_of(s):
    n = 0
    while n < len(s) and s[n] in " \t":
        n += 1
    return n


def is_blank(s):
    return s.strip() == ""


def emit(status, total):
    sys.stdout.write("status=%s\ntotal=%s\n" % (status, total))
    for ln, field in findings:
        sys.stdout.write("M %d %s\n" % (ln, field))
    sys.exit(0)


def missing():
    sys.stdout.write("status=missing\ntotal=0\n")
    sys.exit(0)


# ── frontmatter ──────────────────────────────────────────────────────────────
if not lines or not re.match(r"^---[ \t]*$", lines[0]):
    missing()
fm_end = 0
for i in range(1, len(lines)):
    if re.match(r"^---[ \t]*$", lines[i]):
        fm_end = i
        break
if not fm_end:
    missing()

# ── the estimated_tokens key: top level, exactly once ────────────────────────
et_lines = [
    i for i in range(1, fm_end)
    if indent_of(lines[i]) == 0 and re.match(r"^estimated_tokens:[ \t]*$", lines[i])
]
if not et_lines:
    missing()
if len(et_lines) > 1:
    findings.append((et_lines[1] + 1, "estimated_tokens"))
    emit("malformed", 0)

et = et_lines[0]

# Region = everything under estimated_tokens, up to the next top-level key.
region_end = fm_end - 1
for i in range(et + 1, fm_end):
    if not is_blank(lines[i]) and indent_of(lines[i]) == 0:
        region_end = i - 1
        break
    region_end = i

body = [(i, lines[i]) for i in range(et + 1, region_end + 1) if not is_blank(lines[i])]
if not body:
    findings.append((et + 1, "breakdown"))
    emit("malformed", 0)

child_indent = indent_of(body[0][1])

# ── direct children of estimated_tokens ──────────────────────────────────────
direct = []            # (line_idx, key, value_text)
bd_children = []       # (line_idx, indent, text)
current = None
for i, text in body:
    ind = indent_of(text)
    if ind == child_indent:
        stripped = text.strip()
        p = stripped.find(":")
        if p <= 0:
            findings.append((i + 1, "estimated_tokens"))
            emit("malformed", 0)
        key = stripped[:p].strip()
        direct.append((i, key, stripped[p + 1:].strip()))
        current = key
    else:
        # Deeper than a direct child: legal only as a breakdown category.
        if current != "breakdown":
            findings.append((i + 1, current if current else "estimated_tokens"))
            emit("malformed", 0)
        bd_children.append((i, ind, text))

# Unknown and duplicate direct keys are COLLECTED rather than raised on the
# spot, so a document that both carries a stray key and omits `breakdown:` still
# reports the missing section — the field consumers key off.
seen = {}
for i, key, _v in direct:
    if key in seen or key not in ("total", "breakdown"):
        findings.append((i + 1, key))
        continue
    seen[key] = i

total_line = seen.get("total")
bd_line = seen.get("breakdown")

# `breakdown:` introduces a nested map, so its own value must be EMPTY. The
# value was stored but never shape-checked, so `breakdown: definitely-not-a-map`
# followed by six indented category rows validated as estimate=ok.
if bd_line is not None:
    bd_value = direct[[d[0] for d in direct].index(bd_line)][2]
    if bd_value != "":
        findings.append((bd_line + 1, "breakdown"))
        emit("malformed", 0)

# `total` is resolved first so a partial document still reports a usable total.
total_val = None
if total_line is not None:
    vtext = direct[[d[0] for d in direct].index(total_line)][2]
    if re.match(r"^[0-9]+$", vtext):
        total_val = int(vtext)

partial_total = total_val if total_val is not None else 0

if bd_line is None:
    findings.append((et + 1, "breakdown"))
    emit("malformed", partial_total)

# ── breakdown categories ─────────────────────────────────────────────────────
if not bd_children:
    findings.append((bd_line + 1, "breakdown"))
    emit("malformed", partial_total)

cat_indent = bd_children[0][1]
MAP_RE = re.compile(r"^\{([^{}]*)\}$")

found = {}
values = {}
for i, ind, text in bd_children:
    if ind > cat_indent:
        # An extra nesting level under a category is not a category.
        findings.append((i + 1, "breakdown"))
        emit("malformed", partial_total)
    stripped = text.strip()
    p = stripped.find(":")
    if p <= 0:
        findings.append((i + 1, "breakdown"))
        continue
    name = stripped[:p].strip()
    vtext = stripped[p + 1:].strip()
    if name not in CATEGORIES or name in found:
        findings.append((i + 1, name))
        found[name] = i
        continue
    found[name] = i

    m = MAP_RE.match(vtext)
    if not m:
        findings.append((i + 1, name))
        continue
    fields = {}
    bad = False
    for part in m.group(1).split(","):
        q = part.find(":")
        if q <= 0:
            bad = True
            break
        k = part[:q].strip()
        v = part[q + 1:].strip()
        if k not in ("count", "unit_tokens", "subtotal") or k in fields:
            bad = True
            break
        if not re.match(r"^[0-9]+$", v):
            bad = True
            break
        fields[k] = int(v)          # exact integers, arbitrary precision
    if bad or len(fields) != 3:
        findings.append((i + 1, name))
        continue
    values[name] = fields

sum_ok = True
total_sum = 0
for cat in CATEGORIES:
    if cat not in found:
        findings.append((0, cat))
        sum_ok = False
        continue
    if cat not in values:
        sum_ok = False
        continue
    f = values[cat]
    if f["subtotal"] != f["count"] * f["unit_tokens"]:
        findings.append((found[cat] + 1, cat))
        sum_ok = False
        continue
    total_sum += f["subtotal"]

if total_line is None:
    findings.append((et + 1, "total"))
elif total_val is None:
    findings.append((total_line + 1, "total"))
elif sum_ok and total_val != total_sum:
    findings.append((total_line + 1, "total"))

if findings:
    findings.sort(key=lambda t: t[0])
    emit("malformed", partial_total)

near_lower = budget * 9 // 10
if total_val < near_lower:
    st = "ok"
elif total_val <= budget:
    st = "near"
else:
    st = "over"
emit(st, total_val)
PY
}

# mb_estimate_lib_spec <tasks-file>
# Spec/candidate C3 parser. Emits the contract key=value lines plus the control
# lines `__malformed=<line>:<field>`, `__mismatch=<0|1>`, `__overflow=<0|1>`,
# `__legacy=<csv>`. Stage sums are aggregated over the ACTUAL stage ids present
# (Stage 0 included) so the 400000 hard cap applies to every stage. Frontmatter
# `total`/`stages` values must be whole non-negative integers (a numeric prefix
# like `100junk` is malformed, not accepted).
mb_estimate_lib_spec() {
  awk '
    function asort_ids(src, n, dst,   i, j, t) {
      for (i = 1; i <= n; i++) dst[i] = src[i]
      for (i = 2; i <= n; i++) {
        t = dst[i]; j = i - 1
        while (j >= 1 && dst[j] > t) { dst[j + 1] = dst[j]; j-- }
        dst[j + 1] = t
      }
      return n
    }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    BEGIN { seen_task = 0; np = 0; nt = 0; curid = ""; malformed = 0; mline = 0 }
    {
      line = $0
      is_open = 0
      if (line ~ /<!--[ \t]*mb-task:[0-9]+/ && line !~ /<!--[ \t]*\/mb-task:/) is_open = 1
      if (!seen_task && !is_open) { pre[++np] = line; next }
      seen_task = 1
      if (is_open) {
        s = line; sub(/.*mb-task:[ \t]*/, "", s); sub(/[^0-9].*/, "", s)
        curid = s + 0
        nt++; tasks[nt] = curid; present[curid] = 1
        budget_seen[curid] = 0; stage_of[curid] = 1
        next
      }
      if (curid != "") {
        if (line ~ /^\*\*Budget:\*\*/) {
          v = line; sub(/^\*\*Budget:\*\*[ \t]*/, "", v); v = trim(v)
          budget_seen[curid] = 1
          if (v ~ /^[0-9]+$/) budget[curid] = v + 0
          else { malformed = 1; if (mline == 0) { mline = NR; mfield = "Budget" } }
        } else if (line ~ /^\*\*Stage:\*\*/) {
          v = line; sub(/^\*\*Stage:\*\*[ \t]*/, "", v); v = trim(v)
          if (v ~ /^[0-9]+$/) stage_of[curid] = v + 0
          else { malformed = 1; if (mline == 0) { mline = NR; mfield = "Stage" } }
        }
        if (line ~ /<!--[ \t]*\/mb-task:/) curid = ""
      }
    }
    END {
      et = 0; instages = 0; fm_total = -1; fm_present = 0
      for (i = 1; i <= np; i++) {
        l = pre[i]
        if (l ~ /^estimated_tokens:[ \t]*$/) { et = 1; fm_present = 1; continue }
        if (et) {
          if (l ~ /^[^ \t]/) { et = 0; instages = 0; continue }
          if (l ~ /^[ \t]+total:/) {
            v = l; sub(/^[ \t]+total:[ \t]*/, "", v); v = trim(v); instages = 0
            if (v ~ /^[0-9]+$/) fm_total = v + 0
            else { malformed = 1; if (mline == 0) { mline = i; mfield = "total" } }
          } else if (l ~ /^[ \t]+stages:[ \t]*$/) {
            instages = 1
          } else if (instages && l ~ /^[ \t]+"[^"]+":/) {
            sid = l; sub(/^[ \t]+"/, "", sid); sub(/".*/, "", sid)
            val = l; sub(/^[ \t]+"[^"]+":[ \t]*/, "", val); val = trim(val)
            if (val ~ /^[0-9]+$/) { fm_stage[sid] = val + 0; fm_stage_seen[sid] = 1 }
            else { malformed = 1; if (mline == 0) { mline = i; mfield = "stages" } }
          }
        }
      }

      # Walk the ids actually collected, sorted — never a dense 1..maxid range.
      # A single `mb-task:999999999` block used to spin the loop a billion times
      # on a two-line file (minutes of CPU for one task).
      spec_total = 0; maxstage = 0; minstage = -1
      n_sorted = asort_ids(tasks, nt, sorted_ids)
      for (si = 1; si <= n_sorted; si++) {
        id = sorted_ids[si]
        if (!(id in present)) continue
        if (budget_seen[id]) {
          b = budget[id]
          printf "task.%d=%d\n", id, b
          spec_total += b
          st = stage_of[id]; stagesum[st] += b; stage_present[st] = 1
          if (st > maxstage) maxstage = st
          if (minstage < 0 || st < minstage) minstage = st
          if (b > 120000) task_over_list = (task_over_list == "" ? id : task_over_list "," id)
        } else {
          legacy_list = (legacy_list == "" ? id : legacy_list "," id)
        }
      }
      stage_over_list = ""
      n_st = 0
      for (st in stage_present) { n_st++; stage_ids[n_st] = st + 0 }
      n_st = asort_ids(stage_ids, n_st, sorted_stages)
      for (si = 1; si <= n_st; si++) {
        st = sorted_stages[si]
        printf "stage.%d=%d\n", st, stagesum[st]
        if (stagesum[st] > 400000) stage_over_list = (stage_over_list == "" ? st : stage_over_list "," st)
      }

      printf "spec.total=%d\n", spec_total
      printf "task_over=%s\n", (task_over_list == "" ? "none" : task_over_list)
      printf "stage_over=%s\n", (stage_over_list == "" ? "none" : stage_over_list)

      if (spec_total < 900000) sp = "ok"
      else if (spec_total <= 1000000) sp = "near"
      else sp = "over"
      printf "spec=%s\n", sp
      printf "legacy_missing=%s\n", (legacy_list == "" ? "none" : legacy_list)

      mismatch = 0
      if (fm_present) {
        if (fm_total != spec_total) mismatch = 1
        for (si = 1; si <= n_st; si++) {
          st = sorted_stages[si]
          if (!(st in fm_stage_seen) || fm_stage[st] != stagesum[st]) mismatch = 1
        }
        for (sid in fm_stage_seen) {
          if (!(sid in stage_present) && fm_stage[sid] != 0) mismatch = 1
        }
      }

      if (malformed) printf "__malformed=%d:%s\n", mline, mfield
      printf "__mismatch=%d\n", mismatch
      printf "__overflow=%d\n", ((sp == "over") || (task_over_list != "") || (stage_over_list != "")) ? 1 : 0
      if (legacy_list != "") printf "__legacy=%s\n", legacy_list
    }
  ' "$1"
}
