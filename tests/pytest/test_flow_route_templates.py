"""Lint invariants for the five declarative flow-ROUTE templates.

dynamic-flow Phase 2 Task 11 (REQ-DF-012, REQ-DF-013, REQ-DF-021; ADR-4/6/7).

The host agent reads `goal.md`, runs `analyze-task` (which resolves a route via
`scripts/mb-flow-route.sh`), then opens the matching `flow-templates/<route>.md`
and walks its phases — it IS the interpreter. These ROUTE templates are the
declarative flow definitions the router resolves to; the PATTERN templates under
`flow-templates/patterns/` are the reusable orchestration shapes a route
composes (validated separately by `test_flow_pattern_templates.py`).

These tests guarantee, for the five known routes:

- all five files exist: `code-change`, `bugfix`, `arch`, `migration`, `research`
  (`arch.md` present = DoD#3 / REQ-DF-022 — the route-floor can FORCE `arch`, so
  its template must exist or the floor points at nothing);
- `code-change.md` REUSES the `commands/work.md` loop verbatim as ONE skill and
  does NOT re-decompose implement→review→fix into its own phase list (DoD#1,
  REQ-DF-013, ADR-7 — the anti-over-split guard);
- `bugfix.md` carries the exact phase chain reproduce → debug → patch → verify;
- each EXPANDED route (`bugfix`, `arch`, `migration`, `research`) declares all
  five DoD facets as non-empty `##` sections — Phases, Per-phase skill, Boundary
  checks, Retry rule, Sequential fallback — plus the Patterns-invoked and
  Firewall sections (DoD#2, REQ-DF-021);
- every route boundary fires the firewall `scripts/mb-flow-verify.sh` and routes
  its result through it before "done" (consistency with the pattern templates +
  REQ-DF-024/044);
- each expanded route names at least one of the SIX known patterns it invokes
  (an unknown pattern name is a fail — guard against vapor refs);
- NO vapor: any cited `scripts/*.sh`, `commands/*.md`,
  `flow-templates/patterns/*.md`, or `mb-*` role-agent must resolve on disk.
  A build step is NOT cited as a real command (ADR-6: `build` resolves to skip).
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent.parent
ROUTES_DIR = REPO / "flow-templates"
PATTERNS_DIR = ROUTES_DIR / "patterns"
SCRIPTS_DIR = REPO / "scripts"
AGENTS_DIR = REPO / "agents"
COMMANDS_DIR = REPO / "commands"

# The full five-route catalogue (REQ-DF-021), ranked research<bugfix<code-change
# <arch<migration to mirror scripts/mb-flow-route.sh::route_rank.
ROUTE_FILES = (
    "code-change.md",
    "bugfix.md",
    "arch.md",
    "migration.md",
    "research.md",
)

# code-change is the dominant case: it REUSES the work.md loop verbatim (ADR-7),
# so it is deliberately thin and does NOT declare the expanded phase facets. The
# four EXPANDED routes must declare every facet.
EXPANDED_ROUTES = ("bugfix.md", "arch.md", "migration.md", "research.md")

# The five DoD facets (REQ-DF-021) + the pattern-naming + firewall sections, each
# asserted as a non-empty `##` heading on every expanded route.
REQUIRED_EXPANDED_SECTIONS = (
    "Phases",
    "Per-phase skill",
    "Boundary checks",
    "Retry rule",
    "Sequential fallback",
    "Patterns invoked",
    "Firewall",
)

# The six known pattern names a route may invoke (must match the files under
# flow-templates/patterns/). An unknown name in a `## Patterns invoked` section is
# a vapor ref and a fail.
KNOWN_PATTERNS = frozenset(
    {
        "classify-and-act",
        "fanout-synthesize",
        "adversarial-verify",
        "generate-filter",
        "tournament",
        "loop-until-done",
    }
)

_MB_TOKEN_RE = re.compile(r"mb-[a-z0-9][a-z0-9-]*")
_SCRIPT_REF_RE = re.compile(r"scripts/([a-z0-9][a-z0-9_-]*\.(?:sh|py))")
_COMMAND_REF_RE = re.compile(r"commands/([a-z0-9][a-z0-9_-]*\.md)")
_PATTERN_REF_RE = re.compile(r"flow-templates/patterns/([a-z0-9-]+)\.md")
_PATTERN_NAME_RE = re.compile(r"\b([a-z]+(?:-[a-z]+)+)\b")
_BACKTICK_RE = re.compile(r"`([^`]+)`")
_HYPHEN_IDENT_RE = re.compile(r"[a-z]+(?:-[a-z]+)+")
# A numbered phase item: `N. **<label>** — …` (label may carry spaces / hyphens).
_NUMBERED_PHASE_RE = re.compile(r"^\s*\d+\.\s+\*\*([a-z][a-z /-]*?)\*\*", re.I)
# A numbered OR bulleted item with a bolded label (used to detect a re-decomposed
# implement/review/fix hop list in the otherwise-thin code-change route).
_HOP_ITEM_RE = re.compile(r"^\s*(?:\d+\.|[-*])\s+\*\*([a-z][a-z /-]*?)\*\*", re.I)
_SECTION_RE_TMPL = r"(?m)^##\s+{0}\s*$"

# L2 skill identifiers (Phase-3 net-new; cited as identifiers, not files) — these
# may appear in backticks without being a pattern or a fabricated asset.
L2_SKILL_WORDS = frozenset(
    {
        "analyze-task",
        "write-spec",
        "plan",
        "implement",
        "review",
        "critique",
        "risk-find",
        "verify",
        "update-mb",
        "final-report",
    }
)

# The firewall's default check set (scripts/mb-flow-verify.sh CHECK_NAMES). The
# `--phase` flag is informational and does NOT change the gate; `mb_updated` is
# not a check at all, and `build` resolves to skip (ADR-6 / REQ-DF-043). A route
# must not promise the firewall runs a check it does not.
KNOWN_FIREWALL_CHECKS = frozenset({"tests", "lint", "no_todo", "diff_scope", "acceptance"})

# The loop hops code-change must NOT re-decompose into separate phase items
# (ADR-7 — implement→review→fix stay the one work.md loop).
_LOOP_HOPS = frozenset({"implement", "review", "fix"})

# `--phase` is informational and does NOT change the firewall gate. A route must
# not POSITIVELY claim it does. Detecting that robustly means a phase-conditional
# verb applied to a gate-target with NO negation on either side of the verb.
_PHASE_VERB_STEMS = (
    "change",
    "select",
    "control",
    "determine",
    "choose",
    "skip",
    "pick",
    "alter",
    "drive",
    "dictate",
    "filter",
    "govern",
    "decide",
    "affect",
    "toggle",
    "enable",
    "disable",
    "configure",
    "influence",
    "modif",  # modify / modifies / modified
    "adjust",
    "vary",
    "switch",
    # NB: `set` / `scope` are deliberately EXCLUDED — they collide with the real
    # template words "check set" / "fixed check set" and "diff_scope" / "scoped".
)
_PHASE_VERB_RE = re.compile(r"\b(?:" + "|".join(_PHASE_VERB_STEMS) + r")\w*")
_PHASE_TARGET_RE = re.compile(r"\b(?:gate|gates|check set|checks?|tests?)\b")
# `only`/`informational` are NOT negations (they do not deny the verb); a real
# negation is not/never/no/n't/cannot.
_NEG_RE = re.compile(r"\b(?:not|never|no|cannot)\b|n't")


def _read(name: str) -> str:
    path = ROUTES_DIR / name
    assert path.exists(), f"flow-route template missing: {path}"
    return path.read_text(encoding="utf-8")


def _real_mb_names() -> set[str]:
    """Every real `mb-*` asset basename on disk (scripts + agents), with and
    without its file extension — the universe a template is allowed to cite."""
    names: set[str] = set()
    for pat in ("mb-*.sh", "mb-*.py"):
        for f in SCRIPTS_DIR.glob(pat):
            names.add(f.name)  # e.g. mb-flow-verify.sh
            names.add(f.stem)  # e.g. mb-flow-verify
    for f in AGENTS_DIR.glob("mb-*.md"):
        names.add(f.name)  # e.g. mb-developer.md
        names.add(f.stem)  # e.g. mb-developer
    return names


def _section_body(text: str, heading_lower_prefix: str) -> str:
    """Extract the body of the first `## <heading>` whose lowercased text starts
    with `heading_lower_prefix` (also lowercased)."""
    prefix = heading_lower_prefix.lower()
    lines = text.splitlines()
    body: list[str] = []
    capture = False
    for line in lines:
        if re.match(r"^##\s+", line):
            capture = line.strip().lower().startswith(prefix)
            continue
        if capture:
            body.append(line)
    return "\n".join(body)


def _normalize_ws(s: str) -> str:
    """Collapse runs of whitespace (incl. line wraps) to single spaces so a
    predicate split across two wrapped lines still matches."""
    return re.sub(r"\s+", " ", s)


def _numbered_phases(body: str) -> list[str]:
    """Ordered list of bolded labels from a numbered `N. **label** — …` phase
    list (lowercased). Used to assert a route's EXACT phase chain, not just the
    relative order of a few keywords."""
    out: list[str] = []
    for line in body.splitlines():
        m = _NUMBERED_PHASE_RE.match(line)
        if m:
            out.append(m.group(1).strip().lower())
    return out


def _redecomposed_hops(text: str) -> list[str]:
    """Bolded numbered/bulleted item labels that are loop hops
    (implement/review/fix). A non-empty result means the route re-decomposed the
    work.md loop into separate hop items — forbidden for code-change (ADR-7).
    A prose arrow-chain like `implement → verify → review → fix` is NOT a list
    item and is correctly ignored."""
    hops: list[str] = []
    for line in text.splitlines():
        m = _HOP_ITEM_RE.match(line)
        if m and m.group(1).strip().lower() in _LOOP_HOPS:
            hops.append(m.group(1).strip().lower())
    return hops


def _phase_makes_false_claim(text: str) -> bool:
    """True iff `text` POSITIVELY (un-negatedly) claims `--phase` changes /
    selects / controls / skips the firewall gate, checks, check set, or tests.

    Negation-aware on BOTH sides of the verb (regex negation-scoping is the trap
    that made the prior guard brittle):
      - a negation BEFORE the verb disclaims it
        (`--phase ... does not change the gate` → not a claim);
      - a negation BETWEEN the verb and the target denies that target
        (`--phase changes the summary field, not the gate` → not a claim).
    `only` / `informational` are NOT treated as negations, so
    `--phase only controls which checks run` IS caught. The verb set is broad
    (change/select/control/affect/toggle/enable/…) so synonyms do not slip
    through, and BOTH voices are detected: active (`--phase controls the checks`)
    and passive (`the gate is controlled by --phase`). A placeholder form
    (`--phase <p> controls the gate`) IS scanned — the command-fence usage is
    excluded instead by cutting the window at the code-fence ```` ``` ````, so the
    exit-code prose after a `bash … --phase <p>` invocation cannot bleed in."""
    norm = _normalize_ws(text).lower()

    # ── active voice: `--phase … <verb> … <target>` ─────────────────────────────
    for pm in re.finditer(r"--phase\b", norm):
        window = norm[pm.end() : pm.end() + 140]
        # Bound to the clause: stop at a sentence boundary OR a code-fence close
        # (the latter ends a `bash … --phase <p>` command and walls off the
        # following exit-code prose, which otherwise contributes a stray
        # "skipped … severity-gate" → false positive).
        cut = re.search(r"[.;:—]|```", window)
        if cut:
            window = window[: cut.start()]
        nxt = window.find("--phase")
        if nxt != -1:
            window = window[:nxt]  # don't bleed into the next --phase mention
        for vm in _PHASE_VERB_RE.finditer(window):
            if _NEG_RE.search(window[: vm.start()]):
                continue  # verb is negated ("does not change") — disclaimed
            post = window[vm.end() : vm.end() + 40]
            tm = _PHASE_TARGET_RE.search(post)
            if not tm:
                continue
            if _NEG_RE.search(post[: tm.start()]):
                continue  # "..., not the gate" — target denied, not claimed
            return True

    # ── passive voice: `<target> … (is/are) <verb>ed by --phase` ────────────────
    for bm in re.finditer(r"\bby\s+`?--phase\b", norm):
        # look back within the clause for an un-negated gate-target tied to the
        # `by --phase` agent (e.g. "the gate is controlled by --phase").
        back = norm[max(0, bm.start() - 70) : bm.start()]
        cut = None
        for sep in (".", ";", ":", "—", "```"):
            idx = back.rfind(sep)
            if idx != -1 and (cut is None or idx > cut):
                cut = idx
        if cut is not None:
            back = back[cut + 1 :]
        targets = list(_PHASE_TARGET_RE.finditer(back))
        if not targets:
            continue
        tm = targets[-1]  # the target nearest the `by --phase`
        if _NEG_RE.search(back[tm.end() :]):
            continue  # "…, not controlled by --phase" — denied
        return True

    return False


