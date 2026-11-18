# /mb groom — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `groom <topic>` (also `grooming`) — Critical grooming session for any task/idea at any stage: challenge necessity + approach, cover white spots, propose solutions. Summary → `context/<topic>-groom.md`; confirmed decisions routed to `agreements.md` (AGR) / `adr.md` (ADR) / backlog `## Ideas`; proposes next steps (spec/plan). No EARS. See `commands/groom.md`.

### groom <topic>

Critical grooming session — **not** a spec-producing interview. Dispatch to `commands/groom.md` for the canonical workflow. Accept both spellings: `groom` and `grooming`.

Summary: challenge whether the task should be done at all and how, propose own solutions with trade-offs, cover white spots (grilling rules from `commands/discuss.md` apply; no EARS, no fixed phases). Output: `context/<topic>-groom.md` (same folder as discuss); confirmed decisions → `mb-agree.sh add` (AGR-NNN) / `mb-adr.sh` (ADR) / `mb-idea.sh` (I-NNN); hypotheses → `mb-agree.sh question`; finish by proposing next steps (`/mb sdd`, `/mb plan`, amend existing spec, or stop).
