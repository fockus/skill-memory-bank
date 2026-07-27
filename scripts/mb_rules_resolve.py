#!/usr/bin/env python3
"""Rule-source resolution core for mb-rules-resolve.sh (svp-contract-test-loop C2).

    mb_rules_resolve.py [<declared-source>...]

Inputs arrive as MBR_* environment variables from the shell wrapper, which
owns argument parsing and path canonicalisation. This module owns the two
resolution modes, the `## Quality DoD` grammar, the rubric rendering and the
JSON contract.

stdout: the C2 JSON object. stderr: `rule_source_missing=` (exit 1),
`quality_dod_malformed=` / `review_rubric_unreadable=` (exit 2).
"""

import json
import os
import re
import sys

REPO = os.environ["MBR_REPO"]
BANK = os.environ["MBR_BANK"]
SPEC = os.environ["MBR_SPEC"]
SKILL_ROOT = os.environ["MBR_SKILL_ROOT"]
PIPELINE = os.environ["MBR_PIPELINE"]
KINDS = ("project", "profile", "skill")
CHECKER = "scripts/mb-rules-check.sh"

declared_flags = sys.argv[1:]


def die_usage(detail):
    sys.stderr.write("quality_dod_malformed=%s\n" % detail)
    raise SystemExit(2)


def rel_to(base, path):
    """Repo-relative POSIX path — or the ABSOLUTE path when it escapes base.

    A bank registered with `--storage=global` genuinely lives outside the repo,
    so there is no repo-relative name for it. Emitting `../../../..` there would
    hand downstream C5 a traversal chain that renders into a spec and reads as
    repo-relative; the absolute path is the honest answer.
    """
    try:
        rel = os.path.relpath(path, base).replace(os.sep, "/")
    except ValueError:
        return path
    if rel == ".." or rel.startswith("../"):
        return path
    return rel


def check_grammar(path, detail_prefix):
    """A declared path is repo-relative BY CONTRACT — proven before any stat."""
    if not path:
        die_usage("%s:empty_path" % detail_prefix)
    if path.startswith("/"):
        die_usage("%s:absolute_path" % detail_prefix)
    if "\\" in path:
        die_usage("%s:backslash" % detail_prefix)
    if ".." in path.split("/"):
        die_usage("%s:traversal" % detail_prefix)