def _named_patterns(body: str) -> set[str]:
    """Pattern identifiers a `## Patterns invoked` section CLAIMS: backtick-wrapped
    bare identifiers that are pattern-shaped (a known single-word pattern OR a
    hyphenated identifier), excluding role-agents (`mb-*`), paths/files (`/`/`.`),
    slash-commands, and L2 skill identifiers. Every such claim must be a real
    pattern — an unknown one is vapor."""
    claimed: set[str] = set()
    for tok in _BACKTICK_RE.findall(body):
        t = tok.strip().lower()
        if not t or "/" in t or "." in t or " " in t:
            continue  # path, file, slash-command, or phrase — not a bare pattern id
        if t.startswith("mb-"):
            continue  # role-agent, not a pattern
        if t in L2_SKILL_WORDS:
            continue  # L2 skill identifier, not a pattern
        if t in KNOWN_PATTERNS or _HYPHEN_IDENT_RE.fullmatch(t):
            claimed.add(t)
    return claimed


# ── existence (DoD#3: arch.md present) ───────────────────────────────────────


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_route_file_exists(name: str) -> None:
    assert (ROUTES_DIR / name).exists(), f"flow-route template missing: {name}"


def test_full_five_route_catalogue_present() -> None:
    assert ROUTES_DIR.exists(), f"flow-templates dir missing: {ROUTES_DIR}"
    on_disk = {p.name for p in ROUTES_DIR.glob("*.md")}
    assert set(ROUTE_FILES) <= on_disk, f"missing route files: {set(ROUTE_FILES) - on_disk}"


