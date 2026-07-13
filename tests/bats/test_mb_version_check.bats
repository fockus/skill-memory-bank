#!/usr/bin/env bats
# Tests for scripts/mb-version-check.sh — the single authority for
# "is there a newer release?". No UI, no side effects beyond its own cache.
#
# The network is stubbed via MB_VERSION_CHECK_FETCH_BIN (the same seam
# pattern mb-drive.sh uses for its sub-scripts: MB_GOAL_ACCEPTANCE_BIN,
# MB_FLOW_VERIFY_BIN, ...). No test in this suite touches the real network.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-version-check.sh"
  TMPDIR="$(mktemp -d)"
  SKILL_DIR="$TMPDIR/skill"
  CACHE_FILE="$TMPDIR/cache/.mb-version-check.json"

  [ -f "$SCRIPT" ] || skip "scripts/mb-version-check.sh not implemented yet (TDD red phase)"

  mkdir -p "$SKILL_DIR"
  printf '5.9.0\n' > "$SKILL_DIR/VERSION"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# $1=filename $2=exit-code $3=stdout-body -> path to a chmod+x stub script.
# Records every invocation (one line per call) to $TMPDIR/calls.log so tests
# can assert "the stub was never invoked" rather than merely inspect output.
fake_fetch() {
  local path="$TMPDIR/$1"
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/calls.log"
printf '%s\n' '$3'
exit $2
EOF
  chmod +x "$path"
  printf '%s' "$path"
}

# A fetch stub whose response depends on which URL it was called with — the
# GitHub Releases API is tried first, PyPI JSON is the fallback. $1=filename
# $2=exit-code-github $3=body-github $4=exit-code-pypi $5=body-pypi
fake_fetch_dual() {
  local path="$TMPDIR/$1"
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/calls.log"
case "\$*" in
  *github*)
    printf '%s\n' '$3'
    exit $2
    ;;
  *pypi*)
    printf '%s\n' '$5'
    exit $4
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$path"
  printf '%s' "$path"
}

call_count() {
  [ -f "$TMPDIR/calls.log" ] || { echo 0; return 0; }
  wc -l < "$TMPDIR/calls.log" | tr -d ' '
}

json_field() {
  # $1=raw json $2=python-expression-safe key -> prints the field's value
  printf '%s' "$1" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data["'"$2"'"])
'
}

# ═══ strict JSON shape ═══

@test "version-check: output is strict JSON with exactly the seven contract keys" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.9.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
assert set(data.keys()) == {
    "current", "latest", "update_available", "flavor",
    "upgrade_command", "checked_at", "source",
}, data.keys()
assert isinstance(data["update_available"], bool), data["update_available"]
' "$output"
}

# ═══ numeric semver compare (the trap) ═══

@test "version-check: newer release available -> update_available true" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "True" ]
  [ "$(json_field "$output" latest)" = "5.10.0" ]
}

@test "version-check: 5.10.0 > 5.9.0 numerically (a lexical compare gets this backwards)" {
  printf '5.9.0\n' > "$SKILL_DIR/VERSION"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"5.10.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "True" ]
}

@test "version-check: equal local version -> update_available false" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.9.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
}

@test "version-check: older remote (local ahead) -> update_available false" {
  printf '5.10.0\n' > "$SKILL_DIR/VERSION"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.9.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
}

# ═══ pre-release / malformed tags ═══

@test "version-check: pre-release tag (v5.3.0-rc1) is ignored -> false, exit 0" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.3.0-rc1"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
  [ "$(json_field "$output" latest)" = "" ]
}

@test "version-check: malformed tag (garbage) is ignored -> false, exit 0" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"garbage"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
}

# ═══ fail-open ═══

@test "version-check: fetch fails (non-zero exit) -> fail-open false, exit 0, no stderr noise" {
  local fetch; fetch=$(fake_fetch fetch.sh 1 '')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run --separate-stderr bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
  [ -z "$stderr" ]
}

