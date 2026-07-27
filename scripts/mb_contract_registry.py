"""The Contract-checkers registry — one reader, one schema, two consumers.

svp-contract-test-loop C3a. The registry is a fenced ```json Contract-checkers```
block inside the body of the contract task in `<spec-dir>/tasks.md`.

WHY THIS IS A MODULE AND NOT TWO COPIES
───────────────────────────────────────
Two things read this block: `mb_spec_validate_layers.py`, which reports a
malformed registry as a spec violation, and `mb-contract-gate.sh`, which
refuses to execute one at all. The design states the closed schema twice, once
per consumer, in the same words. Two implementations of one closed schema drift
in exactly one direction — one side accepts what the other rejects — and the
symptom is a registry that passes `mb-spec-validate.sh` and then dies at exit 2
inside the gate, or worse, the reverse. So the schema lives here and both
callers get the same verdict and the same wording.

The split of responsibility is deliberate:

* Everything decidable from the TEXT is here — key set, types, id grammar,
  evidence shape, whether the ERE compiles.
* Everything needing the FILESYSTEM (does the topic directory resolve outside
  the bank through a symlink?) belongs to the gate, which is the only consumer
  that has a bank to resolve against.

`output_ere` is compiled with `grep -E`, the same engine that will match it at
run time, so a Python-only construct like `(?=…)` is rejected here rather than
silently never matching later.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

LAYERS = ("contract", "integration", "e2e")
CHECKER_KEYS = ("id", "covers", "path", "argv", "evidence", "output_ere")
PHASES = ("red", "verify")
EVIDENCE_ROOT = "tmp/contract-gate"

LAYER_FIELD_RE = re.compile(r"^\*\*Layer:\*\*[ \t]*(.*?)[ \t]*$", re.IGNORECASE | re.MULTILINE)
REGISTRY_RE = re.compile(
    r"^```json[ \t]+Contract-checkers[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL
)
_CHECKER_ID_RE = re.compile(r"^[a-z0-9_]+$")
_REQ_TOKEN_RE = re.compile(r"^(?:[A-Za-z0-9_.-]+:)?REQ-[A-Za-z0-9-]+$")


def layer_of(body: str) -> str | None:
    """The task's ``**Layer:**`` value, or None for an implementation task."""
    m = LAYER_FIELD_RE.search(body or "")
    return m.group(1) if m else None


def find_registry(body: str) -> str | None:
    """The raw JSON text of the registry block, or None when absent."""
    m = REGISTRY_RE.search(body or "")
    return m.group(1) if m else None


def canonical_cmd(argv) -> str:
    """The command as a byte-comparable string: compact JSON of the argv."""
    return json.dumps(list(argv), separators=(",", ":"))


def cmd_digest(cmd: str) -> str:
    return hashlib.sha256(cmd.encode("utf-8")).hexdigest()


def ere_ok(pattern: str) -> bool:
    """Compile with the engine that will match it later (grep -E, exit 2)."""
    try:
        return (
            subprocess.run(
                ["grep", "-E", "--", pattern],
                input="",
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            ).returncode
            != 2
        )
    except OSError:
        return False


def ere_match(pattern: str, text: str) -> bool:
    """True when the declared signature appears in the checker's output."""
    try:
        return (
            subprocess.run(
                ["grep", "-E", "-q", "--", pattern],
                input=text,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            ).returncode
            == 0
        )
    except OSError:
        return False


# ── schema ──────────────────────────────────────────────────────────────────


def _check_evidence(label: str, value, prefix: str, errors: list) -> None:
    if not isinstance(value, str) or not value:
        errors.append("Contract-checkers: checker %s evidence must be a non-empty string" % label)
        return
    if value.startswith("/"):
        errors.append(
            "Contract-checkers: checker %s evidence must be bank-relative, got `%s`"
            % (label, value)
        )
        return
    if ".." in Path(value).parts:
        errors.append(
            "Contract-checkers: checker %s evidence must not escape the bank: `%s`" % (label, value)
        )
        return
    if not value.startswith(prefix):
        errors.append(
            "Contract-checkers: checker %s evidence must live under `%s`, got `%s`"
            % (label, prefix, value)
        )
        return
    if "{phase}" not in value:
        errors.append(
            "Contract-checkers: checker %s evidence needs the `{phase}` placeholder" % label
        )


