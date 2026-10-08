// Governed driver: portable state/gates; named fresh children via public RPC.
import { randomUUID, createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { createBackend, selectBackend } from './pi_native_backend.mjs';

function argumentsForWork(argv) {
  const options = {};
  const flags = new Set(['range', 'workflow', 'pipeline', 'model', 'authorize-provider', 'budget', 'max-cycles', 'main-review', 'resume-run', 'backend']);
  for (let i = 0; i < argv.length; i++) {
    const value = argv[i];
    if (!value.startsWith('--')) {
      if (options.target) throw new Error('Only one work target is supported');
      options.target = value; continue;
    }
    const [key, inline] = value.slice(2).split('=', 2);
    if (!flags.has(key)) throw new Error(`Unsupported work flag: ${value}`);
    options[key] = inline ?? argv[++i];
    if (!options[key] || options[key].startsWith('--')) throw new Error(`Missing value: ${key}`);
  }
  for (const key of ['budget', 'max-cycles']) {
    if (options[key] && !/^[1-9][0-9]*$/.test(options[key])) throw new Error(`Invalid ${key}`);
  }
  return options;
}

function verdict(text, step) {
  let value;
  try { value = JSON.parse(text); } catch { throw new Error(`Malformed ${step} verdict`); }
  if (!value || typeof value !== 'object') throw new Error(`Malformed ${step} verdict`);
  return value;
}

export async function runWork(port) {
  const { pi, ctx, bank, argv, script, decoder, resolveLaunch, signal } = port;
  const options = argumentsForWork(argv);
  const runId = options['resume-run'] || `pi-native-${randomUUID()}`;
  if (!/^[A-Za-z0-9_-]+$/.test(runId)) throw new Error('Invalid resume run identity');
  const env = { MB_WORK_PARALLEL: '1', MB_WORK_RUN_ID: runId, ...(options.pipeline ? { MB_PIPELINE: options.pipeline } : {}) };
  const exec = (name, args, more = {}) => script(name, args, ctx.cwd, { env, signal, ...more });
  const state = (...args) => exec('mb-work-state.sh', [...args, '--run-id', runId, '--mb', bank]);
  const pipelinePath = (await exec('mb-pipeline.sh', ['path', bank])).trim();
  const config = await decoder('pipeline', pipelinePath, ctx.cwd);
  const workflow = JSON.parse(await exec('mb-workflow.sh', [ ...(options.workflow ? ['--workflow', options.workflow] : []), '--mb', bank, '--json' ]));
  if (config.workflows?.[workflow.name]?.review_profile === 'ensemble') throw new Error('Native ensemble review is not supported; select an explicit single-review pipeline rather than dropping ensemble gates');
  if (workflow.steps.includes('fix') && workflow.loop?.returns_to && workflow.loop.returns_to !== 'verify') throw new Error('Unsupported fix return step; refusing to alter selected gates');
  const supported = new Set(['implement', 'verify', 'review', 'judge', 'fix', 'done']);
  if (workflow.steps.some(step => !supported.has(step))) throw new Error('Native work requires an existing plan/spec execution workflow');
  if (workflow.steps.includes('done') && !workflow.steps.includes('verify')) throw new Error('Closure requires verification');
  const maxCycles = Number(options['max-cycles'] || workflow.loop?.max_cycles || 2);
  if (!Number.isSafeInteger(maxCycles) || maxCycles < 1) throw new Error('Invalid cycle ceiling');
  const rows = (await exec('mb-work-plan.sh', [ ...(options.target ? ['--target', options.target] : []),
    ...(options.range ? ['--range', options.range] : []), '--mb', bank ]))
    .split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line)).filter(item => item.status !== 'done');
  if (!rows.length) throw new Error('No pending work items');
  const folder = join(bank, 'reports', 'native-work', runId);
  await mkdir(folder, { recursive: true });
  const authorization = options['authorize-provider'] ? { runId, provider: options['authorize-provider'] } : undefined;
  const backend = await createBackend({ name: await selectBackend(options.backend, bank), pi, ctx, decoder, resolveLaunch, runId, authorization });
  const completed = [];
  let budgetInitialized = !!options['resume-run'];
  for (const item of rows) {
    if (signal.aborted) throw new Error('Native work cancelled');
    let prior;
    if (options['resume-run']) {
      prior = JSON.parse(await state('status'));
      if (rows.length !== 1 || prior.run_id !== runId || prior.source_path !== item.source_path || prior.item_no !== item.item_no || prior.phase === 'done') throw new Error('Resume requires exact live source/item identity');
    } else await state('init', item.source, String(item.item_no), '--source-path', item.source_path,
      '--source-topic', item.source_topic, '--heading', item.heading, '--max-cycles', String(maxCycles));
    const source = await readFile(item.source_path, 'utf8');
    await writeFile(join(folder, `source-${item.item_no}.md`), source);
    const identity = { runId, pipelinePath, workflow, ownerAuthorization: authorization, ...item,
      backend: backend.name, sessionId: backend.binding.sessionId, runtimeGeneration: backend.binding.generation, roleContracts: {},
      sourceHash: createHash('sha256').update(source).digest('hex'),
      pipelineHash: createHash('sha256').update(await readFile(pipelinePath)).digest('hex'), nativeEval: 'UNVERIFIED' };
    let saved;
    if (prior) {
      saved = JSON.parse(await readFile(join(folder, `identity-${item.item_no}.json`), 'utf8'));
      if (saved.backend !== backend.name || saved.sessionId !== identity.sessionId) throw new Error('Conflicting resume backend/session owner');
      if (saved.sourceHash !== identity.sourceHash || saved.pipelineHash !== identity.pipelineHash || JSON.stringify(saved.workflow) !== JSON.stringify(workflow)) throw new Error('Resume source/pipeline changed; owner reconciliation required');
      const terminal = JSON.parse(await readFile(join(folder, `implement-${item.item_no}-0.json.terminal.json`), 'utf8'));
      if (terminal.success !== true || terminal.state !== 'complete') throw new Error('Resume needs reconciled successful implementation receipt');
    }
    await writeFile(join(folder, prior ? `resume-identity-${item.item_no}-${randomUUID()}.json` : `identity-${item.item_no}.json`), JSON.stringify(identity, null, 2));
    if (options.budget && !budgetInitialized) { await exec('mb-work-budget.sh', ['init', options.budget, '--run-id', runId, '--mb', bank]); budgetInitialized = true; }
    const roles = {
      implement: { ...(config.roles?.[item.role] || {}), agent: item.agent, model: options.model || item.model },
      fix: { ...(config.roles?.[item.role] || {}), agent: item.agent, model: options.model || item.model },
      verify: config.roles?.verifier, review: config.roles?.reviewer, judge: config.roles?.judge,
    };
    for (const key of ['verify', 'review', 'judge']) {
      if (roles[key]) roles[key] = { ...roles[key], ...(options.model ? { model: options.model } : {}) };
    }
    // Resolve every selected role before the first mutation-capable child.
    for (const step of workflow.steps.filter(s => roles[s] || !['done'].includes(s))) {
      if (step === 'done') continue;
      const child = await backend.preflight(roles[step], item.heading, join(folder, `${step}-${item.item_no}-preflight.json`));
      const { launchContractDigest, ...retained } = child.contract;
      identity.roleContracts[step] = retained;
    }
    if (saved && JSON.stringify(saved.roleContracts) !== JSON.stringify(identity.roleContracts)) throw new Error('Retained agent/model/tool contract drift; owner reconciliation required');
    await writeFile(join(folder, prior ? `resume-contract-${item.item_no}-${randomUUID()}.json` : `identity-${item.item_no}.json`), JSON.stringify(identity, null, 2));
    let feedback = '', verificationPassed = false, reviewPassed = false, judgePassed = false;
    const dispatch = async (step, cycle) => {
      if (signal.aborted) throw new Error('Native work cancelled');
      await state('step', step);
      const output = join(folder, `${step}-${item.item_no}-${cycle}${prior ? `-resume-${randomUUID()}` : ''}.json`);
      const task = `${item.heading}\nSource identity: ${JSON.stringify(identity)}\nRead source: ${item.source_path}\n` +
        `Prior feedback/artifacts: ${feedback || folder}\nNo commits. Do not close source checkboxes. ` +
        (['implement', 'fix'].includes(step) ? 'Implement only this item using TDD. Return JSON with changed_files (string array) and tokens (nonnegative integer).' :
          step === 'verify' ? 'Read the item, artifacts and changes independently. Return strict JSON {"verdict":"PASS"|"FAIL"}.' :
          step === 'review' ? 'Independent fresh review. Return strict reviewer JSON verdict, counts and issues per mb-work-review-parse.sh.' :
          'Independent judge. Return strict JSON decision GO|GO_WITH_BACKLOG|NO_GO, blocking_issues, backlog_items per agents/mb-judge.md.');
      const child = await backend.preflight(roles[step], task, output);
      const terminal = await backend.dispatch(`${step}-${item.item_no}-${cycle}`, child, {
        signal, onLaunch: receipt => writeFile(`${output}.launch.json`, JSON.stringify({ ...receipt, backend: backend.name, sessionId: identity.sessionId,
          runtimeGeneration: backend.binding.generation, sourceHash: identity.sourceHash, roleContract: child.contract }, null, 2)),
      });
      await writeFile(`${output}.terminal.json`, JSON.stringify(terminal, null, 2));
      // Read the runtime-bound artifact, never infer success from spawn text.
      const text = await readFile(output, 'utf8');
      feedback = output;
      const value = verdict(text, step);
      if (options.budget) {
        if (!terminal.results.length || terminal.results.some(r => !r.usage || !Number.isSafeInteger(r.usage.input) || !Number.isSafeInteger(r.usage.output))) throw new Error('Missing runtime budget usage evidence');
        const tokens = terminal.results.reduce((total, r) => total + r.usage.input + r.usage.output + (r.usage.cacheRead || 0) + (r.usage.cacheWrite || 0), 0);
        if (!Number.isSafeInteger(tokens) || tokens < 0) throw new Error('Invalid runtime budget usage');
        await exec('mb-work-budget.sh', ['add', String(tokens), '--run-id', runId, '--mb', bank]);
        await exec('mb-work-budget.sh', ['check', '--run-id', runId, '--mb', bank]);
      }
      if (['implement', 'fix'].includes(step)) {
        if (!Array.isArray(value.changed_files) || value.changed_files.some(f => typeof f !== 'string')) throw new Error('Missing changed-file evidence');
        if (value.changed_files.length) await exec('mb-work-protected-check.sh', [...value.changed_files, '--mb', bank]);
      }
      return { value, text };
    };
    const checkReview = async (result, cycle) => {
      const normalized = await exec('mb-work-review-parse.sh', [], { stdin: result.text });
      await exec('mb-work-severity-gate.sh', ['--counts', normalized, '--workflow', workflow.name, '--mb', bank]);
      if (JSON.parse(normalized).verdict !== 'APPROVED') throw new Error('Review CHANGES_REQUESTED; work remains open');
      if (roles.review.parallel_with) {
        if (roles.review.parallel_with !== 'main-agent' || !options['main-review']) throw new Error('Configured main-session review requires independent receipt');
        const bound = JSON.parse(await readFile(options['main-review'], 'utf8'));
        if (bound.runId !== runId || bound.sourceHash !== identity.sourceHash || bound.itemNo !== item.item_no || bound.cycle !== cycle) throw new Error('Unbound or stale main-session review receipt');
        const main = await exec('mb-work-review-parse.sh', [], { stdin: JSON.stringify(bound.review) });
        await exec('mb-work-severity-gate.sh', ['--counts', main, '--workflow', workflow.name, '--mb', bank]);
        if (JSON.parse(main).verdict !== 'APPROVED') throw new Error('Main-session review did not approve');
      }
    };
    let cycle = prior?.cycle || 0;
    for (const step of workflow.steps) {
      if (step === 'done' || step === 'fix' || (prior && step === 'implement')) continue;
      const result = await dispatch(step, cycle);
      if (step === 'verify') {
        verificationPassed = result.value.verdict === 'PASS';
        if (!verificationPassed) throw new Error('Verification FAIL or malformed verdict; work remains open');
      }
      if (step === 'review') {
        await checkReview(result, cycle);
        reviewPassed = true;
      }
      if (step === 'judge') {
        let judgment = result.value;
        while (judgment.decision === 'NO_GO' && workflow.steps.includes('fix')) {
          await state('cycle'); cycle++;
          await dispatch('fix', cycle);
          const verify = await dispatch('verify', cycle);
          if (verify.value.verdict !== 'PASS') throw new Error('Verification FAIL after fix');
          const review = await dispatch('review', cycle);
          await checkReview(review, cycle);
          judgment = (await dispatch('judge', cycle)).value;
        }
        if (!['GO', 'GO_WITH_BACKLOG'].includes(judgment.decision) || !Array.isArray(judgment.blocking_issues) || judgment.blocking_issues.length) throw new Error('Judge NO_GO or malformed decision');
        if (judgment.acceptance_summary?.dod_met !== true || judgment.acceptance_summary?.verification_passed !== true || judgment.acceptance_summary?.review_blockers_remaining !== 0 || !Array.isArray(judgment.backlog_items)) throw new Error('Judge acceptance summary is unmet or malformed');
        if (judgment.decision === 'GO_WITH_BACKLOG') {
          if (!judgment.backlog_items.length) throw new Error('GO_WITH_BACKLOG omitted backlog evidence');
          for (const entry of judgment.backlog_items) {
            if (![entry.title, entry.rationale, entry.source].every(v => typeof v === 'string' && v.trim()) || !['minor', 'major'].includes(entry.severity)) throw new Error('Malformed judge backlog item');
            await exec('mb-idea.sh', [`${entry.title} — ${entry.rationale} (source: ${entry.source}; native run ${runId})`, entry.severity === 'major' ? 'HIGH' : 'MED', bank]);
          }
        }
        judgePassed = true;
      }
    }
    if (workflow.steps.includes('done')) {
      if (!verificationPassed || (workflow.steps.includes('review') && !reviewPassed) || (workflow.steps.includes('judge') && !judgePassed)) throw new Error('Closure gate unmet');
      await state('done');
      completed.push({ ...identity, result: 'done', outputFolder: folder });
    }
  }
  return { runId, completed, nativeEval: 'UNVERIFIED', runtimeInventory: backend.runtimeInventory, outputFolder: folder };
}
