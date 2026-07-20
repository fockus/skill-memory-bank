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
#   mb-sdd-review-result.sh decide --topic <topic> --attempt <n> \
#        --input <path|-> [--mb <bank>]
#
# check  — called BEFORE dispatch. Equal generator/reviewer models → stderr
#          `same_model`, exit 2 (dispatch forbidden). Otherwise exit 0.
# record — takes the reviewer's RAW JSON on --input (`-` = stdin), validates it
#          strictly (extra fields → malformed), and appends ONE compact line to
#          `<bank>/tmp/spec-review/<topic>.jsonl` with helper-added `ts`
#          (UTC ISO-8601) + `attempt`. History is never rewritten; the last
#          valid line is the current verdict. A payload containing a secret is
#          refused (`secret_blocked`, exit 2) — the log is append-only, so a
#          leaked credential in it would be permanent.
#
# Reviewer provenance is CLAIMED, not verified: the identity flags and the JSON
# `reviewer` block come from the same caller, so their agreement proves internal
# consistency only. Every record therefore carries `reviewer_provenance:
# "claimed"`; no consumer may treat it as proof that the named model ran.
#
# decide — the C7 explicit human/orchestrator decision, written as its OWN
#          append-only JSONL line. sdd.md allows `ready` on an explicit accept
#          over a SKIPPED review or dismissed issues, but there was no way to
#          record that through the single sanctioned writer: the only options
#          were a hand-rolled append or a false APPROVED, both of which corrupt
#          the audit trail (r3 review [4]). Closed schema, no reviewer identity
#          (a decision is not a review):
#            {"status":"decided","decision":"accept"|"reject",
#             "basis":"skipped"|"dismissed_issues",
#             "rationale":"<non-empty>","decided_by":"<non-empty>"}
#
# exit : 0 APPROVED | decided-accept · 1 CHANGES_REQUESTED | decided-reject
#        · 2 same_model | unavailable(skipped) | malformed | usage.
#
# The triple's requirements.md status is NOT changed here — that is the
# orchestrator's C7 state-machine decision, keyed on this exit code.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
SECRET_SCAN="$SCRIPT_DIR/mb-secret-scan.sh"

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

case "$ACTION" in record|decide) : ;; *) usage_error ;; esac
{ [ -n "$TOPIC" ] && [ -n "$ATTEMPT" ] && [ -n "$INPUT" ]; } || usage_error
if [ "$ACTION" = "record" ]; then
  # All reviewer-identity flags are MANDATORY for record (blocker #4): the helper
  # records the reviewer identity and must verify it against the resolved IDs the
  # prompt actually dispatched — record must never sign a foreign identity.
  { [ -n "$GEN" ] && [ -n "$REV" ] && [ -n "$AGENT" ] && [ -n "$THINKING" ]; } || usage_error
fi

# Topic must be a safe slug (blocker #9): no traversal, no separators.
case "$TOPIC" in
  *[!A-Za-z0-9._-]*|*..*) usage_error ;;
esac
case "$TOPIC" in [A-Za-z0-9]*) : ;; *) usage_error ;; esac

# same_model must be caught BEFORE any append (resolved IDs are equal). Only
# meaningful for `record`; a decision has no reviewer pair.
if [ "$ACTION" = "record" ] && [ "$GEN" = "$REV" ]; then
  printf 'same_model\n' >&2
  exit 2
fi

if [ "$INPUT" = "-" ]; then
  RAW="$(cat)"
else
  [ -f "$INPUT" ] && [ -r "$INPUT" ] || usage_error
  RAW="$(cat "$INPUT")"
fi

# Storage-aware resolution (review [18]): local, global-registered and legacy
# banks all resolve through the shared resolver — never a hardcoded relative
# `.memory-bank`, which silently created a second bank next to the caller.
BANK="$(mb_resolve_path "$MB_BANK")"
OUTDIR="$BANK/tmp/spec-review"

# Fail-closed secret gate BEFORE any durable write (review [23]): the reviewer
# payload is appended verbatim to an append-only JSONL that is never rewritten,
# so a leaked credential there is permanent. Scanning is delegated to the
# canonical dispatcher — no second regex set lives here. Any verdict other than
# a clean scan refuses the record; `<private>` markers do NOT exempt a payload
# (that guard covers index/search, not durable git-tracked content).
# The payload is STREAMED to the scanner, never spilled to a file first
# (r3 review [7]). The old mktemp round-trip wrote the UNSCANNED credential to
# /tmp and relied on reaching the `rm`; a crash or SIGKILL in that window left it
# readable on disk, which is exactly the leak this gate exists to prevent.
set +e
SCAN_OUT="$(printf '%s' "$RAW" | bash "$SECRET_SCAN" --policy transcript - 2>/dev/null)"
scan_rc=$?
set -e
if [ "$scan_rc" -ne 0 ] || [ "$SCAN_OUT" != "scan=clean" ]; then
  printf 'secret_blocked\n' >&2
  exit 2
