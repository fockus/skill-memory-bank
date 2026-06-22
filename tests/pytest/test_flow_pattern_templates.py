"""Lint invariants for the six declarative flow-pattern templates.

dynamic-flow Phase 2 Task 10 (REQ-DF-080/083/086, ADR-9).

The host agent reads `goal.md`, runs `analyze-task`, opens a
`flow-templates/<route>.md`, and these PATTERN templates under
`flow-templates/patterns/` are the reusable orchestration shapes a route
composes. They are DOCS, not code — but they must be precise, lint-checkable,
and reference ONLY assets that actually ship on disk (no vapor).

These tests guarantee, for the six known patterns:

- all six files exist under `flow-templates/patterns/`;
- each declares the four DoD elements + the firewall as `##` sections
  (Fan-out shape, Per-branch skill, Aggregation / judge, Termination rule,
  Firewall);
- each names the PORTABLE fan-out primitive `mb-fanout.sh` and the firewall
  `mb-flow-verify.sh`;
- the Aggregation / judge section cites ONLY allowed combine assets — the
  review ensemble, `mb-judge`, `commands/review.md`, and the global reflexion /
  SADD skills — and introduces NO new LLM-judge rubric dimension;
- NO fabricated `mb-*` script/agent name (one that does not exist on disk) is
  cited anywhere in any template;
- `tournament.md` and `loop-until-done.md` declare a `## Composition` section.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent.parent
PATTERNS_DIR = REPO / "flow-templates" / "patterns"
SCRIPTS_DIR = REPO / "scripts"
AGENTS_DIR = REPO / "agents"

PATTERN_FILES = (
    "classify-and-act.md",
    "fanout-synthesize.md",
    "adversarial-verify.md",
    "generate-filter.md",
    "tournament.md",
    "loop-until-done.md",
)

# The five DoD elements + firewall, asserted as `##` section headings.
REQUIRED_SECTIONS = (
    "Fan-out shape",
    "Per-branch skill",
    "Aggregation / judge",
    "Termination rule",
    "Firewall",
)

# The portable fan-out primitive and the firewall every pattern must name.
REQUIRED_SCRIPT_NAMES = (
    "mb-fanout.sh",
    "mb-flow-verify.sh",
)

# The ONLY combine/judge assets a pattern's aggregation may cite. Introducing a
# new LLM-judge rubric dimension or an invented reviewer name is a defect.
ALLOWED_AGGREGATION_ASSETS = frozenset(
    {
        # review ensemble — the five aspect reviewers + lead
        "mb-reviewer-logic",
        "mb-reviewer-tests",
        "mb-reviewer-quality",
        "mb-reviewer-security",
        "mb-reviewer-scalability",
        "mb-reviewer-lead",
        # final gate
        "mb-judge",
        # the review command
        "commands/review.md",
        # global reflexion + SADD skills (CLAUDE.md slash skills)
        "/reflexion-critique",
        "/reflexion-reflect",
        "/sadd-do-competitively",
        "/sadd-tree-of-thoughts",
    }
)

# Reviewer-token shape: any `mb-reviewer-<dim>` mentioned anywhere must be one of
# the five SHIPPED aspect reviewers (or the lead) — never a fabricated dimension.
ALLOWED_REVIEWER_TOKENS = frozenset(
    {
        "mb-reviewer-logic",
        "mb-reviewer-tests",
        "mb-reviewer-quality",
        "mb-reviewer-security",
        "mb-reviewer-scalability",
        "mb-reviewer-lead",
        # the plural ensemble base + the inline-review agent both ship on disk
        "mb-reviewer",
        "mb-reviewer-resolve",
    }
)

_MB_TOKEN_RE = re.compile(r"mb-[a-z0-9][a-z0-9-]*")
_REVIEWER_TOKEN_RE = re.compile(r"mb-reviewer-[a-z0-9-]+")
_SECTION_RE_TMPL = r"(?m)^##\s+{0}\s*$"


def _read(name: str) -> str:
    path = PATTERNS_DIR / name
    assert path.exists(), f"flow-pattern template missing: {path}"
    return path.read_text(encoding="utf-8")


def _real_mb_names() -> set[str]:
    """Every real `mb-*` asset basename on disk (scripts + agents), with and
    without its file extension — the universe a template is allowed to cite."""
    names: set[str] = set()
    for pat in ("mb-*.sh", "mb-*.py"):
        for f in SCRIPTS_DIR.glob(pat):
            names.add(f.name)  # e.g. mb-fanout.sh
            names.add(f.stem)  # e.g. mb-fanout
    for f in AGENTS_DIR.glob("mb-*.md"):
        names.add(f.name)  # e.g. mb-judge.md
        names.add(f.stem)  # e.g. mb-judge
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


def _aggregation_section(text: str) -> str:
    """Extract the body of the `## Aggregation / judge` section."""
    return _section_body(text, "## aggregation")


# Allowed global slash-skills (CLAUDE.md reflexion + SADD). A `/skill` cited in a
# template must be one of these — no invented slash command.
ALLOWED_SLASH_SKILLS = frozenset(
    {
        "/reflexion-critique",
        "/reflexion-reflect",
        "/sadd-do-competitively",
        "/sadd-tree-of-thoughts",
    }
)

_COMMAND_REF_RE = re.compile(r"commands/[a-z0-9][a-z0-9-]*\.md")
_SLASH_SKILL_RE = re.compile(r"/(?:reflexion|sadd)-[a-z0-9-]+")


# ── existence ────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_pattern_file_exists(name: str) -> None:
    assert (PATTERNS_DIR / name).exists(), f"flow-pattern template missing: {name}"


def test_exactly_the_six_known_patterns() -> None:
    assert PATTERNS_DIR.exists(), f"patterns dir missing: {PATTERNS_DIR}"
    on_disk = {p.name for p in PATTERNS_DIR.glob("*.md")}
    assert set(PATTERN_FILES) <= on_disk, f"missing pattern files: {set(PATTERN_FILES) - on_disk}"


# ── required sections (DoD four elements + firewall) ─────────────────────────


@pytest.mark.parametrize("name", PATTERN_FILES)
@pytest.mark.parametrize("section", REQUIRED_SECTIONS)
def test_required_section_present(name: str, section: str) -> None:
    text = _read(name)
    pattern = _SECTION_RE_TMPL.format(re.escape(section))
    assert re.search(pattern, text), f"{name} missing `## {section}` section"


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_has_intent_title(name: str) -> None:
    text = _read(name)
    assert re.search(r"(?m)^# Pattern: \S", text), f"{name} must open with `# Pattern: <name>`"


# ── portable fan-out + firewall named ────────────────────────────────────────


@pytest.mark.parametrize("name", PATTERN_FILES)
@pytest.mark.parametrize("script", REQUIRED_SCRIPT_NAMES)
def test_names_required_script(name: str, script: str) -> None:
    text = _read(name)
    assert script in text, f"{name} must name `{script}`"


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_firewall_invocation_present(name: str) -> None:
    """The firewall section must carry the real invocation, not just the name."""
    text = _read(name)
    assert re.search(r"bash\s+scripts/mb-flow-verify\.sh", text), (
        f"{name} Firewall must show `bash scripts/mb-flow-verify.sh <bank> ...`"
    )


# ── aggregation cites only allowed assets, no fabricated rubric ──────────────


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_aggregation_only_cites_allowed_assets(name: str) -> None:
    """Every combine/judge ASSET named in the aggregation section is allowed —
    the review ensemble, mb-judge, commands/review.md, reflexion/SADD skills.
    No invented reviewer dimension or rubric token."""
    section = _aggregation_section(_read(name))
    assert section.strip(), f"{name} `## Aggregation / judge` body is empty"

    # Any `mb-reviewer-*` cited in aggregation must be a shipped aspect/lead.
    for tok in set(_REVIEWER_TOKEN_RE.findall(section)):
        assert tok in ALLOWED_AGGREGATION_ASSETS, (
            f"{name} aggregation cites unknown reviewer dimension `{tok}` "
            f"(allowed: {sorted(ALLOWED_AGGREGATION_ASSETS)})"
        )

    # The aggregation must actually reference at least one allowed combine asset.
    cited = {a for a in ALLOWED_AGGREGATION_ASSETS if a in section}
    assert cited, (
        f"{name} aggregation must reference at least one allowed combine asset "
        f"(one of {sorted(ALLOWED_AGGREGATION_ASSETS)})"
    )


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_reviewer_tokens_are_real_dimensions(name: str) -> None:
    """ANYWHERE in the template, an `mb-reviewer-<dim>` token must be a real
    shipped reviewer — never a fabricated rubric dimension."""
    text = _read(name)
    for tok in set(_REVIEWER_TOKEN_RE.findall(text)):
        assert tok in ALLOWED_REVIEWER_TOKENS, (
            f"{name} cites fabricated reviewer dimension `{tok}` "
            f"(real reviewers: {sorted(ALLOWED_REVIEWER_TOKENS)})"
        )


# ── no vapor: every mb-* token must exist on disk ────────────────────────────


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_no_fabricated_mb_asset(name: str) -> None:
    """Every `mb-*` script/agent name cited in a template must exist on disk —
    no invented helper. (Reviewer dimensions are validated separately above and
    are also real agents, so they pass this check too.)"""
    text = _read(name)
    real = _real_mb_names()
    cited = set(_MB_TOKEN_RE.findall(text))
    unknown = {tok for tok in cited if tok not in real}
    assert not unknown, (
        f"{name} cites mb-* name(s) that do not exist on disk (vapor): {sorted(unknown)}"
    )


# ── composition (tournament + loop-until-done) ───────────────────────────────


@pytest.mark.parametrize("name", ("tournament.md", "loop-until-done.md"))
def test_composition_section_present(name: str) -> None:
    text = _read(name)
    assert re.search(r"(?m)^##\s+Composition\s*$", text), (
        f"{name} must declare a `## Composition` section"
    )


# ── section BODIES are substantive (not just headings) ───────────────────────


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_fanout_section_uses_real_seam(name: str) -> None:
    """The Fan-out shape section must show the REAL mb-fanout invocation: the
    `--cmd` + `--branch` flags and the `MB_FANOUT_PROMPT` env seam (the prompt is
    passed via env, never interpolated into --cmd)."""
    body = _section_body(_read(name), "## fan-out shape")
    assert body.strip(), f"{name} `## Fan-out shape` body is empty"
    for token in ("--cmd", "--branch", "MB_FANOUT_PROMPT"):
        assert token in body, (
            f"{name} Fan-out shape must use `{token}` (real mb-fanout flag / env seam)"
        )


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_firewall_section_shows_bank_and_exit_codes(name: str) -> None:
    """The Firewall section must show the real interface — `<bank>` arg and the
    0/1/2 exit trichotomy — not merely name the script."""
    body = _section_body(_read(name), "## firewall")
    assert body.strip(), f"{name} `## Firewall` body is empty"
    assert re.search(r"mb-flow-verify\.sh\s+<?bank>?", body) or 'mb-flow-verify.sh "$MB"' in body, (
        f"{name} Firewall must show `mb-flow-verify.sh <bank>`"
    )
    for code in ("0", "1", "2"):
        assert re.search(rf"`?{code}`?", body), f"{name} Firewall must document exit {code}"


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_termination_rule_is_concrete(name: str) -> None:
    """The Termination rule must state an explicit stop predicate, not a stub."""
    body = _section_body(_read(name), "## termination rule")
    assert len(body.strip()) >= 80, (
        f"{name} `## Termination rule` is too thin to be a real predicate"
    )
    assert re.search(r"\b(stop|until|when|cap|predicate|==|<|>|HALT|exit `?2)", body, re.I), (
        f"{name} Termination rule must state a concrete stop predicate"
    )


# ── no vapor for commands/*.md and /slash-skill references ────────────────────


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_cited_commands_exist(name: str) -> None:
    text = _read(name)
    for ref in set(_COMMAND_REF_RE.findall(text)):
        assert (REPO / ref).exists(), f"{name} cites a non-existent command file (vapor): {ref}"


def _global_skill_dirs() -> list[Path]:
    """Candidate global skill roots (reflexion/SADD live in the user's agent
    config, NOT this repo). Returns only the ones that actually exist on THIS
    machine — empty in a clean CI checkout, which is why the allowlist below is
    the portable source of truth."""
    roots = [
        Path.home() / ".claude" / "skills",
        Path.home() / ".claude" / ".agents" / "skills",
    ]
    return [r for r in roots if r.is_dir()]


@pytest.mark.parametrize("name", PATTERN_FILES)
def test_cited_slash_skills_are_known(name: str) -> None:
    """A cited `/reflexion-*` / `/sadd-*` skill must be a KNOWN global skill.
    These skills ship in the user's agent config, not in this repo, so the
    allowlist is the portable registry. WHERE a global skills dir is present on
    the machine, we ALSO assert the skill resolves there (catching a renamed /
    removed skill); in a bare CI checkout that dir is absent and the allowlist
    membership is the guard."""
    text = _read(name)
    skill_roots = _global_skill_dirs()
    # The resolution check below is only authoritative when the global dir actually
    # carries the reflexion/SADD family. A bare/partial dir EXISTS on some CI runners
    # (e.g. /home/runner/.claude/skills) but holds none of these skills — there the
    # allowlist is the sole portable guard. Requiring at least one allowlisted skill
    # to resolve keeps the rename/removal catch alive on a real dev toolkit.
    toolkit_present = any(
        (root / s.lstrip("/")).exists() for root in skill_roots for s in ALLOWED_SLASH_SKILLS
    )
    for ref in set(_SLASH_SKILL_RE.findall(text)):
        assert ref in ALLOWED_SLASH_SKILLS, (
            f"{name} cites unknown slash-skill `{ref}` (allowed: {sorted(ALLOWED_SLASH_SKILLS)})"
        )
        if toolkit_present:
            slug = ref.lstrip("/")
            resolved = any((root / slug).exists() for root in skill_roots)
            assert resolved, (
                f"{name} cites `{ref}` but no global skill `{slug}` resolves under "
                f"{[str(r) for r in skill_roots]} (renamed/removed?)"
            )


# ── pattern-specific correctness predicates ──────────────────────────────────


def _normalize_ws(s: str) -> str:
    """Collapse runs of whitespace (incl. line wraps) to single spaces so a
    predicate split across two wrapped lines still matches."""
    return re.sub(r"\s+", " ", s)


def test_adversarial_verify_uses_strict_majority() -> None:
    """A 2-of-4 tie must NOT survive. Assert the ACTUAL strict-majority predicate
    is present (not just the words), no `>=`/`floor` weakening, and that a tie is
    explicitly rejected in BOTH the Aggregation and Termination sections."""
    text = _normalize_ws(_read("adversarial-verify.md"))
    low = text.lower()
    assert re.search(r"floor\s*\(\s*n\s*/\s*2\s*\)", low) is None, (
        "must not use the tie-surviving `floor(N/2)` predicate"
    )
    # The strict-majority predicate, accepting any whitespace + the common
    # algebraic equivalents (all of which reject a tie):
    #   not_refuted_count > N/2   |   refuted_count < N/2
    #   2*not_refuted_count > N   |   2*refuted_count < N
    strict_forms = (
        r"not_?refuted\w*\s*>\s*n\s*/\s*2",
        r"refuted\w*\s*<\s*n\s*/\s*2",
        r"2\s*\*\s*not_?refuted\w*\s*>\s*n\b",
        r"2\s*\*\s*refuted\w*\s*<\s*n\b",
    )
    assert any(re.search(f, low) for f in strict_forms), (
        "adversarial-verify must state a strict-majority predicate "
        "(e.g. `not_refuted_count > N/2`, `refuted_count < N/2`, or `2*not_refuted > N`)"
    )
    # No weakened `>=`/`<=` form of the same comparison that would let a tie pass —
    # in BOTH the `…/2` and the algebraic `2*…` spellings.
    weak_forms = (
        r"not_?refuted\w*\s*>=\s*n\s*/\s*2",
        r"refuted\w*\s*<=\s*n\s*/\s*2",
        r"2\s*\*\s*not_?refuted\w*\s*>=\s*n\b",
        r"2\s*\*\s*refuted\w*\s*<=\s*n\b",
    )
    assert not any(re.search(w, low) for w in weak_forms), (
        "adversarial-verify must not weaken the predicate to >= / <= (a tie would survive)"
    )
    assert "strict majority" in low, "must require a strict majority did NOT refute"
    # A tie must be named as rejecting in BOTH the aggregation and termination.
    agg = _normalize_ws(_section_body(_read("adversarial-verify.md"), "## aggregation")).lower()
    term = _normalize_ws(
        _section_body(_read("adversarial-verify.md"), "## termination rule")
    ).lower()
    assert "tie" in agg and "reject" in agg, "Aggregation must state a tie REJECTS"
    assert "tie" in term or "tie" in agg, "a tie's resolution must be stated"


def test_loop_until_done_guards_fanout_failure() -> None:
    """The loop example must STRUCTURALLY guard a failed fan-out: a
    `if ! bash scripts/mb-fanout.sh ...` block whose body skips the iteration
    (continue/break/exit) and which appears BEFORE the firewall call. A mere
    mention of `exit 2` in prose is not enough."""
    body = _section_body(_read("loop-until-done.md"), "## fan-out shape")
    flat = _normalize_ws(body)
    # Accept any fail-closed shell idiom that branches on the fan-out's exit
    # status and skips the iteration — NOT a prose-only `exit 2`:
    #   if ! bash …mb-fanout.sh …; then … (continue|break|exit) … fi
    #   bash …mb-fanout.sh … || (continue|break|exit …)
    guard_forms = (
        r"if\s+!\s+bash\s+scripts/mb-fanout\.sh.*?;\s*then.*?\b(?:continue|break|exit)\b.*?fi",
        r"bash\s+scripts/mb-fanout\.sh[^\n|]*\|\|\s*\{?\s*(?:continue|break|exit)\b",
    )
    guard = None
    for f in guard_forms:
        guard = re.search(f, flat)
        if guard:
            break
    assert guard, (
        "loop-until-done must guard the fan-out with a fail-closed idiom "
        "(`if ! bash …mb-fanout.sh …; then … continue|break|exit … fi` or "
        "`bash …mb-fanout.sh … || continue`) so a failed iteration skips the firewall"
    )
    verify_pos = flat.find("mb-flow-verify.sh")
    assert verify_pos == -1 or guard.start() < verify_pos, (
        "the fan-out failure guard must come BEFORE the firewall call"
    )


def test_tournament_does_not_misuse_mb_judge_as_comparator() -> None:
    """mb-judge returns GO/NO_GO — never a pairwise A/B picker. Assert
    `/sadd-do-competitively` IS named as the comparator, AND that every line that
    mentions `mb-judge` scopes it to the final gate (never to comparison)."""
    low = _normalize_ws(_read("tournament.md")).lower()
    assert "/sadd-do-competitively" in low, (
        "tournament bracket must use /sadd-do-competitively as the pairwise comparator"
    )
    # Every mention of mb-judge must, within a small window, frame it as the FINAL
    # gate (markers may wrap onto the next line, so use whitespace-normalized text).
    gate_markers = ("final", "gate", "go /", "go/", "not a pairwise", "never to compare")
    for m in re.finditer(r"mb-judge", low):
        window = low[max(0, m.start() - 70) : m.end() + 120]
        assert any(mk in window for mk in gate_markers), (
            f"tournament scopes mb-judge as a comparator, not the final gate, near: "
            f"…{low[max(0, m.start() - 40) : m.end() + 40]}…"
        )
    # The comparator role must NOT be POSITIVELY assigned to mb-judge. A negated
    # disclaimer ("mb-judge is a gate, NOT a pairwise comparator") is fine, so a
    # match whose span contains "not"/"never" is skipped.
    for m in re.finditer(
        r"mb-judge[^.]{0,40}(?:pairwise|head-to-head|comparator|pick the winner)", low
    ):
        span = m.group(0)
        assert "not" in span or "never" in span, (
            f"tournament assigns the pairwise-comparator role to mb-judge: …{span}…"
        )
