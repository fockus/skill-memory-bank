# shellcheck shell=bash
# mb-estimate-lib.sh — sourced awk parsers for mb-estimate-check.sh. The two
# programs live here so the CLI dispatcher stays small and every file is ≤400
# lines (S1 review, fix-cycle 2). Not executed standalone.

# mb_estimate_lib_context <budget> <file>
# Context-file C1 parser. Emits: `status=<ok|near|over|missing|malformed>`,
# `total=<N>`, and one `M <line> <field>` per malformed finding. estimated_tokens
# is honoured ONLY inside the first YAML frontmatter; `breakdown:` must carry
# EXACTLY the six known categories as direct children, each once, each an inline
# `{count,unit_tokens,subtotal}` map with those exact field names (no substring,
# no extra/duplicate field). Any unknown/duplicate key or wrong value shape →
# malformed.
mb_estimate_lib_context() {
  awk -v budget="$1" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function indent_of(s,   n) {
      n = 0
      while (substr(s, n + 1, 1) == " " || substr(s, n + 1, 1) == "\t") n++
      return n
    }
    function parse_map(line, vals,   m, inner, n, parts, i, kv, p, k, v, cnt) {
      # Exactly {count, unit_tokens, subtotal}: exact names, each once, ints ≥0.
      split("", vals)
      if (match(line, /\{[^{}]*\}/) == 0) return "shape"
      m = substr(line, RSTART, RLENGTH); inner = substr(m, 2, length(m) - 2)
      n = split(inner, parts, ","); cnt = 0
      for (i = 1; i <= n; i++) {
        kv = parts[i]; p = index(kv, ":")
        if (p == 0) return "field"
        k = substr(kv, 1, p - 1); v = substr(kv, p + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v)
        if (k != "count" && k != "unit_tokens" && k != "subtotal") return "field"
        if (k in vals) return "field"
        if (v !~ /^[0-9]+$/) return "field"
        vals[k] = v + 0; cnt++
      }
      if (cnt != 3) return "field"
      return ""
    }
    { raw[NR] = $0 }
    END {
      ncat = split("shell_scripts prompt_changes python_modules test_files docs_pages external_integrations", order, " ")
      for (k = 1; k <= ncat; k++) known[order[k]] = 1

      if (NR < 1 || raw[1] !~ /^---[ \t]*$/) { print "status=missing"; print "total=0"; exit }
      fm_end = 0
      for (i = 2; i <= NR; i++) if (raw[i] ~ /^---[ \t]*$/) { fm_end = i; break }
      if (fm_end == 0) { print "status=missing"; print "total=0"; exit }
      et_line = 0
      for (i = 2; i < fm_end; i++) if (raw[i] ~ /^estimated_tokens:[ \t]*$/) { et_line = i; break }
      if (!et_line) { print "status=missing"; print "total=0"; exit }

      region_end = fm_end - 1
      for (i = et_line + 1; i <= fm_end - 1; i++) {
        if (raw[i] ~ /^[^ \t]/ && raw[i] !~ /^[ \t]*$/) { region_end = i - 1; break }
        region_end = i
      }

      total_val = -1; total_line = 0; bd_line = 0
      n_total = 0; n_bd = 0; dup_total_line = 0; dup_bd_line = 0
      for (i = et_line + 1; i <= region_end; i++) {
        l = raw[i]
        if (l ~ /^[ \t]+total:/) {
          n_total++
          if (n_total > 1) { if (!dup_total_line) dup_total_line = i; continue }
          v = l; sub(/^[ \t]+total:[ \t]*/, "", v); v = trim(v); total_line = i
          if (v ~ /^[0-9]+$/) total_val = v + 0; else total_val = -2
        } else if (l ~ /^[ \t]+breakdown:[ \t]*$/) {
          n_bd++
          if (n_bd > 1) { if (!dup_bd_line) dup_bd_line = i; continue }
          bd_line = i
        }
      }

      pt = (total_val >= 0) ? total_val : 0
      # Exactly one `total:` and one `breakdown:` are required. A repeat used to
      # overwrite the earlier value (last-wins), so `total: 1` followed by
      # `total: 0` validated as ok — an ambiguous document must be malformed,
      # not silently resolved. Reported at the DUPLICATE line.
      if (n_total > 1 || n_bd > 1) {
        print "status=malformed"; print "total=" pt
        if (n_total > 1) print "M " dup_total_line " total"
        if (n_bd > 1) print "M " dup_bd_line " breakdown"
        exit
      }
      if (!bd_line) { print "status=malformed"; print "total=" pt; print "M " et_line " breakdown"; exit }

      for (k = 1; k <= ncat; k++) { found[order[k]] = 0; cline[order[k]] = 0; dup[order[k]] = 0; badmap[order[k]] = 0 }
      nf = 0; bd_indent = indent_of(raw[bd_line]); child_indent = -1
      for (i = bd_line + 1; i <= region_end; i++) {
        l = raw[i]
        if (l ~ /^[ \t]*$/) continue
        ind = indent_of(l)
        if (ind <= bd_indent) break            # de-dent ends the breakdown map
        if (child_indent < 0) child_indent = ind
        if (ind > child_indent) continue        # nested under a child, not a key
        key = l; sub(/^[ \t]+/, "", key); p = index(key, ":")
        if (p == 0) { nf++; mline[nf] = i; mfield[nf] = "breakdown"; continue }
        kname = substr(key, 1, p - 1); gsub(/[ \t]+$/, "", kname)
        if (!(kname in known)) { nf++; mline[nf] = i; mfield[nf] = kname; continue }
        if (found[kname]) { dup[kname] = 1; nf++; mline[nf] = i; mfield[nf] = kname; continue }
        found[kname] = 1; cline[kname] = i
        err = parse_map(l, mv)
        if (err != "") { badmap[kname] = 1; nf++; mline[nf] = i; mfield[nf] = kname }
        else { cval[kname] = mv["count"]; uval[kname] = mv["unit_tokens"]; sval[kname] = mv["subtotal"] }
      }

      sum = 0; sum_ok = 1
      for (k = 1; k <= ncat; k++) {
        cat = order[k]
        if (dup[cat] || badmap[cat]) { sum_ok = 0; continue }
        if (!found[cat]) { nf++; mline[nf] = cline[cat]; mfield[nf] = cat; sum_ok = 0; continue }
        if (sval[cat] != cval[cat] * uval[cat]) { nf++; mline[nf] = cline[cat]; mfield[nf] = cat; sum_ok = 0; continue }
        sum += sval[cat]
      }

      if (total_val == -1) { nf++; mline[nf] = et_line; mfield[nf] = "total" }
      else if (total_val == -2) { nf++; mline[nf] = total_line; mfield[nf] = "total" }
      else if (sum_ok && total_val != sum) { nf++; mline[nf] = total_line; mfield[nf] = "total" }

      if (nf > 0) {
        print "status=malformed"; print "total=" pt
        for (k = 1; k <= nf; k++) print "M " mline[k] " " mfield[k]
        exit
      }

      near_lower = int(budget * 9 / 10)
      if (total_val < near_lower) st = "ok"
      else if (total_val <= budget) st = "near"
      else st = "over"
      print "status=" st
      print "total=" total_val
    }
  ' "$2"
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

      spec_total = 0; maxid = 0; maxstage = 0; minstage = -1
      for (k = 1; k <= nt; k++) if (tasks[k] > maxid) maxid = tasks[k]
      for (id = 1; id <= maxid; id++) {
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
      if (minstage >= 0) {
        for (st = minstage; st <= maxstage; st++) {
          if (!(st in stage_present)) continue
          printf "stage.%d=%d\n", st, stagesum[st]
          if (stagesum[st] > 400000) stage_over_list = (stage_over_list == "" ? st : stage_over_list "," st)
        }
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
        if (minstage >= 0) {
          for (st = minstage; st <= maxstage; st++) {
            if (!(st in stage_present)) continue
            if (!(st in fm_stage_seen) || fm_stage[st] != stagesum[st]) mismatch = 1
          }
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
