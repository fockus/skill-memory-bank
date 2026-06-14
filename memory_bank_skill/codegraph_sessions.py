"""Session→graph bridge for the Memory Bank code graph (opt-in via ``--sessions``).

Group B writes a per-session trace to ``<mb>/session/*.md`` (frontmatter + a
``## Live log`` of bullets, each carrying the request, tools, and the absolute
paths of files touched that turn). This module turns that work history into graph
structure so semantic search can answer work-history questions ("where did we fix
the token leak?"):

  * a ``session`` node per session that touched at least one graph module;
  * a ``worked_on`` edge from each session node to every touched module node,
    carrying a one-line work summary;
  * an append to each touched module node's ``doc`` (the embedding/BM25 corpus
    text), capped at the 3 most recent sessions per module.

Defense-in-depth privacy (REQ-026): ``graph.json`` is a committable artifact, so
EVERY session-derived string is passed through :func:`redact_secrets` (the same
high-precision vendor-prefix patterns as ``hooks/lib/redact.py`` /
``sc_redact_secrets``) AND has ``<private>…</private>`` spans stripped at
graph-write time — on top of capture-time redaction. A fake key never reaches
disk (Scenario 9).

Emitted rows are additive JSONL (same discipline as ``codegraph_cochange``):
``{"type":"node","kind":"session",...}`` and
``{"type":"edge","kind":"worked_on",...}``. Unknown row types are ignored by every
existing consumer, so the base build (no ``--sessions``) stays byte-identical.

Pure and fail-open: a missing ``session/`` dir, an unreadable file, or a session
without files-touched yields no rows and never raises.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# ── secret redaction (mirrors hooks/lib/redact.py :: redact_secrets) ──────────
# Kept in lockstep with ``sc_redact_secrets`` (hooks/lib/session-common.sh) and
# ``hooks/lib/redact.py``. High-precision (vendor prefixes / fixed token shapes)
# rather than entropy-based, to avoid mangling ordinary prose.
_REPLACEMENT = "[REDACTED]"

_PLAIN_PATTERNS = [
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),  # OpenAI/Anthropic/OpenRouter keys
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),  # GitHub tokens
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}"),  # GitHub fine-grained PATs
    re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),  # AWS access key IDs
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),  # Slack tokens
    re.compile(r"\bAIza[A-Za-z0-9_-]{30,}"),  # Google API keys
    re.compile(r"\bhf_[A-Za-z0-9]{30,}"),  # Hugging Face tokens
    re.compile(r"\bnpm_[A-Za-z0-9]{30,}"),  # npm publish tokens
    re.compile(r"\bpypi-[A-Za-z0-9_-]{20,}"),  # PyPI publish tokens
    re.compile(r"\beyJ[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_.+/=-]{5,}"),  # JWT
]
# Group 1 (the prefix) is kept; the token after it is replaced.
_PREFIXED_PATTERNS = [
    re.compile(r"\b([Bb]earer\s+)[A-Za-z0-9._~+/=-]{20,}"),
    re.compile(
        r"\b([A-Z0-9_]*(?:API_?KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Z0-9_]*\s*[=:]\s*)"
        r"['\"]?[^\s'\"]{8,}['\"]?"
    ),
]

_PRIVATE_CLOSED_RE = re.compile(r"<private>.*?</private>", re.DOTALL)
_PRIVATE_OPEN_RE = re.compile(r"<private>.*\Z", re.DOTALL)

_FRONTMATTER_RE = re.compile(r"^---\n.*?\n---\n", re.DOTALL)
# A Live-log bullet: ``- HH:MM — User: "<request>" · tools: ... · files: <csv>``
_BULLET_RE = re.compile(r'^- .*?— User: "(?P<req>.*?)" · tools: .*? · files: (?P<files>.*)$')
_STARTED_RE = re.compile(r"^started:\s*(?P<date>\S+)", re.MULTILINE)
_WHAT_CHANGED_RE = re.compile(
    r"^###\s+What changed\s*\n+(?P<body>.+?)(?:\n#|\n##|\Z)", re.DOTALL | re.MULTILINE
)

_SUMMARY_MAX = 160  # one-line summary cap (chars), after redaction
_DOC_CAP = 3  # most-recent sessions appended per module


def redact_secrets(text: str) -> str:
    """Replace recognizable API keys/tokens with ``[REDACTED]`` (mirror of redact.py)."""
    if not text:
        return text
    for pat in _PLAIN_PATTERNS:
        text = pat.sub(_REPLACEMENT, text)
    for pat in _PREFIXED_PATTERNS:
        text = pat.sub(r"\1" + _REPLACEMENT, text)
    return text


def strip_private(text: str) -> str:
    """Remove ``<private>…</private>`` spans (closed and unterminated-to-EOF)."""
    if not text:
        return text
    text = _PRIVATE_CLOSED_RE.sub("", text)
    text = _PRIVATE_OPEN_RE.sub("", text)
    return text


def _sanitize(text: str) -> str:
    """Strip ``<private>`` spans then redact secrets, collapsing inner whitespace."""
    cleaned = redact_secrets(strip_private(text))
    return re.sub(r"\s+", " ", cleaned).strip()


@dataclass
class SessionLayer:
    """Additive graph contribution from the session memory store.

    ``nodes`` / ``edges`` are JSONL-ready dicts (no ``type`` key — the writer
    stamps it). ``doc_appends`` maps a module file-rel to the ordered list of
    one-line summaries to append to that module node's ``doc`` (already capped).
    All strings are pre-redacted and ``<private>``-stripped.
    """

    nodes: list[dict[str, Any]] = field(default_factory=list)
    edges: list[dict[str, Any]] = field(default_factory=list)
    doc_appends: dict[str, list[str]] = field(default_factory=dict)


def _parse_session(text: str) -> tuple[str | None, list[str], list[str]]:
    """Parse one session file → ``(date, requests, abs_files)``.

    ``date`` is the frontmatter ``started`` value (or ``None``). ``requests`` is
    the ordered list of Live-log user requests (newest discipline preserved by
    file order). ``abs_files`` is the de-duplicated list of absolute file paths
    touched across all bullets, in first-seen order.
    """
    date_match = _STARTED_RE.search(text)
    date = date_match.group("date") if date_match else None

    body = _FRONTMATTER_RE.sub("", text, count=1)
    requests: list[str] = []
    abs_files: list[str] = []
    seen: set[str] = set()
    for line in body.splitlines():
        m = _BULLET_RE.match(line.strip())
        if not m:
            continue
        req = m.group("req").strip()
        if req:
            requests.append(req)
        files_csv = m.group("files").strip()
        # The modern Live-log bullet appends ` · <outcome> · <diffstat>` after the
        # files field; the file list is everything up to the first ` · ` (U+00B7)
        # separator — paths never contain it. Old-format bullets (no tail) are a no-op.
        files_csv = files_csv.split(" · ")[0].strip()
        if files_csv in ("", "(none)"):
            continue
        for raw in files_csv.split(","):
            f = raw.strip()
            if f and f not in seen:
                seen.add(f)
                abs_files.append(f)
    return date, requests, abs_files


def _summary_for(text: str, requests: list[str]) -> str:
    """One-line work summary: schema-v2 ``### What changed`` if present, else first request."""
    wc = _WHAT_CHANGED_RE.search(text)
    if wc:
        candidate = wc.group("body").strip().splitlines()[0] if wc.group("body").strip() else ""
    else:
        candidate = requests[0] if requests else ""
    summary = _sanitize(candidate)
    return summary[:_SUMMARY_MAX]


