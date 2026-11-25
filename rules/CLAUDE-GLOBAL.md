## Memory Bank status line

Open the first reply with `[MEMORY BANK: ACTIVE]` if `mb_resolve_path` finds a local, `--storage=global` or legacy bank; otherwise `[MEMORY BANK: ABSENT]`. Use `[MEMORY BANK: INITIALIZED]` immediately after requested setup. Omit the line in later replies, subagent reports and machine output.

A globally installed skill never means this project has a bank; only an explicit `/mb init` creates one. Do not silently initialize Memory Bank for meta/install/debug questions.

### Rules-only mode

Without a bank, engineering rules still apply; `/mb` lifecycle commands stay inactive.

In Git, run `memory-bank rag status --auto-refresh` once per user session (or bundled `scripts/mb-rag.py status --auto-refresh`). Offer Qwen3 (recommended) or Perplexity if unconfigured. Use ready indexes; on ordinary stale, use fallback without waiting or asking. Ask before setup, a reported `memory-bank rag update`, or repair of broken assets.

Hookless: run `MB_AUTO_UPDATE=off bash ~/.claude/skills/memory-bank/hooks/mb-update-notify.sh` once. On a release notice, show both versions and its command in your next reply; offer to run it on request.

# Engineering rules

Edit Key rules with `/mb rules`. Details: `~/.claude/RULES.md`; project overrides: `RULES.md` or `.memory-bank/RULES.md`.

> **Language** — respond in English; technical terms may remain in English.

- Add dependencies only on request. Confirm destructive actions; record significant decisions in an ADR.
- Trivial/small: no plan. Standard+: `/mb plan` with SMART DoD (per stage only at a real boundary). Coverage per profile. See `SKILL.md` § Task routing.

## Memory Bank
- Start with `/mb context` (alias `/mb`); `/mb start` includes the active plan.
- For implementation, call `code_context` with the original question, an English paraphrase preserving identifiers, and `sourceOnly: true`. Read and cite verified lines. For structure: `mb-graph.sh who-calls|impact|tests <Symbol>`.
- `progress.md` is append-only; never reuse I-/EXP-/ADR-NNN IDs. Tick `checklist.md` on completion. `notes/` hold patterns.
- Shared checkout: `mb-coord.sh active` at start, before stages/commits and shared edits. ACK freezes, handovers and commit order in `COORDINATION.md` (`references/coordination.md`).
- Background agents: update `<bank>/orchestrator-console.md` (≤40 lines: questions, tracks, next step, decisions) at milestones before replying. After compaction read it, `mb-agree.sh list` tail, `mb-coord.sh active`, `mb-team.sh status` first. At boundaries offer `/compact` with what to keep. See `references/orchestrator-console.md`.
- Agreements: an explicit user decision → `mb-agree.sh add "<statement>"`, then announce `→ AGR-NNN записано: <statement>`; an unconfirmed idea → `mb-agree.sh question "<text>"`; a changed decision → `add "<new>" --supersedes N` — `references/agreements.md`.