def test_arch_route_present_for_route_floor() -> None:
    """DoD#3 / REQ-DF-022: the deterministic route-floor can FORCE `arch`, so the
    template must exist or the floor resolves to a missing flow."""
    assert (ROUTES_DIR / "arch.md").exists(), (
        "arch.md is mandatory — the route-floor (REQ-DF-022) forces `arch`"
    )


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_has_route_title(name: str) -> None:
    text = _read(name)
    assert re.search(r"(?m)^# Route: \S", text), f"{name} must open with `# Route: <name>`"


# ── code-change reuses work.md verbatim, NOT re-decomposed (DoD#1, ADR-7) ─────


def test_code_change_reuses_work_md_loop() -> None:
    """DoD#1 / REQ-DF-013 / ADR-7: code-change REUSES the existing work.md loop
    rather than re-decomposing it. Assert it cites the loop AND states it is ONE
    skill / not split into separate hops."""
    text = _read("code-change.md")
    low = _normalize_ws(text).lower()
    # It must point at the real loop: the work.md file and/or the /mb work skill.
    assert "commands/work.md" in text or "/mb work" in low, (
        "code-change must cite the existing work.md loop (`commands/work.md` / `/mb work`)"
    )
    # And it must reference the governed-execution workflow it reuses.
    assert "governed-execution" in low, (
        "code-change must name the `governed-execution` workflow it reuses"
    )
    # Anti-over-split: it must explicitly state implement→review→fix stay ONE
    # skill / are NOT split into separate hops (ADR-7).
    one_skill_markers = (
        "one skill",
        "single skill",
        "not split",
        "without splitting",
        "no over-split",
        "not decompose",
        "rather than decomposing",
        "not re-decompose",
        "not re-list",
    )
    assert any(m in low for m in one_skill_markers), (
        "code-change must explicitly state the implement→review→fix loop is ONE "
        "skill / NOT split into separate hops (ADR-7 anti-over-split)"
    )


