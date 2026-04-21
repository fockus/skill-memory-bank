# Security Policy

## Supported Versions

| Version | Supported           |
| ------- | ------------------- |
| 3.0.x   | ✅ Actively maintained |
| 2.x     | ⚠️ Critical fixes only (until 2026-10-01) |
| 1.x     | ❌ End of life      |
| < 1.0   | ❌ End of life      |

## Reporting a Vulnerability

**Please do not open a public GitHub Issue for security vulnerabilities.**

Instead, report privately via one of:

1. **GitHub Security Advisories** (preferred):
   → https://github.com/fockus/skill-memory-bank/security/advisories/new

2. **Email:** open a draft Security Advisory on GitHub — this is the canonical channel.

Include:
- A clear description of the vulnerability.
- Minimal reproduction steps or a PoC.
- Affected versions (e.g. `3.0.0`, `3.0.0-rc1`).
- Your assessment of impact (arbitrary file write, code execution, secret exposure, etc.).

## Response timeline

- **Acknowledgment:** within 72 hours of receipt.
- **Triage & severity classification:** within 5 business days.
- **Fix timeline** (from confirmed severity):
  - Critical / High: patch release within 7 days.
  - Medium: patch release within 30 days.
  - Low: addressed in the next minor release.

## Scope

In scope:
- `install.sh` / `uninstall.sh` — anything that writes to `$HOME` or user projects.
- `memory_bank_skill/` Python package.
- All `adapters/*.sh` cross-agent installers.
- All `hooks/*.sh` and `scripts/*.sh`.
- GitHub Actions workflows (`.github/workflows/*.yml`).

Out of scope (but still welcome as GitHub Issues):
- Vulnerabilities in upstream dependencies (report to the dependency itself).
- Vulnerabilities in user projects that install this skill — we can't audit arbitrary codebases.
- Attacks that require a pre-existing foothold on the user's machine.

## Disclosure policy

We follow **coordinated disclosure**:
1. Reporter and maintainer agree on a patch and disclosure timeline.
2. Maintainer releases a patched version on PyPI + Homebrew.
3. Public advisory is published **with CVE** if applicable.
4. Credit is given to the reporter unless anonymity is requested.

## Known security-relevant design decisions

- `install.sh` uses a marker pattern (`<!-- memory-bank:start/end -->`) to merge into user files idempotently; it never silently overwrites existing content.
- Backups (`.pre-mb-backup.<timestamp>`) are created only when content differs — see FAQ in README.
- Uninstall removes only manifested files after canonical path validation; user content between markers is preserved.
- Project-local `.memory-bank/metrics.sh` overrides are blocked by default and run only with explicit `MB_ALLOW_METRICS_OVERRIDE=1` opt-in.
- Pi native skill mode is not part of the supported default install surface; it remains behind `MB_EXPERIMENTAL_PI_SKILL=1` while the upstream API is unstable.
- The skill does not make network calls at runtime (neither `install.sh` nor the Python CLI).
- No telemetry. No analytics. No opt-in / opt-out to discuss.
