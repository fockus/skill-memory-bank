# Security Audit Report — memory-bank-skill Repository

**Audit Date:** 2026-04-21  
**Scope:** Full repository (`/Users/fockus/Apps/claude-skill-memory-bank`)  
**Files Reviewed:** 45+ shell scripts, Python modules, adapters, hooks, and configuration files  
**Auditor:** OpenCode Security Review  

---

## Executive Summary

The **memory-bank-skill** repository is a well-structured dev-toolkit with generally good security hygiene. No **Critical** vulnerabilities were identified. However, **two High-severity** and **six Medium-severity** issues were found, primarily related to:

1. **Path traversal** in uninstall logic and `.claude-workspace` resolution
2. **Manifest poisoning** enabling arbitrary file deletion
3. **Arbitrary code execution** via intentional but unvalidated override mechanisms
4. **Backup retention** leaks of potentially sensitive migration data

The codebase demonstrates positive patterns: atomic file writes in Python, PII redaction for search/indexing, dangerous-command blocking hooks, and absence of hardcoded secrets.

---

## Findings Summary

| # | Severity | Category | File | Description |
|---|----------|----------|------|-------------|
| 1 | **High** | Path Traversal | `uninstall.sh` | Manifest-based `rm -rf` bypasses prefix validation with traversal sequences |
| 2 | **High** | Path Traversal | `scripts/_lib.sh` | `.claude-workspace` `project_id` is unsanitized, redirecting all MB ops |
| 3 | **High** | Arbitrary File Deletion | `adapters/pi.sh` | `uninstall_skill_mode` runs `rm -rf` on manifest-controlled path |
| 4 | **Medium** | Symlink Attack | `install.sh` | `backup_if_exists` follows symlinks, enabling arbitrary overwrites |
| 5 | **Medium** | Arbitrary Code Execution | `scripts/mb-metrics.sh` | Auto-executes `.memory-bank/metrics.sh` if present |
| 6 | **Medium** | Data Exposure | `hooks/file-change-log.sh` | File paths logged to predictable location; racy rotation |
| 7 | **Medium** | Sensitive Data Retention | `scripts/mb-import.py` | JSONL transcripts may contain secrets beyond PII regex scope |
| 8 | **Medium** | Backup Leak | `scripts/mb-migrate-structure.sh` | Migration backups in `.pre-migrate/` never auto-purged |
| 9 | **Low** | Race Condition | `hooks/file-change-log.sh` | Non-atomic log rotation may lose/corrupt entries |
| 10 | **Low** | Backup Leak | `adapters/git-hooks-fallback.sh` | Hook backups persist in `.git/hooks/` if uninstall skipped |

---

## Detailed Findings

### 1. HIGH — uninstall.sh Path Traversal via Manifest Poisoning

- **File:** `uninstall.sh`
- **Lines:** 32–63
- **Severity:** High
- **Description:**
  The uninstaller reads file paths from `.installed-manifest.json` and performs prefix checks:
  ```bash
  case "$filepath" in
    "$HOME/.claude/"*) rm -rf "$filepath" && echo "  rm $filepath" ;;
  ```
  Bash `case` prefix matching is vulnerable to **directory traversal sequences embedded in the path**. A manifest entry like:
  ```json
  "/home/user/.claude/../../etc/passwd"
  ```
  starts with `/home/user/.claude/` and therefore passes the prefix check, causing `rm -rf /etc/passwd` to execute.
- **Exploit Scenario:**
  An attacker with write access to `.installed-manifest.json` (or who tricks the user into installing from a poisoned manifest) can delete arbitrary files or directories owned by the user.
- **Recommendation:**
  Resolve and canonicalize paths before validation:
  ```bash
  resolved=$(realpath -m "$filepath" 2>/dev/null || readlink -f "$filepath" 2>/dev/null || echo "$filepath")
  case "$resolved" in
    "$HOME/.claude/"*|"$HOME/.codex/"*|"$HOME/.cursor/"*|"$HOME/.config/opencode/"*) ... ;;
    *) echo "  [SKIP] $resolved (outside managed dirs)" ;;
  esac
  ```
  Additionally, verify the resolved path is still within the expected directory subtree.

---

### 2. HIGH — scripts/_lib.sh Path Traversal via .claude-workspace

- **File:** `scripts/_lib.sh`
- **Lines:** 12–31
- **Severity:** High
- **Description:**
  The `mb_resolve_path()` helper reads `project_id` from `.claude-workspace` without sanitization:
  ```bash
  project_id=$(grep '^project_id:' .claude-workspace 2>/dev/null | awk '{print $2}' | tr -d '"' || true)
  if [ -n "$project_id" ]; then
    printf '%s\n' "$HOME/.claude/workspaces/$project_id/.memory-bank"
  ```
  A malicious `.claude-workspace` file in the working directory (e.g., `project_id: ../../../etc`) redirects **all** memory-bank scripts (`mb-note.sh`, `mb-compact.sh`, `mb-search.sh`, etc.) to operate outside the intended directory.
