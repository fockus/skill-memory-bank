"""Unit tests for the checklist v2 parser (`memory_bank_skill.checklist_v2`).

The module is exercised end-to-end through `mb-checklist-prune.sh`,
`mb-plan-sync.sh`, `mb-plan-done.sh` and `mb-work-checkbox.sh`, but those tests
run it behind a shell wrapper and a CLI. These assert the pure functions
directly, so a parser regression names itself instead of surfacing as a failure
three layers up.

Invariant under test throughout (AGR-043): nothing is ever lost. `merge` never
resets a ✅, `upsert` never touches a stage it did not add, and a v1 block folds
into v2 with every stage and its status intact.
"""

from memory_bank_skill.checklist_v2 import (
    flip,
    legacy_key,
    legacy_text,
    merge,
    parse,
    plan_title,
    render_block,
    rewrite,
    upsert,
)

V1 = """\
<!-- mb-plan:alpha.md -->
## Stage 1: first thing
- ✅ first thing

<!-- mb-plan:alpha.md -->
## Stage 2: second thing
- ⬜ second thing
""".splitlines()

V2 = """\
<!-- mb-plan:beta.md -->
## Beta plan — 1/2
- ✅ Stage 1 — already done
- ⬜ Stage 2 — still open
""".splitlines()


def test_parse_reads_two_v1_stage_blocks_of_one_plan():
    blocks, legacy = parse(V1)
    assert [b.plan for b in blocks] == ["alpha.md", "alpha.md"]
    assert legacy == []
    assert sorted(n for b in blocks for n in b.stages) == [1, 2]


def test_parse_reads_a_v2_block_with_its_statuses():
    blocks, _ = parse(V2)
    assert len(blocks) == 1
    stages = blocks[0].stages
    assert stages[1].done is True
    assert stages[2].done is False
    assert stages[2].name == "still open"


def test_merge_folds_v1_stage_blocks_into_one_ordered_set():
    blocks, _ = parse(V1)
    _, stages, _ = merge(blocks)
    assert sorted(stages) == [1, 2]
    assert stages[1].done is True
    assert stages[2].done is False


def test_merge_never_resets_a_done_stage_when_a_pending_duplicate_follows():
    # A stale v1 block claiming ⬜ must not un-tick a v2 block's ✅ — the fold
    # is an OR over `done`, so re-running a sync can only ever move forward.
    mixed = V2 + [
        "",
        "<!-- mb-plan:beta.md -->",
        "## Stage 1: already done",
        "- ⬜ already done",
    ]
    blocks, _ = parse(mixed)
    _, stages, _ = merge(blocks)
    assert stages[1].done is True


def test_render_block_emits_the_v2_shape_with_a_recomputed_count():
    blocks, _ = parse(V2)
    _, stages, _ = merge(blocks)
    out = render_block("beta.md", "Beta plan", stages)
    assert out[0] == "<!-- mb-plan:beta.md -->"
    assert out[1] == "## Beta plan — 1/2"
    assert out[2] == "- ✅ Stage 1 — already done"
    assert out[3] == "- ⬜ Stage 2 — still open"


def test_upsert_adds_a_missing_stage_and_is_idempotent():
    once, added = upsert(list(V2), "beta.md", "Beta plan", [(3, "brand new")])
    assert added == 1
    assert any("Stage 3 — brand new" in line for line in once)
    twice, added_again = upsert(list(once), "beta.md", "Beta plan", [(3, "brand new")])
    assert added_again == 0
    assert twice == once


def test_upsert_leaves_an_existing_done_stage_alone():
    out, _ = upsert(list(V2), "beta.md", "Beta plan", [(1, "already done")])
    assert "- ✅ Stage 1 — already done" in out
    assert "- ⬜ Stage 1 — already done" not in out


def test_flip_ticks_one_stage_and_recomputes_the_count():
    out, changed = flip(list(V2), "beta.md", 2)
    assert changed is True
    assert "- ✅ Stage 2 — still open" in out
    assert "## Beta plan — 2/2" in out


def test_flip_of_an_unknown_plan_changes_nothing():
    out, changed = flip(list(V2), "nosuch.md", 1)
    assert changed is False
    assert out == V2


def test_plan_title_strips_a_leading_kind_prefix():
    assert plan_title("# Fix: make it faster\n\nbody", "fallback") == "make it faster"
    assert plan_title("no heading at all", "fallback") == "fallback"


LEGACY_TWIN = """\
### Closed work
first body. Plan: [plans/done/a.md](plans/done/a.md)
- ✅ one

### Closed work
second body. Plan: [plans/done/b.md](plans/done/b.md)
- ✅ two
""".splitlines()


def test_rewrite_drops_only_the_legacy_section_named_by_its_key():
    # Two sections may share a heading; they must not share a drop key, or
    # archiving one deletes the other's content along with it (AGR-043).
    _, legacy = parse(LEGACY_TWIN)
    assert len(legacy) == 2
    first, second = legacy
    out = "\n".join(rewrite(list(LEGACY_TWIN), drop={legacy_key(first, legacy_text(LEGACY_TWIN, first))}))
    assert "first body." not in out
    assert "second body." in out