def test_code_change_does_not_redecompose_phases() -> None:
    """ADR-7: code-change must NOT introduce its own re-decomposed phase list
    that duplicates work.md. It is deliberately thin — no `## Phases` /
    `## Per-phase skill` enumeration, AND no numbered/bulleted hop list that
    breaks implement/review/fix into separate items under ANY heading. A prose
    arrow-chain describing the loop as one unit is fine; an enumerated hop list
    is the over-split ADR-7 forbids."""
    text = _read("code-change.md")
    assert not re.search(_SECTION_RE_TMPL.format("Phases"), text), (
        "code-change must NOT declare a `## Phases` list — it reuses work.md as "
        "ONE skill (ADR-7); re-decomposing it duplicates the loop"
    )
    assert not re.search(_SECTION_RE_TMPL.format("Per-phase skill"), text), (
        "code-change must NOT declare a `## Per-phase skill` list — ADR-7 keeps "
        "implement→review→fix as the single work.md loop"
    )
    hops = _redecomposed_hops(text)
    assert not hops, (
        "code-change must NOT enumerate implement/review/fix as separate "
        f"numbered/bulleted hop items — that re-decomposes the work.md loop "
        f"(ADR-7 anti-over-split); found hop items {hops}"
    )


def test_code_change_names_firewall() -> None:
    """Even the thin route routes its result through the firewall (REQ-DF-044)."""
    text = _read("code-change.md")
    assert re.search(r"bash\s+scripts/mb-flow-verify\.sh", text), (
        "code-change must route its result through `bash scripts/mb-flow-verify.sh`"
    )


