// Native command mechanics use portable MB scripts with argv data only.
import { spawn } from 'node:child_process';
import { access, readFile, readdir, stat } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { runWork } from './pi_native_work.mjs';

export function execute(file, args, cwd, { signal, env = {}, stdin = '', timeoutMs = 30000 } = {}) {
  return new Promise((resolveResult, reject) => {
    const child = spawn(file, args, { cwd, detached: process.platform !== 'win32',
      env: { ...process.env, MB_AGENT: 'pi', ...env }, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '', stderr = '', terminated;
    const stop = reason => {
      terminated = reason;
      try { process.platform === 'win32' ? child.kill('SIGKILL') : process.kill(-child.pid, 'SIGKILL'); } catch {}
    };
    const abort = () => stop('cancelled');
    const timer = setTimeout(() => stop('timed out'), timeoutMs);
    child.stdout.on('data', chunk => { stdout += chunk; if (stdout.length > 2 * 1024 * 1024) stop('output limit exceeded'); });
    child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-16384); });
    child.on('error', reject);
    child.on('close', code => {
      clearTimeout(timer); signal?.removeEventListener('abort', abort);
      if (terminated || code !== 0) reject(Object.assign(new Error(`${file}: ${terminated || `exit ${code}`} ${stderr}`), { stdout, code }));
      else resolveResult(stdout);
    });
    child.stdin.on('error', () => {}); child.stdin.end(stdin);
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
  });
}

// Bank of the live project via _lib.sh (local, global and legacy layouts); null when absent.
// Like mb-graph.sh, a session started in a project subfolder walks up to the nearest ancestor
// that resolves a bank, stopping at the filesystem root.
const WALK_UP = `source "$1"; d="$PWD"
while :; do
  b=$(cd "$d" && mb_resolve_path) && case "$b" in /*) ;; *) b="$d/$b" ;; esac
  [ -d "$b" ] && { printf '%s\\n' "$b"; exit 0; }
  [ "$d" = / ] && exit 0
  d=$(dirname "$d")
done`;

export async function findBank(skillDir, cwd, options = {}) {
  const output = (await execute('bash', ['-c', WALK_UP, 'mb-native', join(skillDir, 'scripts/_lib.sh')], cwd, options)).trim();
  if (!output) return null;
  const bank = resolve(cwd, output);
  return await stat(bank).then(s => s.isDirectory(), () => false) ? bank : null;
}

export async function registerNativeCommands(pi, skillDir, resolveLaunch) {
  let active;
  const python = await access(join(skillDir, '.venv/bin/python')).then(() => join(skillDir, '.venv/bin/python')).catch(() => 'python3');
  const decoder = async (mode, value, cwd) => {
    const text = await execute(python, [join(skillDir, 'adapters/pi_native_argv.py'), mode, value], cwd);
    try { return JSON.parse(text); }
    catch (error) { throw new Error(`Malformed ${mode} data from pi_native_argv.py: ${error.message}`); }
  };
  const script = (name, args, cwd, options = {}) => execute('bash', [join(skillDir, 'scripts', name), ...args], cwd, { ...options, env: { PATH: `${dirname(python)}:${process.env.PATH}`, ...options.env } });
  const resolveBank = async cwd => {
    const bank = await findBank(skillDir, cwd);
    if (!bank) throw new Error(`Memory bank absent: ${resolve(cwd, '.memory-bank')}`);
    return bank;
  };
  const templates = new Set((await readdir(join(skillDir, 'commands'))).filter(f => f.endsWith('.md')).map(f => f.slice(0, -3)));
  const handle = async (command, raw, ctx) => {
    if (command === 'work') {
      // Cancel must not pay the argv-decoder subprocess latency; a late abort can
      // miss the child it is meant to stop. The decoder path below stays for
      // forms like `work "--cancel"`.
      if (raw.trim() === '--cancel') {
        if (!active) throw new Error('No active native work run');
        active.abort(); return;
      }
      const argv = await decoder('argv', raw, ctx.cwd);
      if (argv.length === 1 && argv[0] === '--cancel') {
        if (!active) throw new Error('No active native work run');
        active.abort(); return;
      }
      if (active) throw new Error('Native work already active; concurrent execution refused');
      const controller = new AbortController(); active = controller;
      try {
        const bank = await resolveBank(ctx.cwd);
        const result = await runWork({ pi, ctx: { ...ctx, pi }, skillDir, bank, argv,
          script, decoder, resolveLaunch, signal: controller.signal });
        pi.sendMessage({ customType: 'mb-native-work', content: JSON.stringify(result), display: true }, { triggerTurn: false });
      } finally { if (active === controller) active = undefined; }
      return;
    }
    if (command === 'context' || command === 'start') {
      const argv = await decoder('argv', raw, ctx.cwd);
      if (argv.some(arg => !['--deep', '--full'].includes(arg))) throw new Error('Context accepts only --deep or --full');
      const bank = await resolveBank(ctx.cwd);
      const content = await script('mb-context.sh', [...argv, bank], ctx.cwd, { signal: ctx.signal });
      pi.sendMessage({ customType: 'mb-native-context', content, display: true }, { triggerTurn: false });
      return;
    }
    if (!templates.has(command) || command === 'mb') throw new Error(`Unknown MB command: ${command}`);
    const instructions = await readFile(join(skillDir, 'commands', `${command}.md`), 'utf8');
    pi.sendUserMessage(`${instructions}\n\nArguments (data): ${JSON.stringify(raw)}`);
  };
  pi.registerCommand('mb', { description: 'Native Memory Bank mechanics and explicit agentic templates',
    handler: async (args, ctx) => {
      const match = args.trim().match(/^(\S+)(?:\s+([\s\S]*))?$/);
      return handle(match?.[1] || 'context', match?.[2] || '', ctx);
    } });
  for (const name of templates) {
    if (name === 'mb') continue;
    pi.registerCommand(`mb-${name}`, { description: `Memory Bank ${name} (${['work', 'start'].includes(name) ? 'native' : 'agentic'})`,
      handler: (args, ctx) => handle(name, args, ctx) });
  }
  pi.registerCommand('mb-context', { description: 'Restore Memory Bank context without LLM routing', handler: (args, ctx) => handle('context', args, ctx) });
  pi.registerCommand('work', { description: 'Native governed Memory Bank execution', handler: (args, ctx) => handle('work', args, ctx) });
  pi.registerCommand('start', { description: 'Restore current Memory Bank context', handler: (args, ctx) => handle('start', args, ctx) });
  pi.on('session_shutdown', () => { active?.abort(); active = undefined; });
  return { decoder, resolveBank };
}
