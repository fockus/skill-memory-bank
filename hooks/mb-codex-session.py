#!/usr/bin/env python3
"""Capture public Codex final turns; stdout contains metadata only."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / 'lib'))
from codex_session import capture  # noqa: E402


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict) or len(sys.argv) != 2:
            raise ValueError('invalid input')
        path = capture(payload, Path(sys.argv[1]))
        print(json.dumps({'captured': path is not None, 'session_file': str(path) if path else None}))
    except (ValueError, OSError, TypeError):
        print(json.dumps({'captured': False, 'error': 'invalid_capture_input'}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
