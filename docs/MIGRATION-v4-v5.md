# Migration guide — v4.x → v5.0.0

v5.0.0 makes the **review stage opt-in** and the `/mb work` pipeline **composable
end-to-end**. The changes are **behavioral only** — there is no on-disk file
migration, no script to run, and existing `.memory-bank/` banks keep working
unchanged. If you never relied on review running automatically, upgrading is a
no-op.

> **Coming from PyPI 3.1.2?** 5.0.0 is the first published release since 3.1.2
> (4.0.0 was tagged but its PyPI publish failed and was never available). You
> also inherit everything in the [4.0.0] CHANGELOG section. This guide covers
> only the v4 → v5 breaking changes; nothing here requires a data migration.

---

## What changed (breaking)

### 1. Review is OFF by default

The default `/mb work` workflow is `execution` — `implement → verify → done` —
with **no reviewer**. The shipped `references/pipeline.default.yaml`
`stage_pipeline` no longer contains a `review` step.

**Before (v4):** the default per-item pipeline included a review step, so every
`/mb work` item ran the reviewer + severity gate.

**After (v5):** review is an opt-in stage. The review policy (severity gate,
max-cycles) now lives in a top-level `review:` block that ships `enabled: false`:

```yaml
# references/pipeline.default.yaml (excerpt)
stage_pipeline:
  - step: implement
  - step: verify
  - step: done

review:
  enabled: false            # ← review is opt-in
  severity_gate: { blocker: 0, major: 0, minor: 3 }
  max_cycles: 3
  on_max_cycles: stop_for_human
```

### 2. `mb-work-severity-gate.sh` PASSes when no review is configured

Previously the gate aborted with `exit 2 "no 'review' step in stage_pipeline"`
when there was no review step. It now resolves the gate from
`review:` block ▸ legacy `stage_pipeline[review]` ▸ active workflow
`loop.severity_gate`, and **PASSes as a no-op (`exit 0`)** when none of those is
configured. Behaviour is identical on the PyYAML and no-PyYAML paths.

### 3. `full` is now a first-class preset, not an alias

`workflow.aliases.full → full-cycle` is removed. `--workflow full` now resolves
to the complete 8-stage chain:

```
discuss → sdd → plan → implement → verify → review → judge → done
```

The previous 6-stage interactive flow is unchanged and still available as
`--workflow full-cycle`. A new `everything` alias points at `full`.

---

## New capability — composable pipeline

You can now compose the stage list three ways, in increasing precedence:

1. **Built-in default** — `execution` (`implement → verify → done`).
2. **`pipeline.yaml`** — `workflow.default: <preset>` plus per-stage
   `<stage>.enabled: true` toggles.
3. **Launch flags** (win over `pipeline.yaml`):

| Flag | Effect |
|---|---|
| `--workflow <preset>` | Select a preset (`full`, `governed-execution`, …). |
| `--review` / `--no-review` | Add / remove the single-reviewer stage. |
| `--judge` / `--no-judge` | Add / remove the independent judge (requires review). |
| `--brainstorm` / `--no-brainstorm` | Add / remove `discuss` (brainstorm = discuss). |
| `--sdd` / `--no-sdd` | Add / remove `sdd`. |
| `--plan` / `--no-plan` | Add / remove `plan`. |
| `--stages a,b,c` | Escape hatch — exact ordered list, overrides everything. |

Canonical order is fixed (`discuss → sdd → plan → implement → verify → review →
judge → done`); composition adds/removes stages but never reorders them, except
`--stages`. `--judge` without review, or `sdd`/`plan` with no topic/spec input,
**fails fast** before execution.

---

## How to migrate

| If you… | Do this |
|---|---|
| used the default `execution` flow (no review) | Nothing — you already match the v5 default. |
| relied on review running automatically | Add `--review` per run, or set `review.enabled: true` in your project `pipeline.yaml`. |
| want the heavyweight 5-reviewer ensemble | Use `--workflow governed-execution` (unchanged). |
| used `--workflow full` expecting the 6-stage flow | Switch to `--workflow full-cycle`; `full` now means the complete 8-stage chain. |
| scripted `mb-work-severity-gate.sh` and depended on the `exit 2` "no review" error | Expect `exit 0` (PASS no-op) instead; configure a `review:` block to enforce limits. |

### Restore the v4 "review in the default" behaviour

Edit your project `pipeline.yaml` (`/mb config init` if you don't have one):

```yaml
review:
  enabled: true             # run review on every /mb work item
```

…or pass `--review` per run:

```bash
/mb work my-feature --review
```

---

## Verify

```bash
# Composed stage list for a run (no review by default):
bash scripts/mb-workflow.sh --mb .memory-bank --steps
# → implement / verify / done

# With review opted in:
bash scripts/mb-workflow.sh --mb .memory-bank --review --steps
# → implement / verify / review / done

# Validate a composed chain before running it:
bash scripts/mb-pipeline-validate.sh --stages implement,verify,review,judge,done
```

---

## See also

- `commands/work.md` — `/mb work` reference (flags, precedence, presets).
- `references/pipeline.default.yaml` — the shipped default + opt-in `review:` block.
- `CHANGELOG.md#500--2026-06-10` — complete change list.
- `.memory-bank/specs/composable-work-pipeline/` — the SDD spec this feature was built from.
