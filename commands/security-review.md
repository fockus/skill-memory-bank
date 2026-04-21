---
description: Scan code for security vulnerabilities (OWASP, secrets, dependencies)
allowed-tools: [Read, Glob, Grep, Bash]
---

# Security Review: $ARGUMENTS

## 1. Scope

- If `$ARGUMENTS` is provided, analyze the specified module/directory
- If not provided, analyze all changed files (`git diff --name-only`)

## 2. Automated analysis

Detect the stack and run the appropriate scanners:

### Go
```bash
gosec -quiet ./...
golangci-lint run --enable=gosec,errcheck,govet
```

### Python
```bash
bandit -r . -f txt -ll
safety check 2>/dev/null
```

### Node.js
```bash
npm audit 2>/dev/null
```

### Secret scanning
```bash
grep -rn --include="*.go" --include="*.py" --include="*.js" --include="*.ts" --include="*.yaml" --include="*.yml" --include="*.env*" \
  -E "(password|secret|api_key|token|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|sk_live_)" .
```

## 3. Manual analysis

Read each file in scope and check for:

- **Injection:** SQL, command, XSS, LDAP, template injection
- **Authentication:** weak passwords, missing rate limiting, credential storage issues
- **Authorization:** missing permission checks, IDOR, privilege escalation
- **Data Exposure:** secret logging, excessive API response data, stack traces in production
- **Configuration:** debug mode, `CORS *`, disabled HTTPS, default credentials
- **Dependencies:** known CVEs
- **Cryptography:** MD5/SHA1 for passwords, hardcoded keys, missing salt

## 4. OWASP Top 10 Checklist

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