def load_rubric():
    """`pipeline.yaml:review_rubric` flattened to canonical bullets, in AUTHOR
    order — a sorted or regrouped rubric is a different document (R2-012)."""

    def unreadable(detail):
        # Loud, never []. The rubric is half the criterion the reviewer and the
        # judge are handed; degrading it to silence would let them return a
        # verdict against a criterion nobody noticed was empty. This is REQ-017's
        # rule — fail loudly rather than fall back quietly — applied to the
        # second half of the same block.
        sys.stderr.write("review_rubric_unreadable=%s detail=%s\n" % (PIPELINE, detail))
        raise SystemExit(2)

    try:
        with open(PIPELINE, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        unreadable("open_failed")
    try:
        import yaml  # noqa: F401  (optional; the bundle does not require it)

        cfg = yaml.safe_load(text)
    except ImportError:
        sys.path.insert(0, os.path.join(SKILL_ROOT, "scripts"))
        from mb_pipeline_minimal_yaml import minimal_pipeline_load

        cfg = minimal_pipeline_load(text)
    except Exception:
        unreadable("parse_failed")
    rubric = (cfg or {}).get("review_rubric")
    if rubric is None:
        # Genuinely absent is the one case the contract calls empty (C2).
        return []
    if not isinstance(rubric, dict):
        unreadable("not_a_mapping")
    bullets = []
    for category, items in rubric.items():
        if items is not None and not isinstance(items, list):
            unreadable("category_not_a_list:%s" % category)
        for item in items or []:
            # The category is kept: "No secrets in code" means something
            # different filed under `security` than under `tests`, and the
            # reviewer is shown this list without the file it came from.
            bullets.append("%s: %s" % (category, item))
    return bullets


def parse_quality_dod(design_path):
    """Declared `- [<kind>] <path>` entries from the `## Quality DoD` section.

    Lines that are not source declarations — the rubric bullets and the Checker
    line C5 also writes into this section — are IGNORED, not rejected. Rejecting
    them would make the canonical block C5 generates unreadable by C2 and break
    the closed loop.
    """
    try:
        with open(design_path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except OSError:
        die_usage("design_unreadable")

    # Fence-aware, like mb_spec_validate_v2.py:220-227. `references/templates.md`
    # documents this very section inside a ```-block, so a design.md that quotes
    # the template as an example has two literal matches: without this, the
    # example counted as a real section and a valid spec was refused
    # `duplicate_section` — or, with no real section beside it, a commented-out
    # example was parsed as the live declaration.
    start = None
    in_fence = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence and stripped == "## Quality DoD":
            if start is not None:
                die_usage("duplicate_section")
            start = i
    if start is None:
        die_usage("section_absent")

    body = []
    in_fence = False
    for line in lines[start + 1 :]:
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            # A fenced example INSIDE the section is documentation, not a
            # declaration. Collecting it would reintroduce the same defect one
            # level down: an illustrative `- [project] …` line parsed as a real
            # rule source.
            continue
        if line.startswith("## "):
            break
        body.append(line)

    entries = []
    decl_re = re.compile(r"^- \[([^\]]*)\](.*)$")
    for line in body:
        mo = decl_re.match(line.rstrip())
        if not mo:
            continue
        kind, rest = mo.group(1).strip(), mo.group(2).strip()
        if kind not in KINDS:
            die_usage("unknown_kind:%s" % (kind or "<empty>"))
        check_grammar(rest, "kind_%s" % kind)
        entries.append({"kind": kind, "path": rest})
    return entries


def classify(path):
    if path == "rules/RULES.md":
        return "skill"
    if "rules-profile" in os.path.basename(path):
        return "profile"
    return "project"


def base_for(kind):
    # A `skill` source is bundle-relative; everything else is repo-relative.
    return SKILL_ROOT if kind == "skill" else REPO


def emit(sources, fallback_used):
    sources = sorted(sources, key=lambda s: s["path"].encode("utf-8"))
    sys.stdout.write(
        json.dumps(
            {
                "sources": sources,
                "review_rubric": load_rubric(),
                "fallback_used": fallback_used,
                "checker": CHECKER,
            },
            ensure_ascii=False,
        )
        + "\n"
    )
    raise SystemExit(0)


# ── validation mode ─────────────────────────────────────────────────────────
if SPEC or declared_flags:
    entries = parse_quality_dod(os.path.join(SPEC, "design.md")) if SPEC else []
    for path in declared_flags:
        kind = classify(path)
        check_grammar(path, "declared_source")
        entries.append({"kind": kind, "path": path})

    missing = sorted(
        {
            e["path"]
            for e in entries
            if not os.path.exists(os.path.join(base_for(e["kind"]), e["path"]))
        }
    )
    if missing:
        # Loud, and with nothing on stdout: a caller that only checks stdout
        # must not be able to read this as an empty-but-valid resolution.
        for path in missing:
            sys.stderr.write("rule_source_missing=%s\n" % path)
        raise SystemExit(1)

    seen, unique = set(), []
    for entry in entries:
        key = (entry["kind"], entry["path"])
        if key not in seen:
            seen.add(key)
            unique.append(entry)
    # Fallback is FORBIDDEN here: the answer is what the spec declared.
    emit(unique, False)

# ── discovery mode ──────────────────────────────────────────────────────────
sources = []
for candidate in (
    os.path.join(REPO, "AGENTS.md"),
    os.path.join(REPO, "RULES.md"),
    os.path.join(BANK, "RULES.md"),
):
    if os.path.isfile(candidate):
        sources.append({"kind": "project", "path": rel_to(REPO, candidate)})

profile_paths = []
bank_profile = os.path.join(BANK, "rules-profile.json")
if os.path.isfile(bank_profile):
    profile_paths.append(rel_to(REPO, bank_profile))
try:
    prof = json.loads(os.environ.get("MBR_PROFILE_JSON") or "{}")
except ValueError:
    prof = {}
for key in ("project_profile", "user_profile"):
    node = prof.get(key) or {}
    if node.get("exists") and node.get("path"):
        path = node["path"]
        candidate = path if os.path.isabs(path) else os.path.join(REPO, path)
        if os.path.isfile(candidate):
            rel = rel_to(REPO, candidate)
            if rel not in profile_paths:
                profile_paths.append(rel)
for path in profile_paths:
    sources.append({"kind": "profile", "path": path})

# The bundled rules are a LAST resort, not an addition: they appear only when
# the project declares no rules of its own, and `fallback_used` says so out loud
# rather than letting a caller infer it from the path.
fallback_used = not any(s["kind"] == "project" for s in sources)
if fallback_used:
    sources.append({"kind": "skill", "path": "rules/RULES.md"})

emit(sources, fallback_used)
