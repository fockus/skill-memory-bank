#!/usr/bin/env bash
# mb-sdd-review-result.sh — executable owner of the spec-review exit codes
# (svp-sdd-core design C5, F-009). `commands/sdd.md` owns the MODEL DISPATCH
# (only a prompt can call an agent); this helper owns the VALIDATION, the
# append-only record, and the exit codes — so "exit 0/1/2" has an executor
# rather than staying prose in design.
#
# Usage:
#   mb-sdd-review-result.sh check  --generator-model <exact> --reviewer-model <exact> \
#        [--reviewer-agent <exact>] [--thinking <low|medium|high>] [--mb <bank>]
#   mb-sdd-review-result.sh record --topic <topic> --attempt <n> \
#        --generator-model <exact> --reviewer-model <exact> --reviewer-agent <exact> \
#        --thinking <low|medium|high> --input <path|-> [--mb <bank>]
#
# check  — called BEFORE dispatch. Equal generator/reviewer models → stderr
#          `same_model`, exit 2 (dispatch forbidden). Otherwise exit 0.
# record — takes the reviewer's RAW JSON on --input (`-` = stdin), validates it
#          strictly (extra fields → malformed), and appends ONE compact line to
#          `<bank>/tmp/spec-review/<topic>.jsonl` with helper-added `ts`
#          (UTC ISO-8601) + `attempt`. History is never rewritten; the last
#          valid line is the current verdict.
#
# exit : 0 APPROVED · 1 CHANGES_REQUESTED · 2 same_model | unavailable(skipped)
#        | malformed | usage.
#
# The triple's requirements.md status is NOT changed here — that is the
# orchestrator's C7 state-machine decision, keyed on this exit code.

set -euo pipefail

usage_error() { printf 'error=usage\n' >&2; exit 2; }

[ "$#" -ge 1 ] || usage_error
ACTION="$1"; shift

GEN=""; REV=""; AGENT=""; THINKING=""; TOPIC=""; ATTEMPT=""; INPUT=""; MB_BANK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --generator-model) [ "$#" -ge 2 ] || usage_error; GEN="$2"; shift ;;
    --reviewer-model)  [ "$#" -ge 2 ] || usage_error; REV="$2"; shift ;;
    --reviewer-agent)  [ "$#" -ge 2 ] || usage_error; AGENT="$2"; shift ;;
    --thinking)        [ "$#" -ge 2 ] || usage_error; THINKING="$2"; shift ;;
    --topic)           [ "$#" -ge 2 ] || usage_error; TOPIC="$2"; shift ;;
    --attempt)         [ "$#" -ge 2 ] || usage_error; ATTEMPT="$2"; shift ;;
    --input)           [ "$#" -ge 2 ] || usage_error; INPUT="$2"; shift ;;
    --mb)              [ "$#" -ge 2 ] || usage_error; MB_BANK="$2"; shift ;;
    *) usage_error ;;
  esac
  shift
done

# ── check ────────────────────────────────────────────────────────────────────
if [ "$ACTION" = "check" ]; then
  [ -n "$GEN" ] && [ -n "$REV" ] || usage_error
  if [ "$GEN" = "$REV" ]; then
    printf 'same_model\n' >&2
    exit 2
  fi
  exit 0
fi

[ "$ACTION" = "record" ] || usage_error
{ [ -n "$TOPIC" ] && [ -n "$ATTEMPT" ] && [ -n "$INPUT" ]; } || usage_error
# All reviewer-identity flags are MANDATORY for record (blocker #4): the helper
# records the reviewer identity and must verify it against the resolved IDs the
# prompt actually dispatched — record must never sign a foreign identity.
{ [ -n "$GEN" ] && [ -n "$REV" ] && [ -n "$AGENT" ] && [ -n "$THINKING" ]; } || usage_error

# Topic must be a safe slug (blocker #9): no traversal, no separators.
case "$TOPIC" in
  *[!A-Za-z0-9._-]*|*..*) usage_error ;;
esac
case "$TOPIC" in [A-Za-z0-9]*) : ;; *) usage_error ;; esac

# same_model must be caught BEFORE any append (resolved IDs are equal).
if [ "$GEN" = "$REV" ]; then
  printf 'same_model\n' >&2
  exit 2
fi

if [ "$INPUT" = "-" ]; then
  RAW="$(cat)"
