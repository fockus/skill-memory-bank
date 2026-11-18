# shellcheck shell=bash
# Keep install.sh / uninstall.sh / adapters from writing into this checkout.
#
# The checkout is the owner's live skill (~/.claude/skills/memory-bank symlinks
# here). Without MB_MANIFEST_PATH, install.sh writes its manifest next to itself
# (scripts/_lib.sh::mb_resolve_manifest_path) — overwriting the owner's real
# install manifest — and without --project-root it installs project adapters
# into $PWD, which is the repo root when bats runs from there.
#
# setup_suite.bash in tests/bats and tests/e2e calls mb_repo_guard_setup /
# mb_repo_guard_check, so every run defaults both to temp dirs and fails if
# anything still lands in the repo. A test that exercises the resolver's own
# default must `unset MB_MANIFEST_PATH` and run from an rsync copy of the skill.

MB_GUARD_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# What an install writes into the skill dir (manifest) or a project root.
MB_GUARD_PATHS=".installed-manifest.json .mb-agents-owners.json .mb-pi-manifest.json
.mb-cline-manifest.json .codex .cursor .pi .windsurf .clinerules .kilocode .opencode
opencode.json .git/hooks"

# mb_repo_fingerprint [root] — path, mtime and sha256 of every guarded file.
mb_repo_fingerprint() {
  local root="${1:-$MB_GUARD_REPO_ROOT}" common
  # The shared git dir too: from a worktree `.git` is a file, so `.git/hooks` above
  # sees nothing, yet a test under a leaked GIT_DIR writes the common hooks and
  # core.* (`git init` there sets core.bare=true for every checkout).
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$common" ] && git config --file "$common/config" --get-regexp '^core\.' 2>/dev/null
  # shellcheck disable=SC2086  # word-split the path list on purpose
  (cd "$root" && python3 - $MB_GUARD_PATHS ${common:+"$common/hooks"} <<'PY'
import hashlib, os, sys

def files(top):
    if not os.path.isdir(top):
        yield top
        return
    for d, dirs, names in os.walk(top):
        dirs[:] = sorted(x for x in dirs if x != "node_modules")
        for n in sorted(names):
            yield os.path.join(d, n)

for top in sys.argv[1:]:
    for p in files(top):
        if os.path.isfile(p):
            with open(p, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            print(p, os.stat(p).st_mtime_ns, digest)
PY
  )
}

mb_repo_guard_setup() {
  # Run from a git hook (a linked worktree's pre-commit exports an absolute
  # GIT_DIR), every `git -C <tmp>` in a test would act on the committing repo.
  # shellcheck disable=SC2046  # one variable name per word
  unset $(git rev-parse --local-env-vars 2>/dev/null)
  MB_GUARD_BEFORE="$BATS_SUITE_TMPDIR/repo-fingerprint.before"
  mb_repo_fingerprint > "$MB_GUARD_BEFORE"
  export MB_GUARD_BEFORE
  export MB_MANIFEST_PATH="$BATS_SUITE_TMPDIR/installed-manifest.json"
  mkdir -p "$BATS_SUITE_TMPDIR/project"
  cd "$BATS_SUITE_TMPDIR/project" || return 1
}

mb_repo_guard_check() {
  local after="$BATS_SUITE_TMPDIR/repo-fingerprint.after"
  mb_repo_fingerprint > "$after"
  cmp -s "$MB_GUARD_BEFORE" "$after" && return 0
  echo "This test run wrote into the repo checkout $MB_GUARD_REPO_ROOT:" >&2
  diff "$MB_GUARD_BEFORE" "$after" >&2
  return 1
}

# mb_python_direct — put the interpreter that `python3` resolves to first on PATH.
# A pyenv shim costs ~0.6 s per start (measured: 0.59 s shim vs 0.02 s direct);
# one adapters/opencode.sh install spawns ~500 python3 processes (286 s vs 51 s).
mb_python_direct() {
  local bin
  bin="$(python3 -c 'import os, sys; print(os.path.dirname(sys.executable))' 2>/dev/null)" || return 0
  [ -x "$bin/python3" ] && export PATH="$bin:$PATH"
  return 0
}
