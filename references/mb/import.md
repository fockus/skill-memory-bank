# /mb import — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `import --project <path> [--since YYYY-MM-DD] [--apply]` — Bootstrap MB from Claude Code JSONL (`~/.claude/projects/<slug>/*.jsonl`). Extracts `progress.md` (daily), `notes/` (architecture-discussion heuristic), PII auto-wrap. Dedup via SHA256 + resume state

### import --project  [--since YYYY-MM-DD] [--apply]

Bootstrap Memory Bank from Claude Code JSONL transcripts. Cold-start in seconds instead of weeks of manual reconstruction.

**Source:** `~/.claude/projects/<slug>/*.jsonl` — Claude Code stores all session transcripts there. The slug is derived from project paths (for example `-Users-fockus-Apps-X` for `/Users/fockus/Apps/X`).

**Extract strategy:**

- `progress.md` — daily-grouped `## YYYY-MM-DD (imported)` sections with a summary (N user turns + M assistant replies + the first 120 chars of the first user prompt)
- `notes/` — heuristic architectural discussions: ≥3 consecutive assistant messages >1K chars → note `YYYY-MM-DD_NN_<topic-slug>.md` with frontmatter `importance: medium`, tags `[imported, discussion]`, body = compressed first + last message

**Safety:**

- `--dry-run` (default) — stdout summary (jsonls/events/days/notes counts), 0 file changes
- `--apply` — performs writes + touches `.memory-bank/.import-state.json`
- **Dedup:** SHA256(timestamp + first 500 chars of text) persisted in state — two consecutive runs are idempotent
- **PII auto-wrap:** email + API key (`sk-...`, `sk-ant-...`, `Bearer <long>`, `gh[pousr]_<long>`) regex → `<private>...</private>`. This intersects with Stage 3 so imported data is protected from leaking into `index.json` / search
- **Resume:** `.import-state.json` stores `seen_hashes` — repeated imports skip already-seen events
- **Broken JSONL line:** skip with warning; continue parsing the rest

Run directly:

```bash
python3 ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-import.py $ARGS_AFTER_IMPORT
```

**Typical cold-start flow:**

```
User: /mb import --project ~/.claude/projects/-Users-fockus-Apps-myproject/ --since 2026-03-01
→ dry-run output:
  jsonls=5
  events=342
  days=18
  notes=12
  mode=dry-run

User: /mb import --project ~/.claude/projects/-Users-fockus-Apps-myproject/ --since 2026-03-01 --apply
→ writes progress.md (18 daily sections) + 12 notes → state saved
  jsonls=5 events=342 days=18 notes=12 mode=apply
```

**Limitations in v2.2:**

- Summarization is currently deterministic (first+last chars), not LLM-based. Haiku-powered compression is backlog for v2.3+ if summary quality proves insufficient
- Debug-session detection for `lessons.md` — TODO (v2.2+)
- `status.md` seed — manual only