def _modules_touched(abs_files: list[str], modules: set[str]) -> list[str]:
    """Map absolute file paths to graph module file-rels by path-suffix match.

    A module ``pkg/alpha.py`` is touched when an absolute path equals it or ends
    with ``/pkg/alpha.py``. Returns the matched modules in first-seen order,
    de-duplicated. Longest module suffix wins per file (avoids ``a.py`` shadowing
    ``pkg/a.py``).
    """
    by_len = sorted(modules, key=len, reverse=True)
    out: list[str] = []
    seen: set[str] = set()
    for path in abs_files:
        posix = path.replace("\\", "/")
        for mod in by_len:
            if posix == mod or posix.endswith("/" + mod):
                if mod not in seen:
                    seen.add(mod)
                    out.append(mod)
                break
    return out


def extract_session_layer(mb_path: Path | str, modules: set[str]) -> SessionLayer:
    """Build the session graph layer from ``<mb>/session/*.md`` (pre-redacted).

    Sessions are processed in sorted filename order (chronological, since names
    are timestamp-prefixed). A session whose touched files map to no graph
    ``module`` is skipped entirely. ``doc_appends`` keeps the last ``_DOC_CAP``
    summaries per module. Fail-open: missing dir / unreadable file → empty layer.
    """
    layer = SessionLayer()
    if not modules:
        return layer
    sess_dir = Path(mb_path) / "session"
    if not sess_dir.is_dir():
        return layer

    for sess_file in sorted(sess_dir.glob("*.md")):
        try:
            text = sess_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        date, requests, abs_files = _parse_session(text)
        touched = _modules_touched(abs_files, modules)
        if not touched:
            continue  # no files-touched mapping to the graph → skip

        sid = sess_file.stem
        summary = _summary_for(text, requests)
        # ``name`` mirrors the id so graph analytics (pagerank/communities/
        # betweenness) that key on ``node["name"]`` treat session nodes uniformly.
        node: dict[str, Any] = {
            "kind": "session",
            "name": f"session:{sid}",
            "id": f"session:{sid}",
        }
        # REQ-026: the frontmatter date is session-derived too — strip <private>
        # spans AND redact secrets (full _sanitize, not redact-only), same as every
        # other string written into the committable graph.json.
        safe_date = _sanitize(date) if date else None
        if safe_date:
            node["date"] = safe_date
        layer.nodes.append(node)

        for mod in touched:
            layer.edges.append(
                {
                    "kind": "worked_on",
                    "src": f"session:{sid}",
                    "dst": mod,
                    "summary": summary,
                }
            )
            appends = layer.doc_appends.setdefault(mod, [])
            label = f"sessions: {summary} ({safe_date})" if safe_date else f"sessions: {summary}"
            appends.append(label)
            # Keep only the most recent _DOC_CAP appends (file order is chronological).
            if len(appends) > _DOC_CAP:
                del appends[0]
    return layer
