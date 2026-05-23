from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _line_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines())


def test_graph_rag_changed_sources_stay_below_srp_threshold() -> None:
    paths = [
        REPO_ROOT / "scripts" / "mb-graph-query.py",
        REPO_ROOT / "scripts" / "mb_graph_query_core.py",
        REPO_ROOT / "scripts" / "mb_graph_query_render.py",
        REPO_ROOT / "scripts" / "mb-code-context.py",
        REPO_ROOT / "scripts" / "mb_code_context_core.py",
        REPO_ROOT / "adapters" / "pi.sh",
        REPO_ROOT / "scripts" / "mb-rules-check.sh",
        REPO_ROOT / "scripts" / "mb_rules_check_lib.sh",
    ]

    offenders = {
        path.relative_to(REPO_ROOT).as_posix(): _line_count(path)
        for path in paths
        if _line_count(path) > 300
    }

    assert offenders == {}
