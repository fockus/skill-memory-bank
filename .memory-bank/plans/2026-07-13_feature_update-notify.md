---
title: "Update notification + cross-install upgrade"
type: feature
status: done
created: 2026-07-13
owner: main-agent (Opus) — plan; /mb work — execution
roles: "implement=sonnet · review=codex gpt-5.5 · judge=opus"
parallel_safe: false
---

# Update notification + cross-install upgrade

## Why

Issue #2 showed the failure mode: a broken `5.2.0` sat on PyPI and users had **no way to
learn** a fix existed. They had to hit the bug, then find the repo. The skill knows its own
version and can see the latest release — it should just say so.

Today `scripts/mb-upgrade.sh` (297 ln) already:
- detects the install flavor when `.git` is absent — **git / pipx / pip** (`:119-168`);
- upgrades git-clone installs (`git pull` + re-install), persisting install options (A21);
- prints the right native command for pipx/pip and exits 0.

**What is missing — exactly the three asks:**

| Ask | Gap |
|---|---|
| Update the skill for existing users | Partially covered: `mb-upgrade.sh` handles git; pipx/pip get a *printed* command; **Homebrew is not detected at all** |
| Tell the user at session start that a newer version exists | **Nothing checks the latest RELEASE.** `--check` diffs the git *remote branch*, not a released version — and for pipx/pip it doesn't compare versions at all, it just prints a hint and exits 0 |
| Let the skill auto-update | **Does not exist** |

## Scope

Five tasks. TDD throughout (bats for shell, pytest where a parser is involved).

**Non-negotiable safety invariants** (these gate every task):
1. **Never block a session.** The SessionStart path is fail-open: network timeboxed, any
   error → silent exit 0. A user offline, behind a proxy, or rate-limited must see no
   error and lose no time.
2. **Never auto-run a package manager.** Auto-update applies to git-clone installs with a
   clean tree only. `pipx`/`pip`/`brew` are the user's tools; we print, never invoke.
3. **Auto-update is opt-in** (`MB_AUTO_UPDATE=on`, default `off`). Changing the user's
   installed code without asking is not a default.
4. **The check is disableable** (`MB_UPDATE_CHECK=off`) and cached (default 24h TTL) — one
   network call a day, not one per session.

---

<!-- mb-stage:1 -->
## Stage 1 — `mb_install_flavor` in `_lib.sh` (+ Homebrew)

`mb-upgrade.sh:119-168` detects the flavor inline. Stage 3's checker needs the same answer,
so extract it once (DRY) rather than duplicating a second copy that drifts.

**Role:** backend

**Testing (bats, RED first):** a fixture skill-dir per flavor →
- `.git/` present → `git`
- resolves under `*pipx/venvs/memory-bank-skill*` → `pipx`
- resolves under `*site-packages*` / `*dist-packages*` → `pip`
- resolves under a Homebrew Cellar/opt prefix (`*/Cellar/*` or `$(brew --prefix)`) → `brew`
- anything else → `unknown`
- a symlinked alias still resolves to the real flavor (the existing `readlink -f` path,
  with the BSD single-hop fallback — macOS ships bash 3.2 and a readlink without `-f`)

**DoD:**
- [ ] `_lib.sh::mb_install_flavor <dir>` prints exactly one of `git|pipx|pip|brew|unknown`, exit 0 always.
- [ ] `_lib.sh::mb_upgrade_command <flavor>` prints the native command for that flavor.
- [ ] `mb-upgrade.sh` calls them — its inline `case` is deleted, not merely bypassed (no second source of truth).
- [ ] Existing `mb-upgrade.sh` behaviour is byte-identical for git/pipx/pip (regression bats).
- [ ] bash 3.2 clean; shellcheck clean.

<!-- mb-stage:2 -->
## Stage 2 — `scripts/mb-version-check.sh` (the resolver)

The single authority for "is there a newer release?". No UI, no side effects beyond its cache.

**Role:** backend

**Testing (bats, RED first):** the network is stubbed via `MB_VERSION_CHECK_FETCH_BIN` (a
seam, same pattern `mb-drive.sh` uses for its five sub-scripts) —
- newer release → `update_available: true`
- equal / older local → `false`
- **semver compare is numeric, not lexical**: `5.10.0 > 5.9.0` must hold (a string compare
  gets this wrong — the exact class of bug that ships silently)
