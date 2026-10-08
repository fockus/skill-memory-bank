"""Adapter-owned strict argv/config decoding; no shell execution or YAML guessing."""

import json
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from memory_bank_skill.pipeline_yaml import load_file, load_text  # noqa: E402


def main():
    mode, value = sys.argv[1:]
    if mode == "argv":
        print(json.dumps(shlex.split(value)))
    elif mode == "pipeline":
        print(json.dumps(load_file(value)))
    elif mode == "agent":
        text = Path(value).read_text(encoding="utf-8-sig")
        parts = text.split("---", 2)
        if len(parts) != 3 or parts[0].strip():
            raise ValueError("Agent requires YAML frontmatter")
        print(json.dumps({"frontmatter": load_text(parts[1]), "body": parts[2].strip()}))
    else:
        raise ValueError("Unsupported decoder mode")


if __name__ == "__main__":
    main()
