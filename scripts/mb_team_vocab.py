"""Closed vocabulary: user prompt phrases -> track pipeline `--layer prompt` values.

Only explicit phrases map (design §4). A phrase that names a pipeline field
without a value from the vocabulary, two phrases that disagree, or an unknown
lens become questions for the user instead of a guess (REQ-TEAM-013/014).

`parse(text)` -> {"set": {key: value}, "questions": [str]}; values are strings
ready for `mb_team_pipeline.py resolve --prompt key=value`.
"""

from __future__ import annotations

import re

from mb_pipeline_validate_team import normalize_lens

MODEL_RE = re.compile(r"\b(opus|sonnet|haiku|fable|premium|mid|inherit|(?:gpt|claude)-[\w.-]+)\b")

# (pattern, assignments) — checked in order inside one clause.
PHRASES: tuple[tuple[str, dict], ...] = (
    (r"оркестратор ведет|\borchestrated\b", {"mode": "work", "work": "orchestrated"}),
    (r"через\s*/?mb work|по движку|\bvia\s*/?mb work\b", {"mode": "work"}),
    (r"без tdd|тесты не обязательн\w*|\bno tdd\b|\btdd optional\b", {"tdd": "optional"}),
    (r"(?:^|\s)с tdd|tdd обязател\w*|\btdd required\b", {"tdd": "required"}),
    (r"без верификатора|\bno verifier\b|\bwithout verifier\b", {"verifier": "none"}),
    (r"с верификатором|\bwith verifier\b", {"verifier": "plan-verifier"}),
    (r"без ревью|\bno review\b|\bwithout review\b", {"review": "none"}),
    (r"одним ревьюером|один ревьюер|\bsingle review\b|\bone reviewer\b", {"review": "single"}),
    (r"линзами|\bwith lenses\b|\blenses\b", {"review": "lenses"}),
    (r"маленьк\w*|\bsmall\b", {"size": "small"}),
    (r"стандартн\w*|\bstandard\b", {"size": "standard"}),
    (r"крупн\w*|\blarge\b", {"size": "large"}),
    (r"effort low", {"effort": "low"}),
    (r"effort medium", {"effort": "medium"}),
    (r"effort high|думай глубже|\bthink harder\b", {"effort": "high"}),
)

# A field mentioned without a mapped value is a question, not a default.
TRIGGERS = {
    "mode": r"\bwork\b|движ|облегченн|напрямую|\blight\b|\bdirect\b",
    "tdd": r"\btdd\b|тест",
    "verifier": r"верификатор|\bverifier\b",
    "review": r"ревью|ревьюер|\breview",
    "size": r"размер|\bsize\b",
    "effort": r"effort|думай",
    "models": r"модел|\bmodel",
}

# Which model key a model name in a clause belongs to.
MODEL_ROLES = (
    ("models.lenses", r"линз|\blens"),
    ("models.lead", r"\bлид\w*|\blead\b"),
    ("models.verifier", r"верификатор|\bverifier\b"),
    ("models.reviewer", r"ревью|ревьюер|\breview"),
)


def _clauses(text: str) -> list[tuple[str, list[str]]]:
    """Split on , ; and «и»; a `[…]` lens list stays with its clause."""
    lists: list[str] = []

    def keep(match: re.Match) -> str:
        lists.append(match.group(1))
        return f" <list{len(lists) - 1}> "

    masked = re.sub(r"\[([^\]]*)\]", keep, text)
    out = []
    for clause in re.split(r"[,;]|\s+и\s+|\s+and\s+", masked):
        found = [lists[int(i)] for i in re.findall(r"<list(\d+)>", clause)]
        if clause.strip():
            out.append((clause.strip(), found))
    return out


def parse(text: str) -> dict:
    lowered = text.lower().replace("ё", "е")
    values: dict[str, set] = {}
    questions: list[str] = []

    def put(key: str, value: str) -> None:
        values.setdefault(key, set()).add(value)

    for clause, lists in _clauses(lowered):
        hit: set[str] = set()
        for pattern, assignment in PHRASES:
            if re.search(pattern, clause):
                for key, value in assignment.items():
                    put(key, value)
                    hit.add(key)
        for raw in lists:
            names = [n.strip() for n in raw.split(",") if n.strip()]
            bad = [n for n in names if normalize_lens(n) is None]
            if bad:
                questions.append(f"lenses: unknown lens {bad} in '{clause}'")
            else:
                put("lenses", ",".join(normalize_lens(n) for n in names))
        models = MODEL_RE.findall(clause)
        if len(models) > 1:
            questions.append(f"models: several models in '{clause}' — which one, for which role?")
        elif models:
            key = next((k for k, pat in MODEL_ROLES if re.search(pat, clause)), "models.executor")
            put(key, models[0])
            hit.add("models")
        for field, pattern in TRIGGERS.items():
            if field not in hit and re.search(pattern, clause) and not (field == "review" and "models" in hit):
                questions.append(f"{field}: '{clause}' does not map to a value — say it explicitly")
    result = {}
    for key, found in values.items():
        if len(found) > 1:
            questions.append(f"{key}: conflicting values {sorted(found)}")
        else:
            result[key] = found.pop()
    return {"set": result, "questions": questions}