- pre-release / malformed tag (`v5.3.0-rc1`, `garbage`) → ignored, `false`, exit 0
- fetch fails / times out / returns non-JSON → **fail-open**: `false`, exit 0, no stderr noise
- `MB_UPDATE_CHECK=off` → immediate exit 0, **zero** network calls (assert the stub is never invoked)
- cache: a fresh cache file → no fetch; stale (> TTL) → fetch; `--force` → always fetch
- a corrupt cache file → treated as stale, never a crash

**DoD:**
- [ ] `mb-version-check.sh [--force] [--json]` prints strict JSON:
      `{current, latest, update_available, flavor, upgrade_command, checked_at, source}`.
- [ ] Latest release from GitHub Releases (`/releases/latest` → `tag_name`), falling back to
      the PyPI JSON API. `source` records which answered.
- [ ] Network is timeboxed (`--max-time`, default 3s) and **always** fail-open → exit 0.
- [ ] Cache at `<config>/.mb-version-check.json`, TTL `MB_UPDATE_CHECK_TTL` (default 86400).
- [ ] `MB_UPDATE_CHECK=off` short-circuits before any network call.
- [ ] shellcheck clean; ≤400 lines.

<!-- mb-stage:3 -->
## Stage 3 — `hooks/mb-update-notify.sh` (SessionStart notice)

**Role:** devops

**Testing (bats, RED first):**
- update available → notice on stdout naming current → latest **and** the flavor's exact command
- up to date → **no output at all** (silence is the contract; a chatty hook gets disabled by users)
- checker fails/absent → no output, exit 0
- `MB_UPDATE_CHECK=off` → no output, exit 0
- hook is registered for every host that supports SessionStart; hosts that don't are
  documented as an honest gap (the `test_cross_agent_runtime_parity.bats` pattern)

**DoD:**
- [x] Hook runs `mb-version-check.sh` (cached → typically zero network) and prints a ≤3-line notice.
- [x] Exit 0 unconditionally; never writes to the bank; never blocks.
- [x] Registered in `settings/hooks.json` + the adapters with a SessionStart transport.
- [x] Notice shows the command for the **detected** flavor (a pipx user is never told to `git pull`).

<!-- mb-stage:4 -->
## Stage 4 — opt-in auto-update

**Role:** backend

**Testing (bats, RED first) — the safety matrix is the test:**
- default (`MB_AUTO_UPDATE` unset) → **never** upgrades, notice only
- `on` + git + clean tree + update available → runs `mb-upgrade.sh --force`
- `on` + git + **dirty tree** → refuses, notice only (never discards the user's edits)
- `on` + **pipx/pip/brew** → refuses to invoke the package manager, notice only
- `on` + upgrade fails → session still starts, exit 0 (fail-open holds)

**DoD:**
- [x] `MB_AUTO_UPDATE=on` gates it; default `off`.
- [x] Auto-apply restricted to `flavor == git` **and** a clean working tree.
- [x] A package manager is never invoked on the user's behalf.
- [x] The applied upgrade is recorded (version → version) so it is not silent.

<!-- mb-stage:5 -->
## Stage 5 — docs

**Role:** analyst

**DoD:**
- [x] `commands/mb.md` `upgrade` section documents the check, the notice, and the three env vars.
- [x] `SKILL.md` Tools table gains `mb-version-check.sh` (`test_doc_counts` enforces this).
- [x] `README.md` — a short "staying up to date" section.
- [x] `CHANGELOG.md` under `[Unreleased]` (in-flight wording — the guard rejects release-claim language).
- [x] Config reference: `MB_UPDATE_CHECK`, `MB_UPDATE_CHECK_TTL`, `MB_AUTO_UPDATE` with defaults.

---

## Verification (whole plan)

- [x] Full bats + pytest green; shellcheck + ruff clean.
- [x] **Offline run**: with the network unavailable, session start is silent and adds no
      measurable delay (the invariant that matters most — a broken check must never be worse
      than no check).
- [x] A pipx install is told `pipx upgrade`, a git install is told/does `git pull` — verified
      end-to-end against a real pipx install, not just a stub.
