---
type: spec-examples
topic: mb-team
status: draft
created: 2026-10-10
linked_design: design.md
---

# Examples: mb-team

Golden references for the templates and the config validator. The example team is a corporate-SSO delivery with three
tracks in one integration tree, a shared native build and a disk threshold — the shape of the harness runs of
2026-10-09..10, with the project specifics generalized.

## 1. `pipeline.yaml` — `team:` section

Nested block mappings and scalar inline lists only (design D6), so the stdlib fallback parser and PyYAML agree.

```yaml
team:
  default_size: standard
  max_parallel: 6

  # Size → track pipeline. This table IS the project default (AGR-148 layer 1).
  # Omitted sizes fall back to the bundled presets in references/pipeline.default.yaml.
  presets:
    small:
      mode: direct
      tdd: required
      verifier: none
      review: none
      models: {executor: mid}
      effort: medium
    standard:
      mode: direct
      tdd: required
      verifier: none            # AGR-147 in this project: quality comes from the team lens review
      review: none
      models: {executor: mid}
      effort: medium
    large:
      mode: direct
      tdd: required
      verifier: none
      review: single
      models: {executor: premium, reviewer: premium}
      effort: high

  # Forced on every track whatever its size (applied after the preset).
  overrides:
    tdd: required

  # Project rules rendered into every brief, after the built-in rules.
  rules:
    - "Go code: gofmt and go vet clean before you report."
    - "Dockerfile and Helm are not edited; environment goes into the client code."
    - "Do not run find or du over the whole home directory."

  review:
    enabled: true             # opt-in; bundled default is false
    lenses: [logic, security, tests, scalability, quality]
    clean_when: {blocker: 0, major: 0, medium: 0}
    max_cycles: 5
    models: {lenses: premium, lead: premium}

  resources:
    build:
      kind: mutex
      scope: host               # one native build per machine, across trees and banks
      preconditions:
        free_disk_gb: 25
        disk_path: /System/Volumes/Data
        check: "test -x ./ya"
      stop_threshold:
        free_disk_gb: 12
      maintenance: "./ya gc cache"
      watch_interval_s: 30
    full-tests:
      kind: mutex
      scope: bank               # the repository's full suite flakes under parallel load (I-223)

  checkpoint:
    dir: ../.local-stand/backups
    max_untracked_mb: 512
    extra: "bash .local-stand/r-work/vm_snapshot.sh"
```

## 2. One resource, end to end

Config above (`team.resources.build`) resolves to the C3 JSON:

```json
{"name": "build", "kind": "mutex", "scope": "host", "path": "/var/folders/xy/T/mb-locks/build",
 "preconditions": {"free_disk_gb": 25, "disk_path": "/System/Volumes/Data", "check": "test -x ./ya"},
 "stop_threshold": {"free_disk_gb": 12, "check": null}, "maintenance": "./ya gc cache",
 "watch_interval_s": 30, "poll_s": 5}
```

A track runs its build in the background and keeps working:

```bash
bash "$SKILL_DIR"/scripts/mb-lock.sh run build --owner D3 --mb /Users/me/proj/.memory-bank -- \
  ./ya make -tt neuroexpert/backend/documents/internal/parsers/docx
```

What it prints and returns:

```
mb-lock: queued for build as #2; held by R pid 36940 since 12:56:59 (43m): ./ya make -k -j4 bundle
mb-lock: waiting #1 (next); held by T515 pid 41210 since 13:40:02 (6m): ./ya make -tt harness
mb-lock: acquired build; free 21 GiB < 25 → maintenance: ./ya gc cache
mb-lock: free 31 GiB, preconditions ok; running
...
exit 0            # child status; 75 wait timeout · 76 stop threshold hit · 77 still < 25 GiB after maintenance
```

Orchestrator view and the background disk guard:

```bash
bash "$SKILL_DIR"/scripts/mb-lock.sh status --mb /Users/me/proj/.memory-bank
bash "$SKILL_DIR"/scripts/mb-lock.sh watch build --mb /Users/me/proj/.memory-bank   # run_in_background
```

```
build  held by D3 (pid 51002, child 51007) 14m  ./ya make -tt …/docx     alive
       queue: G 9m · T516 3m
       free 18 GiB · preconditions false (< 25) · stop 12 ok
full-tests  free
```

## 3. Brief — `reports/sso-20261010/brief.md` (rendered, then completed by the orchestrator)

