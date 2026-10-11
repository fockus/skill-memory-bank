#!/usr/bin/env bash
# mb-team-review.sh — team review cycles (design §8): start | gate | external | ingest.
# Logic lives in mb_team_review.py (usage and exit codes in its docstring).
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mb_team_review.py" "$@"
