# Stage 1 behavioral RED

Command: `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py`
Exit: 1. Output: `24 failed in 5.09s`. All tests reach the real legacy extension command factory; failures observe prompt forwarding/missing aliases/no named RPC child steps, not module import errors. Full retained output: stage1-red.log. Harness-only preliminary failures (placeholder replacement/init script typo) corrected before this RED.

Source hashes before product code:
```json
{
  "adapters/pi_subagent_extension.ts": "63e608274745a40a129fdefed8e1fcbe121face22a3f5d437f87cfdfad4a9907",
  "adapters/pi_native_commands.mjs": null,
  "adapters/pi_native_subagents.mjs": null,
  "adapters/pi_native_work.mjs": null,
  "adapters/pi_native_argv.py": null,
  "tests/pytest/test_pi_native_commands.py": "dd1e277d89f5b924fcd40b2dd2adf5fda11cec8a9967718bc5dbdf184638603a",
  "tests/pytest/test_pi_native_work.py": "4998e5679ecc97e1f62fb261b21278f32725fc849e40381f68e8264327203cfc",
  "tests/fixtures/pi_native_host.mjs": "3cc53bc2684b252db5edc426c9b8870c91c0a0175d7e78f9ddeb8226d4daf48d",
  "references/pi-native-integration.md": null
}
```

## Additional gates before work driver
29 failures in 6.11s, pytest exit 1 (the wrapper echo incorrectly reflected tail exit 0; actual pytest summary is RED). The extra tests preceded work driver/TS native wiring. Initial command bridge edits had already begun after original 24-test RED.

## Self-review RED for alias/resume/runtime usage
`.venv/bin/python -m pytest -q tests/pytest/test_pi_native_work.py -k "work_alias or resume or runtime_usage or late_terminal or same_source"`: exit 1; `3 failed, 2 passed, 22 deselected in 5.31s`. Working driver lacks work alias/resume and incorrectly trusts child-reported usage. Before fixes source hashes:
```json
{
  "adapters/pi_subagent_extension.ts": "997ad17a7f371f2f15679bd93212315c2d5d48c453dccae32b424d929cef6bac",
  "adapters/pi_native_commands.mjs": "87ab2984b0be9ae548dbf4830783fca7b04c07a8ea8c0a0fa64ec7277ad174f8",
  "adapters/pi_native_subagents.mjs": "31212f906e864236a05e422e49771892976efeed41a4cfd397ba1db46af8c561",
  "adapters/pi_native_work.mjs": "f4d90d57b6fa5b27033f52c57c4713457ad7abc079a7d0d4ea2b975a63c4619c",
  "adapters/pi_native_argv.py": "89331895b1ba3300906f11c46abe057873435dc3f875b74819b04fe32f5b6ca5",
  "tests/pytest/test_pi_native_commands.py": "faae37a45f1bc98b47989a364c0e035bd2c71f1723c22e6d83a46f50eea4354d",
  "tests/pytest/test_pi_native_work.py": "1e1b019e04947a623c72cf59413de998d92dd3f1cd29e4a558a879df7cb28f5f",
  "tests/fixtures/pi_native_host.mjs": "299e27ec8322a2174c8554e8fb4f06a18247d979bbfb36a40ededb1e218be283",
  "references/pi-native-integration.md": "7c88f476a5db2d64594637c20d8267747c397cbf7f2e0362c61ce9d789d37557"
}
```

Paused native terminal RED: `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_work.py -k paused`, exit 1, `1 failed, 27 deselected in 1.28s`. Public runner source confirms paused can have exitCode=0; completion now must also prove state/success. Source hashes pre-fix:
```json
{
  "adapters/pi_subagent_extension.ts": "997ad17a7f371f2f15679bd93212315c2d5d48c453dccae32b424d929cef6bac",
  "adapters/pi_native_commands.mjs": "87ab2984b0be9ae548dbf4830783fca7b04c07a8ea8c0a0fa64ec7277ad174f8",
  "adapters/pi_native_subagents.mjs": "31212f906e864236a05e422e49771892976efeed41a4cfd397ba1db46af8c561",
  "adapters/pi_native_work.mjs": "f4d90d57b6fa5b27033f52c57c4713457ad7abc079a7d0d4ea2b975a63c4619c",
  "adapters/pi_native_argv.py": "89331895b1ba3300906f11c46abe057873435dc3f875b74819b04fe32f5b6ca5",
  "tests/pytest/test_pi_native_commands.py": "faae37a45f1bc98b47989a364c0e035bd2c71f1723c22e6d83a46f50eea4354d",
  "tests/pytest/test_pi_native_work.py": "bbea146a993e748fe827d6da67f55c120ab6670caedc1f08ff839104ab062356",
  "tests/fixtures/pi_native_host.mjs": "11dfb0c80b04675409ac2de5e26687a83414becf9744a38ddd7e7f6c9e965f3e",
  "references/pi-native-integration.md": "7c88f476a5db2d64594637c20d8267747c397cbf7f2e0362c61ce9d789d37557"
}
```

