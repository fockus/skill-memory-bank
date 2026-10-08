# AGR-058 managed host — observed RED before production edits

Command: `PATH="$PWD/.venv/bin:$PATH" pytest -q tests/pytest/test_pi_native_host.py -k managed_factory_binding`

Actual result: **1 failed, 12 deselected in 0.75s**, exit 1. Business assertion `assert result["ready"]` failed: the actual public SDK 1.0.2 ordinary session exists with a real session ID, but has no authoritative managed MB binding (`ready=false`). No collection/import/setup failure. Fixture runs without prompts or child calls in sandbox HOME.

The complete 13 host/lifecycle contract scenarios were written before new host production modules. Pre-edit SHA-256/ABSENT records are in `stage1-managed-host-preimages.json`; complete output in `stage1-managed-host-red.log`. Historical Nico receipts remain unchanged. Factory-attributed Tintin settings and public runtime binding still require GREEN plus separate actual pinned-factory smoke; this RED is not compatibility proof.
