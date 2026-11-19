#!/usr/bin/env bash
# Run shard <k> of <n> of one CI test suite, so the suites spread over parallel runners.
# Usage: .github/ci-run.sh <suite> <k> <n>
#   bats          tests/bats, without perf tests
#   bats-quick    tests/bats, without slow and perf tests (macOS on every push)
#   serial        perf-tagged bats tests alone, then hooks/tests bats (k, n ignored)
#   e2e           tests/e2e
#   pytest        tests/pytest + hooks/tests; CI_COVERAGE=1 writes .coverage.<k> for a combine job
#   pytest-quick  the same without the slow marker
#   node          tests/*.test.mjs, the OpenCode adapter contracts (k, n ignored)
# Locally: `.github/ci-run.sh bats 1 8` runs what CI shard 1 of 8 runs.
set -euo pipefail
cd "$(dirname "$0")/.."
suite="$1" k="${2:-1}" n="${3:-1}"
jobs="$(getconf _NPROCESSORS_ONLN)"

# Files of shard k: greedy balance, heaviest file first onto the lightest shard.
# Weight = test count; a `file_tags=slow` bats file counts 5x (install-heavy).
# ponytail: test count stands in for runtime; feed real per-file timings if shards drift apart.
shard() {
  local pattern="$1" f c
  shift
  for f in "$@"; do
    c="$(grep -cE "$pattern" "$f" || true)"
    if grep -q 'file_tags=slow' "$f"; then c=$((c * 5)); fi
    printf '%s %s\n' "$c" "$f"
  done | sort -k1,1nr -k2 | awk -v k="$k" -v n="$n" '
    { i = 1; for (j = 2; j <= n; j++) if (load[j] < load[i]) i = j
      load[i] += $1; if (i == k) print $2 }'
}

py_files() { ls tests/pytest/test_*.py hooks/tests/*_test.py; }

case "$suite" in
  bats | bats-quick)
    tags='!perf'; [ "$suite" = bats ] || tags='!slow,!perf'
    # shellcheck disable=SC2046  # one path per word, no spaces in test file names
    bats --timing --jobs "$jobs" --filter-tags "$tags" $(shard '^@test' tests/bats/*.bats) ;;
  serial)
    bats --timing --filter-tags perf tests/bats/
    bats --timing --jobs "$jobs" hooks/tests/*.bats ;;
  e2e)
    # shellcheck disable=SC2046
    bats --timing --jobs "$jobs" $(shard '^@test' tests/e2e/*.bats) ;;
  pytest | pytest-quick)
    args=(-n auto -o 'python_files=*_test.py test_*.py')
    [ "$suite" = pytest ] || args+=(-m 'not slow')
    if [ "${CI_COVERAGE:-0}" = 1 ]; then
      export COVERAGE_FILE=".coverage.$k"
      args+=(--cov --cov-report=)
    fi
    # shellcheck disable=SC2046
    python -m pytest "${args[@]}" $(shard '^\s*(async )?def test_' $(py_files)) ;;
  node)
    node --test tests/*.test.mjs ;;
  *) echo "unknown suite: $suite" >&2; exit 2 ;;
esac
