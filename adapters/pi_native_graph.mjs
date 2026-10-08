// Pi GraphRAG: native code_context/graph/search tools and graph lifecycle hooks over the
// portable MB scripts. Every call resolves the bank of the live ctx.cwd; failures are thrown
// (Pi marks the tool result as an error), weaker answers are labeled `degraded`.
import { access, appendFile, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { execute, findBank } from './pi_native_commands.mjs';

const TOOL_TIMEOUT_MS = 90000;
const CATCHUP_TIMEOUT_MS = 120000;
const HOOK_TIMEOUT_MS = 10000;
const CODE_FILE = /\.(py|go|js|jsx|ts|tsx|rs|java)$/;
const STRUCTURAL_BASH = /(^|[;&|\s])(rtk\s+)?(rg|grep|egrep)(\s|$)/;

const parse = text => { try { return JSON.parse(text); } catch { return null; } };
const exists = path => access(path).then(() => true, () => false);

export function registerGraphRag(pi, { Type, skillDir, projectRoot = '', python }) {
  const interpreter = python ? Promise.resolve(python)
    : exists(join(skillDir, '.venv/bin/python')).then(ok => ok ? join(skillDir, '.venv/bin/python') : 'python3');
  const scriptPath = name => join(skillDir, 'scripts', name);

  // Resolve per call: the live project, never the install-time one (global installs bake '').
  async function locate(ctx) {
    const cwd = projectRoot || ctx.cwd;
    const bank = await findBank(skillDir, cwd, { timeoutMs: HOOK_TIMEOUT_MS });
    if (!bank) return { cwd, bank: null };
    // A global bank does not sit inside its project: the source root is then the live cwd.
    const root = basename(bank) === '.memory-bank' ? dirname(bank) : cwd;
    return { cwd, bank, root, graph: join(bank, 'codebase', 'graph.json') };
  }

  async function runJson(tool, argv, cwd, signal) {
    let stdout;
    try {
      stdout = await execute(await interpreter, argv, cwd, { signal, timeoutMs: TOOL_TIMEOUT_MS });
    } catch (error) {
      const payload = parse(error.stdout || '');
      const reason = payload?.error || payload?.warnings?.join('; ') || payload?.message;
      throw new Error(`${tool} failed: ${reason ? `${JSON.stringify(reason)}; ` : ''}${String(error.message).trim()}`);
    }
    const payload = parse(stdout);
    if (!payload || typeof payload !== 'object') throw new Error(`${tool} failed: script printed no JSON result`);
    if (payload.ok === false) throw new Error(`${tool} failed: ${JSON.stringify(payload.error || payload.warnings || payload)}`);
    return payload;
  }

  function result(payload, reasons) {
    const status = reasons.length ? 'degraded' : 'ok';
    const head = status === 'ok' ? 'status: ok' : `status: degraded — ${reasons.join('; ')}`;
    return { content: [{ type: 'text', text: `${head}\n${JSON.stringify(payload, null, 2)}` }],
      details: { status, reasons, payload } };
  }

  const tools = {
    code_context: {
      description: 'GraphRAG-lite code context for the current project: semantic candidates, graph expansion, text/read fallback.',
      promptSnippet: 'Use code_context for ambiguous code-understanding questions.',
      promptGuidelines: [
        'Use code_context when the user asks where logic lives or how code fits together.',
        'Use graph tools directly for exact callers/imports/impact/tests questions; search_code for concept search.',
      ],
      parameters: {
        query: Type.String({ description: 'Natural-language code question' }),
        mode: Type.Optional(Type.String({ description: 'auto | graph | semantic' })),
        semanticCandidates: Type.Optional(Type.String({ description: 'JSON file with semantic candidates' })),
        semanticProvider: Type.Optional(Type.String({ description: 'none | unavailable' })),
        semanticOnly: Type.Optional(Type.Boolean({ description: 'Use only semantic candidates and recommended reads' })),
      },
      argv: (p, loc) => [scriptPath('mb-code-context.py'), '--query', p.query, '--project-root', loc.root,
        '--mb-path', loc.bank, '--mode', p.mode || 'auto', '--json',
        ...(p.semanticCandidates ? ['--semantic-candidates', p.semanticCandidates] : []),
        ...(p.semanticProvider ? ['--semantic-provider', p.semanticProvider] : []),
        ...(p.semanticOnly ? ['--semantic-only'] : [])],
      reasons: payload => payload.warnings || [],
    },
    search_code: {
      description: 'Concept search over the current project code graph (embeddings when the local vector index is warm, otherwise labeled BM25).',
      parameters: {
        query: Type.String({ description: 'Exact name or natural-language phrase' }),
        backend: Type.Optional(Type.String({ description: 'auto | embeddings | bm25 (default auto)' })),
        k: Type.Optional(Type.Number({ description: 'Number of hits (default 10)' })),
        sourceOnly: Type.Optional(Type.Boolean({ description: 'Exclude test/spec files' })),
      },
      argv: (p, loc) => [scriptPath('mb-semantic-search.py'), p.query, '--backend', p.backend || 'auto',
        '--k', String(p.k || 10), '--json', ...(p.sourceOnly ? ['--source-only'] : []), loc.bank],
      reasons: (payload, p) => [
        ...((p.backend || 'auto') !== 'bm25' && payload.backend === 'bm25' ? ['vector search unavailable — BM25 fallback (lexical match only)'] : []),
        ...(payload.warnings || []),
      ],
    },
  };
  for (const [name, command, description] of [
    ['graph_neighbors', 'neighbors', 'Incoming/outgoing code-graph edges for a symbol or file in the current project.'],
    ['graph_impact', 'impact', 'Dependents, dependencies and tests for a symbol or file in the current project.'],
    ['graph_tests', 'tests', 'Tests linked to a symbol or file in the current project.'],
  ]) {
    tools[name] = {
      description,
      parameters: {
        symbol: Type.Optional(Type.String({ description: 'Symbol name' })),
        file: Type.Optional(Type.String({ description: 'File path' })),
      },
      argv: (p, loc) => [scriptPath('mb-graph-query.py'), command, '--graph', loc.graph, '--json',
        ...(p.symbol ? ['--symbol', p.symbol] : []), ...(p.file ? ['--file', p.file] : [])],
      reasons: payload => payload.graph_catchup ? [`graph catch-up ${payload.graph_catchup.result}: answer may be stale`] : [],
    };
  }

  for (const [name, spec] of Object.entries(tools)) {
    pi.registerTool({
      name, label: `Memory Bank ${name}`, description: spec.description,
      ...(spec.promptSnippet ? { promptSnippet: spec.promptSnippet, promptGuidelines: spec.promptGuidelines } : {}),
      parameters: Type.Object(spec.parameters),
      async execute(_toolCallId, params, signal, _onUpdate, ctx) {
        const loc = await locate(ctx);
        if (!loc.bank) throw new Error(`${name} failed: no Memory Bank for ${loc.cwd}`);
        const payload = await runJson(name, spec.argv(params, loc), loc.root, signal);
        return result(payload, spec.reasons(payload, params));
      },
    });
  }

  // Lifecycle — fail-open: graph upkeep never blocks or breaks the session.
  pi.on('session_start', async (_event, ctx) => {
    if (process.env.MB_GRAPH_CATCHUP === 'off') return;
    const loc = await locate(ctx).catch(() => ({}));
    if (!loc.bank || !await exists(loc.graph)) return;
    // Detached from startup: the bounded single-consumer catch-up (flock, budget, cooldown).
    const log = join(loc.bank, 'codebase', '.graph-catchup.log');
    void interpreter
      .then(py => execute(py, [scriptPath('mb-graph-query.py'), 'catchup', '--graph', loc.graph, '--src-root', loc.root, '--json'],
        loc.root, { timeoutMs: CATCHUP_TIMEOUT_MS }))
      .then(out => writeFile(log, out), error => writeFile(log, `${JSON.stringify({ result: 'error', error: String(error.message) })}\n`))
      .catch(() => {});
  });

  pi.on('session_compact', async (_event, ctx) => {
    const loc = await locate(ctx).catch(() => ({}));
    if (!loc.bank) return;
    await execute('bash', [join(skillDir, 'hooks/mb-graph-nudge.sh'), '--reset'], loc.root,
      { env: { MB_PATH: loc.bank }, timeoutMs: HOOK_TIMEOUT_MS }).catch(() => {});
  });

  pi.on('tool_result', async (event, ctx) => {
    if (event.isError) return undefined;
    if (event.toolName === 'write' || event.toolName === 'edit') {
      const target = String(event.input?.path || '');
      if (!CODE_FILE.test(target)) return undefined;
      const loc = await locate(ctx).catch(() => ({}));
      if (!loc.bank || !await exists(loc.graph)) return undefined;
      const file = resolve(loc.cwd, target);
      const rel = relative(loc.root, file);
      if (rel.startsWith('..') || isAbsolute(rel)) return undefined; // another project's file
      // Same append-only queue the Claude PostToolUse hook feeds; the next query/start consumes it.
      await appendFile(join(loc.bank, 'codebase', '.graph-dirty'), `${file}\n`).catch(() => {});
      return undefined;
    }
    const structural = event.toolName === 'grep'
      || (event.toolName === 'bash' && STRUCTURAL_BASH.test(String(event.input?.command || '')));
    if (!structural || process.env.MB_GRAPH_NUDGE === 'off') return undefined;
    const loc = await locate(ctx).catch(() => ({}));
    if (!loc.bank || !await exists(loc.graph)) return undefined;
    const input = { tool_name: event.toolName === 'grep' ? 'Grep' : 'Bash', tool_input: event.input || {},
      cwd: loc.root, session_id: ctx.sessionManager?.getSessionId?.() || '' };
    const out = await execute('bash', [join(skillDir, 'hooks/mb-graph-nudge.sh')], loc.root,
      { env: { MB_PATH: loc.bank }, stdin: JSON.stringify(input), timeoutMs: HOOK_TIMEOUT_MS }).catch(() => '');
    const nudge = parse(out)?.hookSpecificOutput?.additionalContext;
    if (!nudge) return undefined;
    return { content: [...event.content, { type: 'text', text: `[Memory Bank] ${nudge}` }],
      ...(event.structuredContent === undefined ? {} : { structuredContent: event.structuredContent }) };
  });
}
