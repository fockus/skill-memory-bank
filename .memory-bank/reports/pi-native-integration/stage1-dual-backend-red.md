# AGR-057/058 dual-backend observed RED

Before common-driver/backend product edits, wrote 17 selected-backend/common-gate contract cases in `tests/pytest/test_pi_native_backends.py` (fake remote roles, separate from real producer smoke).

Command: `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_backends.py -k selected_engine`

Actual output: **4 failed, 13 deselected in 1.01s**, exit 1. All four business assertions `assert not result.get("error")` failed because `--backend` is not supported; default/named pipelines cannot select either explicit backend. Collection/import/setup succeeded. Full output: `stage1-dual-backend-red.log`; exact pre-edit hashes: `stage1-dual-backend-preimages.json`.

Historical Nico RED/GREEN and original Stage 1 baseline are preserved. This RED does not claim Tintin controls, scoped roles or complete gate compatibility are implemented.
