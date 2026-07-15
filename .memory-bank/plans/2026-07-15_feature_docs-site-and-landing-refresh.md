---
title: "Docs site (MkDocs Material) + landing refresh"
type: feature
status: draft
created: 2026-07-15
owner: main-agent (Opus) — plan; /mb work — execution
roles: "implement=sonnet · review=codex gpt-5.5 · judge=opus"
parallel_safe: false
---

# Docs site (MkDocs Material) + landing refresh

## Why

Two user-visible surfaces have drifted from the shipped product:

1. **No docs site.** `https://fockus.github.io/skill-memory-bank/docs/` is a hard 404 — the
   only real broken URL. All reference material lives as `docs/*.md` (GitHub-blob-rendered) and
   `commands/*.md` / `references/*.md` scattered in the repo, with no searchable, navigable home.
   `pyproject.toml [project.urls]` has no `Documentation` entry.
2. **Landing is stuck at v5.0.0.** `site/index.html` predates the 5.1–5.3 releases: Reviewer 2.0,
   work-loop-v2 sprint contracts, the cross-session coordination board, and the context-window
   statusline are all shipped but invisible. The hero `h1`
   (`site/styles.css:216`, `clamp(3.4rem, 9vw, 6.6rem)`) is oversized and pushes the feature grid
   below the first screen.

**AGR-010 (user-confirmed):** docs site = **MkDocs Material, English-only**, deployed as the
`/docs/` subpath of the *existing* GitHub Pages artifact (the landing stays at root). Existing
`docs/*.md` migrate **as-is** (nav/link fixes only). i18n via `mkdocs-static-i18n` is deferred —
**do not build it now**. Unreleased features (`update-notify`, `/mb agree`) must **not** appear
on the site or in docs yet.

## Scope

### In scope
- **Track A — docs site:** `mkdocs.yml` at repo root; Material theme (search + dark/light palette
  toggle); the approved nav; migrate the ~14 existing `docs/*.md` as-is; author ~9 new pages by
  **condensing/restructuring existing sources** (`commands/*.md`, `references/*.md`, `rules/*.md`,
  `README.md`) — not by inventing content; wire the combined GitHub Pages deploy (landing at root +
  MkDocs output under `docs/`); fix 3 broken relative doc links; add `Documentation` URL to
  `pyproject.toml`; retarget doc links in `site/index.html` + `README.md` to the new docs site.
- **Track B — landing refresh:** shrink the hero `h1` + tighten first-screen rhythm; refresh the
  feature grid for 5.1–5.3 (Reviewer 2.0, sprint contracts/work-loop-v2, coordination board,
  statusline); a "what's new in 5.x" pass; a usability sweep (mobile nav, Docs nav item → `/docs/`).

### Out of scope
- `mkdocs-static-i18n` / any non-English docs (deferred per AGR-010).
- Any mention of unreleased features (`update-notify`, `/mb agree`) on the public site/docs.
- Rewriting existing `docs/*.md` prose beyond nav/link fixes.
- Runtime dependency changes — MkDocs is a **dev/docs dependency group only** (`uv`), never a
  runtime dep. `dependencies = []` stays empty.
- Custom MkDocs plugins/theming beyond stock Material + search + palette toggle.

## Assumptions
- The CI runner can `uv run mkdocs build` (Python 3.11/3.12 as CI already pins; MkDocs Material is
  pure-Python, no native build).
- `mkdocs build --strict` is the acceptance gate for every content stage — it fails on broken
  internal links, missing nav targets, and orphaned pages, which substitutes for a link-check test.
- The existing GitHub Pages workflow (`.github/workflows/pages.yml`) uploads **one** artifact
  (`./site`). The combined-deploy stage must stage landing + docs into a single directory and keep
  it a **single** `upload-pages-artifact` (two artifacts break Pages).
- The 9 "new" pages are condensations of sources that already exist in-repo — the author reads the
  named source and restructures; no external research.
- `site_url` = `https://fockus.github.io/skill-memory-bank/docs/`; the landing keeps the root URL.

