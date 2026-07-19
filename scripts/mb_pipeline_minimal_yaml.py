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