@test "version-check: fetch returns non-JSON body -> fail-open false, exit 0" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 'not json at all')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
}

@test "version-check: fetch binary missing/unreachable host -> fail-open false, exit 0" {
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$TMPDIR/no-such-binary" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
}

# ═══ GitHub -> PyPI fallback ═══

@test "version-check: GitHub answers -> source is github" {
  local fetch; fetch=$(fake_fetch_dual fetch.sh 0 '{"tag_name":"v5.10.0"}' 0 '{"info":{"version":"5.10.0"}}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" source)" = "github" ]
}

@test "version-check: GitHub fails -> falls back to PyPI, source is pypi" {
  local fetch; fetch=$(fake_fetch_dual fetch.sh 1 '' 0 '{"info":{"version":"5.10.0"}}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" source)" = "pypi" ]
  [ "$(json_field "$output" update_available)" = "True" ]
}

@test "version-check: both GitHub and PyPI fail -> fail-open false, source none" {
  local fetch; fetch=$(fake_fetch_dual fetch.sh 1 '' 1 '')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
  [ "$(json_field "$output" source)" = "none" ]
}

# ═══ MB_UPDATE_CHECK=off ═══

@test "version-check: MB_UPDATE_CHECK=off -> exit 0, ZERO network calls" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_UPDATE_CHECK=off MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "False" ]
}

# ═══ cache ═══

@test "version-check: fresh cache -> no fetch at all" {
  mkdir -p "$(dirname "$CACHE_FILE")"
  local now; now="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  printf '{"latest":"5.10.0","source":"github","checked_at":"%s"}\n' "$now" > "$CACHE_FILE"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.11.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" MB_UPDATE_CHECK_TTL=86400 \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 0 ]
  [ "$(json_field "$output" latest)" = "5.10.0" ]
  [ "$(json_field "$output" source)" = "cache" ]
  [ "$(json_field "$output" update_available)" = "True" ]
}

@test "version-check: stale cache (older than TTL) -> fetches" {
  mkdir -p "$(dirname "$CACHE_FILE")"
  local old; old="$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=99999)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  printf '{"latest":"5.9.0","source":"github","checked_at":"%s"}\n' "$old" > "$CACHE_FILE"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.11.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" MB_UPDATE_CHECK_TTL=86400 \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -ge 1 ]
  [ "$(json_field "$output" latest)" = "5.11.0" ]
  [ "$(json_field "$output" source)" = "github" ]
}

@test "version-check: --force always fetches even with a fresh cache" {
  mkdir -p "$(dirname "$CACHE_FILE")"
  local now; now="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  printf '{"latest":"5.9.0","source":"github","checked_at":"%s"}\n' "$now" > "$CACHE_FILE"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.11.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" MB_UPDATE_CHECK_TTL=86400 \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [ "$(call_count)" -ge 1 ]
  [ "$(json_field "$output" latest)" = "5.11.0" ]
}

@test "version-check: corrupt cache file is treated as stale, never a crash" {
  mkdir -p "$(dirname "$CACHE_FILE")"
  printf 'not { valid json' > "$CACHE_FILE"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.11.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" MB_UPDATE_CHECK_TTL=86400 \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -ge 1 ]
  [ "$(json_field "$output" latest)" = "5.11.0" ]
}

@test "version-check: no cache file yet -> fetches and writes a cache for next time" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.11.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$CACHE_FILE" ]
  [ "$(json_field "$(cat "$CACHE_FILE")" latest)" = "5.11.0" ]
}

# ═══ flavor / upgrade_command wiring (reuses _lib.sh, not reimplemented) ═══

@test "version-check: git install dir -> flavor git, upgrade_command mentions mb-upgrade.sh" {
  mkdir -p "$SKILL_DIR/.git"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.9.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" flavor)" = "git" ]
  [[ "$(json_field "$output" upgrade_command)" == *"mb-upgrade.sh"* ]]
}