## Risks
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| CI change (`pages.yml`) breaks the live site — a protected `ci/`-class file | Med | High | Stage 4 is isolated; validate the combined artifact layout locally (`mkdocs build` + tree assertion) before touching the workflow; keep it one artifact + one upload; explicit user request covers the CI edit |
| `mkdocs build --strict` fails on a link in migrated `docs/*.md` that was fine on GitHub-blob rendering | High | Med | Stage 1 runs `--strict` over the migrated set and fixes/relativises links before adding new pages |
| Landing feature copy drifts into unreleased territory (update-notify/agree) | Med | Med | Explicit released-only rule; Stage 5 DoD asserts no `update-notify`/`agree` strings on the landing |
| Hero `h1` shrink regresses mobile layout | Low | Low | Stage 5 DoD includes a mobile-width smoke (≤390px) check for no overflow |
| Doc-link retarget (Stage 4) points at pages that do not yet exist | Med | Med | Retargeting depends on Stages 1–3; only link to pages present in the built nav |
| New nav references a page file that was never created → strict build fails | Med | Low | Each content stage lists exact file paths; strict build is the gate |

---

<!-- mb-stage:1 -->
## Stage 1 — MkDocs skeleton + migrate existing pages + strict build green (local)

**Role:** analyst
**Complexity:** M · ~5 min
**Dependencies:** —
**Files:**
- create `mkdocs.yml` (repo root)
- edit `pyproject.toml` (`[project.optional-dependencies]` → add a `docs` group)
- move/copy the existing `docs/*.md` into the MkDocs `docs_dir` layout (keep `docs/` as `docs_dir`;
  no file relocation needed if `docs_dir: docs` — only nav wiring)

### Tasks
1. Add a `docs = ["mkdocs>=1.6", "mkdocs-material>=9.5"]` group under
   `[project.optional-dependencies]` in `pyproject.toml`. Do **not** touch `dependencies` or `dev`.
2. Create `mkdocs.yml`: `site_name`, `site_url: https://fockus.github.io/skill-memory-bank/docs/`,
   `repo_url`, `docs_dir: docs`, `theme: name: material` with `features: [navigation.sections,
   navigation.top, search.suggest, content.code.copy]` and a `palette` block with a dark/light
   **toggle** (two `palette` entries with `scheme: default` / `scheme: slate` + `toggle`), and
   `plugins: [search]`.
3. Wire a `nav:` that references **only pages that exist right now** (the ~14 migrated `docs/*.md`,
   including `concepts/*.md`, `security/*.md`, and the 4 Migration files). New pages come in
   Stages 2–3 — leave their nav slots out until then (strict build must stay green).
4. Ensure `docs/README.md` is not double-served as both index and a nav page (set an explicit
   `index.md` or map the home appropriately).

### DoD
- [x] `uv run --group docs mkdocs build --strict` exits 0 with **zero** warnings.
- [x] Every `docs/*.md`, `docs/concepts/*.md`, `docs/security/*.md`, and the 4 `MIGRATION-*.md`
      appears exactly once in the built site nav (no orphan-page warnings).
- [x] `pyproject.toml` has a `docs` optional-dependencies group; `dependencies = []` unchanged;
      `dev` group unchanged.
- [x] `mkdocs.yml` `site_url` ends in `/docs/`; palette has a working dark/light toggle; search enabled.
- [x] No runtime dependency added (grep `dependencies = []` still matches).

### Verification commands
```bash
uv run --group docs mkdocs build --strict --site-dir /tmp/mb-docs-site
python -c "import tomllib,sys; d=tomllib.load(open('pyproject.toml','rb')); \
  assert d['project']['dependencies']==[], 'runtime deps changed'; \
  assert 'docs' in d['project']['optional-dependencies'], 'no docs group'"
grep -q 'site_url:.*\/docs\/' mkdocs.yml
```

### Edge cases
- A migrated page links to another `docs/*.md` with a `docs/`-prefixed or repo-root-relative path →
  strict build flags it; fix to a nav-relative path here (this is the natural place, before new pages).
- `docs/README.md` colliding with an auto-generated index → give the home an explicit source.

---

<!-- mb-stage:2 -->
## Stage 2 — New Getting Started + Concepts pages

