"""Shared foundations across /mb team tracks: the mechanisms registry, foundation detection, EXTRACT handovers.

Registry: `<bank>/shared-mechanisms.md`, a markdown table `| Mechanism | Home | Status | Keywords |`
(status `exists` or `being-extracted`, keywords comma-separated). A track prompt lists the rows relevant to
the track; the reviewer treats a second copy of a listed mechanism as a blocker.

Foundation detection: parallel tracks forbidden to touch each other's files each write their own copy of a
mechanism they all need. A signal named by ≥2 tracks — a shared path segment (`platform`, `shared`, `common`,
`kit`) in their globs or task text, a `<word> kit|boundary|client|registry` phrase, a registry row — is a
foundation group, blocking until one of the tracks is the foundation the others depend on, the registry row
says `exists`, or the orchestrator accepts the signal (`team plan --accept-shared <signal>`).
"""

from __future__ import annotations

import re
from pathlib import Path

import mb_team_state as st  # module attr: mb_team_state imports render, which imports this module

SHARED_DIRS = ("platform", "shared", "common", "kit")
PHRASE_RE = re.compile(r"\b([a-z][\w-]*)[\s-]+(kit|boundary|client|registry)\b", re.I)
PATH_RE = re.compile(r"(?:[\w.-]+/)+[\w.*-]*")
# Words before kit/boundary/client/registry that do not name a mechanism: articles, pronouns, prepositions,
# conjunctions and quantifiers ("send errors to client", "for each client").
NOT_A_QUALIFIER = frozenset(
    ["a", "an", "the", "this", "that", "these", "those", "its", "their", "our", "your", "my", "each", "every", "any", "all", "some", "no", "new", "one", "own", "same", "to", "for", "with", "and", "or", "per", "from", "by", "of", "in", "on", "into", "via", "as", "at", "over", "under", "through", "between"]
)
EXTRACT_RE = re.compile(r"^extract:\s*([\w./-]+)")


def load_registry(bank: str) -> list[dict]:
    path = Path(bank) / "shared-mechanisms.md"
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines() if path.is_file() else []:
        cells = [c.strip().strip("`") for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or not line.lstrip().startswith("|") or set(cells[0]) <= set("-: "):
            continue
        if cells[0].lower() == "mechanism":
            continue
        rows.append(
            {
                "mechanism": cells[0],
                "home": cells[1].rstrip("/"),
                "status": cells[2].lower(),
                "keywords": [
                    k.strip() for k in (cells[3] if len(cells) > 3 else "").split(",") if k.strip()
                ],
            }
        )
    return rows


def _named(row: dict, text: str) -> bool:
    """Mechanism name or a keyword as a whole word (`id` must not match `validate`)."""
    return any(re.search(rf"(?<![\w-]){re.escape(w)}(?![\w-])", text, re.I)
               for w in (row["mechanism"], *row["keywords"]))


def relevant(rows: list[dict], track: dict) -> list[dict]:
    """Rows the track's task names, or whose home lies under one of the track's globs."""
    return [
        r
        for r in rows
        if _named(r, track.get("task") or "")
        or any(st.globs_overlap(f"{r['home']}/**", g) for g in track.get("files") or [])
    ]


def _shared_prefix(path: str) -> str | None:
    parts = path.split("/")
    hit = next((i for i, p in enumerate(parts) if p in SHARED_DIRS), None)
    return "/".join(parts[: hit + 1]) if hit is not None else None


def signals(track: dict, rows: list[dict]) -> set[str]:
    text = track.get("task") or ""
    paths = [*(track.get("files") or []), *PATH_RE.findall(text)]
    out = {f"path:{p}" for p in map(_shared_prefix, paths) if p}
    out |= {
        f"word:{m.group(1).lower()}-{m.group(2).lower()}"
        for m in PHRASE_RE.finditer(text)
        if m.group(1).lower() not in NOT_A_QUALIFIER
    }
    return out | {f"mech:{r['mechanism']}" for r in rows if _named(r, text)}


def _closure(tracks: list[dict]) -> dict[str, set[str]]:
    deps = {t["id"]: set(t.get("deps") or []) for t in tracks}
    changed = True
    while changed:
        changed = False
        for ds in deps.values():
            more = set().union(*(deps.get(d, set()) for d in ds)) - ds
            if more:
                ds |= more
                changed = True
    return deps


def foundation_groups(team: dict, rows: list[dict]) -> list[dict]:
    tracks = [t for t in team["tracks"] if t["status"] != "cancelled"]
    by_signal: dict[str, list[str]] = {}
    for t in tracks:
        for s in sorted(signals(t, rows)):
            by_signal.setdefault(s, []).append(t["id"])
    accepted = set(team.get("accepted_shared") or [])
    existing = {f"mech:{r['mechanism']}" for r in rows if r["status"] == "exists"}
    closure = _closure(tracks)
    groups = []
    for s, ids in by_signal.items():
        if len(ids) < 2 or s in accepted or s in existing:
            continue
        # Resolved by a foundation: a member every other member depends on. A foundation track carries the
        # signal too (its task names the mechanism or it owns the shared path), so it is a member of the group.
        if any(all(f in closure[o] for o in ids if o != f) for f in ids):
            continue
        groups.append(
            {
                "signal": s,
                "tracks": ids,
                "suggest": f"add a foundation track that owns `{s.split(':', 1)[1]}` and add it to "
                f"--deps of {','.join(ids)}; or `plan --accept-shared {s}`",
            }
        )
    return groups


def blocking(team: dict, rows: list[dict]) -> list[str]:
    """Signals of foundation groups that still have a planned track (dispatch is the last chance)."""
    status = {t["id"]: t["status"] for t in team["tracks"]}
    return [
        g["signal"]
        for g in foundation_groups(team, rows)
        if any(status[i] == "planned" for i in g["tracks"])
    ]


def extract_actions(board: dict) -> list[str]:
    """`extract <track> <mechanism>` for every open `HANDOVER · <track>: extract:<mechanism>`."""
    out = []
    for e in board.get("open_handover") or []:
        m = EXTRACT_RE.match(e.get("title") or "")
        if m and e.get("track"):
            out.append(f"extract {e['track']} {m.group(1)}")
    return out


def prompt_section(rows: list[dict]) -> str:
    if not rows:
        return ""
    lines = ["## Shared mechanisms (registry — use, do not copy)"]
    for r in rows:
        if r["status"] == "exists":
            lines.append(
                f"- Use `{r['mechanism']}` from `{r['home']}`; do not copy it into your files."
            )
        else:
            lines.append(
                f"- `{r['mechanism']}` is being extracted to `{r['home']}`: do not write your own; if you "
                f"need it before it lands, run `mb-coord.sh append --type HANDOVER --track <id> --title "
                f"extract:{r['mechanism']}` and go on with the rest."
            )
    return "\n".join(lines) + "\n\n"
