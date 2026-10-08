// Boundary harness: real extension factory + scripts; only remote children are fake.
import { readFile, writeFile, mkdir, mkdtemp, cp } from 'node:fs/promises';
import { join } from 'node:path';
import { EventEmitter } from 'node:events';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const input = JSON.parse(await readFile(0, 'utf8').catch(async () => {
  let text = ''; for await (const chunk of process.stdin) text += chunk; return text;
}));
const root = process.cwd();
const packageRoot = process.env.PI_PACKAGE_ROOT || join(execFileSync('npm', ['root', '-g'], {encoding:'utf8'}).trim(), '@earendil-works/pi-coding-agent');
const require = createRequire(join(packageRoot, 'package.json'));
const { createJiti } = require('jiti');
const tmp = await mkdtemp(join(input.home, 'loader-'));
await cp(join(root, 'adapters'), tmp, { recursive: true });
const ts = join(tmp, 'pi_subagent_extension.ts');
await writeFile(ts, (await readFile(ts, 'utf8')).replaceAll('__MB_SKILL_DIR_JSON__', JSON.stringify(root)));
const preflightFile = join(tmp, 'preflight.mjs');
await mkdir(join(input.cwd, '.pi', 'agents'), {recursive:true});
for (const name of ['mb-developer','plan-verifier','mb-reviewer','mb-judge','codex-cli']) {
  try { await writeFile(join(input.cwd,'.pi','agents',`${name}.md`), `---\nname: ${name}\ntools: bash, read, write, edit, grep, find\n---\nYou are ${name}. Keep every required gate.\n`, {flag:'wx'}); }
  catch (error) { if(error.code !== 'EEXIST') throw error; }
}
await writeFile(preflightFile, `import {readFile} from 'node:fs/promises'; import {join} from 'node:path'; import {createHash} from 'node:crypto';
export async function resolveSubagentLaunchContract(p) {
 if (p.agent === 'missing-agent') return {ok:false,message:'missing_agent'};
 const filePath=join(p.cwd,'.pi','agents',p.agent+'.md'); const text=await readFile(filePath,'utf8');
 let raw=text.match(/^tools:\\s*(.*)$/m)?.[1] || ''; try {raw=JSON.parse(raw);} catch {}
 const tools=raw.split(',').map(s=>s.trim()).filter(Boolean); const model=p.model || 'openai/gpt-6.1-sol';
 const launchContractDigest=createHash('sha256').update(JSON.stringify([text,p.task,p.output,model,tools])).digest('hex');
 return {ok:true,contract:{agent:{name:p.agent,filePath},model:p.agent==='codex-cli'?undefined:(model+':high'),thinking:'high',launchContractDigest,tools:{effectiveAllowlist:tools,fanoutAuthorized:false}}};
}`);
const sdkManifest = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'));
const aliases = { typebox: require.resolve('typebox'), 'pi-subagents/preflight': preflightFile,
  '@earendil-works/pi-coding-agent': join(packageRoot, sdkManifest.exports['.'].import) };
