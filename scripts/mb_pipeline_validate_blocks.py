"""Per-block pipeline validators (budget .. named-pipeline metadata).

Split out of mb_pipeline_validate_core.py so both stay <=400 lines (S2 review
[25]). Pure extraction: the block bodies are verbatim, wrapped in `run()` with
the core's shared context passed in explicitly instead of read as globals.
"""

from __future__ import annotations

import re

import mb_pipeline_minimal_yaml as minimal_yaml

# YAML scalars that are NOT strings, recognised on the raw inline-map tokens the
# spec_review grammar produces (review [20]).
_YAML_BOOL_RE = re.compile(r"^(true|false|yes|no|on|off)$", re.I)
_YAML_NULL_RE = re.compile(r"^(null|~)$", re.I)
_YAML_NUM_RE = re.compile(r"^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$")


def _yaml_scalar_kind(token: str) -> str:
    if _YAML_BOOL_RE.match(token):
        return "boolean"
    if _YAML_NULL_RE.match(token):
        return "null"
    if _YAML_NUM_RE.match(token):
        return "number"
    return "string"


def _is_yaml_string(token: str) -> bool:
    return _yaml_scalar_kind(token) == "string"


def run(cfg, err, strip_comment, valid_max_cycles, yaml, text, SEVERITY_KEYS):
    """Validate every optional config block; append findings through `err`."""
    # ── budget ──────────────────────────────────────────────────────────
    budget = cfg.get("budget") or {}
    if not isinstance(budget, dict):
        err("budget: must be a mapping")
        budget = {}
    for pkey in ("warn_at_percent", "stop_at_percent"):
        if pkey in budget:
            v = budget[pkey]
            if not isinstance(v, (int, float)) or isinstance(v, bool) or not (0 <= v <= 100):
                err(f"budget.{pkey}: must be number in [0, 100] (got {v!r})")
    if "default_limit" in budget and budget["default_limit"] is not None:
        v = budget["default_limit"]
        if not isinstance(v, (int, float)) or isinstance(v, bool) or v < 0:
            err("budget.default_limit: must be null or non-negative number")

    # ── protected_paths ────────────────────────────────────────────────
    pp = cfg.get("protected_paths")
    if not isinstance(pp, list):
        err("protected_paths: must be a list")
    else:
        for i, item in enumerate(pp):
            if not isinstance(item, str) or not item:
                err(f"protected_paths[{i}]: must be a non-empty string")

    # ── sprint_context_guard ───────────────────────────────────────────
    guard = cfg.get("sprint_context_guard") or {}
    if not isinstance(guard, dict):
        err("sprint_context_guard: must be a mapping")
        guard = {}
    soft = guard.get("soft_warn_tokens")
    hard = guard.get("hard_stop_tokens")
    if not isinstance(soft, int) or isinstance(soft, bool) or soft <= 0:
        err("sprint_context_guard.soft_warn_tokens: must be int > 0")
    if not isinstance(hard, int) or isinstance(hard, bool) or hard <= 0:
        err("sprint_context_guard.hard_stop_tokens: must be int > 0")
    if (
        isinstance(soft, int)
        and isinstance(hard, int)
        and not isinstance(soft, bool)
        and not isinstance(hard, bool)
    ):
        if hard <= soft:
            err(
                f"sprint_context_guard: hard_stop_tokens ({hard}) must be > soft_warn_tokens ({soft})"
            )

    # ── review_rubric ─────────────────────────────────────────────────
    rubric = cfg.get("review_rubric") or {}
    if not isinstance(rubric, dict):
        err("review_rubric: must be a mapping")
        rubric = {}
    REQUIRED_RUBRIC = ("logic", "code_rules", "security", "scalability", "tests")
    for sec in REQUIRED_RUBRIC:
        if sec not in rubric:
            err(f"review_rubric.{sec}: missing")
            continue
        items = rubric[sec]
        if not isinstance(items, list) or not items:
            err(f"review_rubric.{sec}: must be a non-empty list")
            continue
        for i, item in enumerate(items):
            if not isinstance(item, str) or not item.strip():
                err(f"review_rubric.{sec}[{i}]: must be a non-empty string")

    # ── sdd ────────────────────────────────────────────────────────────
    sdd = cfg.get("sdd") or {}
    if not isinstance(sdd, dict):
        err("sdd: must be a mapping")
        sdd = {}
    for bool_key in (
        "require_ears_in_sdd_command",
        "require_ears_in_plan_command",
        "require_ears_in_plan_with_sdd_flag",
    ):
        if bool_key not in sdd:
            err(f"sdd.{bool_key}: missing")
        elif not isinstance(sdd[bool_key], bool):
            err(f"sdd.{bool_key}: must be boolean")
    policy = sdd.get("covers_requirements_policy")
    if policy not in ("warn", "block", "off"):
        err(f"sdd.covers_requirements_policy: must be one of warn|block|off (got {policy!r})")
    if "full_mode_path" not in sdd or not isinstance(sdd.get("full_mode_path"), str):
        err("sdd.full_mode_path: missing or not a string")
    # Optional opt-in gate: when present, must be boolean. Absent → treated as false.
    if "require_scenarios" in sdd and not isinstance(sdd["require_scenarios"], bool):
        err("sdd.require_scenarios: must be boolean")

    # ── sdd.spec_review (S2-C5) and sdd.spec_judge (S9-C1) ──────────────
    # Both are INLINE maps validated on the RAW text, independent of the YAML
    # loader (major #10): a nested block, a quoted scalar (which could hide a
    # comma/colon) or any comma inside a value must be rejected identically with
    # and without PyYAML. One parser for both, so the two cannot drift.
    _sr_line, _sr_top = minimal_yaml.find_sdd_inline_map(text, "spec_review", strip_comment)
    _sj_line, _sj_top = minimal_yaml.find_sdd_inline_map(text, "spec_judge", strip_comment)
    for _name, _line, _top in (
        ("spec_review", _sr_line, _sr_top),
        ("spec_judge", _sj_line, _sj_top),
    ):
        if _line is None and _top:
            err(
                f"{_name}: must be nested under the top-level `sdd:` block "
                f"(runtime reads sdd.{_name}; a top-level one is never applied)"
            )

    _sr = minimal_yaml.check_sdd_inline_map(
        err,
        "spec_review",
        _sr_line,
        {"enabled", "agent", "model", "thinking", "rubric"},
        _is_yaml_string,
        _yaml_scalar_kind,
    )
    _sj = minimal_yaml.check_sdd_inline_map(
        err,
        "spec_judge",
        _sj_line,
        {"enabled", "agent", "model", "thinking", "max_cycles"},
        _is_yaml_string,
        _yaml_scalar_kind,
    )

    # max_cycles: integer >= 1. A judge loop bounded by "many" is unbounded.
    if _sj is not None and "max_cycles" in _sj:
        _mc = _sj["max_cycles"]
        if not re.fullmatch(r"[0-9]+", _mc or "") or int(_mc) < 1:
            err(f"sdd.spec_judge.max_cycles: must be an integer >= 1 (got {_mc!r})")

    # A judge with nothing to judge is a configuration error, not a no-op: the
    # user asked for adjudication and would silently get none. Absent
    # spec_review counts as disabled -- that is the state a config drifts into
    # when the review map is deleted and the judge is left enabled.
    if _sj is not None and (_sj.get("enabled", "") or "").lower() == "true":
        _review_on = _sr is not None and (_sr.get("enabled", "") or "").lower() == "true"
        if not _review_on:
            err(
                "sdd.spec_judge: spec_judge_requires_spec_review "
                "(enabled judge over a disabled/absent sdd.spec_review has no verdict to judge)"
            )

    # ── sdd.layers (svp-contract-test-loop C1) ──────────────────────────
    # Inline-map discipline, same as spec_review/spec_judge; the grammar and its
    # rationale live beside its siblings in minimal_yaml.check_sdd_layers_map.
    _lay_line, _lay_top = minimal_yaml.find_sdd_inline_map(text, "layers", strip_comment)
    if _lay_line is None and _lay_top:
        err(
            "layers: must be nested under the top-level `sdd:` block "
            "(runtime reads sdd.layers; a top-level one is never applied)"
        )
    minimal_yaml.check_sdd_layers_map(err, _lay_line)

    # ── runtime blocks: review / judge / review_ensemble / done_* / dispatch ──
    KNOWN_AGENTS = {
        "claude-code",
        "cursor",
        "codex",
        "opencode",
        "pi",
        "windsurf",
        "cline",
        "kilo",
    }
    KNOWN_TRANSPORTS = {"pi", "opencode", "codex", "claude-agent"}
    ALLOWED_DONE_REQUIRED = {"tests_pass", "no_critical_violations", "no_placeholders"}

    def _check_severity_gate(prefix, gate):
        if gate is None:
            return
        if not isinstance(gate, dict):
            err(f"{prefix}.severity_gate: must be a mapping")
            return
        unknown = set(gate.keys()) - SEVERITY_KEYS
        if unknown:
            err(
                f"{prefix}.severity_gate: unknown keys {sorted(unknown)}; allowed {sorted(SEVERITY_KEYS)}"
            )
        for sev_k, sev_v in gate.items():
            if not isinstance(sev_v, int) or isinstance(sev_v, bool) or sev_v < 0:
                err(f"{prefix}.severity_gate.{sev_k}: must be int >= 0")

    if "review" in cfg:
        rev = cfg.get("review") or {}
        if not isinstance(rev, dict):
            err("review: must be a mapping")
        else:
            if "enabled" in rev and not isinstance(rev.get("enabled"), bool):
                err("review.enabled: must be boolean")
            _check_severity_gate("review", rev.get("severity_gate"))
            mc = rev.get("max_cycles")
            if mc is not None and (not isinstance(mc, int) or isinstance(mc, bool) or mc < 1):
                err(f"review.max_cycles: must be int >= 1 (got {mc!r})")
            omc = rev.get("on_max_cycles")
            if omc is not None and omc not in valid_max_cycles:
                err(f"review.on_max_cycles: '{omc}' not in {sorted(valid_max_cycles)}")
            cats = rev.get("categories")
            if cats is not None:
                if not isinstance(cats, list) or not all(
                    isinstance(c, str) and c.strip() for c in cats
                ):
                    err("review.categories: must be a list of non-empty strings")

    if "judge" in cfg:
        jud = cfg.get("judge") or {}
        if not isinstance(jud, dict):
            err("judge: must be a mapping")
        else:
            if "enabled" in jud and not isinstance(jud.get("enabled"), bool):
                err("judge.enabled: must be boolean")
            dec = jud.get("decisions")
            if dec is not None:
                if not isinstance(dec, list) or not dec:
                    err("judge.decisions: must be a non-empty list")
                else:
                    bad = [d for d in dec if d not in {"GO", "GO_WITH_BACKLOG", "NO_GO"}]
                    if bad:
                        err(f"judge.decisions: unknown values {bad}")
            if "register_backlog_before_done" in jud and not isinstance(
                jud.get("register_backlog_before_done"), bool
            ):
                err("judge.register_backlog_before_done: must be boolean")
            bp = jud.get("blocking_policy")
            if bp is not None:
                if not isinstance(bp, list) or not all(
                    isinstance(x, str) and x.strip() for x in bp
                ):
                    err("judge.blocking_policy: must be a list of non-empty strings")

    if "review_ensemble" in cfg:
        ens = cfg.get("review_ensemble") or {}
        if not isinstance(ens, dict):
            err("review_ensemble: must be a mapping")
        else:
            mn = ens.get("min_reviewers")
            mx = ens.get("max_reviewers")
            if mn is not None and (not isinstance(mn, int) or isinstance(mn, bool) or mn < 1):
                err("review_ensemble.min_reviewers: must be int >= 1")
            if mx is not None and (not isinstance(mx, int) or isinstance(mx, bool) or mx < 1):
                err("review_ensemble.max_reviewers: must be int >= 1")
            if isinstance(mn, int) and isinstance(mx, int) and mn > mx:
                err("review_ensemble: min_reviewers must be <= max_reviewers")
            revs = ens.get("reviewers")
            if revs is not None:
                if not isinstance(revs, list) or not revs:
                    err("review_ensemble.reviewers: must be a non-empty list")
                else:
                    for i, item in enumerate(revs):
                        if not isinstance(item, dict):
                            err(f"review_ensemble.reviewers[{i}]: must be a mapping")
                        elif not item.get("role") or not isinstance(item.get("role"), str):
                            err(f"review_ensemble.reviewers[{i}].role: must be a non-empty string")

    if "done_gates" in cfg:
        dg = cfg.get("done_gates") or {}
        if not isinstance(dg, dict):
            err("done_gates: must be a mapping")
        else:
            for bk in ("enabled", "allow_force"):
                if bk in dg and not isinstance(dg.get(bk), bool):
                    err(f"done_gates.{bk}: must be boolean")
            req = dg.get("required")
            if req is not None:
                if not isinstance(req, list):
                    err("done_gates.required: must be a list")
                else:
                    bad = [r for r in req if r not in ALLOWED_DONE_REQUIRED]
                    if bad:
                        err(f"done_gates.required: unknown tokens {bad}")

    if "done_placeholders" in cfg:
        dp = cfg.get("done_placeholders") or {}
        if not isinstance(dp, dict):
            err("done_placeholders: must be a mapping")
        else:
            deny = dp.get("deny")
            if deny is not None:
                if not isinstance(deny, list) or not deny:
                    err("done_placeholders.deny: must be a non-empty list")
                elif not all(isinstance(x, str) and x.strip() for x in deny):
                    err("done_placeholders.deny: entries must be non-empty strings")

    if "dispatch" in cfg:
        disp = cfg.get("dispatch") or {}
        if not isinstance(disp, dict):
            err("dispatch: must be a mapping")
        else:
            pri = disp.get("priority")
            if pri is not None:
                if not isinstance(pri, list) or not pri:
                    err("dispatch.priority: must be a non-empty list")
                else:
                    bad = [a for a in pri if a not in KNOWN_TRANSPORTS]
                    if bad:
                        err(f"dispatch.priority: unknown transport(s) {bad}")
            ona = disp.get("on_none_available")
            if ona is not None and ona not in {"fallback", "error"}:
                err(f"dispatch.on_none_available: must be fallback or error (got {ona!r})")
            enum = disp.get("enumerable")
            if enum is not None:
                if not isinstance(enum, list):
                    err("dispatch.enumerable: must be a list")
                else:
                    bad = [a for a in enum if a not in KNOWN_TRANSPORTS]
                    if bad:
                        err(f"dispatch.enumerable: unknown transport(s) {bad}")
            for mk in ("prefer", "model_map", "fallback"):
                if mk in disp and disp[mk] is not None and not isinstance(disp[mk], dict):
                    err(f"dispatch.{mk}: must be a mapping")

    for stage_name in ("discuss", "plan", "sdd", "review", "judge"):
        if stage_name not in cfg:
            continue
        block = cfg.get(stage_name)
        if isinstance(block, dict) and "enabled" in block:
            if not isinstance(block.get("enabled"), bool):
                err(f"{stage_name}.enabled: must be boolean")

    # ── named-pipeline metadata (optional keys; validated only with PyYAML) ──
    # pipeline_name / default / agents are an opt-in layer used by named pipelines.
    # The minimal no-PyYAML loader does not model list values, so we validate these
    # only when a real YAML parse is available — absence stays valid (back-compat).
    if yaml is not None:
        if "pipeline_name" in cfg:
            pn = cfg.get("pipeline_name")
            if not isinstance(pn, str) or not pn.strip():
                err("pipeline_name: must be a non-empty string when present")
        if "default" in cfg and not isinstance(cfg.get("default"), bool):
            err(f"default: must be boolean when present (got {cfg.get('default')!r})")
        if "agents" in cfg:
            agents_val = cfg.get("agents")
            if not isinstance(agents_val, list) or not agents_val:
                err("agents: must be a non-empty list of code-agent ids when present")
            else:
                for i, a in enumerate(agents_val):
                    if not isinstance(a, str) or not a.strip():
                        err(f"agents[{i}]: must be a non-empty string")
                    elif a not in KNOWN_AGENTS:
                        err(
                            f"agents[{i}]: unknown code-agent '{a}' "
                            f"(known: {', '.join(sorted(KNOWN_AGENTS))})"
                        )
