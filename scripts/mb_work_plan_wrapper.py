"""Wrapper-plan resolution for mb-work-plan.sh (svp-sdd-core).

Extracted from the inline heredoc so `mb-work-plan.sh` stays within the 400-line
zone contract once the r3 `linked_spec` containment landed — the same split the
zone already uses for `mb_spec_validate_*.py`. Behaviour is unchanged: argv is
`<plan-path> [mb_arg]`, stdout is `none` or
`wrapper\t<spec tasks.md>\t<wrapper basename>\t<tasks range>`.
"""

import os
import re
import sys

plan_path = sys.argv[1]
mb_arg = sys.argv[2] if len(sys.argv) > 2 else ""

with open(plan_path, encoding="utf-8") as _fh:
    text = _fh.read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    # No frontmatter — plain plan, no wrapper
    print("none")
    sys.exit(0)

def strip_yaml_comment(val: str) -> str:
    in_quote = None
    out = []
    i = 0
    while i < len(val):
        ch = val[i]
        if in_quote:
            out.append(ch)
            if ch == in_quote and (i == 0 or val[i - 1] != "\\"):
                in_quote = None
            i += 1
            continue
        if ch in "\"'":
            in_quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "#":
            break
        out.append(ch)
        i += 1
    return "".join(out).strip()


def parse_scalar(raw: str):
    val = strip_yaml_comment(raw.strip())
    if not val:
        return None
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
        return val[1:-1]
    return val


def fm_value(fm: str, key: str):
    for line in fm.splitlines():
        m = re.match(rf"^{re.escape(key)}:\s*(.*)$", line)
        if m:
            return parse_scalar(m.group(1))
    return None


fm = m.group(1)
linked_spec = fm_value(fm, "linked_spec")
tasks_range = fm_value(fm, "tasks")

if linked_spec is None:
    print("none")
    sys.exit(0)

# Resolve spec tasks.md relative to memory-bank root
plan_dir = os.path.dirname(os.path.realpath(plan_path))
# Try mb_arg first, then go up from plan_dir (plans/ → .memory-bank/)
mb_root = os.path.realpath(mb_arg) if mb_arg else os.path.dirname(plan_dir)

# Containment (r3 review [2]). os.path.join DISCARDS mb_root when linked_spec is
# absolute, so `linked_spec: /tmp/evil` bound the eval gate to a tasks.md the
# bank does not own — a file whose Eval declaration can change under the gate at
# will. A traversing or symlink-escaping value does the same thing. linked_spec
# is a bank-relative locator and nothing else.
# Containment (r3 [2]): os.path.join DISCARDS mb_root for an absolute
# linked_spec, so absolute, traversing and symlink-escaping values all land
# outside the bank and are refused by this one check.
spec_tasks = os.path.join(mb_root, linked_spec, "tasks.md")
real_root = os.path.realpath(mb_root)
if os.path.commonpath([real_root, os.path.realpath(spec_tasks)]) != real_root:
    sys.stderr.write(f"[work-plan] linked_spec escapes the bank: {linked_spec}\n")
    sys.exit(1)

if not os.path.isfile(spec_tasks):
    sys.stderr.write(
        f"[work-plan] linked_spec tasks not found: {spec_tasks}\n"
    )
    sys.exit(1)

wrapper_basename = os.path.basename(plan_path)
tasks_range_out = tasks_range if tasks_range is not None else ""
print(f"wrapper\t{spec_tasks}\t{wrapper_basename}\t{tasks_range_out}")
