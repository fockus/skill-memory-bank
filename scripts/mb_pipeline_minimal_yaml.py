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
    return cfg