- **Exploit Scenario:**
  An attacker places a crafted `.claude-workspace` in a shared project. When the victim runs `mb-note.sh "foo"`, the note is written to `/etc/.memory-bank/notes/...` (if writable), or `mb-compact.sh --apply` archives files from arbitrary locations and deletes them.
- **Recommendation:**
  Sanitize `project_id` to allow only `[a-zA-Z0-9_-]+`:
  ```bash
  project_id=$(printf '%s' "$project_id" | tr -cd 'a-zA-Z0-9_-')
  ```
  Additionally, resolve the final path and verify it resides under `$HOME/.claude/workspaces/`.

---

### 3. HIGH — adapters/pi.sh Arbitrary File Deletion via Manifest

- **File:** `adapters/pi.sh`
- **Lines:** 88–96
- **Severity:** High
- **Description:**
  The `uninstall_skill_mode` function reads `pi_skill_dir` from `.mb-pi-manifest.json` and executes `rm -rf` without validation:
  ```bash
  skill_path=$(jq -r '.pi_skill_dir' "$MANIFEST")
  [ -n "$skill_path" ] && [ -d "$skill_path" ] && rm -rf "$skill_path"
  ```
  If the manifest is tampered with (e.g., `"pi_skill_dir": "/home/user"`), the uninstaller recursively deletes the user's home directory.
- **Exploit Scenario:**
  A malicious manifest placed before uninstall causes catastrophic data loss.
- **Recommendation:**
  Validate that `skill_path` is exactly `~/.pi/skills/memory-bank` or resolve and verify it is a subdirectory of `~/.pi/skills/`.

---

### 4. MEDIUM — install.sh Symlink Attack in backup_if_exists

- **File:** `install.sh`
- **Lines:** 287–312
- **Severity:** Medium
- **Description:**
  `backup_if_exists` checks if a target exists and moves it to a backup path:
  ```bash
  mv "$target" "$backup"
  ```
  If `$target` is a **symlink** pointing to a sensitive file (e.g., `~/.ssh/config`), `mv` moves the symlink itself. The subsequent `cp "$src" "$dst"` writes the new content to the symlink destination, overwriting the sensitive file.
- **Exploit Scenario:**
  An attacker with pre-existing symlink control in `~/.claude/` can redirect installer output to overwrite arbitrary files.
- **Recommendation:**
  Use `cp -L` or `readlink -f` to detect symlinks, and refuse to overwrite targets that are symlinks pointing outside the managed directory tree.

---

### 5. MEDIUM — scripts/mb-metrics.sh Arbitrary Code Execution Override

- **File:** `scripts/mb-metrics.sh`
- **Lines:** 28–31
- **Severity:** Medium
- **Description:**
  The script auto-detects a project-specific metrics override and executes it unconditionally:
  ```bash
  if [[ -f "$DIR/.memory-bank/metrics.sh" ]]; then
    bash "$DIR/.memory-bank/metrics.sh"
  ```
  While this is an intentional extension point, a malicious `.memory-bank/metrics.sh` in a cloned repository will execute arbitrary shell code when the victim runs `mb-metrics.sh`.
- **Exploit Scenario:**
  A cloned repository contains a malicious `.memory-bank/metrics.sh`. The victim runs the memory-bank workflow, triggering code execution.
- **Recommendation:**
  Require an explicit opt-in (e.g., `MB_ALLOW_METRICS_OVERRIDE=1`) before executing user-provided override scripts. Document the security implication clearly.

---

### 6. MEDIUM — hooks/file-change-log.sh Path Disclosure & Racy Rotation

- **File:** `hooks/file-change-log.sh`
- **Lines:** 21, 24–40
- **Severity:** Medium
- **Description:**
  1. **Path disclosure:** File change events are logged to a predictable path `$HOME/.claude/file-changes.log`, including paths to files the user may consider sensitive.
  2. **Race condition:** Log rotation is non-atomic:
     ```bash
     LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
     if [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
       mv "$LOG_FILE" "$LOG_FILE.1"
     ```
     Two concurrent hook invocations can interleave between size check and rotation, causing log loss or corruption.
- **Exploit Scenario:**
  An attacker with read access to the user's home directory can inspect `file-changes.log` to reconstruct the project's file structure and naming conventions. Concurrent tool use may corrupt logs.
- **Recommendation:**
  1. Set restrictive permissions on the log file (`chmod 600`).
  2. Use atomic rotation (e.g., `ln` + `mv` pattern, or append with size checking in a single process).

---

### 7. MEDIUM — scripts/mb-import.py Sensitive Data Retention

- **File:** `scripts/mb-import.py`
- **Lines:** 186–298
- **Severity:** Medium
- **Description:**
  The importer reads Claude Code JSONL session transcripts and extracts content into `.memory-bank/notes/` and `progress.md`. While it redacts **emails** and **API keys** via regex, it does **not** redact:
  - Passwords or authentication tokens in conversation text
  - Proprietary business logic or architecture details
  - Personal Identifiable Information (PII) beyond email addresses
  - The redaction regex itself may miss API key formats not covered by the hardcoded patterns.
- **Exploit Scenario:**
  A developer pastes a database password or proprietary algorithm into a Claude Code session. Later, `mb-import.py --apply` writes this to `.memory-bank/notes/`, where it may be committed to git or shared.
