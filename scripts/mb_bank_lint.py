#!/usr/bin/env python3
"""mb-bank-lint engine (design.md C5): <roadmap|backlog|all> [--mb PATH].

One line per finding:
``severity=<warning|error> code=<code> file=<JSON> line=<int> detail=<JSON>``,
sorted by file, line, code. Exit 0 no errors, 1 at least one error, 2 bad usage.
Never writes into the bank.
"""

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from mb_bank_lint_backlog import check_backlog  # noqa: E402
from mb_bank_lint_roadmap import fence_findings, scan_files  # noqa: E402


def js(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def main(argv):
    if len(argv) != 2 or argv[0] not in ("roadmap", "backlog", "all"):
        sys.stderr.write("usage: mb_bank_lint.py <roadmap|backlog|all> <bank-path>\n")
        return 2
    scope, bank = argv[0], Path(argv[1])
    anchor = bank.resolve().parent

    def rel_of(path):
        return os.path.relpath(str(Path(path).resolve()), str(anchor)).replace(os.sep, "/")

    findings = []
    if scope in ("roadmap", "all"):
        found, groups = scan_files(bank, rel_of)
        findings += found + fence_findings(bank, rel_of, groups, SCRIPT_DIR)
    if scope in ("backlog", "all") and (bank / "backlog.md").is_file():
        findings += check_backlog((bank / "backlog.md").read_text(encoding="utf-8"), rel_of(bank / "backlog.md"))
    findings.sort(key=lambda f: (f[2], f[3], f[1]))
    for sev, code, path, line, detail in findings:
        print(f"severity={sev} code={code} file={js(path)} line={line} detail={js(detail)}")
    return 1 if any(f[0] == "error" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
