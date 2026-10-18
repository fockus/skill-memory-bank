// Native model representation and dispatch only; shared Python/shell own selection/precedence.
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import * as path from 'node:path';
import { validatePath } from './opencode_paths.mjs';
function reference(selector) {
  const match = /^([^/#\s]+)\/([^#\s]+)(?:#([^/#\s]+))?$/.exec(selector);
  if (!match) throw new Error(`[MB] Invalid model ${JSON.stringify(selector)}; use provider/model#variant, never a Claude alias`);
  return { providerID: match[1], id: match[2], ...(match[3] ? { variant: match[3] } : {}) };
}
const selector = ref => `${ref.providerID}/${ref.id}${ref.variant ? `#${ref.variant}` : ''}`;

/** @param {{ctx: import('@opencode/plugin').Plugin.Context, root: string, runner: ReturnType<import('./opencode_process.mjs').createRunner>, directory: string, locate: Function, resolveBank: Function, signal: AbortSignal}} options */
export function createWorkflowBinding({ ctx, root, runner, directory, locate, resolveBank, signal }) {
  const runs = new Map();
  const current = new Map();
  const shells = new Map();
  let definitions, commands;
  const requestOptions = () => ({ signal: AbortSignal.any([signal, AbortSignal.timeout(3000)]) });
  async function validate(ref) {
    const catalog = await ctx.model.list({ location: { directory } }, requestOptions());
    const model = catalog.data.find(model => model.providerID === ref.providerID && model.id === ref.id && model.enabled);
    if (!model || (ref.variant && !model.variants.some(variant => variant.id === ref.variant))) {
      throw new Error(`[MB] Model unavailable: ${selector(ref)}; select an enabled catalog ID and supported variant in this location`);
    }
    return ref;
  }
  async function runFor(sid) {
    for (let depth = 0; sid && depth < 8; depth++) {
      if (runs.has(sid)) return runs.get(sid);
      sid = (await locate(sid))?.parentID;
    }
  }
  const states = async bank => JSON.parse(await runner.run('scripts/mb-work-state.sh', ['status', '--all', '--mb', bank]));
  const nativeEnv = run => ({ MB_PATH: run.bank, MB_WORK_RUN_ID: run.runID,
    MB_WORK_PARALLEL: run.parallel, MB_WORK_RETAIN_STATE: '1', MB_WORK_RETAIN_BANK: run.bank });
  async function selection(bank, args, source = '', resolve = false, currentItem = null) {
      const flags = [...(resolve ? ['--resolve-execution'] : source ? ['--execution-source', source] : []),
        ...(currentItem ? ['--current-item', JSON.stringify(currentItem)] : [])];
      const result = JSON.parse(await runner.run('adapters/opencode_work.py', [bank, ...flags], args, { timeout: 30000, allowSoft: true }));
      if (result.error) throw new Error(`[MB] Work blocked: ${result.error}`);
      for (const role of Object.values(result.roles)) if (role.native) await validate(reference(role.native));
      for (const item of result.items) if (item.native_model) await validate(reference(item.native_model));
      return result;
  }
  async function observe(sid) {
    const run = await runFor(sid);
    if (!run) return;
    if (!run.execution) {
      if (run.admission) {
        const messages = await ctx.session.context({ sessionID: run.owner }, requestOptions());
        const start = messages.findIndex(message => message.id === run.admission && message.type === 'user');
        const next = messages.findIndex((message, index) => index > start && message.type === 'user');
        const generation = start < 0 ? [] : messages.slice(start + 1, next < 0 ? undefined : next);
        const terminal = generation.findLast(message => message.type === 'idle');
        if (terminal && (terminal.outcome !== 'succeeded'
          || generation.some(message => message.type === 'assistant' && message.time.completed && message.finish === 'stop'))) {
          runs.delete(run.owner); return;
        }
      }
      return run;
    }
    const candidates = (await states(run.bank)).filter(state => state.run_id === run.runID);
    if (candidates.length > 1) throw new Error('[MB] Ambiguous canonical work-state; select one run before native dispatch');
    const state = candidates[0];
    if (!state) {
      const retained = JSON.parse(await runner.run('scripts/mb-work-state.sh', ['retained', '--run-id', run.runID, '--mb', run.bank], '', { env: nativeEnv(run) }));
      if (retained.run_id === run.runID && run.items.some(item => item.source_path === retained.source_path && item.item_no === retained.item_no)) {
        const latest = await selection(run.bank, run.args, run.executionSource);
        if (latest.items.length && latest.items.every(item => item.status === 'done')) { runs.delete(run.owner); return; }
      }
      run.state = undefined;
      return run;
    }
    if (run.execution_deferred) {
      // The existing planning path, not native prompt inference, chooses the created declaration.
      run.executionSource = state.source_path;
      Object.assign(run, await selection(run.bank, run.args, run.executionSource));
    }
    const item = run.items.find(item => item.source_path === state.source_path && item.item_no === state.item_no);
    if (!item) throw new Error('[MB] Canonical work-state is outside this work selection; reinitialize the selected source/item');
    if (state.phase === 'in-progress' && run.workflow.steps.some(step => step === 'implement' || step === 'fix')
      && !Object.values(run.roles).some(role => role.source_path === state.source_path && role.item_no === state.item_no)) {
      const active = await selection(run.bank, run.args, run.executionSource, false, { source_path: state.source_path, item_no: state.item_no });
      run.roles = active.roles;
    }
    run.runID = state.run_id;
    run.state = state;
    return run;
  }
  async function prepare(sid, args) {
      if (!await locate(sid)) throw new Error('[MB] Work session location unavailable');
      const bank = await resolveBank(sid);
      if (!bank) throw new Error('[MB] Memory Bank absent; run /mb init explicitly before /mb work');
      let result = await selection(bank, args);
      if (!result.driver.includes('--dry-run')) {
        const execution = result.workflow.steps.some(step => ['implement', 'verify', 'review', 'judge', 'fix', 'done'].includes(step));
        let runID, parallel = '1';
        if (execution) {
          const all = await states(bank);
          const requested = result.driver.indexOf('--run-id');
          if (requested >= 0) {
            runID = result.driver[requested + 1];
            if (result.execution_deferred) result = await selection(bank, args, '', true);
            const selected = state => state.run_id === runID && result.items.some(item => item.source_path === state.source_path && item.item_no === state.item_no);
            const matching = all.filter(state => state.run_id === runID);
            if (matching.length !== 1 || !selected(matching[0])) throw new Error('[MB] Explicit resume requires one matching canonical source/item/run; no claim takeover');
            const modes = [];
            const status = ['status', '--run-id', runID, '--mb', bank];
            for (const mode of ['0', '1']) {
              const state = JSON.parse(await runner.run('scripts/mb-work-state.sh', status, '', { env: { MB_WORK_PARALLEL: mode, MB_WORK_RETAIN_STATE: '0' } }));
              if (selected(state)) modes.push(mode);
            }
            if (modes.length !== 1) throw new Error('[MB] Explicit resume requires one unambiguous canonical slot');
            parallel = modes[0];
            const guarded = JSON.parse(await runner.run('scripts/mb-work-state.sh', status, '', { env: nativeEnv({ bank, runID, parallel }) }));
            if (!selected(guarded)) throw new Error('[MB] Canonical resume source/item/run changed during admission');
          } else {
            const sources = new Set([...result.items.map(item => item.source_path), ...result.existing_sources]);
            if (runs.has(sid) || all.some(state => state.phase !== 'done' && sources.has(state.source_path))) {
              throw new Error('[MB] Unfinished canonical work exists; resume its matching source explicitly with --run-id ID');
            }
            runID = (await runner.run('scripts/mb-work-state.sh', ['new-run-id'])).trim();
            if (all.some(state => state.run_id === runID)) throw new Error('[MB] Canonical run identity collision');
          }
          result.run_id = runID;
        }
        runs.set(sid, { ...result, owner: sid, bank, args, runID, execution, parallel });
      }
      return `\n\nOpenCode work preflight (shared resolvers, authoritative): ${JSON.stringify(result)}\n`
        + 'Read commands/work.md at the supplied skill root and execute its existing per-item loop. '
        + 'For a freeform planning entrypoint, execute discuss/sdd/plan first; only then resolve items through mb-work-plan.sh and initialize their real source. '
        + 'Initialize source_path/source_topic/run_id exactly from these items. Native subagent models below are enforced for this run only. '
        + 'A missing model inherits the parent only when the role is not pinned. '
         + 'Use the supplied canonical run_id for every helper (also supplied to this root\'s native shells); do not allocate another ID or take over a foreign run. '
         + 'Native shell environment preserves the existing canonical slot mode on explicit resume; do not switch it or migrate the state. '
        + 'The existing done/flip/clear sequence may be grouped in one shell action. Never forge state or receipts. '
        + 'Keep the same run_id when advancing items. If one native agent serves different workflow steps with different models, record the current step via mb-work-state.sh step <step> before dispatch. '
        + 'Native nesting remains bounded by experimental.subagent_depth and subagent permission rules; '
        + 'if a selected verifier needs a test-runner child, explicitly allow that role and sufficient finite depth (root→verifier→runner = 2). '
        + 'Do not broaden permissions or depth automatically.';
  }
  return {
    async install() {
      // Minimal contract fixtures omit command registration; the V2 host always exposes it.
      if (!ctx.command) return;
      definitions = await Promise.all(['mb', 'work'].map(async name => {
        const source = await readFile(path.join(root, 'commands', `${name}.md`), 'utf8');
        const body = source.slice(source.indexOf('\n---\n', 4) + 5).trim();
        const description = '[MB native] ' + /^description: "(.*)"$/m.exec(source)?.[1];
        return { name, description, async execute({ sessionID, prompt, delivery }) {
          const args = prompt.text.trim();
          const work = name === 'work' ? args : /^work(?:\s|$)/.test(args) ? args.replace(/^work\s*/, '') : null;
          const binding = work === null ? '' : await prepare(sessionID, work);
          const admitted = await ctx.session.prompt({ sessionID, ...prompt,
             text: body.replaceAll('$ARGUMENTS', prompt.text) + binding, delivery });
          const run = runs.get(sessionID);
          if (binding && run && !run.execution) run.admission = admitted.id;
        } };
      }));
      commands = await ctx.command.transform(editor => { for (const definition of definitions) editor.add(definition); });
      return { async dispose() { await commands?.dispose(); } };
    },
    async refreshCommands() {
      if (!definitions) return;
      const listed = await ctx.command.list({ location: { directory } }, requestOptions());
      if (definitions.every(def => listed.data.some(item => item.name === def.name && item.description === def.description))) return;
      // The config command source activates after local plugins. Rebind on its public update,
      // not a guessed startup delay; subsequent updates retain the last registration's precedence.
      await commands?.dispose();
      commands = await ctx.command.transform(editor => { for (const definition of definitions) editor.add(definition); });
    },
    async context(event) {
      if (event.model) current.set(event.sessionID, event.model);
      await observe(event.sessionID);
    },
    async after(event) {
      for (const [command, owned] of shells) if (owned.sessionID === event.sessionID && owned.id === event.id) shells.delete(command);
      await observe(event.sessionID);
    },
    async shell(event) {
      const cwd = path.resolve(event.cwd);
      if (cwd === directory || cwd.startsWith(`${directory}${path.sep}`)) event.env.MB_PIPELINE_HOST = 'opencode';
      const owned = shells.get(event.command);
      if (!owned) return;
      shells.delete(event.command);
      if (path.resolve(event.cwd) !== owned.cwd) throw new Error('[MB] Native shell location changed after owner admission');
      Object.assign(event.env, nativeEnv(owned.run), { MB_PIPELINE_HOST: 'opencode' });
    },
    async before(event) {
      if (event.tool !== 'subagent' && event.tool !== 'shell') return;
      if (event.tool === 'shell' && shells.has(event.input?.command)) throw new Error('[MB] Native shell admission cannot be replayed by another action');
      const run = await observe(event.sessionID);
      if (!run) return;
      const input = event.input;
      if (event.tool === 'shell') {
        if (!run.execution || event.sessionID !== run.owner) return;
        if (!input || typeof input.command !== 'string' || shells.has(input.command)) throw new Error('[MB] Invalid native shell admission');
        const cwd = path.resolve(directory, input.workdir || directory);
        if (cwd !== directory && !cwd.startsWith(`${directory}${path.sep}`)) throw new Error('[MB] Work shell must remain in its native location');
        await validatePath(cwd, 'directory');
        if (shells.size >= 32) throw new Error('[MB] Native shell admission limit reached');
        input.command = `# MB native action ${randomUUID()}\n${input.command}`;
        shells.set(input.command, { run, cwd, sessionID: event.sessionID, id: event.id });
        return;
      }
      if (!input || typeof input !== 'object' || Array.isArray(input) || typeof input.agent !== 'string') throw new Error('[MB] Invalid subagent input');
      const assigned = Object.values(run.roles).filter(role => role.agent === input.agent);
      if (run.execution && !run.state && assigned.some(role => role.step !== 'plan')) {
        throw new Error('[MB] Initialize or resume the owning canonical work-state before execution-role dispatch');
      }
      const settings = assigned.filter(role => !role.source_path
        || (role.source_path === run.state?.source_path && role.item_no === run.state?.item_no));
      if (assigned.length && !settings.length) throw new Error('[MB] Initialize the canonical work-state for the current selected item before dispatch');
      if (run.execution_deferred && !settings.length) {
        throw new Error('[MB] Complete the selected planning steps and initialize the canonical execution source before dispatch');
      }
      const step = run.state?.steps?.at(-1);
      const effective = new Set(settings.map(role => role.native)).size > 1 ? settings.filter(role => role.step === step || (step === 'fix' && role.step === 'implement')) : settings;
      const choices = new Set(effective.map(role => role.native));
      if (settings.length && !choices.size) throw new Error('[MB] Record the current canonical workflow step before dispatch; model assignment is ambiguous');
      if (!choices.size) {
        if (input.model) await validate(reference(input.model));
        return;
      }
      if (choices.size !== 1) throw new Error(`[MB] Conflicting workflow models for ${input.agent} at the current canonical item/step`);
      const selected = [...choices][0];
      const agent = (await ctx.agent.get({ agentID: input.agent, location: { directory } }, requestOptions())).data;
      if (selected) {
        if (input.model && input.model !== selected) throw new Error(`[MB] ${input.agent} requires ${selected} for this work run`);
        input.model = selector(await validate(reference(selected)));
      } else {
        const parent = current.get(event.sessionID) ?? (await locate(event.sessionID))?.model;
        if (!parent) throw new Error('[MB] Parent session model unavailable from native API; cannot honor inherit');
        if (input.model && input.model !== selector(parent)) throw new Error('[MB] This work role must inherit the exact parent model/variant');
        await validate(parent);
        if (agent.model || input.model) input.model = selector(parent);
      }
    },
    clear(sid) {
      runs.delete(sid); current.delete(sid);
      for (const [command, owned] of shells) if (owned.run.owner === sid) shells.delete(command);
    },
  };
}
