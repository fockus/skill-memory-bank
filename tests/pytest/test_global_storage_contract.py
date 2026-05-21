"""Cross-agent global-storage contract tests (Sprint 2 / Stage 1).

These tests scan production sources for hard-coded `<project>/.memory-bank/`
runtime paths and for global-prompt surfaces that omit the always-on quality
rules. Sprint 2 Stages 2-4 make the tests pass; here they are deliberately RED
to lock the requirement before implementation.

Whitelisting rules:
- Documentation strings (`.md` heredocs in adapters, comments) are ignored — they
  describe Memory Bank to humans, not perform runtime path resolution.
- Hooks that already implement multi-tier resolution (e.g.
  `mb-sprint-context-guard.sh`) are listed in `RESOLVER_AWARE_HOOKS` with the
  reason they are exempt.
- Tests for the local-mode default remain valid and are not flagged.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOKS_DIR = REPO_ROOT / "hooks"
ADAPTERS_DIR = REPO_ROOT / "adapters"
INSTALL_SH = REPO_ROOT / "install.sh"

# Hooks that already resolve MB path through tiered logic and are intentionally
# exempt from the literal-construction audit. Add a reason string so future
# readers understand why.
RESOLVER_AWARE_HOOKS: dict[str, str] = {
    "mb-sprint-context-guard.sh": (
        "uses MB_PATH env override + .claude-workspace + PWD/.memory-bank tiers"
    ),
}

# Pattern that *uses* the Memory Bank — i.e. the file performs runtime
# read/write on `<project>/.memory-bank/`. We only care about hooks that touch
# the bank at all; pure config hooks (e.g. dangerous-prompt blocker) are
# inherently MB-agnostic and don't need MB_PATH.
LITERAL_MB_RE = re.compile(
    r'"\$\{?(CWD|PWD|WORKSPACE|PROJECT_ROOT|_mb_repo)\}?/\.memory-bank"?'
)


# ---------------------------------------------------------------------------
# 1. Hook scripts must honour MB_PATH env override (global-storage contract).
# ---------------------------------------------------------------------------


def test_hook_scripts_resolve_mb_path_through_lib() -> None:
    """Every hook that touches Memory Bank state must honour MB_PATH override.

    The contract is structural: any hook that constructs a path containing
    `/.memory-bank` (in any form) must also reference `MB_PATH` somewhere —
    proof that the hook lets global-mode storage override the local default.
    Hooks that don't touch the bank (e.g. dangerous-prompt blockers) are
    naturally exempt because they never match `LITERAL_MB_RE`.
    """
    violations: list[str] = []
    for path in sorted(HOOKS_DIR.glob("*.sh")):
        if path.name in RESOLVER_AWARE_HOOKS:
            continue
        text = path.read_text(encoding="utf-8")
        # Strip comment-only lines so a `# .memory-bank/...` comment doesn't
        # falsely mark a hook as bank-touching.
        non_comment_text = "\n".join(
            line for line in text.splitlines() if not line.lstrip().startswith("#")
        )
        if not LITERAL_MB_RE.search(non_comment_text):
            # Hook never references local .memory-bank/ — not its problem.
            continue
        if "MB_PATH" not in non_comment_text:
            # Find the first offending line for a helpful error.
            for lineno, line in enumerate(text.splitlines(), start=1):
                if line.lstrip().startswith("#"):
                    continue
                if LITERAL_MB_RE.search(line):
                    violations.append(f"{path.name}:{lineno}: {line.strip()}")
                    break

    assert not violations, (
        "Hook scripts that touch Memory Bank must honour the MB_PATH env "
        "override (global-storage contract). Add a `MB_PATH` check before "
        "falling back to `$VAR/.memory-bank`. Offenders:\n  "
        + "\n  ".join(violations)
    )


# ---------------------------------------------------------------------------
# 2. OpenCode plugin JS must not hard-code local `.memory-bank` directory.
# ---------------------------------------------------------------------------


def test_opencode_plugin_does_not_hardcode_local_mb_path() -> None:
    """`adapters/opencode.sh` emits a JS plugin into `.opencode/plugins/`.

    The plugin must not call `path.join(app.path.cwd, '.memory-bank')` for
    runtime auto-capture — global storage mode places the bank under
    `~/.config/opencode/memory-bank/projects/<id>/.memory-bank`. The plugin
    must either receive an `MB_PATH` env or shell out to a resolver-aware
    helper bundled with the skill.
    """
    text = (ADAPTERS_DIR / "opencode.sh").read_text(encoding="utf-8")
    forbidden = "path.join(app.path.cwd, '.memory-bank')"
    assert forbidden not in text, (
        f"adapters/opencode.sh embedded plugin still contains hard-coded "
        f"{forbidden!r}. Replace with a call to a resolver-aware shell helper "
        "or honour an MB_PATH env injected by the host."
    )


# ---------------------------------------------------------------------------
# 3. git-hooks-fallback post-commit hook must resolve MB path.
# ---------------------------------------------------------------------------


def test_git_hooks_fallback_post_commit_resolves_mb_path() -> None:
    """post-commit hook generated by `adapters/git-hooks-fallback.sh` runs
    inside a git repo with no skill context — it must locate the bank via the
    same resolver (sourcing _lib.sh from the installed skill dir or honouring
    MB_PATH), not by hard-coding `<repo>/.memory-bank`.
    """
    text = (ADAPTERS_DIR / "git-hooks-fallback.sh").read_text(encoding="utf-8")
    # Extract the post-commit body (between the heredoc markers) to scope checks
    match = re.search(
        r"post_commit_body\(\)\s*\{\s*cat\s*<<'HOOK_EOF'(.*?)HOOK_EOF",
        text,
        re.DOTALL,
    )
    assert match, (
        "adapters/git-hooks-fallback.sh must define post_commit_body() with a "
        "HOOK_EOF heredoc — structure unexpectedly changed."
    )
    body = match.group(1)
    has_hardcode = '_mb_dir="$_mb_repo/.memory-bank"' in body
    has_resolver = "mb_resolve_path" in body or "MB_PATH" in body
    assert not has_hardcode or has_resolver, (
        "post-commit fallback hook still hard-codes `$_mb_repo/.memory-bank` "
        "without consulting the resolver. Add MB_PATH override + _lib.sh "
        "source so global-storage projects auto-capture correctly."
    )


# ---------------------------------------------------------------------------
# 4. Codex global AGENTS.md surface must embed critical engineering rules.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "rule_token",
    [
        "TDD",
        "SOLID",
        "Clean Architecture",
        "DRY",
        "KISS",
        "YAGNI",
        "[MEMORY BANK: ABSENT]",
    ],
)
def test_codex_global_agents_section_embeds_rules_only_baseline(
    rule_token: str,
) -> None:
    """`install.sh codex_agents_section` writes `~/.codex/AGENTS.md` for
    global Codex installs. Without project `.memory-bank/` Codex still runs
    under our skill — the section must therefore include the always-on quality
    rules (TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI) and the rules-only
    marker `[MEMORY BANK: ABSENT]`, so Codex respects the same baseline as
    Claude/Cursor/Pi.
    """
    text = INSTALL_SH.read_text(encoding="utf-8")
    # Scope to the codex_agents_section heredoc body.
    match = re.search(
        r"codex_agents_section\(\)\s*\{\s*cat\s*<<EOF(.*?)\nEOF",
        text,
        re.DOTALL,
    )
    assert match, (
        "install.sh codex_agents_section() definition not found — structure "
        "unexpectedly changed."
    )
    body = match.group(1)
    assert rule_token in body, (
        f"install.sh codex_agents_section() must mention {rule_token!r} so the "
        "global Codex AGENTS.md carries the always-on engineering baseline. "
        "Either inline the rules or sed-merge them from rules/CLAUDE-GLOBAL.md "
        "(see pi_agents_section() for a working pattern)."
    )


# ---------------------------------------------------------------------------
# 5. install.sh codex_agents_section must not hard-code only local
#    `.memory-bank/` workflow — global storage mode should be mentioned.
# ---------------------------------------------------------------------------


def test_codex_global_agents_section_mentions_storage_resolver() -> None:
    """In global mode the Codex bank is stored under
    `~/.codex/memory-bank/projects/<id>/.memory-bank`. The global AGENTS.md
    section must point at the resolver / storage modes, not at the literal
    `./.memory-bank/` only."""
    text = INSTALL_SH.read_text(encoding="utf-8")
    match = re.search(
        r"codex_agents_section\(\)\s*\{\s*cat\s*<<EOF(.*?)\nEOF",
        text,
        re.DOTALL,
    )
    assert match, "codex_agents_section() definition missing"
    body = match.group(1)
    has_resolver_mention = (
        "global storage" in body.lower()
        or "--storage" in body
        or "mb_resolve_path" in body
        or "MEMORY BANK: ABSENT" in body
    )
    assert has_resolver_mention, (
        "install.sh codex_agents_section() still describes only local "
        "`./.memory-bank/` workflow. Mention storage modes (local/global) or "
        "the rules-only ABSENT state so Codex users understand the full "
        "support matrix."
    )
