# Track A — admin: users page, roles, secret file

Brief (binding, read it first): /Users/me/proj/.memory-bank/reports/sso-20261010/brief.md
Role: mb-backend · model opus · size large · Skill path: /Users/me/.claude/skills/memory-bank
Working tree: /Users/me/arcadia-int · Bank: /Users/me/proj/.memory-bank

<!-- mb-stage:1 -->
## Task
The admin users page lists Keycloak users of the delivery realm and assigns only `harness-user` and `harness-admin`
through the service client `harness-admin-users`, reading its secret from `KEYCLOAK_USERS_CLIENT_SECRET_FILE`.

**Role:** backend
**Files:** `/Users/me/arcadia-int/neuroexpert/backend/harness-admin/**`, `/Users/me/arcadia-int/neuroexpert/frontend/admin/src/pages/users/**`
**Depends on:** K (read /Users/me/proj/.memory-bank/reports/sso-20261010/K.md before you rely on its work)

**DoD:**
- [ ] Assigning `harness-session-auditor` from the page is refused with 403 and a test proves it.
- [ ] A missing or group-readable secret file stops the admin at start with a clear error; tests cover both.
- [ ] Build and tests of the touched packages are green under `mb-lock.sh run build`.
<!-- /mb-stage:1 -->

## Pipeline (resolved — do not change it)
- This track runs through /mb work on /Users/me/proj/.memory-bank/reports/sso-20261010/tracks/A.prompt.md, driven by the orchestrator: you are dispatched per stage, and the verifier and review gates run inside that loop.
- TDD is required: failing test first; paste the command and output before and after into the report.
- Resource `build`: see the brief, section Resources. Run it in the background with `--owner A`.

## Report and reply
Write /Users/me/proj/.memory-bank/reports/sso-20261010/A.md (format in the brief). Post STATUS on the board when you
start and finish. Reply with the STATUS line, five lines of summary and the report path. Do not commit; do not
message other tracks.
