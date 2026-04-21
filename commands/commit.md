# ~/.claude/commands/commit.md

---

## description: Review staged changes and create a commit

allowed-tools: [Bash, Read]

1. Run `git diff --staged`
2. Check that there is no:
  - Debug code, `fmt.Println`, `console.log`
  - Commented-out code
  - `TODO` / `FIXME` / `HACK`
  - Hardcoded secrets
3. If you find problems, show them and ask whether to continue
4. Generate a commit message in Conventional Commits format:
  - `feat` / `fix` / `refactor` / `test` / `docs` / `chore`
  - Include a scope in parentheses if it is obvious
  - Keep the description short and in English
5. If `$ARGUMENTS` is provided, use it as the commit description
6. Run `git commit -m "<message>"`