**Role:** analyst
**Complexity:** M · ~5 min
**Dependencies:** Stage 1
**Files (create):**
- `docs/quick-start.md` (from `README.md` §"5-minute quick start", `README.md:149`)
- `docs/concepts/memory-bank-layout.md` (NEW — file/invariant reference: `status.md`, `checklist.md`,
  `progress.md` append-only, `notes/`, `plans/`, `specs/`, ID monotonicity — from CLAUDE.md invariants
  + `references/` layout docs)
- `docs/concepts/rules.md` (NEW — condensed from `rules/RULES.md` + rules-only mode from CLAUDE.md)
- `docs/concepts/sdd.md` (NEW — `discuss → sdd → work` flow from `commands/discuss.md`,
  `commands/sdd.md`, `references/templates.md`)

### Tasks
1. Extract the quick-start into `docs/quick-start.md` (condense, keep commands copy-paste accurate).
2. Write `memory-bank-layout.md`: one section per bank file with its invariant (append-only,
   ID rules, ✅/⬜ immediacy). Source = CLAUDE.md "Key invariants" + existing references.
3. Write `concepts/rules.md`: TDD / Clean Architecture / FSD / SOLID thresholds / Testing Trophy /
   coverage / rules-only mode — condensed from `rules/RULES.md`. Link to the source for depth.
4. Write `concepts/sdd.md`: the EARS → requirements → design → `tasks.md` (`<!-- mb-task:N -->`)
   pipeline; keep it released-behaviour only (no OpenSpec-parity/unreleased features).
5. Add all four to `mkdocs.yml` nav under **Getting Started** (quick-start) and **Concepts**
   (the other three), alongside the existing `overview.md`, `code-graph.md`, `session-memory.md`,
   `install.md`, `first-feature.md`, `cross-agent-setup.md`.

### DoD
- [x] 4 new pages exist; each ≥ 30 lines of real content, no `TODO`/`...`/placeholders.
- [x] Nav shows Getting Started (install, quick-start, first-feature, cross-agent-setup) and
      Concepts (overview, memory-bank-layout, rules, code-graph, session-memory, sdd).
- [x] `uv run --group docs mkdocs build --strict` exits 0, zero warnings.
- [x] No page mentions `update-notify`, `/mb agree`, or `/mb upgrade` auto-check as a released feature.
- [x] Every command/env-var shown matches the current `commands/*.md` / README (spot-checked).

### Verification commands
```bash
uv run --group docs mkdocs build --strict --site-dir /tmp/mb-docs-site
for f in docs/quick-start.md docs/concepts/memory-bank-layout.md docs/concepts/rules.md docs/concepts/sdd.md; do \
  test -s "$f" || { echo "MISSING $f"; exit 1; }; done
! grep -rniE 'update-notify|/mb agree|agreements\.sh' docs/quick-start.md docs/concepts/memory-bank-layout.md docs/concepts/rules.md docs/concepts/sdd.md
```

### Edge cases
- Quick-start commands referencing scripts that were renamed post-5.0 → verify against current
  `scripts/` names before publishing.
- Rules page must not contradict `rules/RULES.md` thresholds (≤300 lines SRP, ≤5-method ISP, etc.).

---

<!-- mb-stage:3 -->
## Stage 3 — New Guides + Reference pages

**Role:** analyst
**Complexity:** L · ~5 min
**Dependencies:** Stage 1 (independent of Stage 2 content; may run parallel to Stage 2)
**Files (create):**
- `docs/mb-work.md` (from `commands/work.md` — composable pipeline, review/judge, sprint contracts)
- `docs/reviewer-2.md` (NEW — v5.3 Reviewer 2.0: `mb-review.sh`, calibrated review, test-evidence
  cache, `--require-tests-blocker`, golden calibration suite — from CHANGELOG + `agents/mb-reviewer.md`)
- `docs/coordination.md` (from `references/coordination.md` — the `COORDINATION.md` board protocol)
- `docs/commands.md` (NEW — all `/mb` commands, condensed from `commands/mb.md`)
- `docs/environment-variables.md` (NEW — the env-var table from `README.md:517`, released vars only)
- `docs/pipeline-yaml.md` (NEW — `pipeline.yaml` schema from `references/pipeline.default.yaml`)
- `docs/hooks.md` (NEW — from `references/hooks.md`)