if (input.realPreflight) {
  if (!process.env.PI_SUBAGENTS_ROOT) throw new Error('PI_SUBAGENTS_ROOT required for real preflight');
  const subagentsRequire = createRequire(join(process.env.PI_SUBAGENTS_ROOT, 'package.json'));
  aliases['pi-subagents/preflight'] = subagentsRequire.resolve('pi-subagents/preflight');
  for (const name of ['pi-ai', 'pi-agent-core', 'pi-coding-agent', 'pi-tui']) {
    const dir = name === 'pi-coding-agent' ? packageRoot : join(packageRoot, 'node_modules', '@earendil-works', name);
    const pkg = JSON.parse(await readFile(join(dir, 'package.json'), 'utf8'));
    aliases[`@earendil-works/${name}`] = join(dir, pkg.exports?.['.']?.import || pkg.main);
  }
}
const jiti = createJiti(import.meta.url, { alias: aliases, moduleCache: true });
const commands = new Map(), tools = new Map(), messages = [], launches = [], bus = new EventEmitter();
let cancelled = false;
const controls = [];
const records = new Map();
// Public capability-ceiling double: records registrations and what was active at each Nico spawn.
const ceilings = [];
let activeCeiling;
const registerCapabilityCeiling = input.noCeilingApi ? undefined : options => {
  if (input.ceilingFails) throw new Error('Invalid capability ceiling registration');
  const entry = { ...options, disposed: false };
  ceilings.push(entry); activeCeiling = entry;
  return { update() { throw new Error('unexpected ceiling update'); }, dispose() { entry.disposed = true; if (activeCeiling === entry) activeCeiling = undefined; } };
};
const resolveLaunch = (await jiti.import(preflightFile)).resolveSubagentLaunchContract;
const events = { on(name, fn) { bus.on(name, fn); return () => bus.off(name, fn); }, emit(name, value) { bus.emit(name, value); } };
let serial = 0;
if (!input.offline) events.on('subagents:rpc:v1:request', async (req) => {
  const reply = (data) => events.emit(`subagents:rpc:v1:reply:${req.requestId}`, {version:1,requestId:req.requestId,success:true,data});
  if (req.method === 'ping') return reply({capabilities:{events:{asyncComplete:'subagent:async-complete'}},events:{asyncComplete:'subagent:async-complete'}});
  if (req.method === 'stop') { cancelled = true; controls.push('nico'); return reply({stopped:true}); }
  if (req.method !== 'spawn') return;
  const id = `child-${++serial}`;
  const ceilingAtSpawn = activeCeiling && { sessionId: activeCeiling.sessionId, ...activeCeiling.ceiling };
  if (input.cancelDuringSpawn) {
    setTimeout(()=>commands.get('mb')?.handler('work --cancel',ctx),10);
    setTimeout(()=>reply({details:{asyncId:id,runId:id}}),50);
  } else reply({details:{asyncId:id,runId:id}});
  setTimeout(async () => {
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    try {
      if (input.cancelDuringSpawn) await new Promise(resolve => setTimeout(resolve,100));
      const runs = {async run(key, opts) {
        const source = await readFile(join(input.cwd,'.pi','agents',`${opts.agent}.md`),'utf8');
        let origin=source.match(/^mb_origin_agent:\s*(.*)$/m)?.[1]; if(origin) origin=JSON.parse(origin);
        launches.push({key,...opts,runtimeAgent:opts.agent,agent:origin||opts.agent,backend:'nico',ceiling:ceilingAtSpawn});
        if (input.cancel) { setTimeout(()=>commands.get('mb')?.handler('work --cancel',ctx),10); await new Promise(resolve => setTimeout(resolve, 100)); }
        const step = key.split('-')[0];
        const verdict = input.negative?.step === step ? input.negative.verdict : ({verify:'PASS',review:'APPROVED',judge:'GO'}[step]);
        const result = step === 'review' ? {verdict,counts:{blocker:0,major:verdict==='CHANGES_REQUESTED'?1:0,minor:0},issues:verdict==='CHANGES_REQUESTED'?[{severity:'major',category:'logic',file:'fixture.mjs',line:1,message:'Observable acceptance mismatch',fix:'Correct the fixture outcome'}]:[]} : (step === 'judge' ? {decision:input.backlog?'GO_WITH_BACKLOG':verdict,blocking_issues:verdict==='NO_GO'?[{severity:'major',category:'logic',file:'fixture.mjs',line:1,message:'Unmet observable acceptance',fix:'Correct required behavior'}]:[],backlog_items:input.backlog?[{title:'Native follow-up',rationale:'Measured nonblocking concern',severity:'minor',source:'judge'}]:[],acceptance_summary:{dod_met:!input.judgeUnmet,verification_passed:true,review_blockers_remaining:0}} : {verdict: verdict || 'IMPLEMENTED',changed_files:input.protected?['.env.secret']:[],tokens:input.tokens||0});
        const output = input.malformed === step ? 'not a verdict' : JSON.stringify(result);
        await mkdir(join(opts.output, '..'), {recursive:true}); await writeFile(opts.output, output);
        return {ok: !cancelled, output, outputReference:opts.output};
      }};
      const result = await new AsyncFunction('runs', req.params.script)(runs);
      const row=launches.at(-1); const digest=(await resolveLaunch({agent:row.runtimeAgent,cwd:input.cwd,task:row.task,output:row.output,model:row.model})).contract.launchContractDigest;
      events.emit('subagent:async-complete', {runId:id,exitCode:input.failedChild?1:0,success:!input.failedChild&&!input.pausedChild,state:input.pausedChild?'paused':input.failedChild?'failed':'complete',output:JSON.stringify(result),results:[{index:0,success:!input.failedChild,launchContractDigest:digest,usage:{input:input.runtimeTokens??input.tokens??0,output:0,cacheRead:0,cacheWrite:0},model:row.model||'openai/gpt-6.1-sol'}]});
    } catch (error) { events.emit('subagent:async-complete', {runId:id,exitCode:1,error:String(error),results:[]}); }
  }, 1);
});
const pi = {
  events, registerCommand(name, spec) { commands.set(name,spec); }, registerTool(spec) {tools.set(spec.name,spec);},
  on() { return () => {}; }, sendUserMessage(text) {messages.push({kind:'user',text});},
  sendMessage(message) {messages.push({kind:'custom',...message});}, getThinkingLevel() { return 'high'; },
};
const ctx = {cwd:input.cwd, model:{provider:'openai',id:'gpt-6.1-sol'}, sessionManager:{getSessionId:()=> 'test-session'},
  modelRegistry:{getAvailable:()=> [{provider:'openai',id:'gpt-6.1-sol'},{provider:'anthropic',id:'claude-opus-4'}]}, ui:{notify(text){messages.push({kind:'notify',text});}}};
