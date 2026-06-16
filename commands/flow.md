---
description: Select a route directly (skip classification) — the explicit override escape-hatch
allowed-tools: [Bash, Read]
---

# /mb flow

Explicitly select the flow route, skipping auto-classification. This is the
**escape-hatch** (REQ-DF-025), mirroring the `/mb work --workflow <name>`
precedent: auto-routing via `/mb analyze-task` is the default, and `/mb flow`
is the manual override when you already know the route.

```
/mb flow <route>          # e.g. /mb flow arch
/mb flow --route <route>  # equivalent flag form
```

`<route>` is one of: `bugfix | code-change | arch | migration | research`.

## What it does

1. Resolve the active Memory Bank (`scripts/_lib.sh::mb_resolve_path`).
2. **Skip classification** — there is no LLM step. Hand the named route straight
   to the resolver, which still applies the deterministic floor + writes the
   fence:

   ```bash
   SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # memory-bank skill bundle root
   bash "$SKILL_DIR/scripts/mb-flow-route.sh" --route <route>
   ```

3. Report the **resolved** route from the resolver's JSON. If `floor_triggered`
   is `true`, the override was raised to the floor — say so and name the
   `reasons`.

Add `--dry-run` to preview without writing the fence. The resolver derives the
changed-file scope from git on its own; pass `--changed`/`--changed-file` only
to drive it explicitly.

## The override does NOT bypass safety

Choosing a route here changes only the *starting candidate* — it does not
disable any guard:

- **Route-floor still applies (REQ-DF-022).** An override *below* the floor is
  raised to the floor, never honored blindly (REQ-DF-025). `/mb flow bugfix` on
  a diff that touches `domain/`, an `application/ports` path, a
  `*Protocol`/`ABC`/contract file, a declared `protected_path`, or a linked plan
  with `depends_on > 0` resolves to `arch`, not `bugfix`.
- **Firewall still applies (REQ-DF-040).** The done-gate is still
  `scripts/mb-flow-verify.sh`; the flow is never declared finished on red.

So the override can only *raise* a route or pick among routes at/above the
floor — it can never route *under* the deterministic floor.

## When to use auto-routing instead

Prefer `/mb analyze-task` (the default) and let the classifier pick. Reach for
`/mb flow <route>` only when you have a deliberate reason to fix the route — for
example forcing `research` for a pure spike, or pinning `arch` up front.

## Exit codes (resolver)

- `0` — route resolved (and written to the fence unless `--dry-run`).
- `1` — usage error / unknown route / bad bank (write target missing).
- `2` — internal error (the fence writer failed).
