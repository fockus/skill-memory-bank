# /mb consolidate — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `consolidate [--apply] [--days N]` — Fold sessions older than `N` days (default 30) that cluster by shared files / lexical overlap into 5–15 line `notes/` candidates, archive those session files VERBATIM → `session/archive/`, and move their contiguous auto-capture progress STUBS VERBATIM → `progress-archive.md`. Zero LLM calls. Dry-run is the DEFAULT (writes nothing — bank byte-identical); `--apply` performs it. Real progress entries are immutable and never move

### consolidate [--apply] [--days N]

Fold **old** session memory into durable form, **$0** (zero LLM calls). Sessions whose file mtime is
older than `N` days (default `30`, `MB_CONSOLIDATE_DAYS`) are clustered by shared files-touched or
lexical overlap; any cluster of ≥2 sessions that carries a recurring fact becomes a 5–15 line note
candidate under `notes/`. On `--apply` the command (a) writes the note candidate(s); (b) moves the
windowed session files **verbatim** (byte-for-byte `mv`) to `session/archive/`; (c) moves **only** the
contiguous auto-capture progress STUBS that belong to the archived sessions **verbatim** to
`progress-archive.md` (a byte-preserving splitter — real progress entries are immutable and never
move); (d) rebuilds `session/_recent.md`. Fewer than two windowed sessions, or nothing that clusters →
empty output, exit 0, no writes.

Dry-run is the **DEFAULT** — it prints the plan and writes nothing (the bank stays byte-identical);
pass `--apply` to perform it. Run directly (no subagent):

```bash
bash "$SKILL_DIR/scripts/mb-consolidate.sh" "${ARGS_AFTER_CONSOLIDATE[@]}"
```
