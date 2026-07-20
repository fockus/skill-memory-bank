"""Canonical eval-proof payload for mb-work-state's red→green gate.

Why this module exists: the signed payload used to be inlined in four separate
bash heredocs (eval-red write, eval-green precondition, eval-green re-sign, and
the `done` gate). They drifted — `green_exit` was signed by none of them, so a
hand-edited `green_exit: 0` sailed through the `done` gate that was supposed to
require a real green run (review [11]). One definition, four callers.

HONEST SCOPE (AGR-026). `sign()` is NOT tamper-proof against a determined
adversary: the key lives in the checkout, so anyone who can edit the state file
can also read the key and forge a signature. What it does buy is *integrity
against casual/accidental edits* — a hand-patched state JSON is detected. Real
unforgeability requires the orchestrator-held key described in AGR-026, where
the signing key never enters the agent's process. Until that lands, callers must
describe this as checksum-grade integrity, not proof.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from typing import Any

#: Bumped whenever the signed field set changes, so an old proof cannot be
#: replayed against a newer, stricter verifier.
PROOF_KEY = "mb-work-state/eval-proof/v3"

#: Every field the proof commits to. `green_exit` is included deliberately:
#: without it the `done` gate accepts a forged green. `output_re`/`expected_exit`
#: are the DECLARED red anchors, committed so a recorded proof cannot later be
#: re-pointed at a different anchor than the one actually matched (review [10]).
SIGNED_FIELDS = (
    "cmd_hash",
    "red_exit",
    "red_observed",
    "red_match",
    "green_exit",
    "output_re",
    "expected_exit",
)


def signed_payload(evaluation: Mapping[str, Any]) -> str:
    """Deterministic serialization of the fields the signature commits to."""
    return json.dumps(
        {k: evaluation.get(k) for k in SIGNED_FIELDS},
        sort_keys=True,
        separators=(",", ":"),
    )


def sign(evaluation: Mapping[str, Any], key: str = PROOF_KEY) -> str:
    """Checksum binding the eval object's verdict fields (see module docstring)."""
    return hashlib.sha256((key + "\0" + signed_payload(evaluation)).encode("utf-8")).hexdigest()


def verify(evaluation: Mapping[str, Any], key: str = PROOF_KEY) -> bool:
    """True when the recorded `sig` matches the current verdict fields."""
    if not isinstance(evaluation, Mapping):
        return False
    recorded = evaluation.get("sig")
    if not isinstance(recorded, str) or not recorded:
        return False
    return sign(evaluation, key) == recorded


#: Separate key/field-set for the DECLARATION binding (r3 review [1]).
#:
#: The `done` gate used to re-read the Eval declaration from the live tasks.md,
#: so swapping `**Eval:** <cmd>` for `**Eval:** none — waiver: temporary`
#: between `init` and `done` turned a gated task into a waived one and recorded
#: the lie faithfully as `eval_gate=waived:eval_none`. Round 2 snapshotted the
#: eval COMMAND; presence and waiver status stayed on the mutable path.
#:
#: `init` now binds the whole declaration surface — verdict, command and red
#: anchors — and `done` re-derives it and requires equality. Same honest scope as
#: `sign()`: checksum-grade integrity against casual edits, not tamper-proofing.
DECL_KEY = "mb-work-state/eval-decl/v1"

DECL_FIELDS = ("verdict", "cmd", "anchors")


def decl_payload(decl: Mapping[str, Any]) -> str:
    """Deterministic serialization of the bound declaration fields."""
    return json.dumps(
        {k: decl.get(k) for k in DECL_FIELDS},
        sort_keys=True,
        separators=(",", ":"),
    )


def sign_decl(decl: Mapping[str, Any], key: str = DECL_KEY) -> str:
    """Checksum binding the declaration surface captured at `init`."""
    return hashlib.sha256((key + "\0" + decl_payload(decl)).encode("utf-8")).hexdigest()


def verify_decl(decl: Mapping[str, Any], key: str = DECL_KEY) -> bool:
    """True when the recorded declaration `sig` matches its fields."""
    if not isinstance(decl, Mapping):
        return False
    recorded = decl.get("sig")
    if not isinstance(recorded, str) or not recorded:
        return False
    return sign_decl(decl, key) == recorded
