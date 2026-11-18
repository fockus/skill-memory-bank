# /mb wiki — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:?Set SKILL_DIR from the loaded skill path}}"
```

## Router entries

- `wiki [--dry-run] [src_root]` — **Opt-in LLM layer** (see `### wiki` below). Codebase wiki (one article per community, Haiku) + "surprising connection" `semantic` edges the static graph misses (Sonnet), via host subagents — no API key. Deterministic prep in `scripts/mb-wiki.py`. Default `/mb graph` untouched

### wiki [--dry-run] [src_root]

**Opt-in LLM layer** over the deterministic graph — never runs implicitly. Builds a
per-community codebase wiki and discovers **surprising connections** (semantic links
the static import/call/inherit graph misses) using **host subagents**: no API key,
cost only the subagent calls. Default `/mb graph` output is untouched.

Model tiering: **Haiku** writes per-community articles (cheap, parallel); **Sonnet**
synthesizes cross-cutting connections (one pass). All deterministic prep is in the
tested `scripts/mb-wiki.py`; the LLM steps dispatch subagents via the `Agent` tool.

**Pipeline:**

1. Ensure graph + communities: `mb-codegraph.py --apply .memory-bank .` (communities
   need `networkx`; absent → tell the user to run `MB_SEMANTIC_VENV="$HOME/.claude/hooks/.venv" bash "$SKILL_DIR"/hooks/mb-semantic-bootstrap.sh` and stop).
2. `mb-wiki.py packs .memory-bank .` → writes `codebase/.wiki-packs.json` (per-community
   files / key symbols / code excerpts).
3. `mb-wiki.py plan --json .memory-bank .` → dispatch plan (Haiku count + 1 Sonnet).
   **If `--dry-run`: STOP here and show the plan.**
4. For each pack, dispatch a **Haiku** subagent (parallel, one message) with the prompt
   from `agents/mb-wiki-author.md` + the pack JSON. Write each article:
   `mb-wiki.py write-article --id <N> .memory-bank < article.md`.
5. One **Sonnet** subagent with `agents/mb-wiki-synthesizer.md` over all articles+packs
   → strict-JSON edges. Merge: `mb-wiki.py merge-edges --edges edges.json .memory-bank`
   (validated, confidence-clamped, **idempotent**).
6. `mb-wiki.py index .memory-bank` → `codebase/wiki/index.md`.

**Outputs:** `codebase/wiki/community-<N>.md` + `index.md`; `graph.json` gains
`{"kind":"semantic","confidence":x,"rationale":...}` edges. The wiki articles also
feed semantic search.

**Semantic search** (companion tool, not a `/mb` subcommand): `bash "$SKILL_DIR"/scripts/mb-graph.sh search
"<query>" [--source-only] [--k N]`, a front for `scripts/mb-semantic-search.py "<query>" [mb_path]
[--backend auto|bm25|embeddings]`. Default backend
`auto` = local `fastembed` **embeddings** when installed (best for concept/synonym
queries), else pure-Python **BM25** ($0, zero deps, deterministic — best for exact identifiers),
over graph symbols + wiki articles. `--source-only` drops test/spec files (filtered after
retrieval, so it shares the one cached matrix). Queries reuse the vector matrix under
`.memory-bank/.index/codesearch/` warmed by `/mb graph --apply` — the CLI re-execs itself under
the interpreter that carries `fastembed`, so a plain `python3` reaches it; a cold index answers
from BM25 and warms itself in the background. Build with `/mb graph --apply --docs` to index
docstrings+signatures. Use it for "where is the logic for X?" — it complements the structural
`graph_*` queries.

**Safety:** `--dry-run` stops after the plan; idempotent re-runs; 0 communities → no-op
with a clear message.