else
  [ -f "$INPUT" ] && [ -r "$INPUT" ] || usage_error
  RAW="$(cat "$INPUT")"
fi

BANK="${MB_BANK:-.memory-bank}"
OUTDIR="$BANK/tmp/spec-review"

set +e
STATUS_LINE="$(
  MB_RAW="$RAW" MB_TOPIC="$TOPIC" MB_ATTEMPT="$ATTEMPT" MB_OUTDIR="$OUTDIR" \
    MB_REV_AGENT="$AGENT" MB_REV_MODEL="$REV" MB_THINKING="$THINKING" python3 - <<'PY'
import json, os, sys, datetime, pathlib

raw = os.environ["MB_RAW"]
topic = os.environ["MB_TOPIC"]
outdir = os.environ["MB_OUTDIR"]

def bad(_msg):
    sys.stderr.write("malformed\n")
    sys.exit(2)

try:
    obj = json.loads(raw)
except Exception:
    bad("json")

if not isinstance(obj, dict) or set(obj) != {"status", "verdict", "reviewer", "issues", "reason"}:
    bad("keys")

status = obj["status"]
if status not in ("reviewed", "skipped"):
    bad("status")

verdict = obj["verdict"]
if verdict not in ("APPROVED", "CHANGES_REQUESTED", None):
    bad("verdict")

rv = obj["reviewer"]
if not isinstance(rv, dict) or set(rv) != {"agent", "model", "thinking"}:
    bad("reviewer")
if not all(isinstance(rv[k], str) and rv[k].strip() for k in ("agent", "model", "thinking")):
    bad("reviewer_fields")
if rv["thinking"] not in ("low", "medium", "high"):
    bad("thinking")
# Strict identity match (blocker #4): the JSON reviewer block MUST equal the
# resolved IDs the prompt dispatched — never sign a foreign identity.
if (rv["agent"] != os.environ["MB_REV_AGENT"]
        or rv["model"] != os.environ["MB_REV_MODEL"]
        or rv["thinking"] != os.environ["MB_THINKING"]):
    bad("identity_mismatch")

issues = obj["issues"]
if not isinstance(issues, list):
    bad("issues")
for it in issues:
    if not isinstance(it, dict) or set(it) != {"severity", "category", "req", "description"}:
        bad("issue_keys")
    if it["severity"] not in ("critical", "major", "minor", "nit"):
        bad("severity")
    if not isinstance(it["category"], str):
        bad("category")
    if it["req"] is not None and not isinstance(it["req"], str):
        bad("req")
    if not isinstance(it["description"], str):
        bad("description")

reason = obj["reason"]
if reason is not None and not isinstance(reason, str):
    bad("reason")

try:
    attempt = int(os.environ["MB_ATTEMPT"])
except Exception:
    bad("attempt")

# status/verdict coherence + the owning exit code.
if status == "skipped":
    if not (isinstance(reason, str) and reason.strip()):
        bad("skipped_reason")   # a skip must say why — never silent
    code = 2
else:  # reviewed
    if verdict == "APPROVED":
        code = 0
    elif verdict == "CHANGES_REQUESTED":
        code = 1
    else:
        bad("reviewed_verdict")  # a reviewed status must carry a verdict

# Append-only JSONL: one compact line, helper-added ts + attempt.
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
rec = dict(obj)
rec["ts"] = ts
rec["attempt"] = attempt
d = pathlib.Path(outdir)
d.mkdir(parents=True, exist_ok=True)
# Containment (blocker #9, defense-in-depth over the shell topic guard): the
# resolved JSONL path must be a DIRECT child of the spec-review directory.
target = (d / (topic + ".jsonl")).resolve()
if target.parent != d.resolve():
    bad("path_escape")
with open(target, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, separators=(",", ":"), ensure_ascii=False) + "\n")

sys.stdout.write("spec_review=%s verdict=%s attempt=%d" % (status, verdict, attempt))
sys.exit(code)
PY
)"
rc=$?
set -e

[ -n "$STATUS_LINE" ] && printf '%s\n' "$STATUS_LINE"
# Loud report for a skipped (unavailable) review.
if [ "$rc" -eq 2 ] && printf '%s' "$STATUS_LINE" | grep -q 'spec_review=skipped'; then
  printf 'spec_review: SKIPPED (review unavailable) — recorded to %s/%s.jsonl\n' "$OUTDIR" "$TOPIC" >&2
fi
exit "$rc"
