# Promotion playbook — v5.0.0 launch (2026-06-11)

Source: web research session 2026-06-11 (channels verified individually). Status of repo at
research time: 8 stars, v5.0.0 on PyPI, 20 GitHub topics, social preview NOT set.

## Pitch angles

- **Amnesia** (broad): "Memory Bank ends AI session amnesia — project context, decisions and
  TDD rules persist across every Claude Code / Cursor / Windsurf / Cline session."
- **Toolkit** (power users): "Not just memory: 25 commands, spec-driven development, a code
  graph, and Clean Architecture enforcement — one skill, 30-second install."
- **Universal** (differentiator): "One `.memory-bank/`, eight AI coding clients. Memory that
  follows the project, not the vendor."

## Channels (effort → impact)

| Channel | Mechanism | Notes |
|---|---|---|
| ClawHub (clawhub.ai) | `npm i -g clawhub && clawhub login && clawhub skill publish .` | Use `--dry-run` first (security scanner had a big purge; review scan output) |
| SkillsMP (skillsmp.com) | Automatic GitHub crawl, ≥2 stars | Passive — verify indexing, no action |
| skills.sh (vercel-labs) | Already works: `npx skills add fockus/skill-memory-bank` | Mention in posts |
| claudeskills.club/submit | Web form (repo URL) | 5 minutes |
| hesreallyhim/awesome-claude-code (46k★) | **Recommendation issue**, NOT a PR | Highest leverage; verify issue template first |
| travisvn/awesome-claude-skills | Fork → PR | Requires ~10 stars; no AI-written PR text |
| VoltAgent / GetBindu / ComposioHQ / rohitg00 awesome lists | Fork → PR each | Standard entry format |
| anthropics/skills | PR (high bar, 691 open PRs) | Week 2–3; don't block on it |
| Show HN | Tue–Thu 09:00–12:00 PT | Engineer voice, maker comment ready, reply 6h non-stop |
| r/ClaudeAI | "Tools & Resources" flair + GIF of `/mb start` | Same day as HN or next |
| Anthropic Discord (103k) | #tools/#skills channel post | Short + link |
| X/Twitter | GIF + #ClaudeCode, tag @AnthropicAI | Ongoing |
| dev.to comparison articles | "Memory Bank vs Cline Memory Bank" etc. | Days 8–10; targets existing search intent |
| Product Hunt | 12:01 AM PT Tuesday, week 3 | Needs icon 240×240, gallery, asciinema demo |

## 2-week sequence

1. **Day 1–2:** upload social preview (Settings → Social preview → `site/og-image.png`, done
   in repo), draft HN maker comment + Reddit post, prep ClawHub frontmatter (add version/tags
   to SKILL.md YAML only after validating tests still pass; validate with `--dry-run`).
2. **Day 3:** directory blitz — ClawHub publish, claudeskills.club form, awesome-list
   issue/PRs (travisvn after 10★), verify SkillsMP indexing.
3. **Day 4:** Show HN 10:00 PT + r/ClaudeAI + Discord + X.
4. **Day 5–7:** answer everything; collect questions → FAQ.
5. **Day 8–10:** dev.to article #1 (vs Cline memory bank), cross-post Hashnode with canonical.
6. **Day 11–13:** anthropics/skills PR; Product Hunt assets.
7. **Day 14:** Product Hunt launch (Tuesday).

## Assets still needed

- [x] og-image / social preview file (`site/og-image.png`) — upload to GitHub Settings manually
- [ ] Terminal demo GIF or asciinema (`/mb start` → `/mb plan` → `/mb work` → `/mb done`)
- [ ] HN maker comment draft
- [ ] r/ClaudeAI post draft
- [ ] dev.to article #1 draft
- [ ] Product Hunt: icon 240×240, 3–5 gallery shots, tagline ≤60 chars

## Risks

- travisvn list needs 10★ (at 8) — build stars via Discord/HN first.
- ClawHub scanner false-positives on shell-heavy skills — dry-run + review.
- awesome-claude-code process is issue-based and in reorganization — re-verify before filing.
