"""Per-task structural checks 3-6 for mb-spec-validate.sh.

Split out of the shell heredoc so the CLI stays <=400 lines (S2 review [24]).
Behaviour is unchanged: covers/DoD/Testing per task, plus REQ orphan detection.
Reads TASKS_DATA / REQ_PATH / MB_SCRIPT_DIR from the environment and prints one
violation per line to stdout.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
import mb_req_id as rq  # shared REQ-ID grammar (scheme + slash + def-vs-mention)

tasks_raw = os.environ.get("TASKS_DATA", "")
req_path = os.environ.get("REQ_PATH", "")

tasks = []
for line in tasks_raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        tasks.append(json.loads(line))
    except json.JSONDecodeError:
        # Already reported by check 2; skip silently here.
        continue

req_text = ""
if req_path and os.path.exists(req_path):
    with open(req_path, encoding="utf-8") as fh:
        req_text = fh.read()
req_ids = set(rq.find_definitions(req_text))

covered: set[str] = set()
testing_re = re.compile(r"\btesting\b", re.IGNORECASE)
for item in tasks:
    no = item.get("item_no", "?")
    covers = item.get("covers") or []
    if not covers:
        print(f"task {no} missing Covers field")
    covered.update(rq.extract_req_ids(", ".join(str(c) for c in covers)))
    if not item.get("dod_lines"):
        print(f"task {no} missing DoD checkboxes")
    body = item.get("body") or ""
    if not testing_re.search(body):
        print(f"task {no} missing Testing section")

for req in sorted(req_ids):
    if req not in covered:
        print(f"{req} orphan (no task Covers)")