# ── bugfix has the exact reproduce→debug→patch→verify chain ───────────────────


def test_bugfix_phase_chain_is_reproduce_debug_patch_verify() -> None:
    """The bugfix Phases section must carry EXACTLY the four phases, in order:
    reproduce → debug → patch → verify. Parse the numbered phase list and assert
    exact equality — an inserted/dropped/reordered phase is a fail (a keyword
    `find()` would let an extra phase between debug and patch slip through)."""
    body = _section_body(_read("bugfix.md"), "## phases")
    assert body.strip(), "bugfix `## Phases` body is empty"
    phases = _numbered_phases(body)
    assert phases == ["reproduce", "debug", "patch", "verify"], (
        "bugfix Phases must be EXACTLY reproduce→debug→patch→verify (a numbered "
        f"`N. **label**` list with no extra/missing/reordered phase); got {phases}"
    )


# ── expanded routes declare all five facets (DoD#2, REQ-DF-021) ──────────────


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
@pytest.mark.parametrize("section", REQUIRED_EXPANDED_SECTIONS)
def test_expanded_route_section_present(name: str, section: str) -> None:
    text = _read(name)
    pattern = _SECTION_RE_TMPL.format(re.escape(section))
    assert re.search(pattern, text), f"{name} missing `## {section}` section"


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
@pytest.mark.parametrize("section", REQUIRED_EXPANDED_SECTIONS)
def test_expanded_route_section_non_empty(name: str, section: str) -> None:
    body = _section_body(_read(name), f"## {section}")
    assert body.strip(), f"{name} `## {section}` body is empty"


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
def test_per_phase_skill_cites_a_real_asset(name: str) -> None:
    """The Per-phase skill section must map phases to REAL L2 skills / role-agents,
    not vapor — assert it cites at least one real `mb-*` agent or a known L2 skill
    keyword."""
    body = _section_body(_read(name), "## per-phase skill")
    real = _real_mb_names()
    cited_mb = {t for t in _MB_TOKEN_RE.findall(body) if t in real}
    # L2 skill names that are NOT files (Phase-3 net-new) but are legitimate
    # skill identifiers a route may map a phase to.
    l2_skill_words = (
        "analyze-task",
        "write-spec",
        "plan",
        "implement",
        "review",
        "critique",
        "risk-find",
        "verify",
        "update-mb",
        "final-report",
    )
    low = body.lower()
    cited_skill = any(w in low for w in l2_skill_words)
    assert cited_mb or cited_skill, (
        f"{name} Per-phase skill must map a phase to a real role-agent "
        f"(`mb-*`) or a known L2 skill (one of {l2_skill_words})"
    )


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
def test_boundary_checks_fire_the_firewall(name: str) -> None:
    """Each phase boundary must run the firewall — the Boundary checks section
    must name `mb-flow-verify.sh`."""
    body = _section_body(_read(name), "## boundary checks")
    assert "mb-flow-verify.sh" in body, (
        f"{name} Boundary checks must fire `scripts/mb-flow-verify.sh` at each boundary"
    )


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
def test_retry_rule_is_concrete(name: str) -> None:
    """The Retry rule must state an explicit repair/retry predicate, not a stub."""
    body = _section_body(_read(name), "## retry rule")
    assert len(body.strip()) >= 60, f"{name} `## Retry rule` is too thin to be a real rule"
    low = body.lower()
    assert re.search(r"\b(retry|repair|re-?run|halt|red|cap|max|cycle|re-route)\b", low), (
        f"{name} Retry rule must state a concrete repair/retry predicate"
    )


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
def test_sequential_fallback_is_concrete(name: str) -> None:
    """The Sequential fallback must describe degrading to sequential execution
    (REQ-DF-052) — not an empty placeholder."""
    body = _section_body(_read(name), "## sequential fallback")
    low = _normalize_ws(body).lower()
    assert "sequential" in low, (
        f"{name} Sequential fallback must describe sequential degradation (REQ-DF-052)"
    )
    assert len(body.strip()) >= 60, f"{name} `## Sequential fallback` is too thin"