def _check_checker(entry, index: int, prefix: str, ids: set, errors: list) -> None:
    label = "#%d" % index
    if not isinstance(entry, dict):
        errors.append("Contract-checkers: checker %s must be an object" % label)
        return
    if isinstance(entry.get("id"), str):
        label = "`%s`" % entry["id"]

    for key in entry:
        if key not in CHECKER_KEYS:
            errors.append("Contract-checkers: checker %s has an unknown key `%s`" % (label, key))
    for key in CHECKER_KEYS:
        if key not in entry:
            errors.append("Contract-checkers: checker %s is missing key `%s`" % (label, key))

    ident = entry.get("id")
    if not isinstance(ident, str) or not _CHECKER_ID_RE.match(ident):
        errors.append("Contract-checkers: checker %s id must match [a-z0-9_]+" % label)
    elif ident in ids:
        errors.append("Contract-checkers: checker id `%s` is used more than once" % ident)
    else:
        ids.add(ident)

    covers = entry.get("covers")
    if not isinstance(covers, list) or not covers:
        errors.append("Contract-checkers: checker %s covers must be a non-empty array" % label)
    else:
        for token in covers:
            if not isinstance(token, str) or not _REQ_TOKEN_RE.match(token):
                errors.append(
                    "Contract-checkers: checker %s covers `%s` is not a REQ-ID" % (label, token)
                )

    if not isinstance(entry.get("path"), str) or not entry["path"]:
        errors.append("Contract-checkers: checker %s path must be a non-empty string" % label)

    argv = entry.get("argv")
    if not isinstance(argv, list) or not argv or not all(isinstance(a, str) for a in argv):
        errors.append(
            "Contract-checkers: checker %s argv must be a non-empty array of strings" % label
        )

    if "evidence" in entry:
        _check_evidence(label, entry["evidence"], prefix, errors)

    ere = entry.get("output_ere")
    if not isinstance(ere, str) or not ere:
        errors.append("Contract-checkers: checker %s output_ere must be a non-empty string" % label)
    elif not ere_ok(ere):
        errors.append(
            "Contract-checkers: checker %s output_ere does not compile as a POSIX ERE" % label
        )


def parse_registry(text: str, topic: str) -> tuple:
    """``(checkers, errors)`` for the registry's raw JSON text.

    ``checkers`` is the declared list when the outer shape is sound, so a
    caller can still report per-checker problems; it is empty when the block
    is not even a JSON object with a non-empty ``checkers`` array. ``errors``
    is empty only when the registry fully satisfies the closed schema.
    """
    errors: list = []
    try:
        data = json.loads(text)
    except ValueError as exc:
        return [], ["Contract-checkers: block is not valid JSON — %s" % exc]

    if not isinstance(data, dict):
        return [], ["Contract-checkers: block must be a JSON object"]
    for key in data:
        if key != "checkers":
            errors.append("Contract-checkers: unknown top-level key `%s`" % key)
    checkers = data.get("checkers")
    if not isinstance(checkers, list) or not checkers:
        errors.append("Contract-checkers: a non-empty `checkers` array is required")
        return [], errors

    prefix = "%s/%s/" % (EVIDENCE_ROOT, topic)
    ids: set = set()
    for index, entry in enumerate(checkers, 1):
        _check_checker(entry, index, prefix, ids, errors)
    return checkers, errors


def covered_reqs(checkers) -> set:
    """Canonical REQ-IDs claimed by the registry's ``covers`` fields."""
    out: set = set()
    for entry in checkers:
        if not isinstance(entry, dict):
            continue
        for token in entry.get("covers") or []:
            if isinstance(token, str) and _REQ_TOKEN_RE.match(token):
                out.add(token.split(":")[-1])
    return out
