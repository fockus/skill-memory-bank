---
type: closeout
tags: [graph-rag-lite, code-context, verification, cross-agent]
importance: high
created: 2026-05-21
---

# GraphRAG-lite closeout

## What was done
- Закрыт architecture plan `graph-rag-lite-code-context`: portable graph query CLI, `code_context` evidence pack, Pi native project extension wrapper, OpenCode/Codex/generic AGENTS.md fallback guidance.
- Review remediation выполнена: SRP blockers сняты через split core/render/helper modules; Bats ShellCheck SC2314 исправлен; documentation count updated.
- План перемещён в `plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md` после `/mb verify` PASS.

## New knowledge
- Portable CLI remains source of truth; native wrappers must stay thin delegators to avoid cross-agent drift.
- SRP checks need to include newly extracted helper modules in tests/docs, otherwise `tdd/delta` and doc-count contracts catch the drift.
- Broad `shellcheck scripts/*.sh adapters/*.sh hooks/*.sh` still has legacy noise; use scoped `shellcheck -x -P scripts -P adapters ...` for GraphRAG verification until broader cleanup is planned.

## Verification
- `mb-rules-check`: `violations=[]`.
- Focused pytest: `40 passed`.
- Bats adapter/rules: `17 ok`; install/uninstall filter: `9 ok`.
- `ruff` and scoped `shellcheck`: clean.
- Full `mb-test-run`: `tests_pass=true`, `tests_total=708`.