Self-review gates RED: `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_work.py -k "failed_acceptance or go_with_backlog or unbound_main"`, exit 1; `3 failed, 28 deselected in 4.16s`. Ensemble profile RED also exit 1 (stage1-ensemble-red.log). Before product fixes:
```json
{
  "adapters/pi_subagent_extension.ts": "997ad17a7f371f2f15679bd93212315c2d5d48c453dccae32b424d929cef6bac",
  "adapters/pi_native_commands.mjs": "b65b7ddba4cb692cb61dd5ffb1fbe94dbf8dc402518aad2fe2ada182eaa3b6aa",
  "adapters/pi_native_subagents.mjs": "0d3666ae60d928c9e017d82d7c9c0ca7826bd577ebb681d61402e1d8b875f3e4",
  "adapters/pi_native_work.mjs": "ceb17958ef443ac498644ad5d3c64cadde99d1a494daa17dced2705ed31a7ce2",
  "adapters/pi_native_argv.py": "89331895b1ba3300906f11c46abe057873435dc3f875b74819b04fe32f5b6ca5",
  "tests/pytest/test_pi_native_commands.py": "faae37a45f1bc98b47989a364c0e035bd2c71f1723c22e6d83a46f50eea4354d",
  "tests/pytest/test_pi_native_work.py": "55ae33b7b92f843fe546b05d78c450d51141a5c86080c90c68ad240e8ff537f5",
  "tests/fixtures/pi_native_host.mjs": "d4eec0301d685d74885aa09c1c7eb7ac6e788dcd13f0164320f6b1953e4e4e09",
  "references/pi-native-integration.md": "7c88f476a5db2d64594637c20d8267747c397cbf7f2e0362c61ce9d789d37557"
}
```

Actual public preflight resolves contract.model with a documented thinking suffix; mocked boundary updated to match that DTO. Native provider tests RED before product change: `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_work.py -k "named_pipeline_dispatch or cross_provider_override"`, exit 1. Details stage1-model-suffix-red.log. Before normalization fix:
```json
{
  "adapters/pi_subagent_extension.ts": "997ad17a7f371f2f15679bd93212315c2d5d48c453dccae32b424d929cef6bac",
  "adapters/pi_native_commands.mjs": "b65b7ddba4cb692cb61dd5ffb1fbe94dbf8dc402518aad2fe2ada182eaa3b6aa",
  "adapters/pi_native_subagents.mjs": "0d3666ae60d928c9e017d82d7c9c0ca7826bd577ebb681d61402e1d8b875f3e4",
  "adapters/pi_native_work.mjs": "ff2b671bb55822b427c933fb05da9be4797934359b2aba1e99ce6b865e770f3a",
  "adapters/pi_native_argv.py": "89331895b1ba3300906f11c46abe057873435dc3f875b74819b04fe32f5b6ca5",
  "tests/pytest/test_pi_native_commands.py": "faae37a45f1bc98b47989a364c0e035bd2c71f1723c22e6d83a46f50eea4354d",
  "tests/pytest/test_pi_native_work.py": "55ae33b7b92f843fe546b05d78c450d51141a5c86080c90c68ad240e8ff537f5",
  "tests/fixtures/pi_native_host.mjs": "8832c27a2059dfc13b056fbe536c5087041c1971012aa95b92ccbd9036777634",
  "references/pi-native-integration.md": "7c88f476a5db2d64594637c20d8267747c397cbf7f2e0362c61ce9d789d37557"
}
```

Spawn-handshake cancellation RED: `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_work.py -k during_spawn`, exit 1; stage1-spawn-cancel-red.log. Bridge before fix SHA256 d3423ded7d70ba797e5ddf7204e3d879652775481f69030140de5220ebea55fa. Cancelling in-flight spawn previously discarded child identity before its public RPC reply.

Durable evidence RED: `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_work.py -k "cross_provider_override or resume_reverifies"`, exit 1 (stage1-receipts-red.log). Authorized provider evidence was absent from identity; resume reused a prior role-output filename. Before fix SHA256 ff2b671bb55822b427c933fb05da9be4797934359b2aba1e99ce6b865e770f3a.
