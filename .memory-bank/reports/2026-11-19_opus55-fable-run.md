# Opus 5.5 / Fable acceptance run — master-completion Stage 13 (2026-11-19)

Both runs used the split router (`commands/mb.md` ~12 KB + `references/mb/*.md`) and the `## Graph` push block,
executed as real `/mb work` items through `/mb team` (implementer → reviewer).

| | H1 — Fable | H2 — Opus 5.5 |
|---|---|---|
| Item | I-294 J-1: symlinked default checkpoint dir refused | duplicate `I-NNN` lint in `mb-bank-lint` |
| Implementer tokens / tool calls / wall time | ~49k / 11 / 207 s | ~50k / 20 / 125 s |
| Graph queries / grep sweeps | 5 / 1 | 3 / 1 |
| Test first (red → green) | yes | yes |
| Review (Opus reviewer) | 0 blocker/major/medium, 2 minor | 0 blocker/major/medium, 3 minor |

Both models followed the router (loaded only the matched reference file) and used the graph before grep.
Fable used fewer tool calls and more wall time; Opus the reverse. Neither needed a fix cycle.

## Claude Code upgrade check
A same-HOME upgrade (working tree over an installed HEAD, same checkout) exits 0 and the alias and VERSION
follow the upgrade (reports/master-completion-wave1/upgrade-debug.md, run E2). The temp-HOME repro found a
real bug (rollback copy chown EPERM when the file group is foreign, e.g. HOME under /tmp on macOS) — fixed in
b5a621d; the temp-HOME "manifest HOME does not match" refusal was the repro using the real checkout's
manifest, intended behaviour (follow-ups I-300).

No version bump or tag (AGR-084); CHANGELOG Unreleased updated.
