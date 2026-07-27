"""PyYAML-optional minimal loader for pipeline.yaml.

Split out of mb_pipeline_validate_core.py so every file stays <=400 lines (S2
review [25]). Pure extraction, verbatim: this is the textual fallback parser
used when PyYAML is unavailable, plus the comment-stripping helper the block
validators share.
"""

from __future__ import annotations


def strip_comment(line: str) -> str:
    in_single = False
    in_double = False
    for idx, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:idx]
    return line


def parse_scalar(value: str):
    value = value.strip()
    if not value:
        return None
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered in {"null", "none", "~"}:
        return None
    try:
        return int(value)
    except ValueError:
        return value


def parse_inline_list(value: str) -> list:
    inner = value.strip()[1:-1].strip()
    if not inner:
        return []
    return [parse_scalar(part.strip()) for part in inner.split(",")]


def parse_inline_map(value: str) -> dict:
    inner = value.strip()[1:-1].strip()
    result = {}
    if not inner:
        return result
    for part in inner.split(","):
        key, sep, raw_value = part.partition(":")
        if sep:
            result[key.strip()] = parse_scalar(raw_value)
    return result


def parse_value(value: str):
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        return parse_inline_list(value)
    if value.startswith("{") and value.endswith("}"):
        return parse_inline_map(value)
    return parse_scalar(value)


def block_lines(lines: list[str], name: str) -> list[tuple[int, str]]:
    block: list[tuple[int, str]] = []
    in_block = False
    for raw in lines:
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if not in_block:
            if indent == 0 and stripped == f"{name}:":
                in_block = True
            continue
        if indent == 0 and not stripped.startswith("-"):
            break
        block.append((indent, stripped))
    return block


def _parse_entries(entries: list[tuple[int, str]], pos: int, indent: int):
    """Parse one nested level; returns (value, next_pos).

    Handles the shapes pipeline.yaml actually uses: nested mappings, block
    sequences (`- item`), inline maps/lists, and scalars.
    """
    if pos >= len(entries):
        return None, pos
    if entries[pos][1].startswith("- "):
        items = []
        while pos < len(entries) and entries[pos][0] == indent and entries[pos][1].startswith("- "):
            body = entries[pos][1][2:].strip()
            key, sep, value = body.partition(":")
            if sep and not body.startswith(("[", "{")):
                # `- key: value` starts a mapping item at the bullet's own level.
                item = {key.strip(): parse_value(value)} if value.strip() else {}
                pos += 1
                if not value.strip():
                    nested, pos = _parse_entries(entries, pos, indent + 2)
                    item[key.strip()] = nested
                while pos < len(entries) and entries[pos][0] > indent:
                    k2, s2, v2 = entries[pos][1].partition(":")
                    if s2:
                        item[k2.strip()] = parse_value(v2)
                    pos += 1
                items.append(item)
            else:
                items.append(parse_value(body))
                pos += 1
        return items, pos

    result = {}
    while pos < len(entries) and entries[pos][0] == indent:
        key, sep, value = entries[pos][1].partition(":")
        if not sep:
            pos += 1
            continue
        key = key.strip()
        pos += 1
        if value.strip():
            result[key] = parse_value(value)
            continue
        if pos < len(entries) and entries[pos][0] > indent:
            nested, pos = _parse_entries(entries, pos, entries[pos][0])
            result[key] = nested
        else:
            result[key] = None
    return result, pos


def parse_nested_block(lines: list[str], name: str):
    """Full nested value of a top-level block, or None when it is absent.

    The stdlib fallback previously loaded only a hand-picked subset of blocks,
    so everything the validator checks in workflows/review/judge/
    review_ensemble/done_*/dispatch was simply invisible without PyYAML — a
    closed-enum violation PyYAML rejects passed silently (review [18]).
    """
    entries = block_lines(lines, name)
    if not entries:
        return None
    value, _ = _parse_entries(entries, 0, entries[0][0])
    return value


def parse_simple_mapping(lines: list[str], name: str) -> dict:
    result = {}
    for indent, stripped in block_lines(lines, name):
        if indent != 2 or stripped.startswith("-"):
            continue
        key, sep, value = stripped.partition(":")
        if sep:
            result[key.strip()] = parse_value(value)
    return result