@test "version-check: pipx install dir -> flavor pipx, upgrade_command is pipx upgrade" {
  mkdir -p "$TMPDIR/pipx/venvs/memory-bank-skill/share/memory-bank-skill"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.9.0"}')
  MB_SKILL_DIR="$TMPDIR/pipx/venvs/memory-bank-skill/share/memory-bank-skill" \
    MB_VERSION_CHECK_CACHE="$CACHE_FILE" MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" flavor)" = "pipx" ]
  [ "$(json_field "$output" upgrade_command)" = "pipx upgrade memory-bank-skill" ]
}

# ═══ fail-open: python interpreter missing (B1) ═══

@test "version-check: MB_PYTHON points at a nonexistent interpreter -> exit 0, valid JSON, empty stderr, no network" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_PYTHON="$TMPDIR/no-such-python" MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run --separate-stderr bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(call_count)" -eq 0 ]
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
assert set(data.keys()) == {
    "current", "latest", "update_available", "flavor",
    "upgrade_command", "checked_at", "source",
}, data.keys()
assert data["update_available"] is False, data
' "$output"
}

# ═══ negative caching: a failed fetch must not be re-paid every session (B2) ═══

@test "version-check: a failing fetch is negative-cached -> the second run makes ZERO new network calls" {
  local fetch; fetch=$(fake_fetch fetch.sh 1 '')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local first_count; first_count="$(call_count)"
  [ "$first_count" -ge 1 ]

  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq "$first_count" ]
}

# ═══ MB_UPDATE_CHECK=off must precede flavor detection (B3) ═══

@test "version-check: MB_UPDATE_CHECK=off -> ZERO brew invocations (short-circuits before flavor detection)" {
  local fake_bin="$TMPDIR/bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/brew" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/brew-calls.log"
printf '%s\n' "/opt/homebrew"
exit 0
EOF
  chmod +x "$fake_bin/brew"

  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_UPDATE_CHECK=off MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" PATH="$fake_bin:$PATH" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$TMPDIR/brew-calls.log" ]
  [ "$(call_count)" -eq 0 ]
}

# ═══ oversized response body must not be read in full (major) ═══

@test "version-check: response larger than the max-body cap is truncated before parsing, not trusted" {
  # tag_name sits early in the body; a valid-JSON tail (padding) pushes the
  # total size well past the cap. Uncapped, this still parses fine and
  # "v5.10.0" would be extracted. Capped, the truncated body is no longer
  # syntactically valid JSON at all, so the whole answer is discarded.
  local pad; pad="$(head -c 200000 /dev/zero | tr '\0' 'a')"
  local body; body="{\"tag_name\":\"v5.10.0\",\"padding\":\"$pad\"}"
  local fetch; fetch=$(fake_fetch fetch.sh 0 "$body")
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run --separate-stderr bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(json_field "$output" update_available)" = "False" ]
  [ "${#output}" -lt 10000 ]
}

# ═══ cached `latest` is untrusted input, same as the network (major) ═══

@test "version-check: cache poisoned with a non-semver latest is treated as stale, not trusted verbatim" {
  mkdir -p "$(dirname "$CACHE_FILE")"
  local now; now="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  printf '{"latest":"5.10.0\\u001b]52;c;evil","source":"github","checked_at":"%s"}\n' "$now" > "$CACHE_FILE"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.11.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -ge 1 ]
  [ "$(json_field "$output" latest)" = "5.11.0" ]
  [ "$(json_field "$output" source)" = "github" ]
}

@test "version-check: cache with an unrecognized source value is treated as stale, not trusted verbatim" {
  mkdir -p "$(dirname "$CACHE_FILE")"
  local now; now="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  printf '{"latest":"5.10.0","source":"attacker","checked_at":"%s"}\n' "$now" > "$CACHE_FILE"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.11.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -ge 1 ]
  [ "$(json_field "$output" latest)" = "5.11.0" ]
}

# ═══ symmetric v-prefix handling (major) ═══

@test "version-check: v-prefixed local VERSION compares correctly against latest" {
  printf 'v5.9.0\n' > "$SKILL_DIR/VERSION"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "True" ]
}

