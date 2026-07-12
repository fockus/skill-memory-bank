---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Pipeline model-tier convention: Opus plan/judge, Sonnet implement, Codex review

Decision recorded in `.memory-bank/pipeline.yaml`: planning and final judging stages route to Opus; implementation stages route to Sonnet; code review routes to Codex GPT-5 (external cross-vendor check); all execution subagents (mb-backend/mb-developer/mb-frontend/etc.) always run on Sonnet regardless of stage, never Opus, for consistency and cost control.

**Why:** keep expensive reasoning (architecture planning, go/no-go judgment) on the strongest model while high-volume implementation stays cheap and fast; an external reviewer model catches blind spots a same-vendor reviewer might share with the implementer.

**Applies to:** `reviewer-2.0` and `work-loop-v2` specs, and any future `/mb work` governed pipeline stage added to this repo — check `pipeline.yaml` tier assignments before proposing a different model for a new stage.

---
*Auto-captured by MB session-memory (session 2613696a).*