def parse_simple_list(lines: list[str], name: str) -> list:
    result = []
    for _indent, stripped in block_lines(lines, name):
        if stripped.startswith("- "):
            result.append(parse_value(stripped[2:]))
    return result


def parse_roles(lines: list[str]) -> dict:
    roles = {}
    current = None
    for indent, stripped in block_lines(lines, "roles"):
        if indent == 2:
            key, sep, value = stripped.partition(":")
            if not sep:
                continue
            current = key.strip()
            roles[current] = parse_value(value) if value.strip() else {}
        elif indent == 4 and current:
            key, sep, value = stripped.partition(":")
            if sep:
                roles.setdefault(current, {})[key.strip()] = parse_value(value)
    return roles


def parse_stage_pipeline(lines: list[str]) -> list[dict]:
    steps: list[dict] = []
    current = None
    nested_key = None
    for indent, stripped in block_lines(lines, "stage_pipeline"):
        if indent == 2 and stripped.startswith("- "):
            current = {}
            steps.append(current)
            nested_key = None
            item = stripped[2:]
            key, sep, value = item.partition(":")
            if sep:
                current[key.strip()] = parse_value(value)
        elif indent == 4 and current is not None:
            key, sep, value = stripped.partition(":")
            if not sep:
                continue
            nested_key = None
            key_name = key.strip()
            if value.strip():
                current[key_name] = parse_value(value)
            else:
                current[key_name] = [] if key_name in {"checks", "required_artifacts"} else {}
                nested_key = key_name
        elif indent == 6 and current is not None and nested_key:
            if stripped.startswith("- ") and isinstance(current[nested_key], list):
                current[nested_key].append(parse_value(stripped[2:]))
            elif isinstance(current[nested_key], dict):
                key, sep, value = stripped.partition(":")
                if sep:
                    current[nested_key][key.strip()] = parse_value(value)
    return steps


def parse_review_rubric(lines: list[str]) -> dict:
    rubric = {}
    current = None
    for indent, stripped in block_lines(lines, "review_rubric"):
        if indent == 2:
            key, sep, _value = stripped.partition(":")
            if sep:
                current = key.strip()
                rubric[current] = []
        elif indent == 4 and current and stripped.startswith("- "):
            rubric[current].append(parse_value(stripped[2:]))
    return rubric


def minimal_pipeline_load(text: str) -> dict:
    lines = text.splitlines()
    cfg = {}
    for raw in lines:
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0 and ":" in stripped:
            key, _sep, value = stripped.partition(":")
            if value.strip():
                cfg[key.strip()] = parse_value(value)
    cfg["roles"] = parse_roles(lines)
    cfg["stage_pipeline"] = parse_stage_pipeline(lines)
    cfg["budget"] = parse_simple_mapping(lines, "budget")
    cfg["protected_paths"] = parse_simple_list(lines, "protected_paths")
    cfg["sprint_context_guard"] = parse_simple_mapping(lines, "sprint_context_guard")
    cfg["review_rubric"] = parse_review_rubric(lines)
    cfg["sdd"] = parse_simple_mapping(lines, "sdd")
    # Every remaining block the validators inspect. Without these the stdlib-only
    # path validated a strictly smaller config than the PyYAML path (review [18]).
    for _name in (
        "workflows",
        "review",
        "judge",
        "review_ensemble",
        "done_gates",
        "done_placeholders",
        "dispatch",
        "agents",
        "aliases",
    ):
        _value = parse_nested_block(lines, _name)
        if _value is not None:
            cfg[_name] = _value
    return cfg