# ═══ SKILL_DIR must self-locate, not assume ~/.claude (major) ═══

@test "version-check: no MB_SKILL_DIR -> self-locates its own bundle root, ignoring \$HOME/.claude entirely" {
  local fake_home="$TMPDIR/fakehome"
  mkdir -p "$fake_home/.claude/skills/skill-memory-bank"
  printf '0.0.1-not-the-real-install\n' > "$fake_home/.claude/skills/skill-memory-bank/VERSION"
  local real_version; real_version="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"

  HOME="$fake_home" MB_UPDATE_CHECK=off MB_VERSION_CHECK_CACHE="$CACHE_FILE" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" current)" = "$real_version" ]
}

# ═══ fail-open: unreadable VERSION must never crash the script (B1, round 2) ═══

@test "version-check: chmod 000 VERSION -> exit 0, empty stderr, current is unknown" {
  chmod 000 "$SKILL_DIR/VERSION"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run --separate-stderr bash "$SCRIPT"
  chmod 644 "$SKILL_DIR/VERSION"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(json_field "$output" current)" = "unknown" ]
}

# ═══ fail-open: a python that PASSES `command -v` but dies at exec time
# (a pyenv shim pointing at an uninstalled version is the textbook case)
# must not leak stderr from any of its call sites (B2, round 2) ═══

@test "version-check: python passes command -v but fails at exec -> exit 0, empty stderr" {
  local pybin="$TMPDIR/fake-python3"
  cat > "$pybin" <<'EOF'
#!/usr/bin/env bash
echo "pyenv: python3: command not found" >&2
exit 127
EOF
  chmod +x "$pybin"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_PYTHON="$pybin" MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run --separate-stderr bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
assert set(data.keys()) == {
    "current", "latest", "update_available", "flavor",
    "upgrade_command", "checked_at", "source",
}, data.keys()
' "$output"
}

# ═══ fail-open: $HOME entirely unset must never crash the script (round 3) ═══
# `${XDG_DATA_HOME:-$HOME/.local/share}` on CACHE_FILE's default expands
# `$HOME` unconditionally at assignment time — under `set -u` an unset HOME
# is a hard "unbound variable" abort, even with MB_UPDATE_CHECK=off and even
# when MB_VERSION_CHECK_CACHE is supplied (the default expansion still runs).

@test "version-check: HOME unset -> exit 0, empty stderr, valid JSON" {
  MB_UPDATE_CHECK=off MB_SKILL_DIR="$SKILL_DIR" \
    run --separate-stderr env -u HOME bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
assert set(data.keys()) == {
    "current", "latest", "update_available", "flavor",
    "upgrade_command", "checked_at", "source",
}, data.keys()
' "$output"
}

@test "version-check: HOME unset but an explicit MB_VERSION_CHECK_CACHE is honoured -> no crash, cache written there" {
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" MB_VERSION_CHECK_FETCH_BIN="$fetch" \
    run --separate-stderr env -u HOME bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ -f "$CACHE_FILE" ]
  [ "$(json_field "$output" latest)" = "5.10.0" ]
}

# ═══ usage ═══

@test "version-check: unknown flag -> non-zero exit, usage error on stderr" {
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" run bash "$SCRIPT" --bogus
  [ "$status" -ne 0 ]
  [ -n "$output$stderr" ]
}

# ═══ bash 3.2 portability (macOS system bash) ═══

@test "version-check: runs clean under bash 3.2" {
  command -v /bin/bash >/dev/null 2>&1 || skip "no /bin/bash on this host"
  [[ "$(/bin/bash --version)" == *"version 3."* ]] || skip "system /bin/bash is not 3.x here"
  local fetch; fetch=$(fake_fetch fetch.sh 0 '{"tag_name":"v5.10.0"}')
  MB_SKILL_DIR="$SKILL_DIR" MB_VERSION_CHECK_CACHE="$CACHE_FILE" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch" run /bin/bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(json_field "$output" update_available)" = "True" ]
}