### Tasks
1. `mb-work.md`: implement→verify→review→judge loop, `--review`/`--judge`/`--workflow`,
   severity gates, sprint contracts + progress trend + strategic pivoting
   (`mb-work-contract.sh`/`mb-work-trend.sh`/`mb-work-pivot.sh`).
2. `reviewer-2.md`: the 5.3 Reviewer 2.0 surface — released behaviour only.
3. `coordination.md`: migrate `references/coordination.md` (board protocol, scoped `git add`, FREEZE/ACK).
4. `commands.md`: a compact table of all `/mb` commands + one-line purpose, from `commands/mb.md`.
   Exclude any unreleased command (`/mb agree`).
5. `environment-variables.md`: reproduce the released env-var table; **omit** `MB_UPDATE_CHECK*`
   / `MB_AUTO_UPDATE` (those ship with update-notify, not yet released) — include only vars present
   in a released VERSION's README/docs.
6. `pipeline-yaml.md`: the schema (roles, `stage_pipeline`, budget, `protected_paths`,
   `sprint_context_guard`, `review_rubric`, `sdd`) from `references/pipeline.default.yaml`.
7. `hooks.md`: per-hook install guide from `references/hooks.md` (released hooks only — exclude
   `mb-update-notify.sh`).
8. Add all seven to `mkdocs.yml` nav under **Guides** (mb-work, reviewer-2, coordination,
   rule-profiles, i18n, updating) and **Reference** (commands, agents-reference,
   environment-variables, pipeline-yaml, hooks). Also add `docs/updating.md` and `docs/i18n.md`
   nav slots if not already (existing files).

### DoD
- [x] 7 new pages exist; each ≥ 30 lines; no placeholders.
- [x] Nav has Guides (mb-work, reviewer-2, coordination, rule-profiles, i18n, updating) and
      Reference (commands, agents-reference, environment-variables, pipeline-yaml, hooks).
- [x] `environment-variables.md` contains **no** `MB_UPDATE_CHECK`, `MB_UPDATE_CHECK_TTL`,
      `MB_AUTO_UPDATE` rows (unreleased).
- [x] `hooks.md` does **not** document `mb-update-notify.sh`.
- [x] `commands.md` does **not** list `/mb agree`.
- [x] `uv run --group docs mkdocs build --strict` exits 0, zero warnings.

### Verification commands
```bash
uv run --group docs mkdocs build --strict --site-dir /tmp/mb-docs-site
for f in docs/mb-work.md docs/reviewer-2.md docs/coordination.md docs/commands.md \
  docs/environment-variables.md docs/pipeline-yaml.md docs/hooks.md; do test -s "$f" || { echo "MISSING $f"; exit 1; }; done
! grep -qE 'MB_UPDATE_CHECK|MB_AUTO_UPDATE' docs/environment-variables.md
! grep -q 'mb-update-notify' docs/hooks.md
! grep -q '/mb agree' docs/commands.md
```

### Edge cases
- `commands/mb.md` may reference commands gated behind unreleased work — cross-check against the
  latest **released** VERSION before listing.
- `pipeline.default.yaml` keys must match the shipped validator (`mb-pipeline-validate.sh`) — do not
  document keys the validator rejects.

---

<!-- mb-stage:4 -->
## Stage 4 — Combined Pages deploy + link retargeting + broken-link fixes

**Role:** devops
**Complexity:** M · ~5 min
**Dependencies:** Stages 1, 2, 3 (all docs content must exist and build strict-green first)
**Files:**
- edit `.github/workflows/pages.yml` — **CI file, in scope by explicit user request** (docs deploy).
  Normally `ci/`-class files are protected; this edit is authorised for this plan only.
- edit `pyproject.toml` — add `Documentation` to `[project.urls]`
- edit `docs/cross-agent-setup.md` — fix `../.memory-bank/plans/2026-04-20_refactor_skill-v2.1.md`
- edit `docs/MIGRATION-v3-v3.1.md` — fix `plans/2026-04-21_feature_foo.md` +
  `plans/2026-04-21_refactor_bar.md`
- edit `site/index.html` — retarget doc links from GitHub blob URLs to the docs site
- edit `README.md` — retarget doc links from GitHub blob URLs to the docs site