# ── pattern-naming: each expanded route names a KNOWN pattern ─────────────────


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
def test_patterns_invoked_names_a_known_pattern(name: str) -> None:
    """The `## Patterns invoked` section must (a) name at least one of the six
    known patterns — via a backtick identifier OR a resolved
    `flow-templates/patterns/<p>.md` ref, so a single-word pattern like
    `tournament` cited with its file-ref counts — and (b) name NO unknown
    pattern: every pattern-shaped backtick identifier must be one of the six.
    This bites a vapor `made-up-pattern` even when a real pattern is also named,
    without false-failing role-agents / slash-commands / file paths."""
    body = _section_body(_read(name), "## patterns invoked")
    assert body.strip(), f"{name} `## Patterns invoked` body is empty"

    claimed = _named_patterns(body)
    # (b) no vapor: every claimed pattern identifier must be real.
    vapor = claimed - KNOWN_PATTERNS
    assert not vapor, (
        f"{name} `## Patterns invoked` names unknown pattern(s) {sorted(vapor)} "
        f"(known: {sorted(KNOWN_PATTERNS)})"
    )

    # (a) at least one real pattern — backtick identifier OR resolved file-ref.
    filerefs = set(_PATTERN_REF_RE.findall(body))
    cited_known = (claimed | filerefs) & KNOWN_PATTERNS
    assert cited_known, (
        f"{name} Patterns invoked must name at least one of the six known "
        f"patterns {sorted(KNOWN_PATTERNS)}; found backtick={sorted(claimed)} "
        f"filerefs={sorted(filerefs)}"
    )

    # Any explicit `flow-templates/patterns/<p>.md` ref must resolve and be known.
    for ref in filerefs:
        assert ref in KNOWN_PATTERNS, (
            f"{name} cites unknown pattern `{ref}` (known: {sorted(KNOWN_PATTERNS)})"
        )
        assert (PATTERNS_DIR / f"{ref}.md").exists(), (
            f"{name} cites pattern file that does not exist: patterns/{ref}.md"
        )


# ── firewall section mirrors the pattern templates' block ─────────────────────