- **Recommendation:**
  1. Expand `APIKEY_RE` to cover additional patterns (e.g., `AKIA...` for AWS, `glpat-...` for GitLab).
  2. Add a generic secret detector (e.g., `detect-secrets` or `git-secrets` style entropy check).
  3. Document that `--apply` may retain sensitive conversational data and recommend reviewing imported notes before committing.

---

### 8. MEDIUM — scripts/mb-migrate-structure.sh Backup Retention Leak

- **File:** `scripts/mb-migrate-structure.sh`
- **Lines:** 81–86
- **Severity:** Medium
- **Description:**
  The migrator creates timestamped backups:
  ```bash
  backup_dir="$MB_PATH/.pre-migrate/$timestamp"
  mkdir -p "$backup_dir"
  for f in plan.md STATUS.md BACKLOG.md checklist.md; do
    [ -f "$MB_PATH/$f" ] && cp "$MB_PATH/$f" "$backup_dir/"
  ```
  These backups are **never automatically cleaned up**. Over time, `.pre-migrate/` accumulates historical versions of files that may contain sensitive plans, architecture decisions, or security review findings.
- **Exploit Scenario:**
  A repository containing `.memory-bank/` is shared or published. Old backups in `.pre-migrate/` leak deprecated but sensitive content that the user believed was removed.
- **Recommendation:**
  1. Document backup retention and advise users to periodically clean `.pre-migrate/`.
  2. Optionally, cap retention (e.g., keep only the last 3 backups) or exclude `.pre-migrate/` from git via `.gitignore`.

---

### 9. LOW — hooks/file-change-log.sh Race Condition in Rotation

- **File:** `hooks/file-change-log.sh`
- **Lines:** 24–34
- **Severity:** Low
- **Description:**
  Same as finding #6, but focused on the race condition alone. The size-check-then-move pattern is a classic TOCTOU race. Impact is limited to log integrity.
- **Recommendation:**
  Implement atomic rotation using `ln` and `mv` swap, or use a logrotate wrapper.

---

### 10. LOW — adapters/git-hooks-fallback.sh Backup Leak

- **File:** `adapters/git-hooks-fallback.sh`
- **Lines:** 151–159, 210–222
- **Severity:** Low
- **Description:**
  During install, existing git hooks are backed up as `post-commit.pre-mb-backup`. During uninstall, they are restored. If uninstall is **never run** or fails, these backup files remain in `.git/hooks/`, potentially leaking the contents of the original hooks (which may contain custom logic or secrets).
- **Exploit Scenario:**
  A user installs the adapter, then switches to a different tool without running uninstall. The `.git/hooks/*.pre-mb-backup` files persist and may be committed if the user mistakenly stages them.
- **Recommendation:**
  Add `.pre-mb-backup` to `.gitignore` during install, or store backups outside `.git/hooks/` (e.g., in `.git/mb-backups/`).

---

## Positive Security Practices Observed

| Practice | Where Observed |
|----------|----------------|
| **Atomic file writes** | `settings/merge-hooks.py`, `scripts/mb-import.py`, `scripts/mb-index-json.py`, `scripts/mb-codegraph.py` all use `tempfile.mkstemp()` + `os.replace()` |
| **PII redaction** | `scripts/mb-search.sh` strips `<private>` blocks by default; `mb-index-json.py` excludes them from indexing |
| **Dangerous command blocking** | `hooks/block-dangerous.sh` blocks `rm -rf /`, `DROP TABLE`, force-push, curl pipe-to-shell, etc. |
| **No hardcoded secrets** | No API keys, tokens, or passwords found in any source file |
| **Safe subprocess usage** | `memory_bank_skill/cli.py` uses `subprocess.run()` with list arguments (no `shell=True`) |
| **Input validation** | `mb-plan.sh` sanitizes topics via `mb_sanitize_topic()` to `[a-z0-9-]` |
| **Safe jq usage** | All jq invocations use `--arg` / `--argjson`, preventing injection |
| **No eval/exec** | No `eval`, `exec`, or `source` of user-controlled data found in Python or shell scripts |
| **Trusted Publishing** | `.github/workflows/publish.yml` uses PyPI OIDC instead of long-lived API tokens |

---

## Recommendations Summary

1. **Immediately** fix the path traversal in `uninstall.sh` by canonicalizing paths before prefix validation.
2. **Immediately** sanitize `project_id` in `scripts/_lib.sh` to prevent `.claude-workspace` traversal.
3. **Immediately** validate `pi_skill_dir` in `adapters/pi.sh` before `rm -rf`.
4. **Short-term** require explicit opt-in (`MB_ALLOW_METRICS_OVERRIDE=1`) for `metrics.sh` execution.
5. **Short-term** detect and refuse to follow symlinks in `install.sh` backup logic.
6. **Medium-term** expand secret detection patterns in `mb-import.py` and document data retention risks.
7. **Medium-term** implement automatic cleanup or `.gitignore` for migration backups in `mb-migrate-structure.sh`.
8. **Ongoing** run `shellcheck` and `bandit` in CI to catch unsafe patterns.

---

*End of Report*