def find_sdd_inline_map(text, key, strip_comment):
    """Locate `<key>: {...}` INSIDE the top-level `sdd:` block.

    Returns (inline_text_or_None, seen_at_top_level). Scanning the whole file
    for any `<key>:` accepted a TOP-LEVEL one, which the runtime (reading
    `sdd.<key>`) never sees -- the config validated clean while the feature
    stayed silently off (review [19]). Indentation is therefore part of the check.
    """
    line = None
    at_top_level = False
    in_sdd = False
    for raw_line in text.splitlines():
        raw = strip_comment(raw_line).rstrip()
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip())
        stripped = raw.strip()
        if indent == 0:
            in_sdd = stripped.split(":", 1)[0].strip() == "sdd" and stripped.endswith(":")
        if stripped.startswith(key + ":"):
            if indent == 0:
                at_top_level = True
                continue
            if not in_sdd:
                continue
            line = stripped.split(":", 1)[1].strip()
            break
    return line, at_top_level


SDD_LAYER_KEYS = frozenset({"contract_first", "integration_tests", "e2e_tests"})


def check_sdd_layers_map(err, line):
    """Validate `sdd.layers: {k: bool, ...}`; None (absent) is valid.

    Absent means "use the built-in defaults" — every pipeline.yaml written
    before this feature has no such block. A NESTED block, by contrast, yields
    `layers: None` here and a full dict under PyYAML, so the two branches would
    disagree about whether the layers are configured at all; that is why the
    inline form is a requirement rather than a style choice.
    """
    if line is None:
        return None
    if not (line.startswith("{") and line.endswith("}")):
        err("sdd.layers: must be an inline mapping {%s}" % ", ".join(sorted(SDD_LAYER_KEYS)))
        return None
    parsed = {}
    for part in [p for p in line[1:-1].strip().split(",") if p.strip()]:
        if ":" not in part:
            err("sdd.layers: a value must not contain a comma (inline-map grammar)")
            return None
        key, value = part.split(":", 1)
        parsed[key.strip()] = value.strip()
    extra = sorted(set(parsed) - SDD_LAYER_KEYS)
    if extra:
        err("sdd.layers: unknown keys %s" % extra)
    for key in sorted(parsed):
        if parsed[key].lower() not in ("true", "false"):
            err("sdd.layers.%s: must be boolean (got %r)" % (key, parsed[key]))
    return parsed


def check_sdd_inline_map(err, name, line, allowed, is_string, scalar_kind):
    """Validate the shared inline-map grammar; return the parsed dict or None.

    Shared by spec_review and spec_judge so the two cannot drift: the judge's
    grammar is the reviewer's plus `max_cycles`, and a second hand-rolled copy
    is how one of them silently stops rejecting a bad value.
    """
    if line is None:
        return None
    if not (line.startswith("{") and line.endswith("}")):
        err("sdd.%s: must be an inline mapping {%s}" % (name, ", ".join(sorted(allowed))))
        return None
    if ('"' in line) or ("'" in line):
        err(f"sdd.{name}: values must be unquoted single tokens (no quotes)")
        return None

    inner = line[1:-1].strip()
    parsed = {}
    if inner:
        for part in inner.split(","):
            if ":" not in part:
                err(f"sdd.{name}: a value must not contain a comma (inline-map grammar)")
                return None
            k, v = part.split(":", 1)
            parsed[k.strip()] = v.strip()

    extra = sorted(set(parsed) - allowed)
    if extra:
        err(f"sdd.{name}: unknown keys {extra}")

    enabled_raw = parsed.get("enabled", "")
    if enabled_raw.lower() not in ("true", "false"):
        err(f"sdd.{name}.enabled: must be boolean")
    thinking = parsed.get("thinking")
    if thinking is not None and thinking not in ("low", "medium", "high"):
        err(f"sdd.{name}.thinking: must be one of low|medium|high (got {thinking!r})")
    if enabled_raw.lower() == "true":
        for k in ("agent", "model"):
            val = parsed.get(k)
            if not val:
                err(f"sdd.{name}.{k}: must be a non-empty string when enabled")
            elif not is_string(val):
                # STRING identity is required. The inline form yields raw tokens,
                # so `agent: false` / `model: 123` are the truthy strings
                # "false"/"123" -- they passed the emptiness check while being a
                # boolean and an int to any YAML loader, and to the runtime
                # (review [20]).
                err(
                    f"sdd.{name}.{k}: must be a string, "
                    f"got the {scalar_kind(val)} {val!r}"
                )
        if not thinking:
            err(f"sdd.{name}.thinking: required when enabled")
    return parsed
