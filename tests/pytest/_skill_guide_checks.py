"""Pure checks of the skill against Anthropic skill-authoring rules.

Every check takes the skill root and returns a list of violation strings
(empty list = compliant). Scope is an explicit list of skill directories,
never the whole repository (.memory-bank/, tests/, docs/ are not skill files).
"""

from __future__ import annotations

import re
from pathlib import Path

MAX_DESCRIPTION = 1024
MAX_BODY_LINES = 300
MAX_SKILL_BYTES = 36000
TOC_REQUIRED_OVER = 100
TOC_WITHIN_LINES = 40

WHEN_MARKER = re.compile(r"use when|when the user|triggers", re.IGNORECASE)
TOC_HEADING = re.compile(
    r"^#{1,6}\s+(contents|table of contents|содержание|оглавление)\s*$", re.IGNORECASE
)
HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
ANCHOR_LINK = re.compile(r"\]\(#([^)]+)\)")
PATH_TOKEN = re.compile(
    r"(?:references|rules|scripts|flow-templates|commands|agents|hooks|templates)/[\w./-]+"
)
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n?", re.DOTALL)


def parse_frontmatter(text: str) -> dict[str, str] | None:
    """Minimal YAML frontmatter parser: top-level `key: value`, quoted or block scalars."""
    match = FRONTMATTER.match(text)
    if match is None:
        return None
    result: dict[str, str] = {}
    key = None
    for line in match.group(1).splitlines():
        top = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if top:
            key, value = top.group(1), top.group(2).strip()
            if value in (">", "|", ">-", "|-"):
                value = ""
            elif len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            result[key] = value
        elif key is not None and line.startswith((" ", "\t")):
            result[key] = (result[key] + " " + line.strip()).strip()
    return result


def _body(text: str) -> str:
    match = FRONTMATTER.match(text)
    return text[match.end() :] if match else text


def _skill_md(root: Path) -> str:
    return (root / "SKILL.md").read_text(encoding="utf-8")


def _rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def _md_files(root: Path, patterns: list[str]) -> list[Path]:
    return sorted({p for pattern in patterns for p in root.glob(pattern) if p.is_file()})


def github_slug(heading: str) -> str:
    """GitHub anchor slug: lowercase, drop punctuation except - and _, spaces -> '-'."""
    return re.sub(r"[^\w\- ]", "", heading.strip().lower()).replace(" ", "-")


def _headings(text: str) -> list[str]:
    headings, in_fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith(("```", "~~~")):
            in_fence = not in_fence
        elif not in_fence and (match := HEADING.match(line)):
            headings.append(match.group(2))
    return headings


def check_skill_frontmatter(root: Path) -> list[str]:
    meta = parse_frontmatter(_skill_md(root))
    if meta is None:
        return ["SKILL.md: missing frontmatter"]
    errors = []
    name = meta.get("name", "")
    if not re.fullmatch(r"[a-z0-9-]{1,64}", name):
        errors.append(f"name: invalid format {name!r}")
    if re.search(r"anthropic|claude", name):
        errors.append(f"name: reserved word in {name!r}")
    desc = meta.get("description", "")
    if not 1 <= len(desc) <= MAX_DESCRIPTION:
        errors.append(f"description: length {len(desc)} outside 1..{MAX_DESCRIPTION}")
    if re.search(r"<[A-Za-z/][^>]*>", desc):
        errors.append("description: contains XML tag")
    if not WHEN_MARKER.search(desc):
        errors.append("description: no 'when' marker")
    if desc.startswith(("I ", "You ")):
        errors.append("description: not third person")
    return errors


def check_skill_size(root: Path) -> list[str]:
    text = _skill_md(root)
    errors = []
    body_lines = len(_body(text).splitlines())
    if body_lines > MAX_BODY_LINES:
        errors.append(f"SKILL.md body: {body_lines} lines > {MAX_BODY_LINES}")
    size = len(text.encode("utf-8"))
    if size > MAX_SKILL_BYTES:
        errors.append(f"SKILL.md: {size} bytes > {MAX_SKILL_BYTES}")
    return errors


def _toc_section(lines: list[str]) -> list[str] | None:
    for index, line in enumerate(lines[:TOC_WITHIN_LINES]):
        if TOC_HEADING.match(line):
            section = []
            for follow in lines[index + 1 :]:
                if HEADING.match(follow):
                    break
                section.append(follow)
            return section
    return None


def check_reference_toc(root: Path) -> list[str]:
    errors = []
    for path in _md_files(root, ["references/**/*.md", "rules/RULES.md", "flow-templates/**/*.md"]):
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        if len(lines) <= TOC_REQUIRED_OVER:
            continue
        section = _toc_section(lines)
        if section is None:
            errors.append(f"{_rel(root, path)}: {len(lines)} lines, no table of contents")
            continue
        slugs = {github_slug(h) for h in _headings(text)}
        for anchor in ANCHOR_LINK.findall("\n".join(section)):
            if anchor not in slugs:
                errors.append(f"{_rel(root, path)}: broken ToC anchor #{anchor}")
    return errors


def check_files_mentioned(root: Path) -> list[str]:
    skill = _skill_md(root)
    files = _md_files(root, ["references/**/*.md", "rules/*.md", "flow-templates/**/*.md"])
    return [
        f"{_rel(root, p)}: not mentioned in SKILL.md" for p in files if _rel(root, p) not in skill
    ]


def _path_candidates(text: str) -> list[str]:
    """Text where SKILL.md names files: fenced blocks, inline code spans, link targets.

    Plain prose is excluded on purpose: "local hooks/configs" is wording, not a path.
    """
    fences = re.findall(r"^```.*?^```", text, re.DOTALL | re.MULTILINE)
    prose = re.sub(r"^```.*?^```", "", text, flags=re.DOTALL | re.MULTILINE)
    return fences + re.findall(r"`([^`\n]+)`", prose) + re.findall(r"\]\(([^)]+)\)", prose)


def _foreign_root(prefix: str) -> bool:
    """`.cursor/rules/x`, `~/.claude/agents/` live outside the skill dir."""
    return bool(prefix) and "memory-bank/" not in prefix and (prefix[0] in ".~" or "/." in prefix)


def check_skill_paths_exist(root: Path) -> list[str]:
    tokens = set()
    for chunk in _path_candidates(_skill_md(root)):
        for match in PATH_TOKEN.finditer(chunk):
            prefix = re.search(r"[^\s`(\"']*$", chunk[: match.start()]).group(0)
            if not _foreign_root(prefix):
                tokens.add(match.group(0).rstrip(".,:;)"))
    return [
        f"{token}: referenced in SKILL.md but missing on disk"
        for token in sorted(tokens)
        if not any(c in token for c in "<*{") and not (root / token).exists()
    ]


def check_command_descriptions(root: Path) -> list[str]:
    errors = []
    for path in _md_files(root, ["commands/*.md"]):
        rel = _rel(root, path)
        meta = parse_frontmatter(path.read_text(encoding="utf-8"))
        if meta is None:
            errors.append(f"{rel}: missing frontmatter")
            continue
        desc = meta.get("description", "")
        if not 1 <= len(desc) <= MAX_DESCRIPTION:
            errors.append(f"{rel}: description length {len(desc)} outside 1..{MAX_DESCRIPTION}")
        elif not WHEN_MARKER.search(desc):
            errors.append(f"{rel}: description has no 'when' marker")
        if "disable-model-invocation" in meta:
            errors.append(f"{rel}: disable-model-invocation is forbidden (AGR-061)")
    return errors
