# Contributing to memory-bank-skill

Thanks for your interest in improving `memory-bank-skill`. This document explains how to contribute efficiently.

---

## Ways to contribute

- **Bug reports** — open a GitHub Issue using the Bug Report template.
- **Feature requests** — open a GitHub Issue using the Feature Request template.
- **Pull requests** — see the workflow below.
- **Docs** — typo fixes, clarifications, new examples. Small PRs are welcome.
- **New AI-client adapters** — see [docs/cross-agent-setup.md](docs/cross-agent-setup.md) for the adapter contract.

---

## Development setup

```bash
git clone https://github.com/fockus/skill-memory-bank.git
cd skill-memory-bank

# install dev deps + local package + codegraph extras (required for tree-sitter tests)
python3 -m pip install -e ".[codegraph,dev]"

# install bats for shell tests (macOS)
brew install bats-core

# eat your own dog food — the skill installs itself
./install.sh
```

Verify everything works:

```bash
bats tests/bats/
bats tests/e2e/
python3 -m pytest tests/pytest/ --cov --cov-fail-under=85
shellcheck -x --source-path=SCRIPTDIR scripts/*.sh
shellcheck hooks/*.sh
ruff check settings/ tests/pytest/
```

All four commands must return green before you open a PR.

---

## Code standards

Followed everywhere in the repo — the skill enforces these same rules on user projects:

| Area | Rule |
|---|---|
| **TDD** | Write a failing test first, then the minimal code to pass it. No untested code in PRs. |
| **Clean Architecture** | Infrastructure → Application → Domain, never the reverse. |
| **SOLID / DRY / KISS / YAGNI** | Apply consistently. If in doubt, keep it simple. |
| **Coverage** | 85% overall (enforced by CI). 95% for domain/core logic. |
| **Commits** | Conventional Commits: `feat:`, `fix:`, `ci:`, `docs:`, `test:`, `refactor:`. |
| **No emojis** | Unless explicitly requested by the user in an issue. |
| **Comments** | Explain *why*, not *what*. Redundant narration is deleted on review. |

Details: [rules/RULES.md](rules/RULES.md) (the same file the skill installs into user projects).

---

## Pull request workflow

1. **Fork** the repo and create a feature branch from `main`:
   ```bash
   git checkout -b fix/backup-idempotency
   ```

2. **Write a plan** (optional but recommended for non-trivial work):
   ```bash
   /mb plan fix backup-idempotency
   ```
   Commit the plan file — it documents intent for reviewers.

3. **Red → Green → Refactor:**
   - Add failing tests first. Run them. Confirm they fail for the right reason.
   - Implement the minimum to make them pass.
   - Refactor only after green.

4. **Run the full local test envelope** (see Development setup).

5. **Commit** using Conventional Commits. Example:
   ```
   fix(install): prevent stale backup entries in manifest

   filter backups[] to retain only existing paths, preventing
   uninstall from trying to restore deleted backup files.

   Verified: tests/e2e/test_install_idempotent.bats → 5/5 green.
   ```

6. **Open a PR** using the PR template. Link any related issues.

7. **CI must pass** on Python 3.11 + 3.12 × ubuntu-latest + macos-latest.

8. **Reviews:** expect one round of feedback. Prefer small, focused PRs over large ones.

---

## Tests layout

```
tests/
├── bats/                # fast shell-level unit tests
├── e2e/                 # end-to-end install/uninstall, cross-agent
└── pytest/              # Python unit + integration tests
    ├── test_cli.py
    ├── test_codegraph.py          # Python-only codegraph path
    ├── test_codegraph_ts.py       # tree-sitter extras (skipped without [codegraph])
    ├── test_import.py
    ├── test_index_json.py
    ├── test_merge_hooks.py
    └── test_runtime_contract.py
```

When adding tests:
- **One test = one behavior.** AAA structure (Arrange → Act → Assert).
- **Name:** `test_<what>_<when>_<expected>` — e.g. `test_backup_skipped_when_content_matches`.
- **Assert business facts**, not truthiness. Prefer `assert backup_count == 0` over `assert backups is not None`.
- **Parametrize** variations, don't copy-paste.
- **Mock external boundaries only** (network, LLM, OS). Never mock the code under test.

---

## Release process

Reserved for maintainers. See [docs/release-process.md](docs/release-process.md) for the tag-driven PyPI + Homebrew pipeline.

---

## Code of Conduct

By participating, you agree to uphold our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree your contributions will be licensed under the project's [MIT License](LICENSE).
