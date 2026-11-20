#!/usr/bin/env node
// npm entry point: runs the bundled Python CLI (`python -m memory_bank_skill`).
// install.sh symlinks the skill to the directory it runs from, and the npx cache
// can be cleaned at any time, so the CLI runs from a persistent copy of this package.
"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const pkgRoot = path.resolve(__dirname, "..");
const version = fs.readFileSync(path.join(pkgRoot, "VERSION"), "utf8").trim();
const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share");
// ponytail: one copy per version and old ones stay; prune them if disk use ever matters.
const bundle = path.join(dataHome, "memory-bank-skill", "npm", version);

function ensureBundle() {
  if (fs.existsSync(path.join(bundle, "install.sh"))) return;
  fs.rmSync(bundle, { recursive: true, force: true });
  const tmp = `${bundle}.tmp-${process.pid}`;
  fs.cpSync(pkgRoot, tmp, { recursive: true });
  try {
    fs.renameSync(tmp, bundle);
  } catch (err) {
    fs.rmSync(tmp, { recursive: true, force: true });
    if (!fs.existsSync(path.join(bundle, "install.sh"))) throw err;
  }
}

const python = process.env.MB_PYTHON || "python3";
const probe = spawnSync(python, ["-c", "import sys; sys.exit(sys.version_info < (3, 11))"]);
if (probe.error || probe.status !== 0) {
  console.error(`[memory-bank] needs Python 3.11+ as \`${python}\` (set MB_PYTHON to another interpreter)`);
  process.exit(127);
}

ensureBundle();
const env = {
  ...process.env,
  MB_SKILL_BUNDLE: bundle,
  PYTHONPATH: [bundle, process.env.PYTHONPATH].filter(Boolean).join(path.delimiter),
};
const run = spawnSync(python, ["-m", "memory_bank_skill", ...process.argv.slice(2)], {
  stdio: "inherit",
  env,
});
process.exit(run.status ?? 1);