fi

if [ "$ACTION" = "decide" ]; then
  set +e
  DEC_LINE="$(
    MB_RAW="$RAW" MB_TOPIC="$TOPIC" MB_ATTEMPT="$ATTEMPT" MB_BANK="$BANK" python3 - <<'PYDEC'
import json, os, sys, datetime, pathlib

raw = os.environ["MB_RAW"]
topic = os.environ["MB_TOPIC"]
bank = os.environ["MB_BANK"]
outdir = os.path.join(bank, "tmp", "spec-review")


def bad(_msg):
    sys.stderr.write("malformed\n")
    sys.exit(2)


try:
    obj = json.loads(raw)
except Exception:
    bad("json")

# Closed schema: exactly these keys, exactly these enums. A decision record that
# can say anything is not an audit trail.
if not isinstance(obj, dict) or set(obj) != {
        "status", "decision", "basis", "rationale", "decided_by"}:
    bad("keys")
if obj["status"] != "decided":
    bad("status")
if obj["decision"] not in ("accept", "reject"):
    bad("decision")
if obj["basis"] not in ("skipped", "dismissed_issues"):
    bad("basis")
for k in ("rationale", "decided_by"):
    if not isinstance(obj[k], str) or not obj[k].strip():
        bad(k)   # an unexplained accept is what the trail exists to prevent

try:
    attempt = int(os.environ["MB_ATTEMPT"])
except Exception:
    bad("attempt")

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
rec = dict(obj)
rec["ts"] = ts
rec["attempt"] = attempt
# Same honesty rule as `record`: the actor is asserted by the caller, so it is
# marked CLAIMED and no consumer may read it as verified.
rec["decided_by_provenance"] = "claimed"

pathlib.Path(outdir).mkdir(parents=True, exist_ok=True)
with open(os.path.join(outdir, topic + ".jsonl"), "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, sort_keys=True, separators=(",", ":")) + "\n")

sys.stdout.write("spec_decision=%s basis=%s attempt=%d"
                 % (obj["decision"], obj["basis"], attempt))
sys.exit(0 if obj["decision"] == "accept" else 1)
PYDEC
  )"
  dec_rc=$?
  set -e
  [ "$dec_rc" -eq 2 ] && exit 2
  printf '%s\n' "$DEC_LINE"
  exit "$dec_rc"
fi

set +e
STATUS_LINE="$(
  MB_RAW="$RAW" MB_TOPIC="$TOPIC" MB_ATTEMPT="$ATTEMPT" MB_BANK="$BANK" \
    MB_REV_AGENT="$AGENT" MB_REV_MODEL="$REV" MB_THINKING="$THINKING" python3 - <<'PY'
import json, os, sys, datetime, pathlib

raw = os.environ["MB_RAW"]
topic = os.environ["MB_TOPIC"]
bank = os.environ["MB_BANK"]
outdir = os.path.join(bank, "tmp", "spec-review")

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
# Provenance honesty (review [4]): `reviewer` is asserted by the SAME caller
# that supplies the --reviewer-* flags, so matching them proves only internal
# consistency, never that the named model actually ran. The record therefore
# marks the identity as CLAIMED; no consumer may read it as verified
# provenance. Upgrading this to a verified value needs a dispatch receipt the
# caller cannot mint — deliberately not faked here.
rec["reviewer_provenance"] = "claimed"

# Containment (blocker #9 + review [5]): a symlinked `tmp/spec-review` used to
# pass the old parent-vs-parent comparison and divert the append outside the
# bank. Containment is now checked on the FINAL WRITE PATH against the
# canonical bank, and neither the directory nor the file may be a symlink.
real_bank = os.path.realpath(bank)
d = pathlib.Path(outdir)
if d.is_symlink():
    bad("path_escape")
d.mkdir(parents=True, exist_ok=True)
target = d / (topic + ".jsonl")
if target.is_symlink():
    bad("path_escape")
real_target = os.path.realpath(target)
expected = os.path.join(real_bank, "tmp", "spec-review", topic + ".jsonl")
if real_target != expected:
    bad("path_escape")
if os.path.commonpath([real_target, real_bank]) != real_bank:
    bad("path_escape")
with open(real_target, "a", encoding="utf-8") as fh:
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