if (!input.offline) for (const method of ['ping','spawn','stop','consume']) events.on(`subagents:rpc:${method}`, async req => {
  const reply = data => events.emit(`subagents:rpc:${method}:reply:${req.requestId}`, {success:true,data});
  if (method === 'ping') return reply({version:2});
  if (method === 'stop') {cancelled=true;controls.push('tintin');return reply();}
  if (method === 'consume') return reply();
  const id=`tintin-child-${++serial}`;
  req.options?.onSpawned?.(id);
  if(input.cancelDuringSpawn) {
    setTimeout(()=>commands.get('mb')?.handler('work --cancel',ctx),10);
    setTimeout(()=>reply({id}),50);
  } else reply({id});
  setTimeout(async()=> {
    const source=await readFile(join(input.cwd,'.pi','agents',`${req.type}.md`),'utf8');
    const origin=JSON.parse(source.match(/^mb_origin_agent:\s*(.*)$/m)[1]);
    const tools=JSON.parse(source.match(/^tools:\s*(.*)$/m)[1]).split(',').map(s=>s.trim());
    const key=req.options.description; const step=key.split('-')[0];
    launches.push({key,agent:origin,runtimeAgent:req.type,backend:'tintin',task:req.prompt,context:'fresh'});
    const verdict=input.negative?.step===step?input.negative.verdict:({verify:'PASS',review:'APPROVED',judge:'GO'}[step]);
    const value=step==='review'?{verdict,counts:{blocker:0,major:verdict==='CHANGES_REQUESTED'?1:0,minor:0},issues:verdict==='CHANGES_REQUESTED'?[{severity:'major',category:'logic',file:'fixture.mjs',line:1,message:'Unmet gate',fix:'Correct behavior'}]:[]}:
      step==='judge'?{decision:verdict,blocking_issues:verdict==='NO_GO'?[{severity:'major',category:'logic',file:'fixture.mjs',line:1,message:'Unmet gate',fix:'Correct behavior'}]:[],backlog_items:[],acceptance_summary:{dod_met:!input.judgeUnmet,verification_passed:true,review_blockers_remaining:0}}:
        {verdict:verdict||'IMPLEMENTED',changed_files:input.protected?['.env.secret']:[],tokens:input.tokens||0};
    const model=req.options.model.split('/');
    records.set(id,{id,type:req.type,status:'completed',session:{model:{provider:model[0],id:model.slice(1).join('/')},getActiveToolNames:()=>tools}});
    events.emit('subagents:completed',{id,type:req.type,status:input.failedChild?'error':'completed',result:input.malformed===step?'not a verdict':JSON.stringify(value),usage:{input:input.runtimeTokens??input.tokens??0,output:0,cacheRead:0,cacheWrite:0}});
  },input.cancelDuringSpawn?120:1);
});
const extension = await jiti.import(ts, {default:true});
const {createHostAuthority} = await jiti.import(join(tmp,'pi_native_host.mjs'));
const authority = createHostAuthority(() => session, () => ({cwd:input.cwd,agentDir:join(input.home,'.pi','agent')}));
const session = {sessionManager:ctx.sessionManager};
if (!input.unbound) {
  authority.attach(pi);
  const components = [{name:'nico',source:'explicit remote contract double',version:'fixture',runtimePath:'fixture:nico',resolveLaunch,registerCapabilityCeiling},
    {name:'tintin',source:'explicit remote contract double',version:'fixture',runtimePath:'fixture:tintin',settings:{agentMentions:input.unsafeMentions?'model':'off'},registry:{getRecord:id=>records.get(id)}},
    {name:'mb',source:ts,version:'fixture',runtimePath:'fixture:mb'}];
  try {authority.publish(components,components.map(component=>({path:component.runtimePath})));}
  catch(error) {authority.invalidate(error.message);}
} else {
  // Deliberately unbound child context: no ordinary operator root is composed.
  process.env.PI_SUBAGENT_CHILD = '1';
}
await extension(pi);
let error;
try {
  const command = commands.get(input.command || 'mb');
  if (!command) throw new Error('Command unavailable');
  const pending = command.handler(input.args || '',ctx);
  if (input.concurrent) setTimeout(()=>commands.get('mb')?.handler(input.args,ctx).catch(e=>messages.push({kind:'error',text:String(e)})),30);
  await pending;
} catch (e) { error = String(e); }
console.log(JSON.stringify({error,messages,launches,commands:[...commands.keys()],cancelled,controls,ceilings}));
