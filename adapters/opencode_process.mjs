// Bounded trusted-hook groups and observed descendants; not an OS sandbox (AGR-110).
import { execFile, spawn } from 'node:child_process';
import * as path from 'node:path';
import { promisify } from 'node:util';

// Resolve inside the existing bounded job, including validation and shell grandchildren.
const bundledBootstrap = `umask 077
root="$1"; shift
. "$root/scripts/_lib.sh" || exit 78
physical="$(cd "$root" && pwd -P)" || exit 78
if [ -z "\${MB_PYTHON:-}" ]; then
  case "$physical" in
    */share/memory-bank-skill) [ -x "\${physical%/share/memory-bank-skill}/bin/python3" ] || exit 78 ;;
  esac
fi
python="$(mb_resolve_python "$root")" || exit 78
python="$(command -v "$python")" || exit 78
case "$python" in
  /*) ;;
  *) python="$(cd "$(dirname "$python")" && pwd -P)/$(basename "$python")" || exit 78 ;;
esac
[ -x "$python" ] || exit 78
probe='import json, sys
from pathlib import Path
assert sys.version_info >= (3, 11)
import memory_bank_skill, yaml
from memory_bank_skill.pipeline_yaml import load_text
print(json.dumps([sys.prefix, sys.version_info[:3], str(Path(memory_bank_skill.__file__).resolve())]))'
identity="$("$python" -P -c "$probe" 2>/dev/null)" || exit 79
other="$("\${python%/*}/python3" -P -c "$probe" 2>/dev/null)" || exit 80
[ "$identity" = "$other" ] || exit 80
export MB_PYTHON="$python" PATH="\${python%/*}:$PATH"
if [ "$1" = python3 ]; then shift; set -- "$python" "$@"; fi
exec "$@"`;

async function descendants(seeds) {
  const { stdout } = await promisify(execFile)('ps', ['-ax', '-o', 'pid=,ppid='], { timeout: 1000, maxBuffer: 1024 * 1024 });
  const parents = new Map();
  for (const row of stdout.trim().split('\n')) {
    const [child, parent] = row.trim().split(/\s+/).map(Number);
    if (child > 0 && parent > 0) parents.set(child, parent);
  }
  const found = new Set(seeds);
  let changed = true;
  while (changed) {
    changed = false;
    for (const [child, parent] of parents) if (found.has(parent) && !found.has(child)) { found.add(child); changed = true; }
  }
  return [...found].reverse();
}

