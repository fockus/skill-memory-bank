---
topic: mb-donor-evolution
status: ready
created: 2026-07-15
method: grilling-interview (substitutes /mb discuss per user decision)
source: specs/mb-donor-evolution/source-plan.md
---

# Context: mb-donor-evolution

Donor-driven evolution program: turn Memory Bank into a portable long-session
engineering system (GSD/OpenSpec/Archon/Superpowers/CCPM/Ruflo donors) while
keeping the core contract — agents remember, state belongs to the project,
expensive modes stay opt-in.

Requirements live in the umbrella spec (`specs/mb-donor-evolution/requirements.md`,
REQ-PGM/CP/RK/PI/WF/EX/EV/SR/GH/DS/XE/KB/RP/OP/GSD/OSA). This file records the
discovery decisions taken in the grilling interview of 2026-07-15.

## Decisions (confirmed by user)

1. **Spec structure — umbrella + JIT slices.** One umbrella spec
   `mb-donor-evolution` (per source-plan §0) + plan-as-wrapper only for the
   nearest release. Release-slice specs are created just-in-time before each
   release. No mega-plan, no 11 upfront specs.
2. **Version renumbering — +1 minor shift inside 5.x.** v5.3.0 was already
   released (2026-07-13) before program start, so the remainder of Этап 0
   ships as **v5.4.0 Trustworthy Baseline**. Shifted map:
   doc v5.3.0→**5.4.0** (Baseline), doc v5.4.0→**5.5.0** (Control Plane),
   doc v5.5.0→**5.6.0** (Kernel), doc v5.6.0→**5.7.0** (Plan IR);
   v6.0.0–v6.6.0 unchanged. Sanctioned by source-plan §23 (monotonic shift
   allowed when a semver is already taken; boundaries/priorities preserved).
3. **Roadmap — two parallel tracks.** The legacy "Next" queue keeps living its
   own life; the donor program is a separate roadmap track.
4. **Conflict rule — donor wins.** `parallel-pipeline` is marked superseded
   immediately (source-plan §2.1). Any legacy plan overlapping a donor release
   (work-loop-v2 ↔ 5.6/5.7, reviewer-2.0 ↔ 6.1, …) freezes when that donor
   release starts; surviving requirements move into the release slice via SDD
   delta-review. Until then the legacy plan may proceed freely.
5. **Prioritization — full ICE scoring now.** All releases scored
   Impact×Confidence×Ease; order rebuilt where the dependency graph
   (source-plan §9.3) permits; low-scoring releases may be cut to the
   **icebox** (with a revisit trigger), not just reordered.
6. **Process.** This grilling = the discuss phase (no duplicate interview).
   Umbrella SDD normalized from source-plan via `/mb sdd` flow, validated with
   `mb-spec-validate.sh --require-scenarios` + traceability. Implementation
   later through governed `/mb work` (standing role division: Sonnet
   implementers, external reviewer, judge). Tag/publish/push only with
   explicit user authorization (source-plan §21.5).

## Constraints carried from source-plan (normative)

- `.memory-bank/` stays the single source of truth (INV-01); `/mb work` the
  only execution entrypoint; no second runtime/state store (§0.3).
- Defaults remain economical (INV-09); heavyweight paths opt-in.
- REQ-IDs of §8/§29.16/§30.16 are stable and must not be renumbered.
- mb-task numbering 1..132 is normative (§19.2) and must not be renumbered —
  only release *labels* shift per decision 2.
- No implementation before a valid spec triple (§0.3); DoD never closed on
  agent self-report.

## Out of scope

- Forks/ports of donor runtimes (OpenSpec CLI, GSD command surface, Archon
  Bun/DB/server/UI, Ruflo swarm/daemon/AgentDB) — see source-plan §3.2.
- Auto-publication of releases.
- Real-time dashboards.
