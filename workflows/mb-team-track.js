export const meta = {
  name: 'mb-team-track',
  description: 'Run MB Team tracks through executor → verifier → cross-model review (bounded rounds) → triage → fix → judge, with team.json, board and console bookkeeping at every milestone',
  whenToUse: 'Driving /mb team tracks; args = the JSON printed by `mb-team.sh workflow-args --tracks A,B` (per track you may set start: execute|fix|judge, fixes, notes, reviewFile)',
  phases: [
    { title: 'Execute', detail: 'track agent, TDD, track prompt' },
    { title: 'Verify', detail: 'plan-verifier over the DoD' },
    { title: 'Review', detail: 'external reviewer command from pipeline.yaml, round 2 on the fix diff only' },
    { title: 'Triage', detail: 'keep only real findings under the brief severity scale' },
    { title: 'Fix', detail: 'track agent, failing test first' },
    { title: 'Judge', detail: 'mb-judge: GO / GO_WITH_BACKLOG / NO_GO and the commit path list' },
  ],
}

// Every path and model comes from args (mb_team_workflow.py); a workflow script cannot read files.
const A = args
const q = (p) => (/^[\w@%+=:,./-]+$/.test(p) ? p : "'" + p.replace(/'/g, "'\\''") + "'")
const book = (t, status, note, summary) =>
  `${A.team} track set ${t.id}${status ? ' --status ' + status : ''} --note "${note}"${summary ? ' --summary-file ' + q(summary) : ''}`
const rdir = (t) => `${A.bank}/reports/${A.topic}/${t.id}-review`
const opts = (label, phase, role, schema) => {
  const o = { label, phase, schema }
  if (role.agent) o.agentType = role.agent
  if (role.model) o.model = role.model
  if (role.effort) o.effort = role.effort
  return o
}

const RULES = `Repository ${A.tree}; work only there. Team brief (binding: rules, contract, severity scale, test commands): ${A.brief}.
Never commit, push, change permissions or configuration, read secrets (.env*), or touch protected paths; no network or paid model calls in tests.
Bookkeeping commands below are mandatory; run them exactly — they update team.json, the COORDINATION board and the orchestrator console.`

const STATUS = { type: 'object', properties: { status: { type: 'string' }, summary: { type: 'string' } }, required: ['status', 'summary'] }
const VERIFY = { type: 'object', properties: { pass: { type: 'boolean' }, issues: { type: 'array', items: { type: 'string' } } }, required: ['pass', 'issues'] }
const REVIEW = { type: 'object', properties: { verdict: { type: 'string' }, file: { type: 'string' }, findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string' }, where: { type: 'string' }, text: { type: 'string' } }, required: ['severity', 'text'] } } }, required: ['verdict', 'file', 'findings'] }
const TRIAGE = { type: 'object', properties: { fix: { type: 'array', items: { type: 'string' } }, accept: { type: 'array', items: { type: 'string' } } }, required: ['fix', 'accept'] }
const LIST = { type: 'array', items: { type: 'string' } }
const JUDGE = { type: 'object', properties: { decision: { type: 'string' }, rationale: { type: 'string' }, blocking: LIST, backlog: LIST, commit_paths: LIST, orchestrator_checks: LIST }, required: ['decision', 'rationale', 'blocking', 'backlog', 'commit_paths', 'orchestrator_checks'] }

const execute = (t) => agent(`${RULES}

You are the executor of MB Team track ${t.id}. Task and DoD: ${t.prompt} (read it and the brief first).
1. Run: ${book(t, 'dispatched', 'executor started')}
2. Do the task with TDD: a failing test first for every behaviour, then the code. Keep the diff minimal and inside the track's globs (${(t.files || []).join(', ') || 'see the prompt'}).
3. Run the track's tests, the linter on changed files, and any contract the prompt names.
4. Write your report to ${t.report}: Files · Tests (red → green with output) · Remaining · Questions · Follow-ups, last line STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED.
5. Run: ${book(t, 'returned', '<one-line result with test counts>', t.report)}
${t.notes ? 'Orchestrator notes: ' + t.notes : ''}
Return {status, summary}.`, opts(`exec:${t.id}`, 'Execute', t, STATUS))

const verify = (t) => agent(`${RULES}

You are the plan-verifier for MB Team track ${t.id}. Run first: ${book(t, 'verifying', 'verifier started')}
Check every DoD line in ${t.prompt} against the real code and tests in the working tree (git diff vs HEAD plus new files), run the named tests yourself, and read the executor report ${t.report}. Do not edit files.
Then run: ${book(t, '', 'verifier <PASS|FAIL>: <one line>')}
Return {pass, issues} — issues are concrete unmet DoD items or regressions.`, opts(`verify:${t.id}`, 'Verify', t.verifier, VERIFY))

const review = (t, round, prev) => {
  const dir = rdir(t)
  const cmd = A.review.command.replace('{prompt}', q(`${dir}/round${round}.prompt.md`)).replace('{out}', q(`${dir}/round${round}.out.md`))
  return agent(`${RULES}

You run the cross-model review, round ${round} of at most ${A.review.max_rounds}, for MB Team track ${t.id}. Run first: ${book(t, 'reviewing', `external review r${round} started`)}
1. Build the diff into ${dir}/round${round}.diff (mkdir -p it):
   ${round === 1 ? `the track's changes vs HEAD (git diff -- <the track globs>, plus each new untracked file via git diff --no-index /dev/null <file>; no caches or build output).` : `ONLY this round's fixes: rebuild HEAD + ${dir}/round1.diff in a scratch copy (git archive HEAD <paths> | tar -x; git apply), then diff -u that copy against the working tree for the changed files.`}
2. Write ${dir}/round${round}.prompt.md from the template ${A.review.template}, filling it from ${t.prompt}, ${t.report} and the brief${round > 1 ? `; the round-1 findings are in ${prev}, and the report says which were fixed or accepted` : ''}.
3. Run exactly, in the background, and wait for it to finish (it can take 10–30 minutes):
   cd ${q(A.tree)} && ${cmd}
   Never change the model or the command. If the reviewer CLI is missing or unauthenticated, return verdict SKIPPED with the reason — loudly, never a silent pass.
4. The real verdict is the LAST "VERDICT:" block of ${dir}/round${round}.out.md.
5. Run: ${book(t, '', `external review r${round}: <verdict> <counts>`)}
Return {verdict, file, findings} — file is the output path.`, opts(`review-r${round}:${t.id}`, 'Review', { agent: 'codex-reviewer', model: A.judge.model }, REVIEW))
}

const triage = (t, rv) => agent(`${RULES}

Triage the cross-model findings for MB Team track ${t.id} under the brief's severity scale: fix findings that are real (blocker/major = a realistic scenario) and cheap one-line items; accept everything else to backlog with a reason. Read ${rv.file} (last VERDICT block) and the code it cites; verify each finding before keeping it.
Findings: ${JSON.stringify(rv.findings)}
Do not edit files. Run: ${book(t, '', 'triage: fix <n>, accept <m>')}
Return {fix: [finding + file:line + smallest fix], accept: [finding + reason]}.`, opts(`triage:${t.id}`, 'Triage', A.triage, TRIAGE))

const fix = (t, items, src) => agent(`${RULES}

You are the executor fixing findings for MB Team track ${t.id} (task: ${t.prompt}; your earlier report: ${t.report}${src ? '; review output: ' + src : ''}).
1. Run: ${book(t, 'fixing', `fixing ${items.length} finding(s)`)}
2. For each item: a failing test first, then the smallest fix. Items:
${items.map((x, i) => `   ${i + 1}. ${x}`).join('\n')}
3. Run the track's tests, the linter on changed files, and any contract the prompt names.
4. Append a "Fix round" section to ${t.report} (red → green per item, what was not covered) and keep a last STATUS line.
5. Run: ${book(t, 'returned', 'fixes done: <counts>', t.report)}
Return {status, summary}.`, opts(`fix:${t.id}`, 'Fix', t, STATUS))

const judge = (t, unreviewed) => agent(`${RULES}

You are the final judge for MB Team track ${t.id}: task and DoD ${t.prompt}, executor report ${t.report}, review evidence in ${rdir(t)}/ (verdict blocks are at the END of each .out.md). Run first: ${book(t, '', 'judge started')}
Verify yourself: run the track's tests and named contracts and the linter on changed files; check that what was reviewed matches the working tree; check accepted items are really minor under the brief's scale. ${unreviewed ? `A fix landed after the last allowed review round (${A.review.max_rounds}), so one hunk was never reviewed: review the unreviewed hunk yourself — the diff of the working tree against HEAD + ${rdir(t)}/round1.diff … round${A.review.max_rounds}.diff — with the same severity scale.
` : ''}Give the exact commit path list for this track (no caches, nothing owned by other tracks); a needed file outside the track's globs stays in the list and goes to orchestrator_checks as "widen: track set ${t.id} --add-files <paths>". List in orchestrator_checks every check only the orchestrator may run before the commit (for example a read-only look at live user state the tracks may not touch); empty when none.
Then run: ${book(t, 'done', 'judge <decision>: <one line>')}
   (GO → done; GO_WITH_BACKLOG → --status done_with_concerns; NO_GO, or a track already finished → drop --status.)
Return {decision, rationale, blocking, backlog, commit_paths, orchestrator_checks}.`, opts(`judge:${t.id}`, 'Judge', A.judge, JUDGE))

// The full stage results live in the run's journal.jsonl; the return value stays short for the notification.
async function runTrack(t) {
  const out = { id: t.id, reviews: [], unreviewed: false }
  if (t.start === 'execute') {
    const ex = await execute(t)
    if (!ex || /BLOCKED/.test(ex.status)) return { id: t.id, decision: 'BLOCKED', blocking: [ex ? ex.summary : 'executor returned nothing'] }
    if (t.verifier) {
      const v = await verify(t)
      if (v && !v.pass && v.issues.length) await fix(t, v.issues)
    }
    let prev = null
    for (let round = 1; t.review && round <= A.review.max_rounds; round++) {
      const rv = await review(t, round, prev)
      out.reviews.push(rv ? rv.verdict : 'NONE')
      if (!rv || /SKIPPED|APPROVED/.test(rv.verdict) || !rv.findings.length) break
      const tr = await triage(t, rv)
      if (!tr || !tr.fix.length) break
      await fix(t, tr.fix, rv.file)
      out.unreviewed = round === A.review.max_rounds
      prev = rv.file
    }
  } else if (t.start === 'fix') {
    await fix(t, t.fixes || [], t.reviewFile)
  }
  const j = await judge(t, out.unreviewed) || { decision: 'NO_VERDICT', blocking: [], backlog: [], commit_paths: [], orchestrator_checks: [] }
  log(`${t.id}: judge ${j.decision}`)
  return { id: t.id, decision: j.decision, commit_paths: j.commit_paths, blocking: j.blocking, backlog: j.backlog,
    orchestrator_checks: j.orchestrator_checks, reviews: out.reviews, unreviewed_fix: out.unreviewed }
}

return await parallel(A.tracks.map((t) => () => runTrack(t)))