### Tasks
1. **pages.yml combined artifact:** add a build step (`astral-sh/setup-uv` or `pip install`)
   that runs `uv run --group docs mkdocs build --site-dir <combined>/docs`, then copies `site/*`
   into `<combined>/` root, then a **single** `upload-pages-artifact` pointing at `<combined>`.
   Result: landing at `/`, docs at `/docs/`. Keep it one artifact, one upload, one deploy.
2. Extend the workflow `on.push.paths` to add `docs/**` and `mkdocs.yml` (so docs changes trigger deploy).
3. Add `Documentation = "https://fockus.github.io/skill-memory-bank/docs/"` to `[project.urls]`.
4. Fix the 3 broken relative links: repoint `cross-agent-setup.md` and `MIGRATION-v3-v3.1.md` to
   valid targets (an existing plan/doc, or drop the dead reference if no valid target exists).
5. Retarget the docs links in `site/index.html` and `README.md` that pointed at GitHub blob URLs to
   the new `/docs/...` pages — **only** for pages that now exist in the built nav.

### DoD
- [x] `pages.yml` produces **one** artifact with landing at root + MkDocs output under `docs/`
      (validated by a local dry-run of the same steps producing `<combined>/index.html` and
      `<combined>/docs/index.html`).
- [x] `pages.yml` `on.push.paths` includes `docs/**` and `mkdocs.yml`; still exactly one
      `upload-pages-artifact` step.
- [x] `actionlint` (or `yaml` parse) clean on the edited workflow.
- [x] `pyproject.toml [project.urls]` has a `Documentation` entry ending `/docs/`.
- [x] `mkdocs build --strict` still exits 0 after the 3 link fixes (they are inside `docs/`).
- [x] No remaining GitHub-blob docs link in `site/index.html`/`README.md` that has a `/docs/` equivalent.

### Verification commands
```bash
# local rehearsal of the combined artifact the workflow will build
rm -rf /tmp/mb-pages && mkdir -p /tmp/mb-pages
uv run --group docs mkdocs build --site-dir /tmp/mb-pages/docs --strict
cp -R site/. /tmp/mb-pages/
test -f /tmp/mb-pages/index.html && test -f /tmp/mb-pages/docs/index.html
grep -c 'upload-pages-artifact' .github/workflows/pages.yml   # must be 1
command -v actionlint >/dev/null && actionlint .github/workflows/pages.yml || python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/pages.yml'))"
python -c "import tomllib; d=tomllib.load(open('pyproject.toml','rb')); assert d['project']['urls']['Documentation'].endswith('/docs/')"
```

### Edge cases
- A blob link in `site/index.html` pointing at a page with **no** docs-site equivalent → leave it
  pointing at the repo (do not invent a docs page just to satisfy the retarget).
- The broken relative links may have **no** valid modern target → remove the dead link/sentence
  rather than fabricate a plan path.
- Pages `on.push.paths` already lists `README.md` — keep it; do not drop existing triggers.

---

<!-- mb-stage:5 -->
## Stage 5 — Landing: hero shrink + feature refresh + usability

**Role:** frontend
**Complexity:** M · ~5 min
**Dependencies:** Stage 4 (Docs nav item links to `/docs/`, which must be deploying by then)
**Files:**
- edit `site/styles.css` (hero `h1` at `:216`, first-screen spacing)
- edit `site/index.html` (feature cards, v5 section → 5.x, Docs nav item, "what's new")
- edit `site/app.js` only if the nav/toggle needs it (avoid unless required)

### Tasks
1. **Hero:** change `site/styles.css:216` `font-size` from `clamp(3.4rem, 9vw, 6.6rem)` to
   `clamp(2.2rem, 5vw, 3.8rem)`; tighten the hero vertical rhythm (padding/margins) so the feature
   grid enters the first screen sooner. Keep the hero **copy** unchanged.
2. **Features:** update/add cards for **Reviewer 2.0**, **sprint contracts / work-loop-v2**,
   **coordination board**, **context-window statusline** — released 5.1–5.3 features only.
3. **What's new:** either add a "What's new in 5.3" strip or relabel the "v5 pipeline" section to
   cover 5.x. Released content only — **no** `update-notify` / `/mb agree`.
4. **Usability:** ensure the **Docs** nav item links to `/docs/`; verify the mobile nav
   (hamburger/collapse) still works; check no horizontal overflow at ≤390px.