export function createRunner(root, cwd, signal) {
  const active = new Set();
  let closed = false;
  async function run(relative, args = [], input = '', options = {}) {
    if (closed || signal.aborted) throw new Error('[MB] BLOCKED: runtime cancelled');
    if (options.trustedCustom && (!process.env.MB_SUMMARIZE_BIN || relative !== process.env.MB_SUMMARIZE_BIN)) {
      throw new Error('[MB] BLOCKED: invalid external helper');
    }
    const file = options.trustedCustom ? relative : path.resolve(root, relative);
    if (!options.trustedCustom && (!file.startsWith(`${root}${path.sep}`) || !/^(hooks|scripts|adapters)\//.test(relative))) {
      throw new Error('[MB] BLOCKED: invalid helper');
    }
    const command = file.endsWith('.py') ? 'python3' : 'bash';
    const env = { ...process.env, MB_AGENT: 'opencode', MB_SKILLS_ROOT: root, MB_PROJECT_ROOT: cwd,
      CLAUDE_PROJECT_DIR: cwd, PYTHONPATH: [root, process.env.PYTHONPATH].filter(Boolean).join(path.delimiter), ...options.env, MB_PIPELINE_HOST: 'opencode' };
    if (!options.trustedCustom) {
      // Per-call policy overlays cannot replace the host's core interpreter binding.
      for (const key of ['MB_PYTHON', 'PATH', 'PYTHONHOME']) {
        if (process.env[key] === undefined) delete env[key]; else env[key] = process.env[key];
      }
      env.PYTHONPATH = [root, process.env.PYTHONPATH].filter(Boolean).join(path.delimiter);
    }
    const job = {};
    const promise = new Promise((resolve, reject) => {
      const child = spawn('bash', ['-c', options.trustedCustom ? 'umask 077; exec "$@"' : bundledBootstrap,
        'mb-opencode', ...(options.trustedCustom ? [] : [root]), command, file, ...args], { cwd: options.cwd || cwd, detached: true,
        stdio: ['pipe', 'pipe', 'pipe'],
        env,
      });
      let output = '', bytes = 0, failure, escalation;
      const owned = new Set([child.pid]);
      let observing = true, termination = Promise.resolve();
      // Retain ancestry while it exists: successful parents can also orphan setsid children.
      // ponytail: unobserved reparenting, including a single fork/setsid, can escape; no OS containment (AGR-110).
      const observer = (async () => {
        while (observing) {
          try { for (const pid of await descendants(owned)) owned.add(pid); }
          catch { /* The original process group remains owned if ps is unavailable. */ }
          if (observing) await new Promise(resolve => setTimeout(resolve, 10));
        }
      })();
      const kill = sig => {
        for (const pid of owned) {
          try { process.kill(-pid, sig); } catch { /* Not a process-group leader. */ }
          try { process.kill(pid, sig); } catch { /* Already reaped. */ }
        }
      };
      const stop = reason => {
        if (failure) return;
        failure = reason;
        observing = false;
        // Snapshot before killing parents: nested setsid children otherwise escape ownership.
        termination = observer.then(() => descendants(owned)).catch(() => owned).then(pids => {
          for (const pid of pids) owned.add(pid);
          kill('SIGTERM');
          escalation = setTimeout(() => kill('SIGKILL'), 100);
        });
      };
      job.stop = () => stop('cancelled');
      const onAbort = () => stop('cancelled');
      signal.addEventListener('abort', onAbort, { once: true });
      const timer = setTimeout(() => stop('timed out'), options.timeout ?? 5000);
      const collect = (chunk, stdout) => {
        bytes += chunk.length;
        if (bytes > 65536) stop('output limit exceeded');
        else if (stdout) output += chunk.toString();
      };
      child.stdout.on('data', c => collect(c, true));
      child.stderr.on('data', c => collect(c, false));
      child.stdin.on('error', () => {});
      child.on('error', () => { failure = 'helper unavailable'; });
      child.on('close', async code => {
        clearTimeout(timer);
        observing = false;
        await observer;
        await termination;
        // Kill observed ignored-stdio descendants left behind by a completed helper.
        kill('SIGKILL');
        for (let i = 0; i < 20; i++) {
          const alive = [...owned].some(pid => { try { process.kill(pid, 0); return true; } catch { return false; } });
          if (!alive) break;
          await new Promise(resolve => setTimeout(resolve, 10));
        }
        clearTimeout(escalation);
        signal.removeEventListener('abort', onAbort);
        const runtimeError = !options.trustedCustom && ({
          78: 'Python runtime unavailable; repair MB_PYTHON or reinstall the owning environment',
          79: 'Python runtime needs Python 3.11+, memory_bank_skill and optional PyYAML in its owning environment',
          80: 'Python environment mismatch: sibling python3 must use the selected environment',
        })[code];
        if (!failure && runtimeError) { reject(new Error(`[MB] BLOCKED: ${runtimeError}`)); return; }
        if (failure || (code !== 0 && !(options.allowSoft && code === 1))) {
          reject(new Error(`[MB] BLOCKED: ${path.basename(file)} refused (${failure || `exit ${code}`})`));
        } else resolve(output.trim());
      });
      child.stdin.end(typeof input === 'string' ? input : JSON.stringify(input));
    });
    job.promise = promise;
    active.add(job);
    try { return await promise; } finally { active.delete(job); }
  }
  return {
    run,
    optional: (...args) => run(...args).catch(() => ''),
    async dispose() {
      closed = true;
      for (const job of active) job.stop();
      await Promise.allSettled([...active].map(job => job.promise));
    },
  };
}
