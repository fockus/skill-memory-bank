"""v2 / C8 battery gates for mb-spec-validate.sh (svp-sdd-core).

Extracted from the shell script's heredoc so both files stay ≤400 lines (S2
review [24]) and the gates become unit-testable. Invoked as a subprocess with
the same environment the heredoc used; every violation is printed to stdout,
one per line, and the caller appends them to its violations file.

Env contract:
  TASKS_DATA    JSONL of parsed work items (one object per line)
  REQ_PATH      path to requirements.md
  DESIGN_PATH   path to design.md
  SPECS_ROOT    root that cross-spec `Blocked-by: <topic>#<n>` resolves against
  WAIVERS_FILE  file to append accepted waivers to
  MB_SCRIPT_DIR scripts/ dir (for `import mb_req_id`)
  PIPELINE_YAML resolved pipeline config (roles table); optional

Gates: Blocked-by cycles incl. cross-spec (REQ-052), per-task Eval/waiver/anchor
(REQ-007/049/050/055), Eval coverage (REQ-006), design↔tasks Eval byte-identity
(CPR-D), seam presence + rationale (REQ-051 / C9), scenario parity + coverage
(C8.2), role resolution against the pipeline roles table (C8.3), and cross-spec
Blocked-by resolution (C8.5).
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
import mb_req_id as rq  # noqa: E402
import mb_spec_validate_graph as graph_gate  # noqa: E402
import mb_spec_validate_scope_eval as scope_eval_gate  # noqa: E402
from mb_spec_validate_structural import (  # noqa: E402
    eval_targets,
    is_no_runtime,
    structural_form,
)

out = sys.stdout


def emit(msg: str) -> None:
    out.write(msg + "\n")


def ere_ok(pattern: str) -> bool:
    # Validate with the SAME portable engine used at execution time (grep -E):
    # a bad ERE exits 2 (a Python-only construct like `(?=...)` is rejected).
    try:
        return (
            subprocess.run(
                ["grep", "-E", "--", pattern],
                input="",
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            ).returncode
            != 2
        )
    except OSError:
        return False


def read(p: str) -> str:
    return open(p, encoding="utf-8").read() if p and os.path.exists(p) else ""


tasks = []
for line in os.environ.get("TASKS_DATA", "").splitlines():
    line = line.strip()
    if line:
        with contextlib.suppress(json.JSONDecodeError):
            tasks.append(json.loads(line))
req_text = read(os.environ.get("REQ_PATH", ""))
design_text = read(os.environ.get("DESIGN_PATH", ""))
specs_root = os.environ.get("SPECS_ROOT", "")


def covers_of(t: dict) -> set[str]:
    return set(rq.extract_req_ids(", ".join(str(c) for c in t.get("covers") or [])))


this_topic = os.path.basename(os.path.dirname(os.environ.get("REQ_PATH", ""))) or "."

# Check 10 — Blocked-by graph (local + cross-spec), REQ-052 / review [14][15].
graph_gate.check_graph(tasks, this_topic, specs_root, emit)


def run_v2_gates() -> None:
    # Check 10a — I-174: every runnable test file a task's Scope claims must be
    # run by its own Eval. Beside CPR-D on purpose: it compares declaration to
    # declaration, and it has to fire at spec time, not at battery time.
    scope_eval_gate.check(tasks, emit)

    # gated = defined REQ carrying a SHALL/MUST modal.
    #
    # Modality is a property of the whole requirement BLOCK, not of one physical
    # line: `- **REQ-001** The system` / `  shall persist data` is a single
    # requirement that a per-line scan read as non-gated, letting it skip GWT
    # coverage and accept an `Eval: none` waiver (review [2]). A block runs from
    # its own definition line up to the next definition line or heading.
    all_defs = set(rq.find_definitions(req_text))
    gated = set()
    lines = req_text.splitlines()
    starts = [
        i for i, ln in enumerate(lines) if {r for r in rq.extract_req_ids(ln) if r in all_defs}
    ]
    for idx, i in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
        block = []
        for ln in lines[i:end]:
            # A heading ends the block: prose after it belongs to another section.
            if block and ln.lstrip().startswith("#"):
                break
            block.append(ln)
        if re.search(r"\b(shall|must)\b", "\n".join(block), re.I):
            gated |= {r for r in rq.extract_req_ids(lines[i]) if r in all_defs}

    # Checks 11-13 — per-task Eval/waiver/anchor gates.
    eval_covered = set()
    waivers = []
    for t in tasks:
        no = t["item_no"]
        ev = t.get("eval")
        cov = covers_of(t)
        is_gated = bool(cov & gated)
        scope = [str(s) for s in (t.get("scope") or [])]
        no_runtime = is_no_runtime(scope)
        if ev is None:
            continue
        if ev.get("cmd") == "none":
            w = ev.get("waiver")
            if is_gated:
                emit(
                    f"REQ-007: task {no} declares Eval: none but covers gated {sorted(cov & gated)}"
                )
            elif w is None:
                emit(
                    f"REQ-049: task {no} declares Eval: none without a structural Eval or a waiver"
                )
            elif not w.strip():
                emit(f"REQ-050: task {no} declares a waiver with an empty reason")
            else:
                waivers.append((no, w.strip()))
            continue
        eval_covered |= cov
        cmd = ev.get("cmd") or ""
        if not (ev.get("red") or "").strip():
            emit(f"task {no} Eval declaration is missing a non-empty red: prose")
        ore = ev.get("output_re")
        if is_gated and not ore:
            emit(
                f"REQ-055: task {no} covers a gated req but its Eval has no output~: anchor (exit-only rejected)"
            )
        if ore and not ere_ok(ore):
            emit(f"task {no} Eval output~: is not a valid POSIX ERE (grep -E rejects it): {ore}")
        # REQ-049: a documentation/configuration-only task must carry one of the
        # three structural forms — file presence, section presence, linter exit
        # (review [16]: a behavioural Eval there is not observable pre-code).
        if no_runtime and structural_form(cmd) is None:
            emit(
                f"REQ-049: task {no} has a documentation/configuration-only Scope "
                f"but its Eval is not structural (file presence, section presence "
                f"or linter exit): {cmd}"
            )
        # C1 containment (review [11]): absolute paths AND `..` escapes are both
        # rejected — a target must stay repo-relative and inside the repo.
        for tok in eval_targets(cmd):
            if tok.startswith("/"):
                emit(f"task {no} Eval target is not repo-relative: {tok}")
            elif os.path.normpath(tok).startswith(".."):
                emit(f"task {no} Eval target escapes the repo root: {tok}")

    # Check 14 — REQ-006 Eval-coverage per gated req.
    for req in sorted(gated - eval_covered):
        emit(f"REQ-006: gated {req} has no covering Eval declaration")

    # Check 15a — CPR-D: design.md §Eval line byte-identical to tasks.md.
    # Only structural markdown nesting (indentation + a leading list bullet) is
    # normalised. Backticks and inner spacing are payload and are compared RAW
    # (review [12]): stripping them let a drifting anchor pass under a check
    # whose own message claims byte-identity.
    def norm_eval(s: str) -> str:
        return s.strip().lstrip("- ").strip()

    d_eval: dict[int, str] = {}
    cur = None
    for ln in design_text.splitlines():
        m = re.match(r"^- \*\*T(\d+)\*\*", ln)
        if m:
            cur = int(m.group(1))
        elif cur is not None and "**Eval:**" in ln:
            d_eval[cur] = norm_eval(ln)
            cur = None
    t_eval: dict[int, str] = {}
    for t in tasks:
        ev = t.get("eval") or {}
        # A waiver (`Eval: none`) declares no command, so design.md carries no
        # §Eval entry for it — it is outside the identity gate by construction.
        if ev.get("cmd") == "none":
            continue
        for bl in (t.get("body") or "").splitlines():
            if bl.strip().startswith("**Eval:**"):
                t_eval[t["item_no"]] = norm_eval(bl)
                break
    # Bidirectional: an empty side is a FAILURE, never a silent skip.
    for n in sorted(set(d_eval) | set(t_eval)):
        if n not in d_eval:
            emit(
                f"CPR-D: task {n} declares an Eval in tasks.md but design.md §Eval declarations has none"
            )
        elif n not in t_eval:
            emit(f"CPR-D: design.md declares an Eval for T{n} but tasks.md task {n} has none")
        elif d_eval[n] != t_eval[n]:
            emit(f"CPR-D: design.md Eval for T{n} is not byte-identical to task {n} in tasks.md")

    # Check 15b — seam gate (REQ-051 / C9). A v2 spec must declare EXACTLY one
    # machine-readable Seams block (review [13]: deleting it used to be a silent
    # pass); ≥2 seams inside it still need a rationale.
    lines = design_text.splitlines()
    in_fence = False
    i = 0
    seam_blocks = 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("```"):
            in_fence = not in_fence
            i += 1
            continue
        if not in_fence and s.startswith("**Seams:**"):
            seam_blocks += 1
            j = i + 1
            seams: list[str] = []
            rationale = None
            while j < len(lines):
                sj = lines[j].strip()
                if sj.startswith("- "):
                    seams.append(sj[2:].strip())
                    j += 1
                    continue
                if sj.startswith("**Seam rationale:**"):
                    rationale = sj.split(":**", 1)[1].strip()
                    j += 1
                break
            # A header with no entries is not a seam: REQ-051 wants one seam
            # recorded by default, and an empty block used to satisfy the
            # "exactly one **Seams:** block" count while declaring nothing
            # (review [4]).
            if not seams:
                emit("REQ-051: **Seams:** block is empty (C9 requires at least one seam)")
            if len(seams) >= 2 and not rationale:
                emit(f"REQ-051: {len(seams)} seams declared without a Seam rationale")
            i = j
            continue
        i += 1
    if seam_blocks == 0:
        emit("REQ-051: design.md declares no **Seams:** block (C9 requires exactly one)")
    elif seam_blocks > 1:
        emit(
            f"REQ-051: design.md declares {seam_blocks} **Seams:** blocks (C9 requires exactly one)"
        )

    # Check 16a — scenario parity + ASCII names + gated coverage (C8.2).
    headings = re.findall(r"^### Scenario:\s*(.+?)\s*$", req_text, re.M)
    markers = re.findall(r"^<!--\s*mb-scenario:\d+\s*-->\s*$", req_text, re.M)
    if len(headings) != len(markers):
        emit(
            f"C8.2: scenario parity mismatch — {len(headings)} '### Scenario:' headings vs {len(markers)} markers"
        )
    for h in headings:
        if any(ord(c) > 127 for c in h):
            emit(f"C8.2: scenario name is not ASCII: {h!r}")

    # REQ-006 (verbatim): "While a requirement carries a SHALL or MUST modal,
    # the generated spec shall include at least one GWT scenario and one Eval
    # declaration covering it." Parity alone certified a spec with ZERO
    # scenarios (0 headings == 0 markers) as ready (review [8]); the scenario
    # half of REQ-006 is now enforced for gated reqs on the ordinary v2 path.
    scen_covered: set[str] = set()
    in_scen = False
    for ln in req_text.splitlines():
        if re.match(r"^### Scenario:", ln):
            in_scen = True
        elif in_scen and ln.strip().startswith("**Covers:**"):
            scen_covered |= set(rq.extract_req_ids(ln.split(":**", 1)[1]))
            in_scen = False
    for req in sorted(gated - scen_covered):
        emit(f"REQ-006: gated {req} has no covering GWT scenario")

    # Check 16b — role resolution (C8.3) against the pipeline roles table.
    for t in tasks:
        role = t.get("role", "")
        no = t["item_no"]
        if role.startswith("mb-"):
            emit(f"C8.3: task {no} Role '{role}' must be bare — use '{role[3:]}' not '{role}'")
        elif role not in KNOWN_ROLES:
            emit(f"C8.3: task {no} Role '{role}' is not a known dev role")

    # Check 16c — cross-spec Blocked-by resolution (C8.5).
    if specs_root and os.path.isdir(specs_root):
        for t in tasks:
            no = t["item_no"]
            for b in t.get("blocked_by", []):
                if "#" in str(b):
                    topic, num = str(b).split("#", 1)
                    nums = graph_gate.task_nums(topic, specs_root)
                    if nums is None:
                        emit(f"C8.5: task {no} Blocked-by '{b}' references unknown spec '{topic}'")
                    elif num not in nums:
                        emit(f"C8.5: task {no} Blocked-by '{b}' — spec '{topic}' has no task {num}")

    wf = os.environ.get("WAIVERS_FILE", "")
    if waivers and wf:
        with open(wf, "a", encoding="utf-8") as fh:
            for no, reason in waivers:
                fh.write(f"task {no}: {reason}\n")


def load_roles() -> set[str]:
    """Dev roles from the resolved pipeline roles table (review [20]).

    The normative table lives in the pipeline config, so `planner`/`researcher`
    (real defaults) are accepted and a role a project deleted is rejected.
    Fail-safe: an unreadable/rolesless config falls back to the shipped default
    set — this validator never crashes on config trouble.
    """
    fallback = {
        "backend",
        "frontend",
        "developer",
        "qa",
        "architect",
        "ios",
        "android",
        "devops",
        "analyst",
    }
    path = os.environ.get("PIPELINE_YAML", "")
    if not path or not os.path.exists(path):
        return fallback
    try:
        import yaml  # type: ignore

        with open(path, encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh) or {}
        roles = cfg.get("roles") or {}
        names = {str(k) for k in roles}
    except Exception:
        # PyYAML-optional: scrape the top-level `roles:` block textually.
        names = set()
        try:
            in_roles = False
            with open(path, encoding="utf-8") as fh:
                for ln in fh:
                    if re.match(r"^roles:\s*$", ln):
                        in_roles = True
                        continue
                    if in_roles:
                        if re.match(r"^\S", ln):
                            break
                        m = re.match(r"^\s{2}([A-Za-z0-9_]+):", ln)
                        if m:
                            names.add(m.group(1))
        except OSError:
            return fallback
    # Reviewer roles are pipeline plumbing, not task-authorable dev roles.
    names = {n for n in names if not n.startswith("reviewer")}
    return names or fallback


KNOWN_ROLES = load_roles()

# A v2 artifact must be recognised by ANY v2 field, not by Eval alone. Keying
# the whole gate set off `eval` meant that deleting every Eval line silently
# disabled all of it — gated REQs without GWT, missing Seams, bad Blocked-by —
# and returned exit 0 (review [1]). Fail-closed: any v2 signal turns the gates on.
#
# Detection reads the raw task body, NOT the parsed values: mb_work_items.py
# DEFAULTS stage/scope/budget (1 / ['**'] / 120000) when they are absent, so a
# parsed-value check would classify every legacy spec as v2 and break D-26.
# The legacy exception is therefore explicit: a task whose body declares none of
# these fields is a pre-v2 spec and stays ungated.
V2_FIELD_RE = re.compile(r"^\*\*(Eval|Stage|Scope|Budget):\*\*", re.M)


def is_v2_artifact() -> bool:
    return any(V2_FIELD_RE.search(t.get("body") or "") for t in tasks)


if is_v2_artifact():
    run_v2_gates()
