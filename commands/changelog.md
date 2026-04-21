---
description: Generate a changelog from commits
allowed-tools: [Bash, Read, Edit]
argument-hint: [version]
---

1. Detect the latest tag: `git describe --tags --abbrev=0 2>/dev/null || echo "start"`
2. Collect commits since the latest tag: `git log <tag>..HEAD --pretty=format:"%h %s" --no-merges`
3. Group them by type: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
4. Generate a `CHANGELOG` entry in Keep a Changelog format
5. If `$ARGUMENTS` is provided, use it as the version; otherwise propose one using semver