```markdown
# Corporate SSO on-prem: brief for track executors (2026-10-10)

Plan: /Users/me/proj/.memory-bank/plans/2026-10-09_feature_onprem-corporate-sso.md
Decisions: AGR-131, AGR-132, AGR-133 in /Users/me/proj/.memory-bank/agreements.md. Goal: G-002 (goal.md).
Deadline: code by the freeze on 2026-10-15, delivery 2026-10-18.

## Checked by the orchestrator
- The kit builds the admin binary from HEAD, so a fix in the admin lands in the next bundle without an image rebuild.
- Kit config for Keycloak: bundle/templates/keycloak-realm.json.tmpl. The Helm values are not used by the kit.

## Tracks
| Track | Role | Model | Size | Pipeline | Task | Depends on | Resources | Report |
|---|---|---|---|---|---|---|---|---|
| K | devops | sonnet | standard | direct · TDD | realm, mappers, service client in the kit | — | build | K.md |
| A | backend | opus | large | direct · TDD · review single | admin: users page, roles, secret file | K (contract) | build | A.md |
| C | backend | sonnet | standard | direct · TDD | Core: user resolution order, 403 rules | — | build | C.md |

## Not doing
- SAML attribute mapping beyond NameID: after 2026-10-18.

## Contract between tracks
Frozen on the board as `FREEZE · contract:sso-20261010`. Change it only through a HANDOVER to the orchestrator.
- Token claim `harness_uid`: 1–128 chars of `[A-Za-z0-9._@:-]`, otherwise 403 in frontend, admin and Core.
- User resolution: explicit binding → `harness_uid` with role `harness-user` → 403. org_id comes from `ORG_ID`, not the token.
- Service client `harness-admin-users`: confidential, secret in a 0600 file passed as `KEYCLOAK_USERS_CLIENT_SECRET_FILE`.

## Working tree
- Edit only in /Users/me/arcadia-int (arc). /Users/me/arcadia3 is a clean mirror for bundles: do not touch.
- Run Memory Bank commands with `--mb /Users/me/proj/.memory-bank`, never from inside the bank directory.

## Rules
- Failing test first, then code. Put the test command and its output before and after the change into the report.
- Minimal diff in the layer that owns the invariant; no general refactors.
- Do not commit, push or open PRs: the orchestrator commits. Do not change permissions, settings or CLAUDE.md.
- Do not read or print secrets. Do not touch the stand. Protected paths: .env*, CI, Docker/K8s/Terraform.
- Report to the orchestrator only; never message other tracks. Findings that affect another track: HANDOVER on the board.
- A safety-filter refusal is reported as BLOCKED, not worked around.
- Go code: gofmt and go vet clean before you report.
- Dockerfile and Helm are not edited; environment goes into the client code.
- Do not run find or du over the whole home directory.

## Resources
- **build** — every `ya make` goes through
  `bash /Users/me/.claude/skills/memory-bank/scripts/mb-lock.sh run build --owner <track> --mb /Users/me/proj/.memory-bank -- <command>`.
  Start it in the background and keep writing code and tests while it waits. It runs `./ya gc cache` itself when free
  disk is below 25 GiB; exit 77 means the disk is still short — report BLOCKED. Exit 76 means free disk fell under
  12 GiB during the build and the build was stopped. Never remove a lock; ask the orchestrator.

## Limits
- Build only your own packages (`-tt` on your directories), no `--output`, `-j4` at most.

## Known red tests (do not fix, do not count as regressions)
- library/harness TestRace — trunk data race (since 2026-10-09).

## Board
`bash /Users/me/.claude/skills/memory-bank/scripts/mb-coord.sh append --mb /Users/me/proj/.memory-bank --track <track> --type STATUS|BLOCKED|HANDOVER --title '<one line>'`
STATUS when you start and when you finish; BLOCKED when you cannot continue; read `mb-coord.sh active` before editing a file another track owns.

## Report
`/Users/me/proj/.memory-bank/reports/sso-20261010/<track>.md`, first line `STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT`, then:
Files · Tests (failing before → passing after, with output; each failing test marked new or known-red) · Remaining ·
Questions for the orchestrator · Follow-ups.
```

## 4. Track prompt — `reports/sso-20261010/tracks/A.prompt.md`

