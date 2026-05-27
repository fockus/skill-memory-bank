
# CI baseline Wave 0 closeout

- `test.yml` on `main` is green again: run `26527319286` passed lint plus Ubuntu/macOS × Python 3.11/3.12 matrix.
- Last blockers were Linux-only pytest failures hidden locally by macOS grep behavior: GNU grep matched Cyrillic planning terms in historical Memory Bank data and required policy-reference surfaces.
- Fix pattern: keep the drift test strict for active product surfaces, but whitelist historical `.memory-bank/notes`, `.memory-bank/reports`, `.memory-bank/specs`, migration backups, localized RU templates, and the files that intentionally document legacy aliases.
- Local exact coverage command could not run because the current venv lacks `pytest-cov`; CI remains the authoritative coverage gate.
- Next session should choose between completing active Cursor remediation and starting W0.5 OpenCode-first infrastructure before W1 reviewer-v2.

