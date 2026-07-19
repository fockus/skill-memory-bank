"""Drift guard for the eval-proof signed payload (svp-sdd-core review [11]).

Why this file exists, stated plainly: the round-2 fix for [11] was ITSELF
bypassable on its first cut. The `done` gate required a valid proof, but the
proof committed only to the red fields — `green_exit` was signed by none of the
four inlined copies of the payload — so a hand-edited `green_exit: 0` bought a
`done` without any green run. That is the same failure shape as round 1: a fix
that passes its own test while the property it claims does not hold.

The behavioural gate is covered in tests/bats/test_mb_work_prod_binding.bats.
These tests bind the PAYLOAD itself, so a future edit that quietly drops a field
fails here rather than silently making the gate decorative again.
"""

from __future__ import annotations

import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import mb_work_eval_proof as proof  # noqa: E402

#: Every field the `done` gate's decision depends on. Dropping any one of them
#: makes that part of the verdict forgeable by editing the state file.
REQUIRED_SIGNED_FIELDS = {
    "cmd_hash",
    "red_exit",
    "red_observed",
    "red_match",
    "green_exit",
    "output_re",
    "expected_exit",
}


def _eval_obj(**overrides):
    base = {
        "cmd_hash": "a" * 64,
        "red_exit": 1,
        "red_observed": True,
        "red_match": True,
        "green_exit": 0,
        "output_re": "GATE-RED",
        "expected_exit": "1",
    }
    base.update(overrides)
    return base


def test_signed_fields_cover_every_verdict_input() -> None:
    missing = REQUIRED_SIGNED_FIELDS - set(proof.SIGNED_FIELDS)
    assert missing == set(), (
        f"fields dropped from the signed payload: {sorted(missing)} — "
        "anything unsigned is forgeable by editing .work-state.json"
    )


def test_green_exit_is_signed() -> None:
    """The exact regression that made the first [11] fix bypassable."""
    e = _eval_obj(green_exit=1)
    e["sig"] = proof.sign(e)
    assert proof.verify(e)
    e["green_exit"] = 0  # forge a green without running it
    assert not proof.verify(e), "a forged green_exit still verifies"


def test_each_signed_field_actually_changes_the_signature() -> None:
    """A field in SIGNED_FIELDS that the hash ignores would be a silent hole."""
    e = _eval_obj()
    e["sig"] = proof.sign(e)
    tweaks = {
        "cmd_hash": "b" * 64,
        "red_exit": 2,
        "red_observed": False,
        "red_match": False,
        "green_exit": 1,
        "output_re": "SOMETHING-ELSE",
        "expected_exit": "2",
    }
    for field, value in tweaks.items():
        tampered = dict(e)
        tampered[field] = value
        assert not proof.verify(tampered), (
            f"tampering with {field!r} left the signature valid — "
            "it is listed as signed but does not affect the hash"
        )


def test_verify_rejects_a_missing_or_empty_signature() -> None:
    assert not proof.verify(_eval_obj())  # no sig at all
    assert not proof.verify(_eval_obj(sig=""))
    assert not proof.verify(_eval_obj(sig=None))


def test_proof_key_is_versioned_with_the_field_set() -> None:
    """Changing the signed fields must invalidate old proofs, not accept them."""
    assert proof.PROOF_KEY.rsplit("/", 1)[-1].startswith("v")
    e = _eval_obj()
    e["sig"] = proof.sign(e, key="mb-work-state/eval-proof/v1")
    assert not proof.verify(e), "a proof signed with an older key still verifies"