```markdown
# Track A — admin: users page, roles, secret file

Brief (binding, read it first): /Users/me/proj/.memory-bank/reports/sso-20261010/brief.md
Role: mb-backend · model opus · size large · Skill path: /Users/me/.claude/skills/memory-bank
Working tree: /Users/me/arcadia-int · Bank: /Users/me/proj/.memory-bank

<!-- mb-stage:1 -->
## Task
The admin users page lists Keycloak users of the delivery realm and assigns only `harness-user` and `harness-admin`
through the service client `harness-admin-users`, reading its secret from `KEYCLOAK_USERS_CLIENT_SECRET_FILE`.

**Files:** `neuroexpert/backend/harness-admin/**`, `neuroexpert/frontend/admin/src/pages/users/**`
**Depends on:** K — realm and service client per the contract (read K.md before wiring the client).

**DoD:**
- [ ] Assigning `harness-session-auditor` from the page is refused with 403 and a test proves it.
- [ ] A missing or group-readable secret file stops the admin at start with a clear error; tests cover both.
- [ ] Build and tests of the touched packages are green under `mb-lock.sh run build`.
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- You implement directly. After you return, the orchestrator runs one reviewer (opus) on your diff; there is no verifier.
- TDD is required: failing test first; paste the command and output before and after into the report.
- Resource `build`: see the brief, section Resources. Run it in the background with `--owner A`.

## Report and reply
Write /Users/me/proj/.memory-bank/reports/sso-20261010/A.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
```

## 5. Resolved pipeline with provenance (`/mb team plan`)

User prompt: «трек A крупный, ревью одним ревьюером на opus, исполнитель opus».

```
ID  ROLE     SIZE      MODE    TDD       VERIFIER  REVIEW  EXECUTOR  REVIEWER  EFFORT  WAVE
K   devops   standard  direct  required  none      none    sonnet    -         medium  1
C   backend  standard  direct  required  none      none    sonnet    -         medium  1
A   backend  large     direct  required  none      single  opus      opus      high    2 (deps K)

provenance A: size=prompt mode=preset:large tdd=override review=prompt models.executor=prompt models.reviewer=prompt
warnings: A effort=high but agent mb-backend has effort: medium (Claude Code reads effort from the agent) — accept or change
ready: brief filled · resources defined · no glob overlap in wave 1
```

## 6. `/mb team status`

```
team sso-20261010 · goal G-002 3/6 · tree /Users/me/arcadia-int (arc) · baseline 133e077c · budget off
ID  STATUS       PIPELINE              BOARD (latest)                        REPORT
K   done         direct/tdd            STATUS 10-10 K: realm + mappers ready  K.md STATUS: DONE (collected)
C   reviewing    direct/tdd            STATUS 10-10 C: tests green            C.md STATUS: DONE
A   blocked      direct/tdd/review:1   BLOCKED 10-10 A: disk 12 GiB (no ACK)  A.md STATUS: BLOCKED
resources: build held by C (pid 812, 38m, ./ya make -tt core); queue A 41m · free 12 GiB, preconditions false, stop 12 hit
review: cycle-2 CHANGES_REQUESTED (0 blocker / 1 major / 2 medium / 7 minor) → fixes for A, C
next: stop_human blocked:A · review C
```

## 7. External reviewer prompt — skeleton of `review/external-<name>-cycle-N/prompt.md`

```markdown
# Review <name>: <object title> (cycle N)

You are an independent auditor. Executors keep editing the working tree while you review; you do not edit code.

## Object
- Commit under review: <rev>; baseline: <base>. Diff: `<vcs> diff <base> <rev>` (about <n> files).
- Read files from the commit (`<vcs> show <rev>:<path>`), not from the working tree. Do not review uncommitted changes.
- Earlier cycles: the delta since your last cycle is `<vcs> diff <prev-rev> <rev>`.

## Read first (absolute paths)
- agreements.md — decisions in force; check the change against them.
- the plan, review/cycle-*/master.md, your previous cycle folder.

## Lenses
logic · security · tests · scalability · quality — one line of scope each, from the team review config.

## Known open items — do not reopen without new facts
- <from team.json known_open>

## Output (two files in this folder)
- findings.json: [{"id","severity":"blocker|major|medium|minor","lens","file","line","scenario","fix"}]
- prior-closure.json: [{"id","status":"closed|open|partial","evidence"}] for every medium+ finding of earlier cycles.
```