@pytest.mark.parametrize("name", EXPANDED_ROUTES)
def test_firewall_section_shows_bank_and_exit_codes(name: str) -> None:
    """The Firewall section must show the real interface — the
    `bash scripts/mb-flow-verify.sh <bank> [--phase <p>]` fence and the 0/1/2
    exit trichotomy — mirroring the pattern templates verbatim in shape."""
    body = _section_body(_read(name), "## firewall")
    assert body.strip(), f"{name} `## Firewall` body is empty"
    assert re.search(r"bash\s+scripts/mb-flow-verify\.sh", body), (
        f"{name} Firewall must show `bash scripts/mb-flow-verify.sh <bank> ...`"
    )
    assert re.search(r"mb-flow-verify\.sh\s+<?bank>?", body) or 'mb-flow-verify.sh "$MB"' in body, (
        f"{name} Firewall must show `mb-flow-verify.sh <bank>`"
    )
    for code in ("0", "1", "2"):
        assert re.search(rf"`?{code}`?", body), f"{name} Firewall must document exit {code}"


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_route_routes_result_through_firewall(name: str) -> None:
    """Every route — thin or expanded — routes its result through the firewall
    before "done" (REQ-DF-024/044)."""
    text = _read(name)
    assert re.search(r"bash\s+scripts/mb-flow-verify\.sh", text), (
        f"{name} must route its result through `bash scripts/mb-flow-verify.sh` before done"
    )


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_route_does_not_invent_a_firewall_check(name: str) -> None:
    """A route's Firewall / Boundary-checks must not promise the firewall runs a
    check it does not. `scripts/mb-flow-verify.sh` runs a FIXED default set
    {tests,lint,no_todo,diff_scope,acceptance}; `--phase` is informational and
    "does not change the gate"; `mb_updated` is not a check at all and `build`
    resolves to skip (ADR-6). A research route in particular must NOT claim the
    firewall gates on `mb_updated` or skips `tests` by phase."""
    text = _read(name)
    low_all = text.lower()
    # `mb_updated` is a fabricated check identifier — never legitimate ANYWHERE in
    # a route template (it slips out of the firewall section into Retry prose too).
    for vapor in ("mb_updated", "mb-updated"):
        assert vapor not in low_all, (
            f"{name} cites `{vapor}` — not a real firewall check in mb-flow-verify.sh "
            f"(default set {sorted(KNOWN_FIREWALL_CHECKS)})"
        )
    fw = "\n".join(
        (
            _section_body(text, "## firewall"),
            _section_body(text, "## boundary checks"),
        )
    )
    # `build` is a legitimate English word in prose ("build the implementation",
    # "rebuild derived indexes"), so only ban it as a CHECK token — i.e. cited as
    # a backticked `build` identifier (the way real checks `tests`/`acceptance`
    # are cited) — not as an arbitrary substring.
    backticked = {t.strip().lower() for t in _BACKTICK_RE.findall(fw)}
    assert "build" not in backticked, (
        f"{name} cites `build` as a firewall check — ADR-6: build resolves to skip, "
        f"there is no build check in the firewall set {sorted(KNOWN_FIREWALL_CHECKS)}"
    )
    # `--phase` is informational; a route must not POSITIVELY claim it
    # changes/selects/controls the gate, the checks, or which tests run (see
    # `_phase_makes_false_claim` — whitespace-normalized + two-sided negation-aware).
    assert not _phase_makes_false_claim(fw), (
        f"{name} positively claims `--phase` changes the firewall gate/checks; "
        f"`--phase` is informational only and does not change the gate"
    )


