---
description: Scan code for security vulnerabilities (OWASP, secrets, dependencies)
allowed-tools: [Read, Glob, Grep, Bash]
argument-hint: [scope-path]
---

# Security Review: $ARGUMENTS

## 0. Scope

- If `$ARGUMENTS` is provided, analyze the specified module / directory.
- If empty, analyze changed files from `git diff --name-only` + `git diff --staged --name-only`.

## 1. Stack detection

```bash
eval "$(bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh)"
# Exposes: stack, test_cmd, lint_cmd, src_count
```

If `stack=unknown`, ask the user which stack(s) to scan before proceeding. Do not assume.

## 2. Automated analysis per stack

Run the scanners that match `$stack`. For `multi`, run each applicable set. All tools are optional — skip with a warning if a binary is missing.

### Go
```bash
gosec -quiet ./... 2>/dev/null
golangci-lint run --enable=gosec,errcheck,govet 2>/dev/null
govulncheck ./... 2>/dev/null
```

### Python
```bash
bandit -r . -f txt -ll 2>/dev/null
pip-audit 2>/dev/null || safety check 2>/dev/null
```

### Node.js / TypeScript
```bash
npm audit 2>/dev/null || pnpm audit 2>/dev/null || yarn audit 2>/dev/null
npx eslint-plugin-security . 2>/dev/null
```

### Rust
```bash
cargo audit 2>/dev/null
cargo clippy -- -W clippy::suspicious 2>/dev/null
```

### Java / Kotlin
```bash
# Prefer trivy for fast filesystem scan
trivy fs . --scanners vuln,misconfig,secret 2>/dev/null
# Or OWASP dependency-check if configured
dependency-check --project "$(basename $PWD)" --scan . 2>/dev/null
```

### Ruby
```bash
brakeman --quiet 2>/dev/null
bundle-audit check --update 2>/dev/null
```

### .NET
```bash
dotnet list package --vulnerable --include-transitive 2>/dev/null
```

### Secret scanning (stack-agnostic)

Prefer `trufflehog` or `gitleaks` when installed — they understand entropy, known-key shapes, and git history. Fall back to grep only if neither is available.

```bash
# Preferred:
trufflehog filesystem --no-verification --only-verified=false . 2>/dev/null
gitleaks detect --no-banner 2>/dev/null

# Fallback grep (less accurate):
grep -rn --include="*.go" --include="*.py" --include="*.js" --include="*.ts" \
  --include="*.rs" --include="*.java" --include="*.kt" --include="*.rb" \
  --include="*.cs" --include="*.yaml" --include="*.yml" --include="*.env*" \
  -E "(password|secret|api_key|token|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|sk_live_|sk-ant-)" .
```

## 3. Manual analysis

Read each in-scope file and check:

- **Injection:** SQL, command, XSS, LDAP, template injection
- **Authentication:** weak passwords, missing rate limiting, credential storage issues
- **Authorization:** missing permission checks, IDOR, privilege escalation
- **Data Exposure:** secret logging, excessive API response data, stack traces in production
- **Configuration:** debug mode, `CORS *`, disabled HTTPS, default credentials
- **Dependencies:** known CVEs (surfaced by the automated scanners above)
- **Cryptography:** MD5/SHA1 for passwords, hardcoded keys, missing salt, weak random

## 4. OWASP Top 10 checklist

- [ ] A01 — Broken Access Control
- [ ] A02 — Cryptographic Failures
- [ ] A03 — Injection
- [ ] A04 — Insecure Design
- [ ] A05 — Security Misconfiguration
- [ ] A06 — Vulnerable and Outdated Components
- [ ] A07 — Identification and Authentication Failures
- [ ] A08 — Software and Data Integrity Failures
- [ ] A09 — Security Logging and Monitoring Failures
- [ ] A10 — Server-Side Request Forgery

## 5. Report

```markdown
# Security Review Report
Date: YYYY-MM-DD HH:MM
Stack: <stack>
Scope: <what was reviewed>

## Critical (release-blocking)
- [file:line] <vulnerability> — <recommendation>

## High risk
- [file:line] <description> — <recommendation>

## Medium risk
- [file:line] <description> — <recommendation>

## Low risk
- [file:line] <description> — <recommendation>

## Dependencies
- <package@version>: <CVE>

## Summary
<1-3 sentences: overall assessment, major risks>
```

If `./.memory-bank/` exists, save the report to `./.memory-bank/reports/YYYY-MM-DD_security-review.md`.