### DoD
- [x] `site/styles.css` hero `h1` `font-size` = `clamp(2.2rem, 5vw, 3.8rem)` (or agreed equivalent);
      hero spacing reduced (measurable: feature grid top offset decreases vs. before).
- [x] Feature grid has cards naming Reviewer 2.0, sprint contracts/work-loop-v2, coordination board,
      and statusline.
- [x] The landing has a Docs nav entry whose `href` resolves to `/docs/` (or the full docs URL).
- [x] No `update-notify` / `agree` / unreleased strings anywhere in `site/index.html`.
- [x] `site/index.html` is valid HTML (no unclosed tags) — a parse smoke passes.
- [x] Mobile smoke at 390px width: no horizontal scroll, nav reachable.

### Verification commands
```bash
grep -q 'clamp(2.2rem, 5vw, 3.8rem)' site/styles.css
grep -qiE 'Reviewer 2\.0|reviewer-2' site/index.html
grep -qiE 'coordination|sprint contract|work.?loop|statusline' site/index.html
grep -qiE 'href="[^"]*docs/?"' site/index.html
! grep -qiE 'update-notify|/mb agree' site/index.html
python -c "from html.parser import HTMLParser; import sys; \
  p=HTMLParser(); p.feed(open('site/index.html',encoding='utf-8').read()); print('html-parse-ok')"
# optional visual smoke:
uv run --group docs mkdocs serve  # then open the landing via a static server; manual mobile check
```

### Edge cases
- Shrinking the hero must not clip the CTA buttons on desktop → check ≥1280px too.
- A new feature card must not overflow the grid template (keep the existing 7-card grid rhythm).
- Do not regress existing anchor links (`#features`, `#install`, `#docs`) referenced by the nav.

---

## Dependency graph

```
Stage 1 ──┬── Stage 2 ──┐
          └── Stage 3 ──┴── Stage 4 ── Stage 5
```

Stages 2 and 3 both depend only on Stage 1 and are content-independent of each other → parallelisable.
Stage 4 (deploy + retargeting) needs all docs content to exist. Stage 5 (landing Docs link) needs the
docs deploy path wired by Stage 4.

## Parallelisation
| Phase | Stages | Agents |
|-------|--------|--------|
| 1 | 1 | analyst |
| 2 | 2, 3 | analyst-1, analyst-2 (or sequential — same role, `docs/` files distinct) |
| 3 | 4 | devops |
| 4 | 5 | frontend |

## Potential merge conflicts
- `mkdocs.yml` `nav:` is edited by Stages 1, 2, 3 → if 2 and 3 run in parallel, they touch the same
  `nav:` block. Mitigation: serialise the `mkdocs.yml` nav edits (append distinct nav sub-trees) or
  run 2→3 sequentially. All other files per stage are disjoint.
- `README.md` is edited only in Stage 4; `pyproject.toml` in Stages 1 (deps) and 4 (urls) — distinct
  blocks, low conflict risk but keep edits scoped.

## Checklist (copy into checklist.md)
- ⬜ Stage 1: MkDocs skeleton + migrate existing pages + strict build green
- ⬜ Stage 2: New Getting Started + Concepts pages (quick-start, memory-bank-layout, rules, sdd)
- ⬜ Stage 3: New Guides + Reference pages (mb-work, reviewer-2, coordination, commands, env-vars, pipeline-yaml, hooks)
- ⬜ Stage 4: Combined Pages deploy + link retargeting + 3 broken-link fixes + Documentation URL
- ⬜ Stage 5: Landing hero shrink + feature refresh + usability sweep

## Verification (whole plan)
- [ ] `uv run --group docs mkdocs build --strict` green with the full nav (all migrated + 9 new pages).
- [ ] Local combined-artifact rehearsal yields `index.html` (landing) at root and `docs/index.html`.
- [ ] `pages.yml` = one artifact, one upload, one deploy; `actionlint`/yaml-parse clean.
- [ ] No unreleased feature (`update-notify`, `/mb agree`) appears on the landing or in any docs page.
- [ ] The 3 previously-broken relative doc links resolve; `pyproject.toml` has a `Documentation` URL.
- [ ] Landing hero shrunk; feature grid covers 5.1–5.3; Docs nav item points at `/docs/`.