# The `--phase` false-claim detector is the load-bearing, easy-to-get-wrong piece;
# pin its behaviour both directions with curated examples (incl. the exact forms a
# prior brittle guard mishandled: post-verb negation, `only`/`but` clauses, verb
# synonyms, line-wraps).
_PHASE_GOOD = (  # legitimate — `--phase` is informational / target denied
    "`--phase` is informational and does not change the gate",
    "the check set is fixed — `--phase`\nis informational and does not change the gate",
    "`--phase` is informational only; the checks are fixed",
    "`--phase` changes the summary field, not the gate",
    "`--phase` selects a phase label, not the check set",
    "`--phase` cannot change which checks run",
    "bash scripts/mb-flow-verify.sh <bank> [--phase <p>]",
    "fire the firewall scoped to that phase: `--phase <scope|gather|report>`",
    # a `bash … --phase <p>` command fence followed by exit-code prose must NOT
    # bleed ("green/skipped … severity-gate") into a false claim.
    "```bash\nbash scripts/mb-flow-verify.sh <bank> [--phase <p>]\n```\n"
    "Exit `0` PASS (every check green/skipped + severity-gate passes)",
)
_PHASE_BAD = (  # false claims — `--phase` is load-bearing
    "`--phase` controls which checks run",
    "`--phase` only controls which checks run",
    "`--phase` is informational, but controls which checks run",
    "`--phase` selects the check set for the phase",
    "`--phase` skips the `tests` check for research",
    "`--phase` changes the gate",
    "`--phase` drives the tests",
    "`--phase` dictates which checks the gate runs",
    "`--phase` filters the checks",
    # placeholder-form inline prose claims (round-4 finding) — still false claims
    "`--phase <p>` controls the gate",
    "use `--phase <p>` to skip tests for research",
    "`--phase=<p>` controls which checks run",
    # broadened verbs + passive voice (round-5 finding) — still false claims
    "`--phase <p>` affects which checks run",
    "`--phase <p>` toggles tests for research",
    "`--phase <p>` enables the tests gate",
    "the gate is controlled by `--phase <p>`",
    "the `tests` check is skipped by `--phase`",
)


@pytest.mark.parametrize("good", _PHASE_GOOD)
def test_phase_claim_detector_accepts_legit_forms(good: str) -> None:
    assert not _phase_makes_false_claim(good), f"legit `--phase` sentence wrongly flagged: {good!r}"


@pytest.mark.parametrize("bad", _PHASE_BAD)
def test_phase_claim_detector_catches_false_claims(bad: str) -> None:
    assert _phase_makes_false_claim(bad), f"false `--phase` claim NOT caught: {bad!r}"


# ── no vapor: every cited script / command / agent must exist on disk ─────────


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_no_fabricated_mb_asset(name: str) -> None:
    """Every `mb-*` script/agent name cited in a route template must exist on
    disk — no invented helper. L2 skill NAMES that are not yet files (implement /
    verify / critique / risk-find / final-report / write-spec / update-MB) are
    allowed because they are skill identifiers, not `mb-*` asset basenames."""
    text = _read(name)
    real = _real_mb_names()
    cited = set(_MB_TOKEN_RE.findall(text))
    unknown = {tok for tok in cited if tok not in real}
    assert not unknown, (
        f"{name} cites mb-* name(s) that do not exist on disk (vapor): {sorted(unknown)}"
    )


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_cited_scripts_exist(name: str) -> None:
    text = _read(name)
    for ref in set(_SCRIPT_REF_RE.findall(text)):
        assert (SCRIPTS_DIR / ref).exists(), (
            f"{name} cites a non-existent script (vapor): scripts/{ref}"
        )


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_cited_commands_exist(name: str) -> None:
    text = _read(name)
    for ref in set(_COMMAND_REF_RE.findall(text)):
        assert (COMMANDS_DIR / ref).exists(), (
            f"{name} cites a non-existent command file (vapor): commands/{ref}"
        )


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_cited_pattern_files_exist(name: str) -> None:
    text = _read(name)
    for ref in set(_PATTERN_REF_RE.findall(text)):
        assert (PATTERNS_DIR / f"{ref}.md").exists(), (
            f"{name} cites a non-existent pattern file (vapor): patterns/{ref}.md"
        )
        assert ref in KNOWN_PATTERNS, (
            f"{name} cites unknown pattern `{ref}` (known: {sorted(KNOWN_PATTERNS)})"
        )


@pytest.mark.parametrize("name", ROUTE_FILES)
def test_no_build_command_cited_as_real(name: str) -> None:
    """ADR-6 / REQ-DF-043: there is NO build-runner in v1 — `build` resolves to
    `skip`. A route must not cite a build step as a real runnable command (e.g.
    `mb-build-run.sh` or `bash scripts/...build...`)."""
    text = _read(name)
    # No fabricated build script reference.
    for ref in set(_SCRIPT_REF_RE.findall(text)):
        assert "build" not in ref.lower(), (
            f"{name} cites a build script `scripts/{ref}` — ADR-6: build resolves "
            f"to skip, there is no build-runner in v1"
        )
